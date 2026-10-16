using System.Collections;

namespace MyMod.SelfTest
{
    // One self-test scenario: a coroutine the runner advances one step a frame (yield return null waits a frame;
    // yield return another IEnumerator runs it to the end first). Throwing fails the scenario, ctx.Skip(reason)
    // skips it, finishing passes it. Errors with the mod's prefix logged while it runs fail it too.
    //
    // A scenario makes everything it needs (colonists, items, buildings) and registers its clean-up with
    // ctx.Defer, which runs whether it passes, fails or times out. It must not hold Rand.PushState across a yield:
    // the game empties Verse.Rand's state stack every frame (Rand.EnsureStateStackEmpty).
    //
    // Small scenarios need no class: SelfTestRunner.Register(name, ctx => Body(ctx)).
    public interface ISelfTestScenario
    {
        string Name { get; }

        IEnumerator Run(SelfTestContext ctx);
    }
}
