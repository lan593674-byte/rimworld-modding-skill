using System.Collections;
using RimWorld;
using Verse;

namespace MyMod.SelfTest
{
    // Checks of the test set-up itself; they run first in every self-test, Smoke included.
    internal static class BuiltinScenarios
    {
        public static void Register()
        {
            SelfTestRunner.Register("builtin: test environment", Environment);
            SelfTestRunner.Register("builtin: log reopens after the 10000-message limit", LogLimit);
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
