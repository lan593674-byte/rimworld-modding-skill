using System;
using Microsoft.Extensions.Logging;
using Waylith;
using Waylith.Logging;

namespace GameTestLoader
{
    // 1.7 build: Waylith's log stream and its main loop. Host.Unity.cs is the 1.6 counterpart. Neither callback may
    // throw: LogStream passes an exception back into the code that logged, and an exception from PrePollEvents
    // reaches the engine's main loop and ends the game.
    internal static class Host
    {
        // Every log entry, synchronously on the thread that logged it.
        public static void ListenForErrors(Action<string> onError)
        {
            LogStream.MessageReceived += (level, category, message, stackTrace) =>
            {
                if (level != LogLevel.Error && level != LogLevel.Critical) return;
                try { onError(message); } catch { }
            };
        }

        // Once a frame on the main thread, before input is polled and the game updates.
        public static void CallEveryFrame(Action update)
        {
            EngineApplication.Instance.PrePollEvents += _ =>
            {
                try { update(); }
                catch (Exception ex) { Verse.Log.Message("[TESTLOADER] FAIL frame hook: " + ex); }
            };
        }
    }
}
