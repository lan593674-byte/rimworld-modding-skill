using System;
using Microsoft.Extensions.Logging;
using Waylith;
using Waylith.Logging;

namespace MyMod
{
    // 1.7 build: the engine is Waylith. Everything the mod asks the engine directly, rather than through Verse, is
    // here, in Waylith's own API; Engine.Unity.cs is the 1.6 counterpart with the same members.
    internal static class Engine
    {
        public const string BuildName = "1.7";

        // Waylith's log writes the severity and stack of every error itself.
        public static void KeepErrorStackTraces() { }

        // Waylith publishes every log entry here, synchronously on the thread that logged it and while Verse holds its
        // log lock: the listener must be quick and thread-safe, and must not throw (LogStream does not catch).
        public static void ListenForErrors(Action<string> listener)
        {
            LogStream.MessageReceived += (level, category, message, stackTrace) =>
            {
                if (level != LogLevel.Error && level != LogLevel.Critical)
                    return;
                try { listener(message + "\n" + stackTrace); }
                catch { }
            };
        }

        // Root.Shutdown only asks to quit (Application.Quit, which other code may veto); the exit code is the engine's.
        public static void RequestExit(int code)
        {
            EngineApplication.Instance.ExitCode = code;
            Verse.Root.Shutdown();
        }

        // Quits without asking anyone.
        public static void ForceExit(int code) => EngineApplication.Instance.Quit(code);
    }
}
