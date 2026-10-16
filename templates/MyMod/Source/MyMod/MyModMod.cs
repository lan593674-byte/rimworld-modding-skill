using HarmonyLib;
using MyMod.SelfTest;
using Verse;

namespace MyMod
{
    // The mod's entry point; the game constructs it before loading any Def.
    public sealed class MyModMod : Mod
    {
        public MyModMod(ModContentPack content) : base(content)
        {
            // First, so that nothing that throws below can hide it: the test scripts check which build the game
            // loaded by this line (Source\SourceHash.targets, Get-SourceHash in Source\tools\GameRuntime.ps1).
            ModLog.Message("loaded build=" + Engine.BuildName + " source=" + BuildInfo.SourceHash);
            Engine.KeepErrorStackTraces();
            new Harmony("yourname.mymod").PatchAll(typeof(MyModMod).Assembly);
            SelfTestRunner.Initialize();
        }
    }

    public static class BuildInfo
    {
        private static string sourceHash;

        // The AssemblyMetadata "<AssemblyName>.SourceHash" the build embeds, or "none".
        public static string SourceHash
        {
            get
            {
                if (sourceHash != null)
                    return sourceHash;
                var assembly = typeof(BuildInfo).Assembly;
                string key = assembly.GetName().Name + ".SourceHash";
                sourceHash = "none";
                foreach (object attribute in assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyMetadataAttribute), false))
                {
                    var metadata = (System.Reflection.AssemblyMetadataAttribute)attribute;
                    if (metadata.Key == key && metadata.Value != null)
                        sourceHash = metadata.Value;
                }
                return sourceHash;
            }
        }
    }
}
