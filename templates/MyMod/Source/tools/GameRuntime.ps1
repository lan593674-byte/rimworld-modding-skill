# Shared by every test script (dot-source it). Reads GameTest.psd1, finds the game, and holds everything the
# scripts have in common: the cross-mod test lock, the 1.7 log handling, test profiles, launching and judging a
# game run, and the loaded-build check. Mod-specific settings live in GameTest.psd1 only.
#
# What differs between the game branches:
#   1.6 (Unity): RimWorldWin64.exe; the log goes wherever -logfile says; errors are not marked in the log.
#   1.7 (Waylith, .NET 10): RimWorld.exe; -logfile is gone and every instance writes
#     <user data>\Logs\Player.log (the previous one is renamed Player-prev.log), each line prefixed
#     "yyyy-MM-dd HH:mm:ss.fff LEVEL [category] ". A minimized window renders no frames (no OnGUI), so the
#     scripts use -NoWindow instead; -NoCrashDialog stops a crash from waiting for a click.

Set-StrictMode -Version Latest

$script:GameTestLockName = 'Local\RimWorld.GameTest'
$script:UserDataRoot = Join-Path $env:USERPROFILE 'AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios'

# GameTest.psd1 as a hashtable. Parsed from UTF-8 text (Import-PowerShellDataFile in Windows PowerShell 5.1
# would read a file without a byte order mark in the ANSI code page); only literal data is accepted.
function Read-GameTestConfig([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Test settings missing: $path" }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Cannot parse ${path}: $($errors[0].Message)" }
    $table = $ast.Find({ param($node) $node -is [Management.Automation.Language.HashtableAst] }, $false)
    if ($null -eq $table) { throw "$path holds no @{ ... } table." }
    return $table.SafeGetValue()
}

# The RimWorld folder of the Steam library that has the game.
function Find-RimWorldRoot {
    if ($env:RIMWORLD_GAME_ROOT) { return $env:RIMWORLD_GAME_ROOT }
    $steam = $null
    try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) { throw 'Steam was not found in the registry: set GameRoot in GameTest.psd1 or RIMWORLD_GAME_ROOT.' }
    $libraries = @([IO.Path]::GetFullPath($steam))
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            $libraries += ($match.Groups[1].Value -replace '\\\\', '\')
        }
    }
    foreach ($library in $libraries) {
        $candidate = Join-Path $library 'steamapps\common\RimWorld'
        if (Test-Path -LiteralPath (Join-Path $candidate 'Version.txt')) { return $candidate }
    }
    throw "RimWorld was not found in the Steam libraries ($($libraries -join ', ')): set GameRoot in GameTest.psd1."
}

$script:Cfg = Read-GameTestConfig (Join-Path $PSScriptRoot 'GameTest.psd1')
$script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:DevRoot = Split-Path -Parent $script:RepoRoot
$script:TestRoot = Join-Path $script:DevRoot ($script:Cfg.ModName + 'Test')
$script:ModListsDir = Join-Path $script:DevRoot 'ModLists'
$script:LogBackupDir = Join-Path $script:DevRoot 'player-log-backup'
$script:GameRoot = if ($script:Cfg.GameRoot) { $script:Cfg.GameRoot } else { Find-RimWorldRoot }
$script:GameRoot = [IO.Path]::GetFullPath($script:GameRoot)
$script:WorkshopRoot = [IO.Path]::GetFullPath((Join-Path $script:GameRoot '..\..\workshop\content\294100'))
$script:ModTarget = Join-Path $script:GameRoot ('Mods\' + $script:Cfg.ModName)
$script:DllName = $script:Cfg.ModName + '.dll'
$script:LogPrefixPattern = [regex]::Escape($script:Cfg.LogPrefix)

# ---------------------------------------------------------------------------------------------------------
# Game version

function Get-GameExe {
    $waylith = Join-Path $script:GameRoot 'RimWorld.exe'
    if (Test-Path -LiteralPath $waylith) { return $waylith }
    return Join-Path $script:GameRoot 'RimWorldWin64.exe'
}

function Test-WaylithGame { return (Split-Path -Leaf (Get-GameExe)) -eq 'RimWorld.exe' }

# "1.7.4979 rev109"
function Get-GameVersion { return (Get-Content -LiteralPath (Join-Path $script:GameRoot 'Version.txt') -TotalCount 1).Trim() }

# The version folder the installed game loads ("1.6", "1.7").
function Get-ReleaseFolder {
    $version = Get-GameVersion
    foreach ($folder in $script:Cfg.GameVersions) {
        if ($version -match ('^' + [regex]::Escape($folder) + '(?![0-9])')) { return $folder }
    }
    throw "The installed game is $version; the mod supports $($script:Cfg.GameVersions -join ', ') (GameVersions in GameTest.psd1)."
}

function Test-GameRunning { return @(Get-Process -Name RimWorldWin64, RimWorld -ErrorAction SilentlyContinue).Count -gt 0 }

# ---------------------------------------------------------------------------------------------------------
# Loaded-build check. The build embeds a fingerprint of the sources (Source\SourceHash.targets) and the mod
# logs "<prefix> loaded build=<version folder> source=<hash>" at startup.

function Get-SourceHash([string]$dllPath) {
    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { return $null }
    # Latin-1 keeps one character per byte. In the attribute blob the key is followed by the value's length,
    # 64 = 0x40 = '@', and the value itself.
    $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dllPath))
    $match = [regex]::Match($text, [regex]::Escape($script:Cfg.ModName + '.SourceHash') + '@([0-9a-f]{64})')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

