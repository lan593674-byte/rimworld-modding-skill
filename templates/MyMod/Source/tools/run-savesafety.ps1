# Save-safety acceptance (skill section 4, "3. save safety"):
#   1. vanilla profile: the mod's self-test builds a save holding all of the mod's data (-<prefix>-makesave)
#      and logs "<prefix> [SELFTEST] FIXTURE <save name> <summary>".
#   2. uninstalled profile (the mod removed): the save loads, plays and resaves; while loading only the expected
#      "type or def not found" errors appear, nothing in any later phase.
#   3. the resaved file loads with no error at all and has no trace of the mod left.
#   4. reinstall profile: the original save loads with the mod back (-<prefix>-reportload); the mod's summary
#      ("<prefix> loaded save: <summary>") equals the fixture's, with no error.
#   5. mid-game add: a save that never had the mod loads with it, with no error.
#   -WorkPriorities (mods that add a WorkTypeDef): measures how the colonists' work priorities shift when the mod
#   is removed from a full-profile game (vanilla behaviour, see the skill's pitfall about work priorities).
# The test-only helper mod (TestLoaderMod) does the loading and saving; it is copied to Mods\GameTestLoader for the
# run and always removed afterwards. Exit code 0 only when every step passed.
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateRange(60, 7200)]
    [int]$TimeoutSeconds = 900,
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$SaveName = 'SaveSafety',
    [ValidateSet('Hidden', 'Minimized', 'Normal')]
    [string]$WindowStyle = 'Minimized',
    [ValidateSet('ChineseSimplified', 'English')]
    [string]$Language = 'English',
    [switch]$WorkPriorities,
    # Full profile, for -WorkPriorities: as in run-selftest.ps1.
    [string]$ModList = '',
    # Finish the remaining steps after a failed check; still exits non-zero.
    [switch]$ContinueOnFail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GameRuntime.ps1')
$a = '-' + $Cfg.ArgPrefix + '-'
$p = $LogPrefixPattern
$ns = [regex]::Escape($Cfg.CodeNamespace)
$dp = [regex]::Escape($Cfg.DefPrefix)
$helperId = 'gametest.testloader'
$helperSource = Join-Path $PSScriptRoot 'TestLoaderMod'
$helperTarget = Join-Path $GameRoot 'Mods\GameTestLoader'
$helperInstalled = $false
$mutex = $null
$failures = New-Object 'Collections.Generic.List[string]'
$failure = $null
# Errors that loading a save without the mod is expected to log (load phase only): its classes and defs are gone,
# and a building whose ThingDef is gone takes some vanilla fallout with it.
$allowed = @(
    "Could not find class $ns\.",
    'Can.t load abstract class Verse\.',
    "Could not load reference to \S+ (?:named|with defName|with loadID) \S*$dp",
    "Could not find \S+ named $dp",
    'Could not load reference to Verse\.AI\.Job with loadID Job_\d+',
    'SaveableFromNode exception: System\.NullReferenceException',
    'Exception registering Verse\.Building ',
    'Could not resolve cross refs: System\.NullReferenceException',
    'Exception spawning loaded thing null:'
) + @($Cfg.AllowedUninstallErrors)
$allowedPattern = ($allowed | ForEach-Object { "(?:$_)" }) -join '|'
# Traces of the mod in a save written without it (the helper's own entry in the save's mod list is fine).
$leftoverPattern = "(?i)<li>$([regex]::Escape($Cfg.PackageId))</li>|\b$ns\.[A-Z]|\b$dp"

function Assert-Step([bool]$condition, [string]$message) {
    if ($condition) { return }
    $failures.Add($message)
    Write-Host "CHECK FAILED: $message"
    if (-not $ContinueOnFail) { throw $message }
}

# Runs the helper (or the self-test) once and returns the log. Errors in the log are judged by the caller from
# the helper's own error list, so only a crash or a startup failure stops the run here.
function Invoke-Phase([string[]]$arguments, [string]$profileRoot, [string]$logName, [string]$donePattern) {
    $run = Invoke-GameRun -Arguments ($arguments + @("-testloader-timeout=$TimeoutSeconds", "-savedatafolder=$profileRoot")) `
        -LogPath (Join-Path $profileRoot $logName) -WindowStyle $WindowStyle -TimeoutSeconds ($TimeoutSeconds + 60) `
        -Tolerate @('error', 'scenario') -Done ([scriptblock]::Create("param(`$log) Test-LogMatch `$log '$donePattern'"))
    if ($run.Failure) { throw "$logName`: $($run.Failure) Log: $(Join-Path $profileRoot $logName)" }
    return $run.Log
}

