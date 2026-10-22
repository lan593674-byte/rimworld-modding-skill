# Launches the game in a visible window and lets the mod's VisualCapture take its screenshots into
# <Test>\shots\<Language>. The game logs "[CAPTURE] PLAN <n>" first, "[CAPTURE] SHOT <file>" for each picture and
# "[CAPTURE] DONE" at the end; every announced file must exist and be larger than MinShotBytes. The agent then
# looks at every picture (overlaps, clipped text, misplaced controls).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\run-capture.ps1 -Language ChineseSimplified
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('vanilla', 'core', 'full')]
    [string]$Profile = 'vanilla',
    [ValidateSet('ChineseSimplified', 'English')]
    [string]$Language = 'English',
    [ValidateRange(1, 7200)]
    [int]$TimeoutSeconds = 600,
    [string[]]$ExcludeMods = @(),
    [string]$ModList = '',
    # The window size comes from the profile's Prefs.xml on both branches.
    [int]$Width = 1280,
    [int]$Height = 720,
    # The game's UI scale option and its "disable tiny text" option, written to the profile's Prefs.xml.
    [string]$UIScale = '1',
    [switch]$DisableTinyText,
    # Copy the pictures and the log here before the lock is released: the next capture clears the shots folder.
    [string]$SaveTo = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GameRuntime.ps1')
if ($Profile -eq 'full' -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 3600 }
$a = '-' + $Cfg.ArgPrefix + '-'
$p = $LogPrefixPattern
$shotDir = Join-Path (Join-Path $TestRoot 'shots') $Language
$mutex = $null
$result = 1
$failure = $null
$shots = @()
$logPath = $null
try {
    # Lock first: preparing syncs the release files and rewrites the shared profile.
    $mutex = Enter-GameTestLock
    & (Join-Path $PSScriptRoot 'run-selftest.ps1') -PrepareOnly -Profile $Profile -Language $Language -ModList $ModList `
        -ExcludeMods $ExcludeMods -ScreenWidth $Width -ScreenHeight $Height -UIScale $UIScale -DisableTinyText:$DisableTinyText
    if ($LASTEXITCODE -ne 0) { throw 'Preparing the test profile failed.' }
    $profileRoot = Join-Path $TestRoot $Profile
    $logPath = Join-Path $profileRoot 'capture.log'
    if (Test-Path -LiteralPath $shotDir) { Get-ChildItem -LiteralPath $shotDir -Filter '*.png' | Remove-Item -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null
    $folder = Get-ReleaseFolder
    $arguments = @('-quicktest', ($a + 'selftest'), ($a + 'capture'), ($a + 'shots=' + $shotDir), "-savedatafolder=$profileRoot")
    $run = Invoke-GameRun -Arguments $arguments -LogPath $logPath -WindowStyle Normal -TimeoutSeconds $TimeoutSeconds `
        -Done { param($log) Test-LogMatch $log ('(?m)^' + $p + ' \[CAPTURE\] DONE') }
    Write-ModLines $run.Log
    Write-Host "Log: $logPath"
    $failure = $run.Failure
    $buildFailure = Test-LoadedBuild $run.Log $folder
    if ($buildFailure -and -not $failure) { $failure = $buildFailure }
    $plan = Find-LogMatch $run.Log ('(?m)^' + $p + ' \[CAPTURE\] PLAN (\d+)')
    $shots = @([regex]::Matches($run.Log, '(?m)^' + $p + ' \[CAPTURE\] SHOT (\S+)') | ForEach-Object { $_.Groups[1].Value.Trim() })
    if (-not $failure -and -not $plan.Success) { $failure = 'The capture announced no plan ([CAPTURE] PLAN n).' }
    elseif (-not $failure -and $shots.Count -ne [int]$plan.Groups[1].Value) { $failure = "The capture planned $($plan.Groups[1].Value) pictures but took $($shots.Count)." }
    foreach ($name in $shots) {
        $path = Join-Path $shotDir $name
        if (-not (Test-Path -LiteralPath $path)) { Write-Host "MISSING $path"; if (-not $failure) { $failure = "Missing screenshot: $path" }; continue }
        $size = (Get-Item -LiteralPath $path).Length
        Write-Host ('{0}  {1:N0} bytes' -f $path, $size)
        if ($size -lt $Cfg.MinShotBytes -and -not $failure) { $failure = "Screenshot too small (black or empty?): $path" }
    }
    if (-not $failure) { Write-Host "Captured $($shots.Count) pictures in $shotDir"; $result = 0 }
}
catch { $failure = $_.Exception.Message }
finally {
    try {
        if ($SaveTo -and $shots.Count -gt 0) {
            New-Item -ItemType Directory -Path $SaveTo -Force | Out-Null
            foreach ($name in $shots) { $path = Join-Path $shotDir $name; if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $SaveTo -Force } }
            if ($logPath -and (Test-Path -LiteralPath $logPath)) { Copy-Item -LiteralPath $logPath -Destination (Join-Path $SaveTo 'capture.log') -Force }
            Write-Host "Saved the pictures to $SaveTo"
        }
    }
    catch { $result = 1; if (-not $failure) { $failure = "Could not save the pictures: $($_.Exception.Message)" } }
    Exit-GameTestLock $mutex
}
if ($failure) { $result = 1; Write-Error $failure -ErrorAction Continue }
exit $result
