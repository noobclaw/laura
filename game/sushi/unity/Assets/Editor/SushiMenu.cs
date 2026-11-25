// 別吃壽司 - 選單：Tools > 別吃壽司 > 建立並開啟場景
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class SushiMenu
{
    [MenuItem("Tools/別吃壽司/建立並開啟場景")]
    public static void CreateScene()
    {
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var go = new GameObject("SushiGame");
        go.AddComponent<DontEatSushi.HouseGame>();
        System.IO.Directory.CreateDirectory("Assets/DontEatSushi/Scenes");
        EditorSceneManager.SaveScene(scene, "Assets/DontEatSushi/Scenes/Sushi.unity");
        Debug.Log("別吃壽司：場景已建立，按上方的播放鍵開始。");
    }
}
