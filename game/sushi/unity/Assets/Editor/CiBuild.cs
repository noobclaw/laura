// Cloud build entry point for Dont Eat Sushi. Everything a person would click in the editor
// (pipeline asset, base materials, scene, player settings) is set up here, as in game/supermarket.
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

    // URP types are reached by name so an API change shows up as a logged exception, not a compile error.
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
            foreach (var kv in new (string, object)[] { ("shadowDistance", 60f), ("msaaSampleCount", 4), ("supportsHDR", true), ("shadowCascadeCount", 2), ("mainLightShadowmapResolution", 2048), ("supportsSoftShadows", true) })
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

    public static void Setup()
    {
        Directory.CreateDirectory("Assets/Settings");
        Directory.CreateDirectory("Assets/Resources");
        Directory.CreateDirectory("Assets/Scenes");
        AssetDatabase.Refresh();

        PlayerSettings.colorSpace = ColorSpace.Linear;
        bool urp = SetupUrp();

        // Material assets keep the shaders in the build; the game clones them at run time.
        var lit = (urp ? Shader.Find("Universal Render Pipeline/Lit") : null) ?? Shader.Find("Standard");
        var unlit = (urp ? Shader.Find("Universal Render Pipeline/Unlit") : null) ?? Shader.Find("Unlit/Color");
        Debug.Log("CiBuild: lit = " + (lit ? lit.name : "none") + ", unlit = " + (unlit ? unlit.name : "none"));
        AssetDatabase.CreateAsset(new Material(lit), "Assets/Resources/SushiLit.mat");
        AssetDatabase.CreateAsset(new Material(unlit), "Assets/Resources/SushiUnlit.mat");
        AssetDatabase.SaveAssets(); AssetDatabase.Refresh();
    }

    // Builds the scene without entering play mode and saves pictures, so the look can be reviewed without a machine.
    static void Snap(Camera cam, RenderTexture rt, string name)
    {
        cam.targetTexture = rt; cam.Render();
        RenderTexture.active = rt;
        var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0); tex.Apply();
        RenderTexture.active = null;
        Directory.CreateDirectory("../../../shots");
        File.WriteAllBytes("../../../shots/" + name + ".png", tex.EncodeToPNG());
        Debug.Log("CiBuild: wrote shot " + name);
    }

    static void Shots()
    {
        Debug.Log("CiBuild: shots on " + SystemInfo.graphicsDeviceType + " / " + SystemInfo.graphicsDeviceName);
        for (int pass = 0; pass < 2; pass++)
        {
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            // opening a scene destroys loose objects, so the target is made after it and kept out of scene cleanup
            var rt = new RenderTexture(1600, 900, 24, RenderTextureFormat.ARGB32);
            rt.hideFlags = HideFlags.HideAndDontSave;
            var g = new GameObject("SushiGame").AddComponent<DontEatSushi.HouseGame>();
            var cam = g.EditorSetup(pass == 1);
            string tag = pass == 0 ? "hider" : "hunter";
            // the first frames after a scene is built come out unlit, so render a few before keeping any
            g.EditorCam(new Vector3(0f, 0.5f, 0f), 30f, 40f, 30f);
            cam.targetTexture = rt; for (int w = 0; w < 3; w++) cam.Render();
            Snap(cam, rt, tag + "_1_wide");
            g.EditorCam(new Vector3(-3f, 1.2f, 0f), -15f, 8f, 7f); Snap(cam, rt, tag + "_2_bar");
            g.EditorCam(new Vector3(10f, 1.0f, -4.2f), 100f, 10f, 6f); Snap(cam, rt, tag + "_3_tatami");
            g.EditorCam(new Vector3(-10.5f, 1.1f, 7.2f), -50f, 4f, 5f); Snap(cam, rt, tag + "_4_storage");
            g.EditorCam(new Vector3(-1f, 1.2f, 7.2f), -80f, 5f, 6.8f); Snap(cam, rt, tag + "_5_kitchen");
            g.EditorCam(new Vector3(-2f, 1.0f, -4f), 200f, 12f, 3.5f); Snap(cam, rt, tag + "_6_player");
            g.EditorCam(new Vector3(-11.5f, 1.0f, -0.8f), -75f, 8f, 5f); Snap(cam, rt, tag + "_7_booths");
            g.EditorCam(new Vector3(0f, 1.2f, -8f), 170f, 6f, 4.2f); Snap(cam, rt, tag + "_8_entrance");
            g.EditorCam(new Vector3(10.5f, 1.0f, 4f), 55f, 10f, 6f); Snap(cam, rt, tag + "_9_sake");
        }
    }

    // Host and client in one process over loopback: proves the framing and relay work before anyone plays.
    static void NetTest()
    {
        var h = new DontEatSushi.Net(); var c = new DontEatSushi.Net();
        try
        {
            if (!h.Host()) throw new Exception("host: " + h.error);
            if (!c.Join("127.0.0.1")) throw new Exception("join: " + c.error);
            System.Threading.Thread.Sleep(400);
            c.Send("ping|1"); h.Send("pong|2");
            bool gotJoin = false, gotPing = false, gotPong = false; string m;
            var end = DateTime.Now.AddSeconds(4);
            while (DateTime.Now < end && !(gotPing && gotPong))
            {
                while (h.inbox.TryDequeue(out m)) { if (m.EndsWith("|join")) gotJoin = true; if (m.EndsWith("|ping|1")) gotPing = true; }
                while (c.inbox.TryDequeue(out m)) if (m == "0|pong|2") gotPong = true;
                System.Threading.Thread.Sleep(20);
            }
            Debug.Log("CiBuild: net test " + (gotJoin && gotPing && gotPong ? "ok" : "FAILED") + " join=" + gotJoin + " ping=" + gotPing + " pong=" + gotPong + " clientId=" + c.myId);
        }
        catch (Exception e) { Debug.LogWarning("CiBuild: net test FAILED: " + e.Message); }
        finally { c.Close(); h.Close(); }
    }

    public static void Desktop()
    {
        Setup();
        NetTest();
        if (Arg("-customBuildTarget", EditorUserBuildSettings.activeBuildTarget.ToString()).Contains("Windows"))
        {
            try { Shots(); } catch (Exception e) { Debug.LogWarning("CiBuild: Shots failed: " + e); }
        }

        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        new GameObject("SushiGame").AddComponent<DontEatSushi.HouseGame>();
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/Sushi.unity");

        PlayerSettings.companyName = "noobclaw";
        PlayerSettings.productName = "DontEatSushi";
        PlayerSettings.bundleVersion = "0.1." + Arg("-buildNumber", "0");
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        PlayerSettings.defaultScreenWidth = 1600;
        PlayerSettings.defaultScreenHeight = 900;
        PlayerSettings.resizableWindow = true;
        AssetDatabase.SaveAssets();

        var target = EditorUserBuildSettings.activeBuildTarget;
        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { "Assets/Scenes/Sushi.unity" },
            locationPathName = Arg("-customBuildPath", "build/" + target + "/DontEatSushi"),
            target = target,
            options = BuildOptions.None,
        });
        var ok = report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;
        Debug.Log("CiBuild result: " + report.summary.result + ", errors: " + report.summary.totalErrors + ", target: " + target);
        EditorApplication.Exit(ok ? 0 : 1);
    }
}
