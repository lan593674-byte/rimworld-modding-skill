using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using RimWorld;
using Verse;

namespace GameTestLoader
{
    // Test-only helper for run-savesafety.ps1; never shipped, and it does not reference the mod under test, so one
    // build serves every mod. Every line it logs starts with "[TESTLOADER]".
    //   -testloader-loadsave=NAME     from the main menu load save NAME, play some ticks, resave as NAME-resaved
    //   -testloader-makesave=NAME     (with -quicktest) once the new map is up, play some ticks, save as NAME
    //   -testloader-workpriorities    then print "WORK pawn= def= index= priority= package=" for one colonist
    //   -testloader-pawn=<ThingID>    the colonist to print (default: the first free colonist)
    //   -testloader-ticks=N           ticks to play (default 600)
    //   -testloader-timeout=SECONDS   give up after this long since the process started (default 900)
    // It collects every error the engine logs, by phase (startup, load, play, save), prints them as
    // "ERROR <n> <phase>: <first line>" and quits. It only reads and writes saves inside the -savedatafolder
    // test profile. The engine hooks are in Host.Unity.cs (1.6) and Host.Waylith.cs (1.7).
    public sealed class TestLoaderMod : Mod
    {
        internal static readonly List<string> Errors = new List<string>();
        internal static volatile string Phase = "startup";

        public TestLoaderMod(ModContentPack content) : base(content)
        {
            if (TestLoaderDriver.Active)
                Host.ListenForErrors(OnError);
        }

        // Called on whichever thread logged the error.
        private static void OnError(string message)
        {
            string phase = Phase;
            if (phase == "done") return;
            string firstLine = (message ?? string.Empty).Split('\n')[0].TrimEnd('\r');
            lock (Errors) Errors.Add(phase + ": " + firstLine);
        }
    }

    [StaticConstructorOnStartup]
    public static class TestLoaderStartup
    {
        static TestLoaderStartup()
        {
            if (!TestLoaderDriver.Active) return;
            Host.CallEveryFrame(new TestLoaderDriver().Update);
            Log.Message("[TESTLOADER] driver ready");
        }
    }

    public sealed class TestLoaderDriver
    {
        private enum State { WaitMenu, WaitPlaying, Ticking, Done }

        private static readonly string[] Args = Environment.GetCommandLineArgs();
        public static bool Active => Arg("loadsave") != null || Arg("makesave") != null;

        private readonly string loadName = Arg("loadsave");
        private readonly string makeName = Arg("makesave");
        private readonly int ticks = ParseInt(Arg("ticks"), 600);
        private readonly double timeoutSeconds = ParseInt(Arg("timeout"), 900);
        private readonly DateTime processStart = Process.GetCurrentProcess().StartTime;
        private State state;
        private int startTick;
        private int menuFrames;

        public TestLoaderDriver()
        {
            state = makeName != null ? State.WaitPlaying : State.WaitMenu;
        }

        private static string Arg(string name)
        {
            string key = "testloader-" + name;
            foreach (string raw in Args)
            {
                string arg = raw.TrimStart('-');
                int eq = arg.IndexOf('=');
                if (string.Equals(eq < 0 ? arg : arg.Substring(0, eq), key, StringComparison.OrdinalIgnoreCase))
                    return eq < 0 ? string.Empty : arg.Substring(eq + 1);
            }
            return null;
        }

        private const int TicksPerFrame = 60;

        // What the game was doing, for the timeout message.
        private string StateReport()
        {
            try
            {
                var windows = new List<string>();
                if (Find.WindowStack != null)
                    foreach (var window in Find.WindowStack.Windows) windows.Add(window.GetType().Name + (window.forcePause ? "(forcePause)" : ""));
                return " (program " + Current.ProgramState + ", long event " + LongEventHandler.AnyEventNowOrWaiting
                    + (Current.Game != null && Find.TickManager != null ? ", ticks played " + (Find.TickManager.TicksGame - startTick) : "")
                    + ", windows: " + (windows.Count == 0 ? "none" : string.Join(", ", windows)) + ")";
            }
            catch (Exception ex) { return " (state unavailable: " + ex.GetType().Name + ")"; }
        }

        private static int ParseInt(string text, int fallback) => int.TryParse(text, out int value) && value > 0 ? value : fallback;

