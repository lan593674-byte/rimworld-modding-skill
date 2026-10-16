using System;
using Verse;

namespace MyMod
{
    // Every log line of the mod goes through here and starts with Prefix: the only literal in the code that may hold
    // Chinese, for a Chinese mod name ("[MyMod]" here; keep it equal to LogPrefix in Source\tools\GameTest.psd1).
    // Errors also carry "[ERROR]": 1.6 writes no severity into its log, and the test scripts find the mod's errors
    // on both game versions by "<prefix> [ERROR]".
    public static class ModLog
    {
        public const string Prefix = "[MyMod]";

        public static void Message(string text) => Log.Message(Prefix + " " + text);

        public static void Warning(string text) => Log.Warning(Prefix + " " + text);

        public static void Error(string text) => Log.Error(Prefix + " [ERROR] " + text);

        // Once per key for the whole session (Verse keys ErrorOnce by an int).
        public static void ErrorOnce(string key, string text) => Log.ErrorOnce(Prefix + " [ERROR] " + text, StableHash(key));

        // Runs an action from a game callback (tick, timer, patch) so that an exception ends up as one prefixed
        // error instead of escaping into the game.
        public static void Guard(string key, Action action)
        {
            try { action(); }
            catch (Exception ex) { ErrorOnce(key, key + ": " + ex); }
        }

        // string.GetHashCode differs between runtimes (.NET 10 randomizes it per process); keys must not collide
        // with other mods' by accident, so they are hashed with the prefix.
        private static int StableHash(string key)
        {
            unchecked
            {
                int hash = (int)2166136261;
                foreach (char c in Prefix + key)
                    hash = (hash ^ c) * 16777619;
                return hash;
            }
        }
    }
}
