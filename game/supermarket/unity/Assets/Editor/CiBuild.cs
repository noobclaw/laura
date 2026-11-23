// CI entry point. There is no editor on any of our machines, so everything a person
// would normally click (pipeline asset, base material, scene, player settings) is set up here.
using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

public static class CiBuild
{
    static string Arg(string name, string fallback)
    {
        var a = Environment.GetCommandLineArgs();
        for (int i = 0; i < a.Length - 1; i++) if (a[i] == name) return a[i + 1];
        return fallback;
    }

    // URP types are reached by name so that an API change shows up as a logged
    // exception instead of a compile error that hides everything else.
    static bool SetupUrp()
    {
        try
        {
            const string asm = "Unity.RenderPipelines.Universal.Runtime";
            var dataType = Type.GetType("UnityEngine.Rendering.Universal.UniversalRendererData, " + asm, true);
            var assetType = Type.GetType("UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset, " + asm, true);

            var data = ScriptableObject.CreateInstance(dataType);
            AssetDatabase.CreateAsset(data, "Assets/Settings/Renderer.asset");
            var pkgPath = (string)assetType.GetField("packagePath").GetValue(null);
            var reloader = Type.GetType("UnityEngine.Rendering.ResourceReloader, Unity.RenderPipelines.Core.Runtime", true);
            reloader.GetMethod("ReloadAllNullIn", new[] { typeof(object), typeof(string) }).Invoke(null, new object[] { data, pkgPath });
            EditorUtility.SetDirty(data);

            var create = assetType.GetMethod("Create", new[] { Type.GetType("UnityEngine.Rendering.Universal.ScriptableRendererData, " + asm, true) });
            var asset = (RenderPipelineAsset)create.Invoke(null, new object[] { data });
            AssetDatabase.CreateAsset(asset, "Assets/Settings/URP.asset");
            GraphicsSettings.defaultRenderPipeline = asset;
            QualitySettings.renderPipeline = asset;
            AssetDatabase.SaveAssets();
            Debug.Log("CiBuild: URP asset created");
            return true;
        }
        catch (Exception e)
        {
            Debug.LogWarning("CiBuild: URP setup failed, falling back to built-in pipeline: " + e);
            return false;
        }
    }

    public static void IOS()
    {
        Directory.CreateDirectory("Assets/Settings");
        Directory.CreateDirectory("Assets/Resources");
        Directory.CreateDirectory("Assets/Scenes");
        AssetDatabase.Refresh();

        PlayerSettings.colorSpace = ColorSpace.Linear;
        bool urp = SetupUrp();

        // A material asset keeps the lit shader in the build; runtime objects clone it.
        var shader = (urp ? Shader.Find("Universal Render Pipeline/Lit") : null) ?? Shader.Find("Standard");
        Debug.Log("CiBuild: base shader = " + (shader ? shader.name : "none"));
        AssetDatabase.CreateAsset(new Material(shader), "Assets/Resources/BaseLit.mat");

        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity");

        PlayerSettings.companyName = "noobclaw";
        PlayerSettings.productName = "Souq Tycoon";
        PlayerSettings.SetApplicationIdentifier(UnityEditor.Build.NamedBuildTarget.iOS, "com.noobclaw.souq");
        PlayerSettings.bundleVersion = "0.1.0";
        PlayerSettings.iOS.buildNumber = Arg("-buildNumber", "1");
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
        PlayerSettings.iOS.targetOSVersionString = "15.0";
        // One 1024 px source; Unity scales it to every slot, including the App Store one.
        var icon = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Icon/icon.png");
        if (icon == null) throw new Exception("Assets/Icon/icon.png missing");
        PlayerSettings.SetIcons(UnityEditor.Build.NamedBuildTarget.Unknown, new[] { icon }, IconKind.Any);
        AssetDatabase.SaveAssets();

        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { "Assets/Scenes/Main.unity" },
            locationPathName = Arg("-customBuildPath", "build/iOS/iOS"),
            target = BuildTarget.iOS,
            options = BuildOptions.None,
        });
        var ok = report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;
        Debug.Log("CiBuild result: " + report.summary.result + ", errors: " + report.summary.totalErrors + ", urp: " + urp);
        EditorApplication.Exit(ok ? 0 : 1);
    }
}