# $null when the log shows the game loaded the dll of $folder built from the current sources, else the problem.
function Test-LoadedBuild([string]$log, [string]$folder) {
    $hash = Get-SourceHash (Join-Path $script:RepoRoot "$folder\Assemblies\$($script:DllName)")
    if (-not $hash) { return "The $folder dll has no source fingerprint: cannot tell which build the game loaded." }
    if ($log.Contains("loaded build=$folder source=$hash")) { return $null }
    return "The log has no 'loaded build=$folder source=$hash': the game did not load the $folder dll built from these sources."
}

# ---------------------------------------------------------------------------------------------------------
# One game at a time across all mods' test scripts: they share the Mods folder, the test profiles and, on 1.7,
# the one Player.log. The lock is a named mutex. It is re-entrant on the same thread, so a script that holds it
# can call another test script in-process (& script.ps1); only the outermost holder does the set-up and the
# clean-up below.

if (-not (Test-Path variable:global:GameTestLockDepth)) { $global:GameTestLockDepth = 0 }

# Test games left running by a script that was killed (its finally blocks never ran). Only called while holding
# the lock, so no other test of ours can be running: anything started with a test profile is an orphan.
function Stop-OrphanTestGame {
    $marker = '-savedatafolder=' + $script:DevRoot.TrimEnd('\') + '\'
    foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='RimWorld.exe' OR Name='RimWorldWin64.exe'" -ErrorAction SilentlyContinue)) {
        if ($proc.CommandLine -and $proc.CommandLine.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "Stopping a test game left behind by an earlier run: pid $($proc.ProcessId)"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $proc.ProcessId -Timeout 15 -ErrorAction SilentlyContinue
        }
    }
}

