// When the project is opened in the editor (not the cloud build), set it up once and offer two menu commands.
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

[InitializeOnLoad]
public static class EditorBoot
{
    static EditorBoot()
    {
        if (Application.isBatchMode) return;
        EditorApplication.delayCall += () =>
        {
            if (!File.Exists("Assets/Settings/URP.asset") || !File.Exists("Assets/Resources/Solid.mat")) { Debug.Log("EditorBoot: first-time setup"); CiBuild.Setup(); }
            if (!File.Exists("Assets/Scenes/Main.unity")) { var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single); EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity"); }
        };
    }
    [MenuItem("Souq/Set up project")] static void Setup() { CiBuild.Setup(); }
    [MenuItem("Souq/Save screenshots")] static void Shots() { CiBuild.Shots(); }
}
