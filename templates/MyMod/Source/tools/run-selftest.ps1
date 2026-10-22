# Launches the game on an isolated test profile and judges the mod's in-game self-test from the game log.
# Smoke only checks that the mod loaded and a map was generated; SelfTest runs every registered scenario and the
# game quits after "[SELFTEST] DONE". Exit code 0 only when every scenario passed and the game loaded this build.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\run-selftest.ps1 -Profile vanilla -Language English
#
# powershell -File passes "-ExcludeMods a,b" as one string; commas are split here. -ExtraArgs takes one value
# with -File; for several use: powershell -Command "& 'Source\tools\run-selftest.ps1' -ExtraArgs @('-a','-b'); exit $LASTEXITCODE"
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('vanilla', 'core', 'full')]
    [string]$Profile = 'vanilla',
    [ValidateSet('Smoke', 'SelfTest')]
    [string]$Mode = 'SelfTest',
    # Default 900 s, 3600 s for full (a long mod list loads for many minutes).
    [ValidateRange(1, 7200)]
    [int]$TimeoutSeconds = 900,
    # Default Minimized (see Get-WindowLaunch), Normal for full: some mods crash while loading in a window that
    # has drawn no text yet.
    [ValidateSet('Hidden', 'Minimized', 'Normal')]
    [string]$WindowStyle = 'Minimized',
    # Keep running after a scenario FAIL so every scenario reports (still exits non-zero).
    [switch]$ContinueOnFail,
    # Full profile: packageIds to drop as well (compatibility bisection).
    [string[]]$ExcludeMods = @(),
    # Full profile: copy the mod list from this ModsConfig.xml (a path, or a file name in <dev root>\ModLists).
    [string]$ModList = '',
    [ValidateSet('First', 'Middle', 'Last')]
    [string]$LoadPosition = 'Last',
    [ValidateSet('ChineseSimplified', 'English')]
    [string]$Language = 'English',
    [int]$ScreenWidth = 1280,
    [int]$ScreenHeight = 720,
    # The game's UI scale option and its "disable tiny text" option, written to the profile's Prefs.xml.
    [string]$UIScale = '1',
    [switch]$DisableTinyText,
    # Sync and write the test profile only, no game: for other scripts, which call it in-process (& ...) while
    # they hold the test lock.
    [switch]$PrepareOnly,
    # Appended unchanged, one game argument per entry.
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GameRuntime.ps1')
$ExcludeMods = @($ExcludeMods | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Profile -eq 'full') {
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 3600 }
    if (-not $PSBoundParameters.ContainsKey('WindowStyle')) { $WindowStyle = 'Normal' }
}
$a = '-' + $Cfg.ArgPrefix + '-'
$p = $LogPrefixPattern
$mutex = $null
$result = 1
$failure = $null
try {
    $mutex = Enter-GameTestLock
    # Sync only under the lock: another session's running game uses the published copy.
    & (Join-Path $PSScriptRoot 'sync-to-steam.ps1')
    $profileRoot = New-TestProfile -Profile $Profile -ModList $ModList -ExcludeMods $ExcludeMods -LoadPosition $LoadPosition `
        -Language $Language -ScreenWidth $ScreenWidth -ScreenHeight $ScreenHeight -UIScale $UIScale -DisableTinyText:$DisableTinyText
    if ($PrepareOnly) {
        Write-Host "Prepared profile: $profileRoot"
        $result = 0
    }
    else {
        $folder = Get-ReleaseFolder
        $arguments = @('-quicktest', ($a + 'selftest'))
        if ($Mode -eq 'Smoke') { $arguments += ($a + 'smoke') }
        $arguments += @("-savedatafolder=$profileRoot") + $ExtraArgs
        $logPath = Join-Path $profileRoot 'selftest.log'
        $done = if ($Mode -eq 'Smoke') {
            { param($log) Test-LogMatch $log ('(?m)^' + $p + ' \[SMOKE\] map generated') }
        } else {
            { param($log) Test-LogMatch $log ('(?m)^' + $p + ' \[SELFTEST\] DONE ') }
        }
        $tolerate = if ($ContinueOnFail) { @('scenario') } else { @() }
        $run = Invoke-GameRun -Arguments $arguments -LogPath $logPath -Done $done -WindowStyle $WindowStyle `
            -TimeoutSeconds $TimeoutSeconds -Tolerate $tolerate
        Write-ModLines $run.Log
        Write-Host "Log: $logPath"
        $failure = $run.Failure
        if (-not $failure -and $Mode -eq 'SelfTest') {
            $summary = Find-LogMatch $run.Log ('(?m)^' + $p + ' \[SELFTEST\] DONE passed=(\d+) failed=(\d+)')
            if (-not $summary.Success) { $failure = 'No [SELFTEST] DONE line.' }
            elseif ([int]$summary.Groups[2].Value -gt 0) { $failure = "$($summary.Groups[2].Value) scenario(s) failed." }
            elseif ([int]$summary.Groups[1].Value -eq 0) { $failure = 'No scenario ran (passed=0): are the scenarios registered?' }
        }
        # Printed even after another failure, which usually explains this one (a crash before loading).
        $buildFailure = Test-LoadedBuild $run.Log $folder
        if ($buildFailure) {
            Write-Host "FAILED: $buildFailure"
            if (-not $failure) { $failure = $buildFailure }
        }
        if (-not $failure) {
            Write-Host ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0} passed in {1:F1}s.', $Mode, $run.Seconds))
            $result = 0
        }
    }
}
catch { $failure = $_.Exception.Message }
finally { Exit-GameTestLock $mutex }
if ($failure) { Write-Error $failure -ErrorAction Continue }
exit $result
