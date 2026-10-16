# Mirrors the release files into the game's Mods\<ModName> folder. The game loads that copy and the Workshop
# uploader publishes it as is, so it must never hold .git, Source, docs or other development files; the
# repository itself lives outside the game folder. Runs after every build (SyncToGame in the csproj) and before
# every game test. Takes the cross-mod test lock: it never changes files under another session's running test.
[CmdletBinding(PositionalBinding = $false)]
param(
    # Minutes to wait for another session's test; a build should not wait long (build with -p:SkipSync=true).
    [int]$LockWaitMinutes = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GameRuntime.ps1')
$target = [IO.Path]::GetFullPath($ModTarget)
$versions = @($Cfg.GameVersions)
$keepDirs = @($Cfg.RuntimeDataDirs)
$releaseDirs = @($Cfg.ReleaseDirs) + $versions
# robocopy's defaults retry a locked file a million times, 30 seconds apart: fail fast instead.
$robocopyOptions = @('/MIR', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')

function Test-Under([string]$path, [string]$root) {
    $root = $root.TrimEnd('\')
    return $path.TrimEnd('\') -ieq $root -or $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Remove-ReleaseItem([string]$path) {
    $resolved = [IO.Path]::GetFullPath($path)
    if (-not $resolved.StartsWith($target.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an item outside the release target: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

$mutex = $null
try {
    if ((Test-Under $RepoRoot $target) -or (Test-Under $target $RepoRoot)) {
        throw "The repository and the release target must not contain each other: $RepoRoot, $target"
    }
    # Every version folder must hold this build's dll and nothing else (the game loads every file in Assemblies;
    # a version published without its dll would load the mod there with no code).
    $hashes = @{}
    foreach ($version in $versions) {
        $assemblies = Join-Path $RepoRoot "$version\Assemblies"
        $dll = Join-Path $assemblies $DllName
        if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
            throw "No $version\Assemblies\$DllName in the repository: build every version first (dotnet build Source\$($Cfg.ModName)\$($Cfg.ModName).csproj)."
        }
        $extra = @(Get-ChildItem -LiteralPath $assemblies -Recurse -Force | Where-Object { $_.FullName -ine $dll })
        if ($extra.Count -gt 0) { throw "$version\Assemblies may only hold $DllName; also found: $(($extra | ForEach-Object { $_.Name }) -join ', ')" }
        $hashes[$version] = Get-SourceHash $dll
    }
    # All dlls from one build: after building one target framework alone (dotnet build -f net10.0) the other folder
    # still holds a dll of older sources.
    $distinct = @($hashes.Values | Select-Object -Unique)
    if ($distinct.Count -ne 1 -or -not $distinct[0]) {
        $lines = ($versions | ForEach-Object { "  $_ source=$(if ($hashes[$_]) { $hashes[$_] } else { 'none' })" }) -join "`n"
        throw "The version folders do not hold one build (none: no source fingerprint):`n$lines`nBuild all versions before syncing."
    }

    $mutex = Enter-GameTestLock -WaitMinutes $LockWaitMinutes -FailIfGameRunning
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "The release target must not be a filesystem link: $target"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $target -Force)) {
        $kept = if ($item.PSIsContainer) { ($releaseDirs -contains $item.Name) -or ($keepDirs -contains $item.Name) } else { $Cfg.ReleaseFiles -contains $item.Name }
        if (-not $kept) { Remove-ReleaseItem $item.FullName }
        elseif ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Release items must not be filesystem links: $($item.FullName)" }
    }
    foreach ($dir in $releaseDirs) {
        $source = Join-Path $RepoRoot $dir
        $dest = Join-Path $target $dir
        if (Test-Path -LiteralPath $source -PathType Container) {
            robocopy $source $dest @robocopyOptions | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $dir (exit $LASTEXITCODE): is the game holding the files?" }
        }
        elseif (Test-Path -LiteralPath $dest) { Remove-ReleaseItem $dest }
    }
    foreach ($file in $Cfg.ReleaseFiles) {
        $source = Join-Path $RepoRoot $file
        $dest = Join-Path $target $file
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $dest -Force }
        elseif (Test-Path -LiteralPath $dest) { Remove-ReleaseItem $dest }
    }
    foreach ($version in $versions) {
        $repoDll = Join-Path $RepoRoot "$version\Assemblies\$DllName"
        $synced = Join-Path $target "$version\Assemblies\$DllName"
        if ((Get-FileHash -LiteralPath $repoDll).Hash -ne (Get-FileHash -LiteralPath $synced).Hash) { throw "The synced $synced differs from the repository's." }
    }
    foreach ($dir in $keepDirs) {
        if (Test-Path -LiteralPath (Join-Path $target $dir)) { Write-Host "Mods\$($Cfg.ModName)\$dir holds runtime data: move it out before a Workshop upload, and back afterwards." }
    }
    Write-Host "Synced the release files to $target (source=$($distinct[0]))"
}
finally {
    Exit-GameTestLock $mutex
}
$global:LASTEXITCODE = 0