function Assert-HelperRun([string]$log, [string]$label) {
    $fail = Find-LogMatch $log '\[TESTLOADER\] FAIL[^\r\n]*'
    if ($fail.Success) { throw "$label`: $($fail.Value)" }
    if ($log -notmatch '\[TESTLOADER\] LOADED ok') { throw "$label did not reach LOADED ok." }
    if ($log -notmatch '\[TESTLOADER\] (RESAVED|CREATED) ') { throw "$label did not save." }
}

# The helper's error list ("[TESTLOADER] ERROR <n> <phase>: <text>"). Startup errors come before any save is
# touched (vanilla itself logs some); they are printed but not judged.
function Get-HelperErrors([string]$log) {
    $all = @($log -split '\r?\n' | Where-Object { $_ -match '^\[TESTLOADER\] ERROR \d+ ' })
    $all | Where-Object { $_ -match '^\[TESTLOADER\] ERROR \d+ startup: ' } | ForEach-Object { Write-Host "  (startup, not judged) $_" }
    return , @($all | Where-Object { $_ -notmatch '^\[TESTLOADER\] ERROR \d+ startup: ' })
}

# A profile built from $base's mod list: without the mod, or with it, and the helper at the end.
function New-HelperProfile([string]$name, [string]$base, [bool]$withMod) {
    $root = Join-Path $TestRoot $name
    New-Item -ItemType Directory -Path (Join-Path $root 'Config'), (Join-Path $root 'Saves') -Force | Out-Null
    $mods = New-Object Xml.XmlDocument
    $mods.Load((Join-Path $TestRoot "$base\Config\ModsConfig.xml"))
    $ids = @(Get-ActiveIds $mods | Where-Object { $_ -ine $Cfg.PackageId -and $_ -ine $helperId })
    if ($withMod) { $ids += $Cfg.PackageId }
    Set-ActiveIds $mods ($ids + $helperId)
    $mods.Save((Join-Path $root 'Config\ModsConfig.xml'))
    Copy-Item -LiteralPath (Join-Path $TestRoot "$base\Config\Prefs.xml") -Destination (Join-Path $root 'Config\Prefs.xml') -Force
    Get-ChildItem -LiteralPath (Join-Path $root 'Saves') -File | Remove-Item -Force
    return $root
}

function Install-Helper {
    if (Test-Path -LiteralPath $helperTarget) { throw "$helperTarget already exists (left by a killed run?): check and remove it, then run again." }
    $script:helperInstalled = $true
    New-Item -ItemType Directory -Path $helperTarget -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $helperSource 'About') -Destination $helperTarget -Recurse
    Copy-Item -LiteralPath (Join-Path $helperSource 'LoadFolders.xml') -Destination $helperTarget
    foreach ($version in $Cfg.GameVersions) {
        Copy-Item -LiteralPath (Join-Path $helperSource "bin\$version") -Destination (Join-Path $helperTarget $version) -Recurse
    }
}

function Remove-Helper {
    $resolved = [IO.Path]::GetFullPath($helperTarget)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $GameRoot 'Mods')) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe helper path: $resolved" }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

# Steps 2 and 3: load without the mod, then load what the helper resaved.
function Test-Uninstall([string]$name, [string]$source, [string]$root) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $root "Saves\$name.rws") -Force
    $load1 = Invoke-Phase @("-testloader-loadsave=$name") $root "load1-$name.log" '\[TESTLOADER\] END'
    Assert-HelperRun $load1 "Uninstalled load ($name)"
    $errors1 = Get-HelperErrors $load1
    $unexpected = @($errors1 | Where-Object { $_ -notmatch '^\[TESTLOADER\] ERROR \d+ load: ' -or $_ -notmatch $allowedPattern })
    Write-Host "Uninstalled load: $($errors1.Count) errors, $($unexpected.Count) unexpected"
    $errors1 | ForEach-Object { Write-Host "  $_" }
    Assert-Step ($unexpected.Count -eq 0) "Loading $name without the mod logged $($unexpected.Count) unexpected errors (load1-$name.log)."
    $load2 = Invoke-Phase @("-testloader-loadsave=$name-resaved") $root "load2-$name.log" '\[TESTLOADER\] END'
    Assert-HelperRun $load2 "Resaved load ($name)"
    $errors2 = Get-HelperErrors $load2
    $errors2 | ForEach-Object { Write-Host "  $_" }
    Assert-Step ($errors2.Count -eq 0) "The save resaved without the mod still logs $($errors2.Count) errors (load2-$name.log)."
    $text = [IO.File]::ReadAllText((Join-Path $root "Saves\$name-resaved.rws"))
    $left = [regex]::Matches($text, $leftoverPattern)
    Write-Host "Traces of the mod in the resaved file: $($left.Count)"
    Assert-Step ($left.Count -eq 0) "The resaved $name still names the mod: $(@($left | Select-Object -First 3 | ForEach-Object { $_.Value }) -join ', ')"
}