        public void Update()
        {
            if (state == State.Done) return;
            try
            {
                if ((DateTime.Now - processStart).TotalSeconds > timeoutSeconds)
                {
                    Finish("FAIL timeout in state " + state + StateReport());
                    return;
                }
                switch (state)
                {
                    case State.WaitMenu:
                        if (Current.ProgramState != ProgramState.Entry || LongEventHandler.AnyEventNowOrWaiting) return;
                        // Let the main menu settle for a few frames before switching scenes.
                        if (++menuFrames < 30) return;
                        string path = SavePath(loadName);
                        if (!File.Exists(path)) { Finish("FAIL save missing: " + path); return; }
                        Log.Message("[TESTLOADER] LOADING " + path);
                        TestLoaderMod.Phase = "load";
                        GameDataSaveLoader.LoadGame(loadName);
                        state = State.WaitPlaying;
                        break;
                    case State.WaitPlaying:
                        if (Current.ProgramState != ProgramState.Playing || LongEventHandler.AnyEventNowOrWaiting
                            || Current.Game == null || Current.Game.Maps.Count == 0 || Find.CurrentMap == null) return;
                        TestLoaderMod.Phase = "play";
                        // Random events would change the save between runs.
                        Find.Storyteller.storytellerComps.Clear();
                        Find.Storyteller.incidentQueue.Clear();
                        startTick = Find.TickManager.TicksGame;
                        Find.TickManager.CurTimeSpeed = TimeSpeed.Paused;
                        state = State.Ticking;
                        break;
                    case State.Ticking:
                        // Ticks are run here rather than by game speed: the game ignores speed changes while the
                        // map fades in, and a mod's dialog that forces a pause would stop the clock for good.
                        if (LongEventHandler.AnyEventNowOrWaiting) return;
                        for (int i = 0; i < TicksPerFrame && Find.TickManager.TicksGame - startTick < ticks; i++)
                            Find.TickManager.DoSingleTick();
                        int played = Find.TickManager.TicksGame - startTick;
                        if (played < ticks) return;
                        Log.Message("[TESTLOADER] LOADED ok ticks=" + played + " colonists=" + Find.CurrentMap.mapPawns.FreeColonistsCount);
                        if (Arg("workpriorities") != null) PrintWorkPriorities();
                        TestLoaderMod.Phase = "save";
                        string saveName = makeName ?? loadName + "-resaved";
                        string savePath = SavePath(saveName);
                        if (File.Exists(savePath)) File.Delete(savePath);
                        GameDataSaveLoader.SaveGame(saveName);
                        // SaveGame swallows its own exceptions: the file must exist now.
                        if (!File.Exists(savePath)) { Finish("FAIL save not written: " + savePath); return; }
                        Log.Message("[TESTLOADER] " + (makeName != null ? "CREATED " : "RESAVED ") + savePath);
                        Finish(null);
                        break;
                }
            }
            catch (Exception ex)
            {
                Finish("FAIL exception: " + ex);
            }
        }

        // Saves only inside the test profile given with -savedatafolder, never the player's own.
        private static string SavePath(string name)
        {
            if (string.IsNullOrEmpty(name) || !Regex.IsMatch(name, "^[A-Za-z0-9_-]+$"))
                throw new InvalidOperationException("Save names are letters, digits, - and _ only: " + name);
            string root = null;
            foreach (string raw in Args)
                if (raw.StartsWith("-savedatafolder=", StringComparison.OrdinalIgnoreCase)) root = raw.Substring("-savedatafolder=".Length);
            if (string.IsNullOrEmpty(root)) throw new InvalidOperationException("The test loader runs only with -savedatafolder (a test profile).");
            string path = Path.GetFullPath(GenFilePaths.FilePathForSavedGame(name));
            if (!path.StartsWith(Path.GetFullPath(root).TrimEnd('\\', '/') + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Refusing a save outside the test profile: " + path);
            return path;
        }

        // Work priorities are stored by WorkTypeDef index (DefMap.ExposeData), not by name: removing a mod that adds
        // work types shifts the columns of mods loaded after it. This prints one colonist's priorities to compare.
        private static void PrintWorkPriorities()
        {
            Pawn pawn = null;
            string wanted = Arg("pawn");
            foreach (var candidate in Find.CurrentMap.mapPawns.FreeColonists)
                if (pawn == null && (string.IsNullOrEmpty(wanted) || candidate.ThingID == wanted)) pawn = candidate;
            if (pawn?.workSettings == null) { Log.Message("[TESTLOADER] WORK no colonist" + (wanted != null ? " " + wanted : string.Empty)); return; }
            if (!pawn.workSettings.EverWork) pawn.workSettings.EnableAndInitialize();
            foreach (var def in DefDatabase<WorkTypeDef>.AllDefsListForReading)
                Log.Message("[TESTLOADER] WORK pawn=" + pawn.ThingID + " def=" + def.defName + " index=" + def.index
                    + " priority=" + pawn.workSettings.GetPriority(def) + " package=" + (def.modContentPack?.PackageId ?? "none"));
        }

        private void Finish(string failure)
        {
            state = State.Done;
            TestLoaderMod.Phase = "done";
            List<string> errors;
            lock (TestLoaderMod.Errors) errors = new List<string>(TestLoaderMod.Errors);
            // A mod logging every frame may have hit Verse's 10000-message limit: the report must still get out.
            Log.ResetMessageCount();
            if (failure != null) Log.Message("[TESTLOADER] " + failure);
            Log.Message("[TESTLOADER] ERRORS count=" + errors.Count);
            for (int i = 0; i < errors.Count; i++) Log.Message("[TESTLOADER] ERROR " + (i + 1) + " " + errors[i]);
            Log.Message("[TESTLOADER] END");
            Root.Shutdown();
        }
    }
}