# Whether a 1.7 log was written by a test launch (its Command line points -savedatafolder into the dev root).
function Test-TestLog([string]$path) {
    $header = @(Get-Content -LiteralPath $path -TotalCount 12 -ErrorAction SilentlyContinue) -join "`n"
    return $header -match ('(?m)^Command:.*-savedatafolder=' + [regex]::Escape($script:DevRoot.TrimEnd('\') + '\'))
}

# 1.7 overwrites the player's own Player.log and Player-prev.log. The outermost lock holder keeps a copy and puts
# it back at the end. A "pending" marker in the backup folder means a copy was never put back (a killed run).
function Backup-PlayerLog {
    $logDir = Join-Path $script:UserDataRoot 'Logs'
    $pending = Join-Path $script:LogBackupDir 'pending'
    New-Item -ItemType Directory -Path $script:LogBackupDir -Force | Out-Null
    if (Test-Path -LiteralPath $pending) {
        if (Test-TestLog (Join-Path $logDir 'Player.log')) {
            # The current logs are a test's: the saved pair is still the player's. Keep it as a whole.
            Write-Host 'An earlier test run did not put the player''s log back; the saved copy is kept.'
            return
        }
        # The player played since: the current logs are newer than the saved pair.
    }
    foreach ($name in 'Player.log', 'Player-prev.log') {
        $source = Join-Path $logDir $name
        $copy = Join-Path $script:LogBackupDir $name
        if (Test-Path -LiteralPath $copy) { Remove-Item -LiteralPath $copy -Force }
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $copy -Force }
    }
    Set-Content -LiteralPath $pending -Value (Get-Date -Format o)
}

function Restore-PlayerLog {
    $logDir = Join-Path $script:UserDataRoot 'Logs'
    $pending = Join-Path $script:LogBackupDir 'pending'
    if (-not (Test-Path -LiteralPath $pending)) { return }
    foreach ($name in 'Player.log', 'Player-prev.log') {
        $target = Join-Path $logDir $name
        $copy = Join-Path $script:LogBackupDir $name
        if (Test-Path -LiteralPath $copy) { Copy-Item -LiteralPath $copy -Destination $target -Force }
        elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    }
    Remove-Item -LiteralPath $pending -Force
}

# Takes the lock. Waits up to $WaitMinutes for another test (the default is longer than the longest single test,
# a full profile at 3600 s) and then for the player's own game to close; with -FailIfGameRunning a running game
# is an error at once (the build's sync must not wait for a player). Returns the mutex for Exit-GameTestLock.
function Enter-GameTestLock([int]$WaitMinutes = 90, [switch]$FailIfGameRunning) {
    $mutex = New-Object Threading.Mutex($false, $script:GameTestLockName)
    $owned = $false
    try { $owned = $mutex.WaitOne([TimeSpan]::FromMinutes($WaitMinutes)) }
    catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) {
        $mutex.Dispose()
        throw "Another RimWorld test held the lock for $WaitMinutes minutes."
    }
    $global:GameTestLockDepth++
    if ($global:GameTestLockDepth -gt 1) { return $mutex }
    try {
        Stop-OrphanTestGame
        $deadline = (Get-Date).AddMinutes($WaitMinutes)
        while (Test-GameRunning) {
            if ($FailIfGameRunning) { throw 'RimWorld is running and holds the mod''s files: close it first (or build with -p:SkipSync=true).' }
            if ((Get-Date) -gt $deadline) { throw "RimWorld stayed running for $WaitMinutes minutes; close it before testing." }
            Start-Sleep -Seconds 5
        }
        if (Test-WaylithGame) { Backup-PlayerLog }
    }
    catch {
        Exit-GameTestLock $mutex
        throw
    }
    return $mutex
}

function Exit-GameTestLock($mutex) {
    if ($null -eq $mutex) { return }
    try {
        if ($global:GameTestLockDepth -eq 1) {
            try { Restore-PlayerLog } catch { Write-Warning "Could not put the player's log back: $($_.Exception.Message)" }
        }
    }
    finally {
        if ($global:GameTestLockDepth -gt 0) { $global:GameTestLockDepth-- }
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}

# ---------------------------------------------------------------------------------------------------------
# Logs

function Read-SharedFile([string]$path) {
    if ([string]::IsNullOrEmpty($path)) { return '' }
    # No existence check before the open: 1.7 renames Player.log when the game starts, so the file can go between
    # the two. A log that is not there (yet) reads as empty and the caller keeps waiting.
    try { $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete) }
    catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { return '' }
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

# -match has no time limit: a pattern that backtracks badly on some log would spin for good while holding the
# shared lock. Every log check goes through this (case-insensitive like -match). On a timeout the log is kept in
# $DumpPath when given.
function Test-LogMatch([string]$Content, [string]$Pattern, [string]$DumpPath = '') {
    try { return [regex]::IsMatch($Content, $Pattern, 'IgnoreCase', [TimeSpan]::FromSeconds(10)) }
    catch {
        if ($DumpPath) { try { [IO.File]::WriteAllText($DumpPath, $Content, (New-Object Text.UTF8Encoding($false))) } catch { } }
        throw "Log check failed on pattern $Pattern : $($_.Exception.Message)"
    }
}

function Find-LogMatch([string]$Content, [string]$Pattern) {
    return [regex]::Match($Content, $Pattern, 'IgnoreCase', [TimeSpan]::FromSeconds(10))
}

# The log of game process $GamePid in 1.6 form, so the same patterns work on both branches. On 1.7 the shared
# Player.log only counts once its header names this process; line prefixes are removed, except that error-level
# lines get a "[LOGERROR] " marker. With -Save the processed text is also written to $LogPath.
function Read-GameLog([string]$LogPath, [int]$GamePid, [switch]$Save) {
    if (-not (Test-WaylithGame)) { return Read-SharedFile $LogPath }
    if ($GamePid -le 0) { return '' }
    $content = Read-SharedFile (Join-Path $script:UserDataRoot 'Logs\Player.log')
    if (-not (Test-LogMatch $content ('(?m)^Process:\s+pid ' + $GamePid + '\s*$'))) { return '' }
    $prefix = New-Object regex('(?m)^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} +([A-Z]+)( \[[A-Za-z0-9_.:+-]+\])? ', 'None', [TimeSpan]::FromSeconds(10))
    $plain = $prefix.Replace($content, [Text.RegularExpressions.MatchEvaluator] {
        param($m)
        if ($m.Groups[1].Value -in 'ERROR', 'FATAL', 'CRIT') { return '[LOGERROR] ' }
        return ''
    })
    if ($Save) { try { [IO.File]::WriteAllText($LogPath, $plain, (New-Object Text.UTF8Encoding($false))) } catch { } }
    return $plain
}

# What is wrong in a game log, as @{ Kind; Message }, or $null. Kinds: crash, scenario, capture, error, startup.
# The mod logs its own errors as "<prefix> [ERROR] ..." (ModLog.cs), which works on both branches; errors the
# game raises in the mod's code show its namespace in the stack trace.
function Get-GameLogFailure([string]$Content, [string]$DumpPath = '') {
    $p = $script:LogPrefixPattern
    $ns = [regex]::Escape($script:Cfg.CodeNamespace)
    $name = [regex]::Escape($script:Cfg.ModName)
    # A stack frame in the mod's code inside an error. 1.7 writes a stack under every line, info included, so there
    # only the indented lines (and unindented "[Ref ...]" lines) below a [LOGERROR] line count; one way to match
    # each line, so the pattern cannot backtrack badly. 1.6 writes stacks only for errors (Engine.KeepErrorStackTraces)
    # and exceptions: Mono's "  at MyMod.X.Y (...)" in an exception's text and Unity's "MyMod.X:Y (...)".
    $stackPattern = if (Test-WaylithGame) {
        '(?m)^\[LOGERROR\] [^\n]*\n(?>(?:[ \t]|\[Ref )[^\n]*\n)*?[ \t]+at ' + $ns + '\.'
    } else {
        '(?m)^[ \t]*at ' + $ns + '\.|^' + $ns + '\.[A-Za-z0-9_.`+<>]+:[A-Za-z0-9_`<>]+ ?\('
    }
    # Each pattern in parentheses: in an array literal the comma binds tighter than +.
    $checks = @(
        @('crash', '(?m)(?:^|\] )=== CRASH ===', 'The game crashed; see the crash report named in the log.'),
        @('scenario', ('(?m)^' + $p + ' \[SELFTEST\] FAIL\b'), 'A self-test scenario failed.'),
        @('scenario', ('(?m)^' + $p + ' \[SELFTEST\] DONE passed=\d+ failed=[1-9]'), 'A self-test scenario failed.'),
        @('capture', ('(?m)^' + $p + ' \[CAPTURE\] FAIL\b'), 'The screenshot sequence failed.'),
        @('error', ('(?m)^(?:\[LOGERROR\] )?' + $p + ' \[ERROR\]'), 'The mod logged an error.'),
        @('error', ('(?m)^\[LOGERROR\] ' + $p), 'An error-level line carries the mod''s prefix.'),
        @('error', $stackPattern, 'An error stack trace runs through the mod''s code.'),
        @('error', ('(?im)^(?!Command line arguments:|Command:|Process:|[ \t]+at |' + $p + ')(?=[^\n]*' + $name + ')(?=[^\n]*\b(?:exception|could not (?:load|find|instantiate|resolve)|failed to find)\b)'), 'A log line reports a problem involving the mod.'),
        @('startup', 'Critical error in root Start|Error while generating map|Could not generate starting map|Error in GenStep:', 'The game failed during startup or map generation.')
    )
    foreach ($check in $checks) {
        if (Test-LogMatch $Content $check[1] $DumpPath) { return @{ Kind = $check[0]; Message = $check[2] } }
    }
    return $null
}

# Prints the mod's own lines of a log (the self-test's PASS/FAIL lines among them).
function Write-ModLines([string]$Content) {
    $Content -split '\r?\n' | Where-Object { $_.StartsWith($script:Cfg.LogPrefix) -or $_.StartsWith('[LOGERROR] ' + $script:Cfg.LogPrefix) } | ForEach-Object { Write-Host $_ }
}

# ---------------------------------------------------------------------------------------------------------
# Launching the game

# Windows command-line quoting for one argument.
function ConvertTo-GameArgument([AllowEmptyString()][string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $quoted = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $quoted = [regex]::Replace($quoted, '(\\+)$', '$1$1')
    return '"' + $quoted + '"'
}

# The Start-Process window style and extra game arguments for a requested window. 1.6 sends no OnGUI to a hidden
# window (UI scenarios would draw nothing and still pass), so Minimized is the default there. 1.7 renders no
# frames while minimized and hangs, so anything but Normal becomes -NoWindow, which hides the window and still
# renders. -NoCrashDialog: without it a 1.7 crash waits for someone to click a message box.
function Get-WindowLaunch([string]$WindowStyle) {
    if (-not (Test-WaylithGame)) { return @{ Style = $WindowStyle; Arguments = @() } }
    if ($WindowStyle -ne 'Normal') { return @{ Style = 'Normal'; Arguments = @('-NoWindow', '-NoCrashDialog') } }
    return @{ Style = 'Normal'; Arguments = @('-NoCrashDialog') }
}

# Starts the game with $Arguments, waits until $Done (a script block taking the log) returns true, the log shows a
# failure, the game exits or the timeout passes, then stops the game if it still runs. Failures of the kinds in
# $Tolerate do not stop the run. Returns @{ Log; Failure; Completed; Seconds } with Failure the first cause found.
function Invoke-GameRun {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][scriptblock]$Done,
        [string]$WindowStyle = 'Minimized',
        [int]$TimeoutSeconds = 900,
        [string[]]$Tolerate = @()
    )
    if (Test-GameRunning) { throw 'RimWorld is already running; the game was not started.' }
    if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
    $all = @($Arguments)
    if (-not (Test-WaylithGame)) { $all += @('-logfile', $LogPath) }
    $launch = Get-WindowLaunch $WindowStyle
    $all += $launch.Arguments
    $line = ($all | ForEach-Object { ConvertTo-GameArgument $_ }) -join ' '
    $exe = Get-GameExe
    $crashDir = Join-Path $script:UserDataRoot 'Crashes'
    $started = Get-Date
    Write-Host "Starting: $exe $line"
    $process = Start-Process -FilePath $exe -WorkingDirectory $script:GameRoot -ArgumentList $line -WindowStyle $launch.Style -PassThru
    $null = $process.Handle  # keeps ExitCode readable after the exit
    $result = @{ Log = ''; Failure = $null; Completed = $false; Seconds = 0.0 }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            # Exit first, log second: the game writes its last line and quits at once, so a log read before the exit
            # check could miss that line while the exit check after it sees the game gone.
            $process.Refresh()
            $exited = $process.HasExited
            $log = Read-GameLog $LogPath $process.Id
            $failure = Get-GameLogFailure $log
            if ($failure -and $Tolerate -notcontains $failure.Kind) { $result.Failure = $failure.Message; break }
            if (& $Done $log) {
                $result.Completed = $true
                [void]$process.WaitForExit(20000)
                break
            }
            if ($exited) { $result.Failure = "The game exited before the run completed (exit code $($process.ExitCode))."; break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $result.Completed -and -not $result.Failure) { $result.Failure = "Timed out after $TimeoutSeconds seconds." }
    }
    finally {
        $result.Seconds = $timer.Elapsed.TotalSeconds
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            if (-not $process.WaitForExit(10000) -and -not $result.Failure) { $result.Failure = 'The game process did not terminate.' }
        }
        $result.Log = Read-GameLog $LogPath $process.Id -Save
        $final = Get-GameLogFailure $result.Log ($LogPath + '.check-timeout.txt')
        if ($final -and -not $result.Failure -and $Tolerate -notcontains $final.Kind) { $result.Failure = $final.Message }
        $process.Dispose()
        if (Test-Path -LiteralPath $crashDir) {
            foreach ($report in @(Get-ChildItem -LiteralPath $crashDir -Recurse -File | Where-Object { $_.LastWriteTime -ge $started })) {
                Write-Host "Crash report written by this run (tell the user, it is in their own Crashes folder): $($report.FullName)"
            }
        }
    }
    return $result
}