function Test-WorkPriorities {
    & (Join-Path $PSScriptRoot 'run-selftest.ps1') -PrepareOnly -Profile full -ModList $ModList -Language $Language
    if ($LASTEXITCODE -ne 0) { throw 'Preparing the full profile failed.' }
    $rowPattern = '\[TESTLOADER\] WORK pawn=(\S+) def=(\S+) index=(\d+) priority=(\d+) package=(\S+)'
    $beforeRoot = New-HelperProfile 'full-enabled' 'full' $true
    $before = Invoke-Phase @('-quicktest', "-testloader-makesave=$SaveName-work", '-testloader-workpriorities') $beforeRoot 'priorities-before.log' '\[TESTLOADER\] END'
    Assert-HelperRun $before 'Full priority fixture'
    $rows = @([regex]::Matches($before, $rowPattern))
    if ($rows.Count -eq 0) { throw 'The full priority fixture reported no work types.' }
    $afterRoot = New-HelperProfile 'full-uninstalled' 'full' $false
    Copy-Item -LiteralPath (Join-Path $beforeRoot "Saves\$SaveName-work.rws") -Destination (Join-Path $afterRoot "Saves\$SaveName-work.rws") -Force
    $after = Invoke-Phase @("-testloader-loadsave=$SaveName-work", '-testloader-workpriorities', "-testloader-pawn=$($rows[0].Groups[1].Value)") $afterRoot 'priorities-after.log' '\[TESTLOADER\] END'
    Assert-HelperRun $after 'Full priority load'
    $afterRows = @{}
    foreach ($row in [regex]::Matches($after, $rowPattern)) { $afterRows[$row.Groups[2].Value] = $row }
    $table = @(foreach ($row in $rows) {
        $def = $row.Groups[2].Value
        if ($def.StartsWith($Cfg.DefPrefix)) { continue }
        if (-not $afterRows.ContainsKey($def)) { Write-Host "Work type gone after removing the mod: $def"; continue }
        $loaded = $afterRows[$def]
        [pscustomobject]@{ Def = $def; Package = $row.Groups[5].Value; Before = $row.Groups[4].Value; After = $loaded.Groups[4].Value
            Shifted = $row.Groups[4].Value -ne $loaded.Groups[4].Value }
    })
    $csv = Join-Path $TestRoot 'work-priorities.csv'
    $table | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $table | Format-Table -AutoSize | Out-Host
    Write-Host "Work types whose priority shifted: $(@($table | Where-Object Shifted).Count) of $($table.Count) (written to $csv; report them, they are vanilla behaviour)."
}

