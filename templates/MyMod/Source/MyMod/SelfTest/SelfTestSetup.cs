using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using RimWorld;
using Verse;

namespace MyMod.SelfTest
{
    // The mod-specific part of the self-test: everything a new mod changes is in this file (and the scenario files
    // it registers). The rest of SelfTest\ is generic.
    public static class SelfTestSetup
    {
        // Command-line prefix: -mymod-selftest etc. Keep it equal to ArgPrefix in Source\tools\GameTest.psd1.
        public const string ArgPrefix = "mymod";

        // Every scenario of the self-test, in order. Each gets DefaultTimeoutSeconds unless given its own.
        public static void RegisterScenarios()
        {
            SelfTestRunner.Register(new SaveRoundTripScenario());
            SelfTestRunner.Register("colonist: lives through half a day", ExampleScenarios.ColonistWorks, 180f);
            SelfTestRunner.Register("ui: the greeting fits its label", ExampleScenarios.GreetingFits);
            SelfTestRunner.Register("perf: Summary", ExampleScenarios.SummaryPerf);
        }

        // Screenshots for run-capture.ps1, one picture each.
        public static void RegisterCaptures()
        {
            CaptureKit.Add("01_greeting.png", ExampleScenarios.OpenGreeting);
        }

        // Vanilla methods the mod patches or depends on: the [DIAG] lines list other mods' patches on them.
        public static IEnumerable<MethodBase> DiagnosticTargets()
        {
            yield return AccessTools.Method(typeof(TickManager), nameof(TickManager.DoSingleTick));
        }

        // Builds a game holding every kind of data the mod saves, for the save-safety test (-mymod-makesave).
        public static IEnumerator MakeSaveFixture(SelfTestContext ctx)
        {
            MyModGameComponent.Current.counter = 7;
            yield break;
        }

        // The mod's saved data in one line; equal before removing the mod and after adding it back.
        public static string Summary() => MyModGameComponent.Current?.Summary() ?? "no component";
    }
}
