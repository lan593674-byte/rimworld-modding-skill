using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Threading;
using RimWorld;
using UnityEngine;
using Verse;

namespace MyMod.SelfTest
{
    // The in-game self-test, started by the test scripts in Source\tools (never in a player's game):
    //   -<prefix>-selftest              run the registered scenarios once a map is up, then quit
    //   -<prefix>-smoke                 only the built-in checks (the mod loads, a map is generated)
    //   -<prefix>-capture -<prefix>-shots=<dir>   take the registered screenshots instead
    //   -<prefix>-makesave=<name>       build the save-safety fixture and save it as <name>
    //   -<prefix>-only=<text>           only scenarios whose name contains <text>
    // Log lines (all with the mod's prefix): "[SMOKE] map generated", "[SELFTEST] PASS|FAIL|SKIP <name>",
    // "[SELFTEST] DONE passed=X failed=Y skipped=Z"; in capture mode the tag is [CAPTURE] and there are
    // "PLAN <n>" and "SHOT <file>" lines. The game is driven by the mod's GameComponent (GameComponentUpdate and
    // GameComponentOnGUI), the same code path on 1.6 and 1.7.
    public static class SelfTestRunner
    {
        public static readonly bool Enabled = CommandLine.Has(SelfTestSetup.ArgPrefix + "-selftest");
        private static readonly bool smoke = CommandLine.Has(SelfTestSetup.ArgPrefix + "-smoke");
        public static readonly bool CaptureMode = CommandLine.Has(SelfTestSetup.ArgPrefix + "-capture");
        private static readonly string makeSave = CommandLine.Value(SelfTestSetup.ArgPrefix + "-makesave");
        private static readonly string only = CommandLine.Value(SelfTestSetup.ArgPrefix + "-only");

        // AutosaveIntervalTicks is an int: days * 60000 must stay below int.MaxValue (35791 days), or it wraps
        // negative and the game autosaves every tick.
        public const float NoAutosaveDays = 10000f;
        public const float DefaultTimeoutSeconds = 120f;
        private const float ExitGraceSeconds = 10f;

        private sealed class Entry
        {
            public string Name;
            public Func<SelfTestContext, IEnumerator> Run;
            public float TimeoutSeconds;
        }

        private static readonly List<Entry> scenarios = new List<Entry>();
        private static readonly SelfTestContext context = new SelfTestContext();
        // A scenario may yield another IEnumerator (a helper such as ctx.WaitUntil); it runs to the end first.
        private static readonly Stack<IEnumerator> nested = new Stack<IEnumerator>();
        private static IEnumerator routine;
        private static readonly Stopwatch scenarioClock = new Stopwatch();
        private static readonly Stopwatch exitClock = new Stopwatch();
        private static int index, passed, failed, skipped, errorsAtStart, exitCode;
        private static bool started, finished, waitingForReload;
        private static Verse.Game lastGame;
        private static string Tag => CaptureMode ? "[CAPTURE] " : "[SELFTEST] ";

        // Errors with the mod's prefix (or in its code) logged on any thread since the start; a scenario that adds to
        // it fails even when its own checks pass (the game catches exceptions in ticks and only logs them).
        private static int modErrors;
        public static int ModErrors => Volatile.Read(ref modErrors);

        public static int ReloadCount { get; private set; }

        // Called from the Mod constructor.
        public static void Initialize()
        {
            if (!Enabled)
                return;
            string ns = typeof(SelfTestRunner).Namespace.Split('.')[0] + ".";
            Engine.ListenForErrors(text =>
            {
                if (text != null && (text.Contains(ModLog.Prefix) || text.Contains(ns)))
                    Interlocked.Increment(ref modErrors);
            });
        }

        public static void Register(string name, Func<SelfTestContext, IEnumerator> run, float timeoutSeconds = DefaultTimeoutSeconds)
        {
            if (started) throw new InvalidOperationException("Register scenarios before the runner starts.");
            if (string.IsNullOrEmpty(name) || run == null) throw new ArgumentException("A scenario needs a name and a body.");
            if (only != null && name.IndexOf(only, StringComparison.OrdinalIgnoreCase) < 0) return;
            scenarios.Add(new Entry { Name = name, Run = run, TimeoutSeconds = timeoutSeconds });
        }