# ---------------------------------------------------------------------------------------------------------
# Mods and test profiles

# The installed folder of a mod, from the game's Mods folder or the Workshop downloads, or $null.
function Find-ModFolder([string]$PackageId) {
    foreach ($root in @((Join-Path $script:GameRoot 'Mods'), $script:WorkshopRoot)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Force)) {
            $about = Join-Path $dir.FullName 'About\About.xml'
            if (-not (Test-Path -LiteralPath $about -PathType Leaf)) { continue }
            try { [xml]$meta = [IO.File]::ReadAllText($about, [Text.Encoding]::UTF8) } catch { continue }
            $node = $meta.SelectSingleNode('/ModMetaData/packageId')
            if ($null -ne $node -and $node.InnerText.Trim() -ieq $PackageId) { return $dir.FullName }
        }
    }
    return $null
}

# packageIds of Core and every installed DLC (Data\<name>\About\About.xml): Core first, the DLCs in release
# order, any newer one after them.
function Get-OfficialPackageIds {
    $release = @('royalty', 'ideology', 'biotech', 'anomaly', 'odyssey')
    $dlcs = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $script:GameRoot 'Data') -Directory)) {
        $about = Join-Path $dir.FullName 'About\About.xml'
        if (-not (Test-Path -LiteralPath $about)) { continue }
        [xml]$meta = [IO.File]::ReadAllText($about, [Text.Encoding]::UTF8)
        $id = $meta.ModMetaData.packageId.Trim().ToLowerInvariant()
        if ($id -like 'ludeon.rimworld.*') { $dlcs += $id }
    }
    $sorted = @($dlcs | Sort-Object { $i = [Array]::IndexOf($release, $_.Substring(16)); if ($i -lt 0) { 99 } else { $i } }, { $_ })
    return @('ludeon.rimworld') + $sorted
}

