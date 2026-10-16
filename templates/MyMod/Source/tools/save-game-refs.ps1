# Copies the assemblies a 1.7 (Waylith) build compiles against out of the installed game into <dev root>\GameRefs,
# so the 1.7 build keeps working while Steam has 1.6 installed. Run it with 1.7 installed after each game update,
# then set Rw17Version in Source\GameRefs.props to the folder it names. Shared by all mods; a version folder is
# never changed once written.
#   GameRefs\<version>\     the game's assemblies and its Version.txt (e.g. 1.7.4979-rev109)
#   GameRefs\Harmony-1.7\   0Harmony.dll from the Harmony mod's 1.7 folder (Harmony updates on its own)
[CmdletBinding(PositionalBinding = $false)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GameRuntime.ps1')
$refsRoot = Join-Path $DevRoot 'GameRefs'

if (-not (Test-WaylithGame)) { throw "The game in $GameRoot is not 1.7 (no RimWorld.exe): switch Steam to the 1.7 beta first." }
$version = (Get-GameVersion) -replace '\s+', '-'
$gameFiles = @('Assembly-CSharp.dll', 'UnityStubs.dll', 'Waylith.dll', 'Waylith.UnityCompat.dll', 'RimWorld.dll',
    'Microsoft.Extensions.Logging.Abstractions.dll', 'Version.txt')

function Copy-Ref([string]$source, [string]$targetDir, [bool]$mayReplace) {
    $target = Join-Path $targetDir (Split-Path -Leaf $source)
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash) { return }
        if (-not $mayReplace) { throw "$target differs from the game's copy although the game version ($version) is the same: the build changed without a new version number; save it under a new folder name." }
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "Copied $source"
}

$gameDir = Join-Path $refsRoot $version
New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
foreach ($file in $gameFiles) { Copy-Ref (Join-Path $GameRoot $file) $gameDir $false }

$harmonyMod = Find-ModFolder 'brrainz.harmony'
if ($harmonyMod) {
    $harmony = Join-Path $harmonyMod '1.7\Assemblies\0Harmony.dll'
    if (-not (Test-Path -LiteralPath $harmony)) { throw "Harmony has no 1.7 build: $harmony" }
    $harmonyDir = Join-Path $refsRoot 'Harmony-1.7'
    New-Item -ItemType Directory -Path $harmonyDir -Force | Out-Null
    Copy-Ref $harmony $harmonyDir $true
    Write-Host "Harmony $([Reflection.AssemblyName]::GetAssemblyName((Join-Path $harmonyDir '0Harmony.dll')).Version)"
}
else { Write-Warning 'Harmony (brrainz.harmony) is not installed: mods that use it cannot build for 1.7 until it is.' }
Write-Host "1.7 reference assemblies: $gameDir. Set <Rw17Version>$version</Rw17Version> in Source\GameRefs.props."