        public static void Register(ISelfTestScenario scenario, float timeoutSeconds = DefaultTimeoutSeconds)
            => Register(scenario.Name, scenario.Run, timeoutSeconds);

        // ---- UI drawing: only possible inside OnGUI; ctx.Draw queues an action for the next OnGUI. ----

        private static Action guiAction;
        private static bool guiRepaintOnly;
        public static bool GuiDone { get; private set; }
        public static Exception GuiError { get; private set; }
        public static bool GuiSeen { get; private set; }

        internal static void QueueGui(Action draw, bool repaintOnly)
        {
            GuiDone = false;
            GuiError = null;
            guiRepaintOnly = repaintOnly;
            guiAction = draw;
        }

        public static void OnGUI()
        {
            GuiSeen = true;
            if (guiAction == null || Event.current == null)
                return;
            var type = Event.current.type;
            // Layout runs the whole IMGUI code path too; textures and screenshots need Repaint.
            if (type != EventType.Repaint && (type != EventType.Layout || guiRepaintOnly))
                return;
            var draw = guiAction;
            guiAction = null;
            try { draw(); }
            catch (Exception ex) { GuiError = ex; }
            GuiDone = true;
        }

        // ---- Saving and loading inside a scenario ----

        // Saves the running game for real and loads it back; the scenario continues after the load (ctx.SaveAndReload).
        internal static void SaveAndReload(string name)
        {
            string path = SaveFor(name + "-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            waitingForReload = true;
            GameDataSaveLoader.LoadGame(Path.GetFileNameWithoutExtension(path));
        }

        // Saves the running game as <name> in the test profile and returns the file. GameDataSaveLoader swallows its
        // own exceptions, so an old file of the same name is deleted first and the new one must exist afterwards.
        internal static string SaveFor(string name)
        {
            string path = Path.GetFullPath(GenFilePaths.FilePathForSavedGame(name));
            RequireTestProfile(path);
            if (File.Exists(path)) File.Delete(path);
            GameDataSaveLoader.SaveGame(name);
            if (!File.Exists(path)) throw new InvalidOperationException("The save was not written: " + path);
            ModLog.Message(Tag + "SAVE " + path);
            return path;
        }

        // Self-tests write only into the test profile the script passed with -savedatafolder (and the screenshots
        // folder next to it), never into the player's own data.
        internal static void RequireTestProfile(string path)
        {
            string root = CommandLine.Value("savedatafolder");
            if (string.IsNullOrEmpty(root))
                throw new InvalidOperationException("Self-tests run only with -savedatafolder (a test profile): refusing to write " + path);
            string parent = Path.GetDirectoryName(Path.GetFullPath(root).TrimEnd('\\', '/')) + Path.DirectorySeparatorChar;
            if (!Path.GetFullPath(path).StartsWith(parent, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Self-tests may only write under " + parent + ": " + path);
        }

        // ---- The frame loop ----

        public static void Update()
        {
            if (!Enabled)
                return;
            KeepLogging();
            if (finished)
            {
                // Quitting may be vetoed (1.7) or slow; quit for good after a grace period.
                if (exitClock.IsRunning && exitClock.Elapsed.TotalSeconds > ExitGraceSeconds)
                {
                    exitClock.Reset();
                    Engine.ForceExit(exitCode);
                }
                return;
            }
            // While a save loads Find.CurrentMap throws (the map list is empty): check the load first.
            if (LongEventHandler.ShouldWaitForEvent || Current.ProgramState != ProgramState.Playing || Current.Game == null
                || Current.Game.Maps.Count == 0 || Find.CurrentMap == null)
                return;
            if (!ReferenceEquals(Current.Game, lastGame))
            {
                lastGame = Current.Game;
                StartOrResume();
            }
            if (waitingForReload)
                return;
            if (index >= scenarios.Count)
            {
                Finish();
                return;
            }
            // The map fades in from black for half a second after loading; until then the player has no control and
            // the game ignores speed changes (TickManager.CurTimeSpeed checks Game.PlayerHasControl).
            if (routine == null && ScreenFader.IsFading())
                return;
            var entry = scenarios[index];
            if (routine == null)
            {
                scenarioClock.Restart();
                errorsAtStart = ModErrors;
                context.Begin(entry.Name);
                try { routine = entry.Run(context); }
                catch (Exception ex) { End(entry, Outcome(ex)); return; }
            }
            if (scenarioClock.Elapsed.TotalSeconds > entry.TimeoutSeconds)
            {
                End(entry, "FAIL " + entry.Name + ": timed out after " + entry.TimeoutSeconds.ToString("0", CultureInfo.InvariantCulture)
                    + " s (" + State() + ")");
                return;
            }
            string result;
            try
            {
                if (Step())
                    return;
                result = "PASS " + entry.Name;
            }
            catch (Exception ex) { result = Outcome(ex); }
            int newErrors = ModErrors - errorsAtStart;
            if (newErrors > 0 && result.StartsWith("PASS", StringComparison.Ordinal))
                result = "FAIL " + entry.Name + ": the mod logged " + newErrors + " error(s) while it ran (see the log above)";
            End(entry, result);

            string Outcome(Exception ex)
            {
                if (ex is TargetInvocationException tie && tie.InnerException != null) ex = tie.InnerException;
                return ex is SelfTestContext.SkipException skip ? "SKIP " + entry.Name + ": " + skip.Message : "FAIL " + entry.Name + ": " + ex;
            }
        }

        // Advances the innermost running coroutine one step; false once the scenario has finished.
        private static bool Step()
        {
            while (true)
            {
                var current = nested.Count > 0 ? nested.Peek() : routine;
                if (current.MoveNext())
                {
                    if (current.Current is IEnumerator inner) { nested.Push(inner); continue; }
                    return true;
                }
                if (nested.Count == 0) return false;
                TryDispose(nested.Pop());
            }
        }

        // Logs the result and puts everything back for the next scenario, whatever happened. A plain message, not an
        // error: in dev mode an error would open the debug log window over every later scenario, and the scripts
        // judge by the [SELFTEST] FAIL marker.
        private static void End(Entry entry, string result)
        {
            try
            {
                if (result.StartsWith("PASS", StringComparison.Ordinal)) passed++;
                else if (result.StartsWith("SKIP", StringComparison.Ordinal)) skipped++;
                else failed++;
                KeepLogging();
                ModLog.Message(Tag + result);
            }
            finally
            {
                guiAction = null;
                GuiDone = false;
                GuiError = null;
                while (nested.Count > 0) TryDispose(nested.Pop());
                TryDispose(routine);
                routine = null;
                context.RunDeferred();
                if (Current.Game != null && Find.TickManager != null)
                    Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
                index++;
            }
        }

        private static void TryDispose(IEnumerator coroutine)
        {
            try { (coroutine as IDisposable)?.Dispose(); }
            catch (Exception ex) { ModLog.Message(Tag + "NOTE clean-up of a coroutine failed: " + ex.Message); }
        }

        // What the game was doing when a scenario timed out.
        private static string State()
        {
            var ticks = Find.TickManager;
            var forcing = new List<string>();
            foreach (var window in Find.WindowStack.Windows)
                if (window.forcePause) forcing.Add(window.GetType().Name);
            return "tick " + ticks.TicksGame + ", speed " + ticks.CurTimeSpeed + ", forcePaused " + ticks.ForcePaused
                + (forcing.Count > 0 ? " by " + string.Join(", ", forcing.ToArray()) : string.Empty)
                + ", OnGUI seen " + GuiSeen;
        }

        // ---- Start, resume after a load, finish ----

        private static void StartOrResume()
        {
            // Random raids, traders and drop pods would interfere with fixtures. The storyteller is rebuilt on every
            // load, so this runs after each one.
            Find.Storyteller.storytellerComps.Clear();
            Find.Storyteller.incidentQueue.Clear();
            Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
            UltraSpeedBoostField?.SetValue(null, false);
            if (!started)
            {
                // First: a failure in what follows must not hide that the map is up (Smoke waits for this line).
                ModLog.Message("[SMOKE] map generated");
                // Prefs.data, not the Prefs setters: they call Prefs.Apply, which resets the screen resolution. Only the
                // isolated test profile is affected.
                SelfTestContext.SetPref("autosaveIntervalDays", NoAutosaveDays);
                SelfTestContext.SetPref("adaptiveTrainingEnabled", false);
                // In dev mode the debug log window opens by itself on any error (a full mod list always has some) and
                // would cover every screenshot.
                LogWindowAutoOpen?.SetValue(null, false);
                Find.WindowStack.TryRemove(typeof(LudeonTK.EditWindow_Log), false);
                try { CompatDiagnostics.Log(SelfTestSetup.DiagnosticTargets()); }
                catch (Exception ex) { ModLog.Message("[DIAG] failed: " + ex.Message); }
                try { RegisterAll(); }
                catch (Exception ex)
                {
                    failed++;
                    ModLog.Message(Tag + "FAIL registering the scenarios: " + ex);
                }
                started = true;
                ModLog.Message(Tag + "START scenarios=" + scenarios.Count + " build=" + Engine.BuildName);
                if (CaptureMode) ModLog.Message("[CAPTURE] PLAN " + scenarios.Count);
            }
            if (waitingForReload) ReloadCount++;
            waitingForReload = false;
        }

        private static void RegisterAll()
        {
            if (makeSave != null)
            {
                Register("save fixture " + makeSave, MakeSaveFixture, 600f);
                return;
            }
            if (CaptureMode)
            {
                CaptureKit.PrepareFolder();
                SelfTestSetup.RegisterCaptures();
                return;
            }
            BuiltinScenarios.Register();
            if (!smoke)
                SelfTestSetup.RegisterScenarios();
        }

        private static IEnumerator MakeSaveFixture(SelfTestContext ctx)
        {
            ctx.Require(System.Text.RegularExpressions.Regex.IsMatch(makeSave, "^[A-Za-z0-9_-]+$"), "Save names are letters, digits, - and _ only.");
            yield return SelfTestSetup.MakeSaveFixture(ctx);
            SaveFor(makeSave);
            ModLog.Message("[SELFTEST] FIXTURE " + makeSave + " " + SelfTestSetup.Summary());
        }

        private static void Finish()
        {
            finished = true;
            exitCode = failed > 0 ? 1 : 0;
            ModLog.Message(Tag + "DONE passed=" + passed.ToString(CultureInfo.InvariantCulture)
                + " failed=" + failed.ToString(CultureInfo.InvariantCulture)
                + " skipped=" + skipped.ToString(CultureInfo.InvariantCulture));
            exitClock.Start();
            try { Engine.RequestExit(exitCode); }
            catch (Exception ex) { ModLog.Message(Tag + "NOTE quitting failed: " + ex.Message); }
        }

        // ---- Keeping the log open ----

        // Verse.Log stops writing after 10000 messages; another mod logging an error every frame gets there and would
        // hide PASS, FAIL and DONE from the test scripts. Self-tests turn it back on every frame.
        internal static readonly FieldInfo LogLimitField = typeof(Log).GetField("reachedMaxMessagesLimit", BindingFlags.NonPublic | BindingFlags.Static);
        private static readonly FieldInfo LogWindowAutoOpen = typeof(LudeonTK.EditWindow_Log).GetField("canAutoOpen", BindingFlags.NonPublic | BindingFlags.Static);
        // Ultrafast runs 150 (1.6) or 20000 (1.7) ticks a frame with this dev switch on; scenarios measure at the speeds
        // a player has.
        private static readonly FieldInfo UltraSpeedBoostField = typeof(TickManager).GetField("UltraSpeedBoost", BindingFlags.NonPublic | BindingFlags.Static);

        internal static void KeepLogging()
        {
            try { if (LogLimitField != null && (bool)LogLimitField.GetValue(null)) Log.ResetMessageCount(); }
            catch { }
        }
    }
}
