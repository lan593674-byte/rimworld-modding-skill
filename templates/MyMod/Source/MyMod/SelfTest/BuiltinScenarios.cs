using System.Collections;
using RimWorld;
using UnityEngine;
using Verse;

namespace MyMod.SelfTest
{
    // Checks of the test set-up itself; they run first in every self-test, Smoke included.
    internal static class BuiltinScenarios
    {
        public static void Register()
        {
            SelfTestRunner.Register("builtin: test environment", Environment);
            SelfTestRunner.Register("builtin: the game runs before each scenario", GameRuns);
            SelfTestRunner.Register("builtin: log reopens after the 10000-message limit", LogLimit);
        }

        // Stand-ins for a force-pausing window of another mod and one of the self-test (WindowStack.Add closes
        // windows of the same type, so they need two types).
        private sealed class ForeignPause : Window
        {
            public ForeignPause() { forcePause = true; }
            public override Vector2 InitialSize => new Vector2(200f, 100f);
            public override void DoWindowContents(Rect inRect) { }
        }

        private sealed class OwnPause : Window
        {
            public OwnPause() { forcePause = true; }
            public override Vector2 InitialSize => new Vector2(200f, 100f);
            public override void DoWindowContents(Rect inRect) { }
        }

        // The runner starts every scenario with the game running: it closes force-pausing windows the self-test did
        // not open (not those opened with ctx.Open) and the game ticks again.
        private static IEnumerator GameRuns(SelfTestContext ctx)
        {
            var ticks = Find.TickManager;
            ctx.Require(!ticks.Paused && ticks.CurTimeSpeed == TimeSpeed.Normal, "The scenario started with the game paused (speed "
                + ticks.CurTimeSpeed + ", forcePaused " + ticks.ForcePaused + ").");
            var foreign = new ForeignPause();
            Find.WindowStack.Add(foreign);
            ctx.Defer(() => foreign.Close(false));
            var own = ctx.Open(new OwnPause());
            ctx.Require(ticks.Paused, "A window with forcePause did not pause the game.");
            int closed = SelfTestRunner.CloseForeignPauses();
            ctx.Require(closed == 1 && !Find.WindowStack.IsOpen(foreign), "Closed " + closed + " window(s); the foreign one is "
                + (Find.WindowStack.IsOpen(foreign) ? "still open" : "closed") + ".");
            ctx.Require(Find.WindowStack.IsOpen(own), "The self-test's own window was closed.");
            ctx.Require(ticks.Paused, "The game runs although the self-test's own window pauses it.");
            own.Close(false);
            int tick = ticks.TicksGame;
            yield return ctx.WaitUntil(() => ticks.TicksGame != tick, 10f, "a tick once the windows are closed");
        }

        private static IEnumerator Environment(SelfTestContext ctx)
        {
            ctx.Require(ctx.Map != null && ctx.Map.Size.x > 0, "No map.");
            ctx.Require(!string.IsNullOrEmpty(CommandLine.Value("savedatafolder")), "Not started with -savedatafolder (a test profile).");
            ctx.Require(Find.Storyteller.storytellerComps.Count == 0, "Storyteller events were not disabled.");
            ctx.Require(Prefs.AutosaveIntervalDays >= SelfTestRunner.NoAutosaveDays, "Autosave was not disabled.");
            ctx.Require(Prefs.RunInBackground, "runInBackground is off in the test profile: an unfocused game stops.");
            ctx.Require(MyModGameComponent.Current != null, "The mod's GameComponent is missing.");
            yield break;
        }

        // Another mod logging an error every frame reaches Verse's 10000-message limit; the runner must turn logging
        // back on, or PASS, FAIL and DONE never reach the log.
        private static IEnumerator LogLimit(SelfTestContext ctx)
        {
            ctx.Require(SelfTestRunner.LogLimitField != null, "Log.reachedMaxMessagesLimit is gone: update KeepLogging.");
            SelfTestRunner.LogLimitField.SetValue(null, true);
            ctx.Defer(() => SelfTestRunner.LogLimitField.SetValue(null, false));
            yield return null;
            ctx.Require(!(bool)SelfTestRunner.LogLimitField.GetValue(null), "Logging stayed off after the message limit.");
        }
    }
}