try {
    $mutex = Enter-GameTestLock
    Write-Host '== Build the test-only helper'
    # English output: a localized dotnet writes in the console code page, which comes through garbled here.
    $env:DOTNET_CLI_UI_LANGUAGE = 'en'
    & dotnet build (Join-Path $helperSource 'GameTestLoader.csproj') -c Release -nologo -v q | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Building the helper failed.' }
    if ($WorkPriorities) {
        Install-Helper
        Test-WorkPriorities
    }
    else {
        & (Join-Path $PSScriptRoot 'run-selftest.ps1') -PrepareOnly -Profile vanilla -Language $Language
        if ($LASTEXITCODE -ne 0) { throw 'Preparing the vanilla profile failed.' }
        $folder = Get-ReleaseFolder
        $vanillaRoot = Join-Path $TestRoot 'vanilla'
        Get-ChildItem -LiteralPath (Join-Path $vanillaRoot 'Saves') -Filter "$SaveName*" -File -ErrorAction SilentlyContinue | Remove-Item -Force

        Write-Host '== 1. Make a save with all of the mod''s data (vanilla profile)'
        $run = Invoke-GameRun -Arguments @('-quicktest', ($a + 'selftest'), ($a + 'makesave=' + $SaveName), "-savedatafolder=$vanillaRoot") `
            -LogPath (Join-Path $vanillaRoot 'savesafety-make.log') -WindowStyle $WindowStyle -TimeoutSeconds $TimeoutSeconds `
            -Done { param($log) Test-LogMatch $log ('(?m)^' + $p + ' \[SELFTEST\] DONE ') }
        Write-ModLines $run.Log
        if ($run.Failure) { throw "Making the save failed: $($run.Failure)" }
        $build = Test-LoadedBuild $run.Log $folder
        if ($build) { throw $build }
        $fixture = Find-LogMatch $run.Log ('(?m)^' + $p + ' \[SELFTEST\] FIXTURE (\S+) ([^\r\n]+)')
        if (-not $fixture.Success) { throw 'The fixture line ([SELFTEST] FIXTURE <save name> <summary>) is missing.' }
        $original = Join-Path $vanillaRoot "Saves\$($fixture.Groups[1].Value).rws"
        if (-not (Test-Path -LiteralPath $original)) { throw "The fixture save is missing: $original" }
        $summary = $fixture.Groups[2].Value.Trim()
        Write-Host "Fixture: $original $summary"

        Install-Helper
        Write-Host '== 2-3. Load it without the mod, then load the resaved file'
        $uninstalledRoot = New-HelperProfile 'uninstalled' 'vanilla' $false
        Test-Uninstall $SaveName $original $uninstalledRoot

        Write-Host '== 4. Load the original save with the mod back'
        $reinstallRoot = New-HelperProfile 'reinstall' 'vanilla' $true
        Copy-Item -LiteralPath $original -Destination (Join-Path $reinstallRoot "Saves\$SaveName.rws") -Force
        $load3 = Invoke-Phase @("-testloader-loadsave=$SaveName", ($a + 'reportload')) $reinstallRoot 'load3.log' '\[TESTLOADER\] END'
        Assert-HelperRun $load3 'Reinstall load'
        $build = Test-LoadedBuild $load3 $folder
        if ($build) { throw $build }
        $errors3 = Get-HelperErrors $load3
        $errors3 | ForEach-Object { Write-Host "  $_" }
        $loaded = Find-LogMatch $load3 ('(?m)^' + $p + ' loaded save: ([^\r\n]+)')
        Assert-Step $loaded.Success 'The mod did not report the loaded save (-reportload).'
        if ($loaded.Success) {
            Write-Host "Reinstall summary: $($loaded.Groups[1].Value.Trim()) (fixture: $summary)"
            Assert-Step ($loaded.Groups[1].Value.Trim() -eq $summary) 'The mod''s data differ after removing and adding it back.'
        }
        Assert-Step ($errors3.Count -eq 0) "Loading the original save with the mod logged $($errors3.Count) errors."

        Write-Host '== 5. Add the mod to a save that never had it'
        $virgin = "$SaveName-virgin"
        $make = Invoke-Phase @('-quicktest', "-testloader-makesave=$virgin") $uninstalledRoot 'virgin-make.log' '\[TESTLOADER\] END'
        Assert-HelperRun $make 'Save without the mod'
        $virginPath = Join-Path $uninstalledRoot "Saves\$virgin.rws"
        if ([regex]::IsMatch([IO.File]::ReadAllText($virginPath), $leftoverPattern)) { throw 'The save made without the mod names the mod.' }
        Copy-Item -LiteralPath $virginPath -Destination (Join-Path $reinstallRoot "Saves\$virgin.rws") -Force
        $add = Invoke-Phase @("-testloader-loadsave=$virgin", ($a + 'reportload')) $reinstallRoot 'add.log' '\[TESTLOADER\] END'
        Assert-HelperRun $add 'Mid-game add'
        $addErrors = Get-HelperErrors $add
        $addErrors | ForEach-Object { Write-Host "  $_" }
        Assert-Step ($addErrors.Count -eq 0) "Adding the mod to a running game logged $($addErrors.Count) errors (add.log)."
        Assert-Step (Test-LogMatch $add ('(?m)^' + $p + ' loaded save: ')) 'The mod did not start in a save that never had it.'
    }
    if ($failures.Count -gt 0) { $failure = "$($failures.Count) check(s) failed." }
    else { Write-Host 'Save safety passed.' }
}
catch { $failure = $_.Exception.Message }
finally {
    try { if ($helperInstalled) { Remove-Helper; Write-Host "Helper removed: $(-not (Test-Path -LiteralPath $helperTarget))" } }
    catch { if (-not $failure) { $failure = "Could not remove the helper: $($_.Exception.Message)" } }
    Exit-GameTestLock $mutex
}
if ($failure) { Write-Error $failure -ErrorAction Continue; exit 1 }
exit 0
