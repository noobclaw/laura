// CI entry point. There is no editor on any of our machines, so everything a person
// would normally click (pipeline asset, base material, scene, player settings) is set up here.
using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

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
            foreach (var kv in new (string, object)[] { ("shadowDistance", 150f), ("msaaSampleCount", 4), ("supportsHDR", true), ("shadowCascadeCount", 2), ("mainLightShadowmapResolution", 4096), ("supportsSoftShadows", true) })
            {
                try { var pi = assetType.GetProperty(kv.Item1, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance); if (pi != null && pi.GetSetMethod(true) != null) pi.SetValue(asset, kv.Item2); else Debug.Log("CiBuild: no setter for " + kv.Item1); }
                catch (Exception e) { Debug.Log("CiBuild: could not set " + kv.Item1 + ": " + e.Message); }
            }
            EditorUtility.SetDirty(asset);
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

    static void Snap(Souq.Game g, string name)
    {
        var rt = new RenderTexture(720, 1560, 24, RenderTextureFormat.ARGB32);
        g.cam.targetTexture = rt; Canvas.ForceUpdateCanvases(); g.cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0); tex.Apply();
        RenderTexture.active = null; g.cam.targetTexture = null;
        Directory.CreateDirectory("../../../shots");
        File.WriteAllBytes("../../../shots/" + name + ".png", tex.EncodeToPNG());
        Debug.Log("CiBuild: wrote shot " + name);
    }

    // Plays a mid-game save for a while in the editor and saves pictures of it: the only way to see the game without a device.
    static void GameShots()
    {
        Debug.Log("CiBuild: shots on " + SystemInfo.graphicsDeviceType + " / " + SystemInfo.graphicsDeviceName);
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var s = Souq.Core.Save.Fresh();
        int[] lv = { 130, 62, 27, 9, 1 }; int[] st = { 5, 4, 3, 2, 1 };
        for (int d = 0; d < 5; d++) { s.dOpen[d] = true; s.dLevel[d] = lv[d]; s.dStaff[d] = st[d]; s.dSpeed[d] = 3; }
        s.cLevel[0] = 12; s.cLevel[1] = 8; s.cLevel[2] = 5; s.cLevel[3] = 2; s.cLevel[4] = 1;
        s.parkLevel = 5; s.adLevel = 42; s.coin = 7.4e12; s.gem = 345; s.task = 9; s.star = 1; s.lang = "en"; s.music = false; s.sfx = false;
        var g = new Souq.Game(); g.editor = true; g.Start(s, false);
        for (int i = 0; i < 1500; i++) g.Tick(0.05f);
        g.focus = new Vector3(0, 0, 8); g.zoom = 20f; g.PlaceCamera(); g.Tick(0.02f); Snap(g, "1_store");
        g.focus = new Vector3(0, 0, 14); g.zoom = 11f; g.PlaceCamera(); g.Tick(0.02f); Snap(g, "2_close");
        g.focus = new Vector3(0, 0, -6); g.zoom = 16f; g.PlaceCamera(); g.Tick(0.02f); Snap(g, "3_parking");
        g.focus = new Vector3(0, 0, 8); g.zoom = 20f; g.PlaceCamera();
        g.ui.OpenDept(1); for (int i = 0; i < 20; i++) g.Tick(0.03f); Snap(g, "4_department");
        g.ui.CloseSheet(); g.ui.Banner("x2", Souq.World.DeptColor[0]); g.ui.Confetti(new Vector2(540, 1300), 60); g.ui.FlyIcons(Souq.Spr.Coin, new Vector2(540, 900), g.ui.hud, 12);
        for (int i = 0; i < 12; i++) g.Tick(0.03f); Snap(g, "5_effects");
        for (int i = 0; i < 60; i++) g.Tick(0.03f);
        g.ui.OpenShop(); for (int i = 0; i < 20; i++) g.Tick(0.03f); Snap(g, "6_shop");
        g.ui.CloseSheet(); g.ui.OfflinePopup(3.2e13, 30000, true); for (int i = 0; i < 20; i++) g.Tick(0.03f); Snap(g, "7_offline");
        g.ui.ClosePopup(); g.SetLang(true); g.ui.OpenDept(0); for (int i = 0; i < 20; i++) g.Tick(0.03f); Snap(g, "8_arabic");
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
        var emis = new Material(shader); emis.EnableKeyword("_EMISSION"); emis.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
        if (emis.HasProperty("_EmissionColor")) emis.SetColor("_EmissionColor", Color.white);
        AssetDatabase.CreateAsset(emis, "Assets/Resources/BaseEmis.mat");
        AssetDatabase.SaveAssets(); AssetDatabase.Refresh();
        try { GameShots(); } catch (Exception e) { Debug.LogWarning("CiBuild: GameShots failed: " + e); }

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
