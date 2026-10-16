using System;
using UnityEngine;

namespace MyMod
{
    // 1.6 build: the engine is Unity. Everything the mod asks the engine directly, rather than through Verse, is
    // here; Engine.Waylith.cs is the 1.7 counterpart with the same members. Only this file and its counterpart may
    // differ between the two builds.
    internal static class Engine
    {
        // The version folder this dll was built for; the startup log names it.
        public const string BuildName = "1.6";

        // Unity's player log prints no severity: the test scripts recognise errors the game raises in the mod by the
        // mod's frames in the stack, so errors keep their stacks.
        public static void KeepErrorStackTraces()
            => Application.SetStackTraceLogType(LogType.Error, StackTraceLogType.ScriptOnly);

        // Calls listener with the text of every error logged, on whichever thread logged it.
        public static void ListenForErrors(Action<string> listener)
        {
            Application.logMessageReceivedThreaded += (condition, stackTrace, type) =>
            {
                if (type != LogType.Error && type != LogType.Exception && type != LogType.Assert)
                    return;
                try { listener(condition + "\n" + stackTrace); }
                catch { }
            };
        }

        // Asks the game to quit with an exit code. Unity's player exit code cannot be set from here; 1.6 always ends
        // with 0 and the test scripts judge by the log.
        public static void RequestExit(int code) => Verse.Root.Shutdown();

        // Last resort when RequestExit did not end the game.
        public static void ForceExit(int code) => Application.Quit(code);
    }
}