# Lines of a list file next to the scripts (exclude-1.7.txt, exclude-full.txt): one packageId a line, "#" comments.
function Read-IdList([string]$name) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
}

function New-ModsConfig([string[]]$Ids) {
    $mods = New-Object Xml.XmlDocument
    $mods.LoadXml('<?xml version="1.0" encoding="utf-8"?><ModsConfigData><version /><activeMods /></ModsConfigData>')
    $active = $mods.SelectSingleNode('/ModsConfigData/activeMods')
    foreach ($id in $Ids) { $node = $mods.CreateElement('li'); $node.InnerText = $id; [void]$active.AppendChild($node) }
    return $mods
}

function Get-ActiveIds([xml]$Mods) {
    return @($Mods.SelectNodes('/ModsConfigData/activeMods/li') | ForEach-Object { $_.InnerText.Trim() })
}

function Set-ActiveIds([xml]$Mods, [string[]]$Ids) {
    $active = $Mods.SelectSingleNode('/ModsConfigData/activeMods')
    foreach ($node in @($active.SelectNodes('li'))) { [void]$active.RemoveChild($node) }
    foreach ($id in $Ids) { $node = $Mods.CreateElement('li'); $node.InnerText = $id; [void]$active.AppendChild($node) }
}

# Whether $id always loads first: Harmony, Core and the DLCs, the mod's dependencies.
function Test-FixedHead([string]$id) {
    return ($id -ieq 'brrainz.harmony') -or ($id -ilike 'ludeon.rimworld*') -or ($script:Cfg.Dependencies -icontains $id)
}

