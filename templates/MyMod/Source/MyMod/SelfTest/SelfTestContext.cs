using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Reflection;
using RimWorld;
using Verse;

namespace MyMod.SelfTest
{
    // What scenarios get: checks, waits, fixtures. Scenarios own their fixtures; everything registered with Defer is
    // undone when the scenario ends, however it ends.
    public sealed class SelfTestContext
    {
        public sealed class SkipException : Exception
        {
            public SkipException(string reason) : base(reason) { }
        }

        private readonly List<Action> deferred = new List<Action>();

        public string ScenarioName { get; private set; }
        public Map Map => Find.CurrentMap;

        internal void Begin(string name)
        {
            ScenarioName = name;
            deferred.Clear();
        }

        // ---- Checks ----

        public void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        // Ends the scenario as SKIP (counted apart from passes): for checks that cannot run here, such as drawing
        // in a window that gets no OnGUI.
        public void Skip(string reason) => throw new SkipException(reason);

        // Runs when the scenario ends (pass, fail, skip or timeout), last registered first.
        public void Defer(Action undo) => deferred.Add(undo);

        internal void RunDeferred()
        {
            for (int i = deferred.Count - 1; i >= 0; i--)
            {
                try { deferred[i](); }
                catch (Exception ex) { ModLog.Message("[SELFTEST] NOTE clean-up of " + ScenarioName + " failed: " + ex.Message); }
            }
            deferred.Clear();
        }

        // ---- Time ----

        // Runs game ticks right now, a batch a frame. MapUpdate (power nets, graphics) does not run in between:
        // a scenario that needs it waits real frames instead (WaitUntil with the game running).
        public IEnumerator AdvanceTicks(int ticks, int perFrame = 250)
        {
            Require(ticks >= 0 && perFrame > 0, "Tick counts must be positive.");
            for (int done = 0; done < ticks; done++)
            {
                Find.TickManager.DoSingleTick();
                if ((done + 1) % perFrame == 0) yield return null;
            }
        }

        public IEnumerator WaitFrames(int frames)
        {
            for (int i = 0; i < frames; i++) yield return null;
        }

        public IEnumerator WaitSeconds(float seconds)
        {
            var clock = Stopwatch.StartNew();
            while (clock.Elapsed.TotalSeconds < seconds) yield return null;
        }

        // Waits for a condition in real time and fails with the state of the game when it does not come. Wait on the
        // value you need rather than a fixed number of ticks: pawns act every UpdateRateTicks (up to 15 in vanilla,
        // 60 with mods such as Slower Pawn Tick Rate).
        public IEnumerator WaitUntil(Func<bool> done, float seconds, string what)
        {
            var clock = Stopwatch.StartNew();
            int startTick = Find.TickManager.TicksGame;
            while (!done())
            {
                if (clock.Elapsed.TotalSeconds > seconds)
                    throw new TimeoutException(what + ": not after " + seconds.ToString("0.#", CultureInfo.InvariantCulture) + " s (ticks +"
                        + (Find.TickManager.TicksGame - startTick) + ", speed " + Find.TickManager.CurTimeSpeed + ", forcePaused "
                        + Find.TickManager.ForcePaused + ")");
                yield return null;
            }
        }

        // Lets the game run at a speed until the scenario ends. The game ignores the change without a word while the
        // player has no control (screen fading in, a cutscene): fail here rather than time out later at Normal speed.
        public void RunGame(TimeSpeed speed = TimeSpeed.Normal)
        {
            Find.TickManager.CurTimeSpeed = speed;
            Require(Find.TickManager.CurTimeSpeed == speed, "The game refused speed " + speed + " (screen fading: "
                + ScreenFader.IsFading() + ").");
        }

        // ---- Saving ----

        // Saves the game for real and loads it back; the scenario goes on in the loaded game (fetch components and
        // things again: the old objects belong to the unloaded game).
        public IEnumerator SaveAndReload(string name)
        {
            int before = SelfTestRunner.ReloadCount;
            SelfTestRunner.SaveAndReload(name);
            while (SelfTestRunner.ReloadCount == before) yield return null;
            yield return WaitUntil(() => !ScreenFader.IsFading(), 10f, "screen fade-in after loading");
        }

        // ---- Drawing ----

        // Runs draw inside OnGUI (Repaint only when repaintOnly: textures and screenshots) and waits for it. A window
        // that gets no OnGUI (a hidden 1.6 window) skips the scenario instead of passing it unseen.
        public IEnumerator Draw(Action draw, bool repaintOnly = false, int frames = 300)
        {
            SelfTestRunner.QueueGui(draw, repaintOnly);
            for (int i = 0; i < frames && !SelfTestRunner.GuiDone; i++) yield return null;
            if (!SelfTestRunner.GuiDone)
            {
                SelfTestRunner.QueueGui(null, false);
                if (!SelfTestRunner.GuiSeen) Skip("the game window gets no OnGUI (hidden window?)");
                throw new TimeoutException("No " + (repaintOnly ? "Repaint" : "OnGUI") + " event within " + frames + " frames.");
            }
            if (SelfTestRunner.GuiError != null)
                throw new InvalidOperationException("Drawing failed: " + SelfTestRunner.GuiError.Message, SelfTestRunner.GuiError);
        }

