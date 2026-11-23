// Probe build: makes a one-cube scene in code and exports an iOS Xcode project.
using System;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class CiBuild
{
    static string Arg(string name, string fallback)
    {
        var a = Environment.GetCommandLineArgs();
        for (int i = 0; i < a.Length - 1; i++) if (a[i] == name) return a[i + 1];
        return fallback;
    }

    public static void IOS()
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
        GameObject.CreatePrimitive(PrimitiveType.Cube);
        System.IO.Directory.CreateDirectory("Assets/Scenes");
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity");

        PlayerSettings.companyName = "noobclaw";
        PlayerSettings.productName = "Probe";
        PlayerSettings.SetApplicationIdentifier(UnityEditor.Build.NamedBuildTarget.iOS, "com.noobclaw.probe");

        var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
        {
            scenes = new[] { "Assets/Scenes/Main.unity" },
            locationPathName = Arg("-customBuildPath", "build/iOS/iOS"),
            target = BuildTarget.iOS,
            options = BuildOptions.None,
        });
        var ok = report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;
        Debug.Log("CiBuild result: " + report.summary.result + ", errors: " + report.summary.totalErrors);
        EditorApplication.Exit(ok ? 0 : 1);
    }
}