# Puts the mod at $Position among the other mods; Harmony, Core and the DLCs, then the dependencies stay first.
function Set-TestLoadPosition([xml]$Mods, [ValidateSet('First', 'Middle', 'Last')][string]$Position = 'Last') {
    $self = $script:Cfg.PackageId
    $ids = @(Get-ActiveIds $Mods | Where-Object { $_ -ine $self })
    $head = @($ids | Where-Object { $_ -ieq 'brrainz.harmony' }) + @($ids | Where-Object { $_ -ilike 'ludeon.rimworld*' }) +
        @($ids | Where-Object { $_ -ine 'brrainz.harmony' -and $_ -notlike 'ludeon.rimworld*' -and $script:Cfg.Dependencies -icontains $_ })
    $others = @($ids | Where-Object { -not (Test-FixedHead $_) })
    $insert = switch ($Position) { 'First' { 0 } 'Middle' { [int][Math]::Floor($others.Count / 2) } default { $others.Count } }
    $ordered = @($head) + @($others | Select-Object -First $insert) + @($self) + @($others | Select-Object -Skip $insert)
    Set-ActiveIds $Mods $ordered
}

# Turns a copy of a mod list into the full profile's list: drops excluded mods, tests the local build in place of
# a Workshop copy of the mod (whose packageId the game suffixes with _steam), adds missing dependencies.
function Update-FullModList([xml]$Mods, [string[]]$ExcludeMods) {
    $self = $script:Cfg.PackageId
    $ids = @(Get-ActiveIds $Mods)
    $excluded = @($ids | Where-Object { $ExcludeMods -icontains $_ })
    if ($excluded.Count -gt 0) { Write-Host "Excluding: $($excluded -join ', ')" }
    $ids = @($ids | Where-Object { $ExcludeMods -inotcontains $_ })
    if ($ids -icontains ($self + '_steam')) {
        Write-Host "Testing the local build in place of the Workshop copy ($($self)_steam)."
        $ids = @($ids | ForEach-Object { if ($_ -ieq ($self + '_steam')) { $self } else { $_ } } | Select-Object -Unique)
    }
    foreach ($dep in $script:Cfg.Dependencies) {
        if ($ids -inotcontains $dep) { Write-Host "Adding the missing dependency $dep."; $ids = @($dep) + $ids }
    }
    if ($ids -inotcontains $self) { $ids += $self }
    Set-ActiveIds $Mods $ids
}