        // 1.6 reports a screen of almost 0 x 0 while minimized; windows then fall back to default sizes and are laid
        // out again once the window is restored. Checks against the screen size are only meaningful when this holds.
        public bool ScreenValid => UI.screenWidth >= 100 && UI.screenHeight >= 100;

        // ---- Fixtures ----

        // The cell nearest the map centre (searched over the whole map: random maps can be all mountain or ruins
        // near the centre) whose width x height rectangle is free: standable, unfogged, empty.
        public IntVec3 FindOpenCell(int width = 1, int height = 1)
        {
            var map = Map;
            var center = map.Center;
            foreach (var cell in map.AllCells.OrderBy(c => c.DistanceToSquared(center)))
            {
                var rect = new CellRect(cell.x, cell.z, width, height);
                if (!rect.InBounds(map)) continue;
                bool free = true;
                foreach (var c in rect)
                {
                    if (!c.Standable(map) || c.Fogged(map) || c.GetThingList(map).Count > 0 || c.Roofed(map) && c.GetRoof(map).isThickRoof)
                    {
                        free = false;
                        break;
                    }
                }
                if (free) return cell;
            }
            throw new InvalidOperationException("No free " + width + "x" + height + " area on the map.");
        }

        // A new player colonist on a free cell, removed when the scenario ends. Without the Wimp trait (its shock
        // threshold of 0.3 drops it at the first wound) and with full needs, so it does what the scenario expects.
        public Pawn MakeColonist()
        {
            Pawn pawn = null;
            for (int attempt = 0; attempt < 50 && pawn == null; attempt++)
            {
                try { pawn = PawnGenerator.GeneratePawn(PawnKindDefOf.Colonist, Faction.OfPlayer); }
                catch (Exception) when (attempt < 49) { }
            }
            var wimp = pawn.story?.traits?.GetTrait(TraitDefOf.Wimp);
            if (wimp != null) pawn.story.traits.RemoveTrait(wimp);
            GenSpawn.Spawn(pawn, FindOpenCell(), Map);
            KeepAlive(pawn);
            Defer(() => { if (!pawn.Destroyed) pawn.Destroy(); });
            return pawn;
        }

        // Fills needs and removes what would kill or down a test pawn left outside for days (cold, heat, hunger).
        public void KeepAlive(Pawn pawn)
        {
            if (pawn.needs != null)
                foreach (var need in pawn.needs.AllNeeds) need.CurLevelPercentage = 1f;
            var bad = pawn.health.hediffSet.hediffs.Where(h => h.def.isBad && !(h is Hediff_MissingPart)).ToList();
            foreach (var hediff in bad) pawn.health.RemoveHediff(hediff);
        }

        // ---- Measuring ----

        // Times action (after one warm-up call for the JIT) and logs "[PERF] <label> meanMs=... samples=... budgetMs=...".
        // Fails only above three times the budget, so a slow machine does not fail the test; the report quotes the numbers.
        public double Measure(string label, Action action, int samples, double budgetMs)
        {
            action();
            var clock = Stopwatch.StartNew();
            for (int i = 0; i < samples; i++) action();
            double mean = clock.Elapsed.TotalMilliseconds / Math.Max(1, samples);
            ModLog.Message("[PERF] " + label + " meanMs=" + mean.ToString("0.0000", CultureInfo.InvariantCulture) + " samples=" + samples
                + " budgetMs=" + budgetMs.ToString("0.####", CultureInfo.InvariantCulture));
            Require(mean <= budgetMs * 3, label + " took " + mean.ToString("0.000", CultureInfo.InvariantCulture) + " ms, budget " + budgetMs + " ms.");
            return mean;
        }

        // ---- Preferences ----

        // Writes a PrefsData field directly. The Prefs property setters call Prefs.Apply, which resets the screen
        // resolution. Only the isolated test profile's prefs are affected.
        public static void SetPref(string field, object value)
        {
            var data = typeof(Prefs).GetField("data", BindingFlags.NonPublic | BindingFlags.Static)?.GetValue(null);
            var target = data?.GetType().GetField(field, BindingFlags.Public | BindingFlags.Instance);
            if (target == null) throw new MissingFieldException("PrefsData", field);
            target.SetValue(data, Convert.ChangeType(value, target.FieldType, CultureInfo.InvariantCulture));
        }
    }
}
