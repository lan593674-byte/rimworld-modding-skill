using MyMod.SelfTest;
using Verse;

namespace MyMod
{
    // The mod's per-game state (a stand-in: one saved counter) and the hooks that drive the self-test. The game
    // creates one of these for every game, new or loaded, and calls the hooks only while a game is running.
    public sealed class MyModGameComponent : GameComponent
    {
        public int counter;

        public MyModGameComponent(Game game) { }

        public static MyModGameComponent Current => Verse.Current.Game?.GetComponent<MyModGameComponent>();

        // One line describing everything the mod saved. The save-safety test compares it before removing the mod and
        // after adding it back (-mymod-makesave writes it, -mymod-reportload prints it on load).
        public string Summary() => "counter=" + counter;

        public override void ExposeData()
        {
            Scribe_Values.Look(ref counter, "counter");
        }

        public override void LoadedGame()
        {
            if (CommandLine.Has(SelfTestSetup.ArgPrefix + "-reportload"))
                ModLog.Message("loaded save: " + Summary());
        }

        // The self-test hooks cost one static bool check a frame outside a test.
        public override void GameComponentUpdate()
        {
            if (SelfTestRunner.Enabled)
                ModLog.Guard("selftest.update", SelfTestRunner.Update);
        }

        public override void GameComponentOnGUI()
        {
            if (SelfTestRunner.Enabled)
                ModLog.Guard("selftest.ongui", SelfTestRunner.OnGUI);
        }
    }
}
