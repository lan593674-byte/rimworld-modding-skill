using System;
using System.Collections;
using System.IO;
using UnityEngine;
using Verse;

namespace MyMod.SelfTest
{
    // Screenshots for layout review (Source\tools\run-capture.ps1, a visible window). Each registered capture is one
    // picture: SelfTestSetup.RegisterCaptures calls Add(file, prepare), prepare opens the UI to show, and Take waits
    // for the screen to settle, shoots it into the folder given by -<prefix>-shots=, and logs "[CAPTURE] SHOT <file>".
    public static class CaptureKit
    {
        private const int SettleFrames = 20;
        private const int WriteTimeoutFrames = 600;

        public static string ShotDir => CommandLine.Value(SelfTestSetup.ArgPrefix + "-shots");

        public static void Add(string file, Func<SelfTestContext, IEnumerator> prepare, float timeoutSeconds = 120f)
            => SelfTestRunner.Register(file, ctx => Take(ctx, file, prepare), timeoutSeconds);

        internal static void PrepareFolder()
        {
            if (string.IsNullOrEmpty(ShotDir)) throw new InvalidOperationException("Capture mode needs -" + SelfTestSetup.ArgPrefix + "-shots=<folder>.");
            SelfTestRunner.RequireTestProfile(Path.Combine(ShotDir, "x.png"));
            Directory.CreateDirectory(ShotDir);
        }

        private static IEnumerator Take(SelfTestContext ctx, string file, Func<SelfTestContext, IEnumerator> prepare)
        {
            ctx.Require(ctx.ScreenValid, "The screen is " + UI.screenWidth + "x" + UI.screenHeight + ": not a visible window.");
            yield return prepare(ctx);
            // The map fades in from black for half a second after loading.
            yield return ctx.WaitUntil(() => !ScreenFader.IsFading(), 10f, "screen fade-in");
            // New letters slide into the letter stack for a second (Letter.arrivalTime, real time).
            yield return ctx.WaitUntil(LettersSettled, 10f, "letters sliding in");
            // The previous shot's "screenshot saved" message and any trade message would cover the top of the screen;
            // the debug log window opens on errors (a full mod list always has some).
            Messages.Clear();
            Find.WindowStack.TryRemove(typeof(LudeonTK.EditWindow_Log), false);
            yield return ctx.WaitFrames(SettleFrames);

            string name = Path.GetFileNameWithoutExtension(file);
            string source = Path.Combine(GenFilePaths.ScreenshotFolderPath, name + ".png");
            string target = Path.Combine(ShotDir, file);
            SelfTestRunner.RequireTestProfile(source);
            if (File.Exists(source)) File.Delete(source);
            DateTime requested = DateTime.UtcNow;
            // Requested from a Repaint: the game shows its "saved" message in the frame after the request, so a request
            // from elsewhere could capture its own message on 1.7.
            yield return ctx.Draw(() => ScreenshotTaker.TakeNonSteamShot(name), repaintOnly: true);
            long lastSize = -1;
            int stable = 0;
            for (int frame = 0; frame < WriteTimeoutFrames; frame++)
            {
                yield return null;
                long size = File.Exists(source) ? new FileInfo(source).Length : -1;
                if (size > 0 && size == lastSize && ++stable >= 3)
                {
                    if (File.GetLastWriteTimeUtc(source) < requested.AddSeconds(-2))
                        throw new InvalidOperationException("Old screenshot: " + source + " was written before it was requested.");
                    // 1.7 writes the file from a worker task: it may still be open; try again next frame.
                    if (TryMove(source, target))
                    {
                        ModLog.Message("[CAPTURE] SHOT " + file);
                        yield break;
                    }
                }
                else if (size != lastSize) stable = 0;
                lastSize = size;
            }
            throw new InvalidOperationException("The screenshot was not written: " + source);
        }

        private static bool LettersSettled()
        {
            foreach (var letter in Find.LetterStack.LettersListForReading)
                if (Time.time - letter.arrivalTime < 1.1f) return false;
            return true;
        }

        private static bool TryMove(string source, string target)
        {
            try
            {
                if (File.Exists(target)) File.Delete(target);
                File.Move(source, target);
                return true;
            }
            catch (IOException) { return false; }
        }
    }
}
