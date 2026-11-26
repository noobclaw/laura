#if UNITY_IOS
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

// The App Store lists an app's languages from the .lproj folders in the bundle.
// The game localizes itself at runtime, so Unity ships no .lproj folders and the
// store page showed "English" only. This adds one folder per shipped language
// and declares the same list in Info.plist.
public static class IosLocalizations
{
    static readonly string[] Langs = { "en", "ar", "ja", "ko", "de", "fr", "es", "zh-Hant" };

    [PostProcessBuild(100)]
    public static void OnPostprocessBuild(BuildTarget target, string path)
    {
        if (target != BuildTarget.iOS) return;
        var projPath = PBXProject.GetPBXProjectPath(path);
        var proj = new PBXProject();
        proj.ReadFromFile(projPath);
        var main = proj.GetUnityMainTargetGuid();
        foreach (var l in Langs)
        {
            var name = l + ".lproj";
            var dir = Path.Combine(path, name);
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "InfoPlist.strings"), "\"CFBundleDisplayName\" = \"Souq Tycoon\";\n");
            if (proj.FindFileGuidByProjectPath(name) == null)
                proj.AddFileToBuild(main, proj.AddFolderReference(name, name));
        }
        proj.WriteToFile(projPath);

        var plistPath = Path.Combine(path, "Info.plist");
        var plist = new PlistDocument();
        plist.ReadFromFile(plistPath);
        var arr = plist.root.CreateArray("CFBundleLocalizations");
        foreach (var l in Langs) arr.AddString(l);
        plist.WriteToFile(plistPath);
    }
}
#endif
