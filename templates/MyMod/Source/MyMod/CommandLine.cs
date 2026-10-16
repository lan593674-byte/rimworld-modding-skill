using System;

namespace MyMod
{
    // The game's command line, read the same way on both versions. GenCommandLine.TryGetCommandLineArg wants a value
    // without "=" in it; here the value is everything after the first "=", so paths and patterns may hold "=".
    public static class CommandLine
    {
        private static readonly string[] args = Environment.GetCommandLineArgs();

        // Whether -name (or -name=value) was passed. Names compare case-insensitively, like the game's.
        public static bool Has(string name) => Value(name) != null;

        // The value of -name=value, "" for a bare -name, or null when absent.
        public static string Value(string name)
        {
            for (int i = 1; i < args.Length; i++)
            {
                string arg = args[i].TrimStart('-');
                int eq = arg.IndexOf('=');
                string key = eq < 0 ? arg : arg.Substring(0, eq);
                if (string.Equals(key, name, StringComparison.OrdinalIgnoreCase))
                    return eq < 0 ? string.Empty : arg.Substring(eq + 1);
            }
            return null;
        }
    }
}