# The mod list the full profile copies: $ModList (a path, or a file name in <dev root>\ModLists), else the
# player's own. A player's list of 10 mods or more is also saved to ModLists\user-<date>.xml once a day.
function Get-FullModListSource([string]$ModList) {
    if ($ModList) {
        $path = if (Test-Path -LiteralPath $ModList -PathType Leaf) { $ModList } else { Join-Path $script:ModListsDir $ModList }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -and -not $path.EndsWith('.xml')) { $path += '.xml' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Mod list not found: $ModList (looked in $script:ModListsDir too)" }
        return [IO.Path]::GetFullPath($path)
    }
    $player = Join-Path $script:UserDataRoot 'Config\ModsConfig.xml'
    if (-not (Test-Path -LiteralPath $player)) { throw "No player mod list at $player; pass -ModList." }
    [xml]$mods = [IO.File]::ReadAllText($player, [Text.Encoding]::UTF8)
    if ((Get-ActiveIds $mods).Count -ge 10) {
        $copy = Join-Path $script:ModListsDir ('user-' + (Get-Date -Format 'yyyy-MM-dd') + '.xml')
        if (-not (Test-Path -LiteralPath $copy)) {
            New-Item -ItemType Directory -Path $script:ModListsDir -Force | Out-Null
            Copy-Item -LiteralPath $player -Destination $copy
            Write-Host "Saved a copy of the player's mod list: $copy"
        }
    }
    return $player
}

