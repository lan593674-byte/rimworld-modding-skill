using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace MyMod.SelfTest
{
    // Prints "[DIAG]" lines at the start of a self-test: which other mods patched the vanilla methods this mod
    // depends on (SelfTestSetup.DiagnosticTargets), so a compatibility failure shows who intercepts what. Harmony is
    // found by reflection (the mod need not reference it), and every patch list of HarmonyLib.Patches is read,
    // including the Inner* kinds Harmony 3.0 (RimWorld 1.7) added.
    internal static class CompatDiagnostics
    {
        public static void Log(IEnumerable<MethodBase> targets)
        {
            var harmonies = AppDomain.CurrentDomain.GetAssemblies().Where(a => a.GetName().Name == "0Harmony").ToList();
            var harmony = harmonies.Select(a => a.GetType("HarmonyLib.Harmony")).FirstOrDefault(t => t != null);
            if (harmony == null)
            {
                ModLog.Message("[DIAG] Harmony not loaded; no patch report.");
                return;
            }
            ModLog.Message("[DIAG] Harmony " + string.Join(", ", harmonies.Select(a => a.GetName().Version.ToString()).ToArray())
                + (harmonies.Count > 1 ? " (more than one Harmony assembly is loaded)" : string.Empty));
            var getInfo = harmony.GetMethod("GetPatchInfo", new[] { typeof(MethodBase) });
            foreach (var method in targets)
            {
                if (method == null)
                {
                    ModLog.Message("[DIAG] missing target (renamed in this game version?)");
                    continue;
                }
                string name = method.DeclaringType?.FullName + "." + method.Name;
                object info = getInfo.Invoke(null, new object[] { method });
                if (info == null)
                {
                    ModLog.Message("[DIAG] " + name + ": no patches");
                    continue;
                }
                foreach (var field in info.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance))
                {
                    if (!(field.GetValue(info) is IEnumerable patches) || field.FieldType == typeof(string)) continue;
                    foreach (object patch in patches)
                    {
                        string owner = Member(patch, "owner") as string;
                        var patchMethod = Member(patch, "PatchMethod") as MethodInfo;
                        ModLog.Message("[DIAG] " + name + " " + field.Name + " owner=" + owner + " patch="
                            + patchMethod?.DeclaringType?.FullName + "." + patchMethod?.Name
                            + " assembly=" + patchMethod?.DeclaringType?.Assembly.GetName().Name);
                    }
                }
            }
        }

        private static object Member(object value, string name)
            => value?.GetType().GetField(name)?.GetValue(value) ?? value?.GetType().GetProperty(name)?.GetValue(value, null);
    }
}
