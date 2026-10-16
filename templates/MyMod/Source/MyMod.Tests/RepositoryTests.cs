using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace MyMod.Tests
{
    // Checks every mod should pass, on the files of the repository.
    public class RepositoryTests
    {
        // The repository root: the folder above the test binaries that holds About\About.xml.
        private static readonly string Root = FindRoot();

        private static string FindRoot()
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
                if (File.Exists(Path.Combine(dir.FullName, "About", "About.xml"))) return dir.FullName;
            throw new InvalidOperationException("No About\\About.xml above " + AppContext.BaseDirectory);
        }

        private static IEnumerable<string> CodeFiles() => Directory
            .EnumerateFiles(Path.Combine(Root, "Source", "MyMod"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Split(Path.DirectorySeparatorChar).Any(part => part == "obj" || part == "bin"));

        private static Dictionary<string, HashSet<string>> KeyedByLanguage()
        {
            var result = new Dictionary<string, HashSet<string>>();
            foreach (var language in Directory.GetDirectories(Path.Combine(Root, "Languages")))
            {
                var keys = new HashSet<string>();
                var keyed = Path.Combine(language, "Keyed");
                if (Directory.Exists(keyed))
                    foreach (var file in Directory.GetFiles(keyed, "*.xml", SearchOption.AllDirectories))
                        foreach (var element in XDocument.Load(file).Root.Elements())
                            Assert.True(keys.Add(element.Name.LocalName), "Key " + element.Name.LocalName + " twice in " + language);
                result[Path.GetFileName(language)] = keys;
            }
            return result;
        }

        [Fact]
        public void EveryLanguageHasTheSameKeys()
        {
            var languages = KeyedByLanguage();
            Assert.True(languages.Count >= 2, "Expected at least two languages.");
            var english = languages["English"];
            foreach (var pair in languages)
            {
                Assert.Empty(english.Except(pair.Value).Select(k => pair.Key + " lacks " + k));
                Assert.Empty(pair.Value.Except(english).Select(k => "English lacks " + k + " of " + pair.Key));
            }
        }

        [Fact]
        public void EveryKeyTheCodeTranslatesExists()
        {
            var english = KeyedByLanguage()["English"];
            var used = CodeFiles().SelectMany(f => Regex.Matches(File.ReadAllText(f), "\"(MyMod_[A-Za-z0-9_]+)\"\\s*\\.Translate")
                .Cast<Match>().Select(m => m.Groups[1].Value)).Distinct();
            Assert.All(used, key => Assert.Contains(key, english));
        }

        // UI text goes through language keys; the only literal allowed to hold Chinese is the log prefix.
        [Fact]
        public void CodeHasNoChineseLiterals()
        {
            var bad = new List<string>();
            foreach (var file in CodeFiles())
            {
                var lines = File.ReadAllLines(file);
                for (int i = 0; i < lines.Length; i++)
                {
                    if (lines[i].Contains("public const string Prefix =")) continue;
                    if (lines[i].Any(c => c >= 0x2E80 && c <= 0x9FFF || c >= 0xF900 && c <= 0xFAFF || c >= 0xFF00 && c <= 0xFFEF))
                        bad.Add(Path.GetFileName(file) + ":" + (i + 1));
                }
            }
            Assert.Empty(bad);
        }

        // The test scripts read GameTest.psd1; the code has the same values as constants. They must agree.
        [Fact]
        public void TestSettingsMatchTheCode()
        {
            string settings = File.ReadAllText(Path.Combine(Root, "Source", "tools", "GameTest.psd1"));
            string Setting(string name) => Regex.Match(settings, "(?m)^\\s*" + name + "\\s*=\\s*'([^']*)'").Groups[1].Value;
            string Constant(string file, string name) => Regex.Match(File.ReadAllText(Path.Combine(Root, "Source", "MyMod", file)),
                "const string " + name + " = \"([^\"]*)\"").Groups[1].Value;
            Assert.Equal(Setting("LogPrefix"), Constant("ModLog.cs", "Prefix"));
            Assert.Equal(Setting("ArgPrefix"), Constant(Path.Combine("SelfTest", "SelfTestSetup.cs"), "ArgPrefix"));
            string about = File.ReadAllText(Path.Combine(Root, "About", "About.xml"));
            Assert.Contains("<packageId>" + Setting("PackageId") + "</packageId>", about, StringComparison.OrdinalIgnoreCase);
        }
    }
}