# Writes <Test>\<Name>\Config\ModsConfig.xml and Prefs.xml and returns the profile folder.
#   vanilla  Harmony + Core + every DLC + dependencies + the mod
#   core     Harmony + Core + RequiredDlcs + dependencies + the mod (no DLC the mod does not require)
#   full     a copied mod list (see Get-FullModListSource) + the mod, minus excluded mods
function New-TestProfile {
    param(
        [ValidateSet('vanilla', 'core', 'full')][string]$Profile = 'vanilla',
        [string]$Name = '',
        [string]$ModList = '',
        [string[]]$ExcludeMods = @(),
        [ValidateSet('First', 'Middle', 'Last')][string]$LoadPosition = 'Last',
        [ValidateSet('ChineseSimplified', 'English')][string]$Language = 'English',
        [int]$ScreenWidth = 1280,
        [int]$ScreenHeight = 720,
        # The game's UI scale option (1.7 also caps it by the window size, ResolutionUtility.ResolveUIScale).
        [string]$UIScale = '1',
        [switch]$DisableTinyText
    )
    if (-not $Name) { $Name = $Profile }
    $profileRoot = Join-Path $script:TestRoot $Name
    $configRoot = Join-Path $profileRoot 'Config'
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    foreach ($dep in $script:Cfg.Dependencies) {
        if (-not (Find-ModFolder $dep)) { throw "$dep is not installed (neither in the game's Mods folder nor in $script:WorkshopRoot): subscribe to it first." }
    }
    if ($Profile -eq 'full') {
        $source = Get-FullModListSource $ModList
        Write-Host "Mod list from: $source"
        [xml]$mods = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
        if ($null -eq $mods.SelectSingleNode('/ModsConfigData/activeMods')) { throw "$source has no activeMods element." }
        $listed = (Get-ActiveIds $mods).Count
        if ($listed -lt 10) {
            throw "The mod list has only $listed mods: the game resets a list to Core when switching between 1.6 and 1.7. Pass -ModList with a saved list from $script:ModListsDir."
        }
        if ($listed -lt 200) { Write-Warning "The mod list has only $listed mods; a full test wants 200 or more (see the skill: add a popular Workshop collection)." }
        $exclude = @($ExcludeMods) + @($script:Cfg.IncompatibleMods) + @(Read-IdList 'exclude-full.txt')
        if (Test-WaylithGame) { $exclude += @(Read-IdList 'exclude-1.7.txt') }
        Update-FullModList $mods $exclude
    }
    else {
        $official = @(Get-OfficialPackageIds)
        $dlcs = if ($Profile -eq 'vanilla') { @($official | Select-Object -Skip 1) } else { @($script:Cfg.RequiredDlcs) }
        foreach ($dlc in $dlcs) { if ($official -inotcontains $dlc) { throw "The DLC $dlc is not installed." } }
        $harmony = @($script:Cfg.Dependencies | Where-Object { $_ -ieq 'brrainz.harmony' })
        $others = @($script:Cfg.Dependencies | Where-Object { $_ -ine 'brrainz.harmony' })
        $mods = New-ModsConfig (@($harmony) + @('ludeon.rimworld') + @($dlcs) + @($others) + @($script:Cfg.PackageId))
    }
    # A mod list from another game version is reset to Core only.
    $version = $mods.SelectSingleNode('/ModsConfigData/version')
    if ($null -eq $version) { $version = $mods.CreateElement('version'); [void]$mods.DocumentElement.PrependChild($version) }
    $version.InnerText = Get-GameVersion
    Set-TestLoadPosition $mods $LoadPosition
    $mods.Save((Join-Path $configRoot 'ModsConfig.xml'))
    $ids = @(Get-ActiveIds $mods)
    Write-Host "Test mod list $Name`: count=$($ids.Count) position=$([Array]::IndexOf($ids, $script:Cfg.PackageId)) ($LoadPosition)"

    $prefsPath = Join-Path $configRoot 'Prefs.xml'
    $prefs = New-Object Xml.XmlDocument
    if (Test-Path -LiteralPath $prefsPath) { $prefs.Load($prefsPath) } else { $prefs.LoadXml('<?xml version="1.0" encoding="utf-8"?><PrefsData />') }
    # The language folder name; built from code points so this file stays ASCII.
    $chinese = 'ChineseSimplified (' + (-join [char[]](0x7B80, 0x4F53, 0x4E2D, 0x6587)) + ')'
    $values = [ordered]@{
        devMode = 'true'; runInBackground = 'true'; pauseOnError = 'false'; pauseOnLoad = 'false'
        langFolderName = $(if ($Language -eq 'English') { 'English' } else { $chinese })
        fullscreen = 'false'; screenWidth = "$ScreenWidth"; screenHeight = "$ScreenHeight"
        uiScale = $UIScale; disableTinyText = $(if ($DisableTinyText) { 'true' } else { 'false' })
        # The learning helper covers the top right of windows in screenshots.
        adaptiveTrainingEnabled = 'false'
    }
    foreach ($key in $values.Keys) {
        $node = $prefs.SelectSingleNode("/PrefsData/$key")
        if ($null -eq $node) { $node = $prefs.CreateElement($key); [void]$prefs.DocumentElement.AppendChild($node) }
        $node.InnerText = $values[$key]
    }
    # 1.7 saves the window position into the profile; 1.6 has no such fields and logs an XML error for each.
    if (-not (Test-WaylithGame)) {
        foreach ($key in 'windowPositionX', 'windowPositionY') {
            $node = $prefs.SelectSingleNode("/PrefsData/$key")
            if ($null -ne $node) { [void]$node.ParentNode.RemoveChild($node) }
        }
    }
    $prefs.Save($prefsPath)
    return $profileRoot
}
