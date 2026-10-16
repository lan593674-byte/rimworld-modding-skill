using System.Collections;
using RimWorld;
using UnityEngine;
using Verse;

namespace MyMod.SelfTest
{
    // Examples of the usual kinds of scenario; replace them with the mod's own.

    // A class-based scenario: the mod's data survive a real save and load.
    internal sealed class SaveRoundTripScenario : ISelfTestScenario
    {
        public string Name => "save: the counter survives saving and loading";

        public IEnumerator Run(SelfTestContext ctx)
        {
            MyModGameComponent.Current.counter = 42;
            yield return ctx.SaveAndReload("roundtrip");
            // A new game object now: fetch the component again.
            ctx.Require(MyModGameComponent.Current.counter == 42, "counter is " + MyModGameComponent.Current.counter + " after loading.");
        }
    }

    internal static class ExampleScenarios
    {
        // A fixture pawn living through half a day at full speed; wait on the outcome, not on a fixed number of frames.
        public static IEnumerator ColonistWorks(SelfTestContext ctx)
        {
            var pawn = ctx.MakeColonist();
            int start = Find.TickManager.TicksGame;
            ctx.RunGame(TimeSpeed.Ultrafast);
            yield return ctx.WaitUntil(() => pawn.Dead || Find.TickManager.TicksGame - start >= GenDate.TicksPerDay / 2, 150f, "half a game day");
            ctx.Require(!pawn.Dead, "The colonist died: " + pawn.health?.hediffSet?.hediffs?.Count + " hediffs.");
            ctx.Require(pawn.Spawned, "The colonist is gone from the map.");
        }

        // A drawing check: measured inside OnGUI (Text only works there), skipped in a window without OnGUI.
        public static IEnumerator GreetingFits(SelfTestContext ctx)
        {
            float width = 0f;
            yield return ctx.Draw(() =>
            {
                Text.Font = GameFont.Small;
                width = Text.CalcSize("MyMod_Greeting".Translate()).x;
            });
            ctx.Require(width > 0f && width <= 300f, "The greeting is " + width + " px wide; the label is 300.");
        }

        // Times code the mod runs every frame or tick (here a stand-in); the report quotes the numbers of the vanilla
        // and the full profile.
        public static IEnumerator SummaryPerf(SelfTestContext ctx)
        {
            var component = MyModGameComponent.Current;
            ctx.Measure("Summary", () => component.Summary(), 1000, 0.01);
            yield break;
        }

        // Opens the window to photograph; it is closed again when the capture ends.
        public static IEnumerator OpenGreeting(SelfTestContext ctx)
        {
            var dialog = new Dialog_MessageBox("MyMod_Greeting".Translate());
            Find.WindowStack.Add(dialog);
            ctx.Defer(() => dialog.Close(false));
            yield return ctx.WaitFrames(5);
        }
    }
}
