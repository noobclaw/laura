// Import settings and materials for the art that would normally be set up by hand in the editor:
// kit textures and models, ground textures, and the shopper character with its two animations.
using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public static class MkImport
{
    [Serializable] class Item { public string name, d, n, m, alpha; public float cut, metal, smooth; public bool emis, two; }
    [Serializable] class Manifest { public Item[] items; }

    const string Tex = "Assets/Art/MkTex/", Ground = "Assets/Art/Ground/", Out = "Assets/Resources/MkMat/";

    static void TexSetting(string path, bool normal, bool linear, bool alpha, int max)
    {
        var ti = AssetImporter.GetAtPath(path) as TextureImporter; if (ti == null) { Debug.LogWarning("MkImport: no texture " + path); return; }
        var type = normal ? TextureImporterType.NormalMap : TextureImporterType.Default; bool srgb = !normal && !linear;
        if (ti.textureType == type && ti.sRGBTexture == srgb && ti.maxTextureSize == max && ti.alphaIsTransparency == alpha && ti.mipmapEnabled && ti.anisoLevel == 4) return;
        ti.textureType = type; ti.sRGBTexture = srgb; ti.maxTextureSize = max; ti.alphaIsTransparency = alpha; ti.mipmapEnabled = true; ti.anisoLevel = 4;
        ti.wrapMode = TextureWrapMode.Repeat; ti.textureCompression = TextureImporterCompression.Compressed;
        ti.SaveAndReimport();
    }
    static Texture2D Load(string path) => string.IsNullOrEmpty(path) ? null : AssetDatabase.LoadAssetAtPath<Texture2D>(path);

    static void Surface(Material mat, string alpha, float cut, bool two)
    {
        mat.SetFloat("_Cull", two ? 0f : 2f);
        if (alpha == "MASK")
        {
            mat.SetFloat("_AlphaClip", 1); mat.SetFloat("_Cutoff", cut); mat.EnableKeyword("_ALPHATEST_ON"); mat.renderQueue = (int)RenderQueue.AlphaTest; mat.SetOverrideTag("RenderType", "TransparentCutout");
        }
        else if (alpha == "BLEND")
        {
            mat.SetFloat("_Surface", 1); mat.SetFloat("_Blend", 0); mat.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha); mat.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
            mat.SetFloat("_ZWrite", 0); mat.EnableKeyword("_SURFACE_TYPE_TRANSPARENT"); mat.renderQueue = (int)RenderQueue.Transparent; mat.SetOverrideTag("RenderType", "Transparent");
            mat.SetShaderPassEnabled("ShadowCaster", false);
        }
    }

    static Material Lit(Shader sh, Texture2D d, Texture2D n, Texture2D m, float metal, float smooth)
    {
        var mat = new Material(sh);
        if (d != null) { mat.SetTexture("_BaseMap", d); mat.mainTexture = d; }
        mat.SetColor("_BaseColor", Color.white);
        if (n != null) { mat.SetTexture("_BumpMap", n); mat.EnableKeyword("_NORMALMAP"); }
        if (m != null) { mat.SetTexture("_MetallicGlossMap", m); mat.EnableKeyword("_METALLICSPECGLOSSMAP"); mat.SetTexture("_OcclusionMap", m); mat.EnableKeyword("_OCCLUSIONMAP"); mat.SetFloat("_Smoothness", 0.9f); mat.SetFloat("_Metallic", 1f); mat.SetFloat("_OcclusionStrength", 0.8f); }
        else { mat.SetFloat("_Metallic", metal); mat.SetFloat("_Smoothness", smooth); }
        return mat;
    }

    public static void Run(Shader lit)
    {
        Directory.CreateDirectory(Out); AssetDatabase.Refresh();
        // ----- kit materials -----
        var man = JsonUtility.FromJson<Manifest>(File.ReadAllText("Assets/Art/mk_materials.json")); int made = 0;
        AssetDatabase.StartAssetEditing();
        try
        {
            foreach (var it in man.items)
            {
                if (!string.IsNullOrEmpty(it.d)) TexSetting(Tex + it.d, false, false, it.alpha != "OPAQUE", 1024);
                if (!string.IsNullOrEmpty(it.n)) TexSetting(Tex + it.n, true, false, false, 512);
                if (!string.IsNullOrEmpty(it.m)) TexSetting(Tex + it.m, false, true, false, 512);
            }
            foreach (var g in new[] { "interior_tiles", "clean_asphalt", "concrete_floor_02", "white_plaster_02", "large_floor_tiles_02" })
            { TexSetting(Ground + g + "_diff.jpg", false, false, false, 1024); TexSetting(Ground + g + "_nor.jpg", true, false, false, 1024); }
        }
        finally { AssetDatabase.StopAssetEditing(); }
        AssetDatabase.Refresh();
        foreach (var it in man.items)
        {
            var mat = Lit(lit, Load(Tex + it.d), Load(Tex + it.n), Load(Tex + it.m), it.metal, it.smooth);
            Surface(mat, it.alpha, it.cut, it.two);
            if (it.emis) { mat.EnableKeyword("_EMISSION"); mat.SetTexture("_EmissionMap", Load(Tex + it.d)); mat.SetColor("_EmissionColor", Color.white * 1.6f); mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None; }
            AssetDatabase.CreateAsset(mat, Out + it.name + ".mat"); made++;
        }
        // ----- ground and wall materials (Poly Haven, CC0) -----
        (string, string, float)[] gs = { ("G_floor", "large_floor_tiles_02", 0.62f), ("G_tiles", "interior_tiles", 0.55f), ("G_asphalt", "clean_asphalt", 0.12f), ("G_concrete", "concrete_floor_02", 0.2f), ("G_plaster", "white_plaster_02", 0.1f) };
        foreach (var g in gs)
        {
            var mat = Lit(lit, Load(Ground + g.Item2 + "_diff.jpg"), Load(Ground + g.Item2 + "_nor.jpg"), null, 0f, g.Item3);
            AssetDatabase.CreateAsset(mat, Out + g.Item1 + ".mat"); made++;
        }
        // a plain see-through material keeps the transparent shader variant in the build (floor glows, shadows blobs)
        var soft = new Material(lit); Surface(soft, "BLEND", 0, true); soft.SetColor("_BaseColor", new Color(1, 1, 1, 0.5f)); AssetDatabase.CreateAsset(soft, "Assets/Resources/BaseFade.mat");
        Debug.Log("MkImport: " + made + " materials");

        // ----- kit models: plain meshes, no extras -----
        int models = 0;
        foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { "Assets/Resources/Mk" }))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid); var mi = AssetImporter.GetAtPath(path) as ModelImporter; if (mi == null) continue; models++;
            if (!mi.importCameras && !mi.importLights && mi.meshCompression == ModelImporterMeshCompression.Low && !mi.isReadable && !mi.importAnimation) continue;
            mi.importCameras = false; mi.importLights = false; mi.importAnimation = false; mi.isReadable = false; mi.meshCompression = ModelImporterMeshCompression.Low;
            mi.SaveAndReimport();
        }
        Debug.Log("MkImport: " + models + " kit models");
        People(lit);
        AssetDatabase.SaveAssets(); AssetDatabase.Refresh();
    }

    // The character arrives with its own materials for the built-in pipeline and its pictures packed inside the file.
    // Unpack the pictures, give it our materials, and save a lighter copy of its mesh for crowds.
    static Texture2D FindPersonTex(string matName)
    {
        string key = matName.ToLowerInvariant().Replace("mat", ""); if (key.Length < 3) return null; Texture2D best = null;
        foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { "Assets/Art/PeopleTex" }))
        {
            string path = AssetDatabase.GUIDToAssetPath(guid), n = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
            if (!n.Contains(key) || n.Contains("normal") || n.Contains("spec") || n.Contains("gloss") || n.Contains("_n.") || n.EndsWith("_n")) continue;
            best = AssetDatabase.LoadAssetAtPath<Texture2D>(path); if (n.Contains("diff") || n.Contains("color") || n.Contains("albedo")) break;
        }
        return best;
    }

    static Mesh Thin(Mesh src, float cell, string name)
    {
        var v = src.vertices; var nrm = src.normals; var uv = src.uv; var bw = src.boneWeights; int n = v.Length;
        if (n == 0 || bw.Length != n) return null;
        var map = new Dictionary<long, int>(); var remap = new int[n]; var nv = new List<Vector3>(); var nn = new List<Vector3>(); var nu = new List<Vector2>(); var nb = new List<BoneWeight>(); var cnt = new List<int>();
        for (int i = 0; i < n; i++)
        {
            long kx = Mathf.FloorToInt(v[i].x / cell) + 4096, ky = Mathf.FloorToInt(v[i].y / cell) + 4096, kz = Mathf.FloorToInt(v[i].z / cell) + 4096; long key = (kx << 40) | (ky << 20) | kz;
            int j; if (!map.TryGetValue(key, out j)) { j = nv.Count; map[key] = j; nv.Add(Vector3.zero); nn.Add(Vector3.zero); nu.Add(uv.Length == n ? uv[i] : Vector2.zero); nb.Add(bw[i]); cnt.Add(0); }
            nv[j] += v[i]; if (nrm.Length == n) nn[j] += nrm[i]; cnt[j]++; remap[i] = j;
        }
        for (int j = 0; j < nv.Count; j++) { nv[j] /= cnt[j]; nn[j] = nn[j].sqrMagnitude > 1e-10f ? nn[j].normalized : Vector3.up; }
        var m = new Mesh { name = name }; if (nv.Count > 65000) m.indexFormat = IndexFormat.UInt32;
        m.SetVertices(nv); m.SetNormals(nn); m.SetUVs(0, nu); m.boneWeights = nb.ToArray(); m.bindposes = src.bindposes; m.subMeshCount = src.subMeshCount;
        for (int sm = 0; sm < src.subMeshCount; sm++)
        {
            var t = src.GetTriangles(sm); var o = new List<int>(t.Length); var seen = new HashSet<long>();
            for (int k = 0; k + 2 < t.Length; k += 3)
            {
                int a = remap[t[k]], b = remap[t[k + 1]], c = remap[t[k + 2]]; if (a == b || b == c || a == c) continue;
                int lo = Mathf.Min(a, Mathf.Min(b, c)), hi = Mathf.Max(a, Mathf.Max(b, c)), mid = a + b + c - lo - hi; long key = ((long)lo << 42) | ((long)mid << 21) | (long)hi;
                if (!seen.Add(key)) continue; o.Add(a); o.Add(b); o.Add(c);
            }
            m.SetTriangles(o, sm);
        }
        m.RecalculateBounds(); return m;
    }

    static void People(Shader lit)
    {
        try
        {
            Directory.CreateDirectory("Assets/Resources/People/Mat"); Directory.CreateDirectory("Assets/Art/PeopleTex"); Directory.CreateDirectory("Assets/Art/PeopleLite");
            foreach (var file in new[] { "Walking", "Idle" })
            {
                string path = "Assets/Resources/People/" + file + ".fbx"; var mi = AssetImporter.GetAtPath(path) as ModelImporter;
                if (mi == null) { Debug.LogWarning("MkImport: missing " + path); continue; }
                mi.animationType = ModelImporterAnimationType.Legacy; mi.importAnimation = true; mi.animationWrapMode = WrapMode.Loop; mi.importCameras = false; mi.importLights = false;
                mi.animationCompression = ModelImporterAnimationCompression.KeyframeReduction; mi.isReadable = true;
                if (file == "Walking")
                {
                    bool ex = false; try { ex = mi.ExtractTextures("Assets/Art/PeopleTex"); } catch (Exception e) { Debug.LogWarning("MkImport: texture unpack failed: " + e.Message); }
                    AssetDatabase.Refresh(); int texCount = AssetDatabase.FindAssets("t:Texture2D", new[] { "Assets/Art/PeopleTex" }).Length;
                    Debug.Log("MkImport: unpacked person textures ok=" + ex + " files=" + texCount);
                    foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { "Assets/Art/PeopleTex" }))
                    {
                        string tp = AssetDatabase.GUIDToAssetPath(guid); string ln = tp.ToLowerInvariant(); bool normal = ln.Contains("normal");
                        var ti = AssetImporter.GetAtPath(tp) as TextureImporter; if (ti == null) continue;
                        ti.maxTextureSize = 1024; ti.textureType = normal ? TextureImporterType.NormalMap : TextureImporterType.Default; ti.textureCompression = TextureImporterCompression.Compressed; ti.SaveAndReimport();
                        Debug.Log("MkImport: person texture " + Path.GetFileName(tp));
                    }
                    foreach (var o in AssetDatabase.LoadAllAssetsAtPath(path))
                    {
                        var src = o as Material; if (src == null) continue;
                        Texture tex = null; foreach (var prop in new[] { "_MainTex", "_BaseMap" }) if (tex == null && src.HasProperty(prop)) tex = src.GetTexture(prop);
                        if (tex == null) tex = FindPersonTex(src.name);
                        var mat = new Material(lit); if (tex != null) { mat.SetTexture("_BaseMap", tex); mat.mainTexture = tex; }
                        string n = src.name.ToLowerInvariant();
                        Color c = Color.white; if (tex == null) c = n.Contains("body") ? new Color(0.86f, 0.66f, 0.52f) : n.Contains("hair") ? new Color(0.30f, 0.22f, 0.16f) : n.Contains("shoe") ? new Color(0.92f, 0.92f, 0.92f) : n.Contains("lash") ? new Color(0.1f, 0.1f, 0.1f) : Color.white;
                        mat.SetColor("_BaseColor", c); mat.SetFloat("_Smoothness", 0.2f); mat.SetFloat("_Metallic", 0f);
                        if (tex != null && (n.Contains("hair") || n.Contains("lash"))) { mat.SetFloat("_AlphaClip", 1); mat.SetFloat("_Cutoff", 0.35f); mat.EnableKeyword("_ALPHATEST_ON"); mat.SetFloat("_Cull", 0); mat.renderQueue = (int)RenderQueue.AlphaTest; }
                        AssetDatabase.CreateAsset(mat, "Assets/Resources/People/Mat/" + src.name + ".mat");
                        mi.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material), src.name), mat);
                        Debug.Log("MkImport: person material " + src.name + " tex=" + (tex != null ? tex.name + " " + tex.width : "none"));
                    }
                }
                mi.SaveAndReimport();
                foreach (var o in AssetDatabase.LoadAllAssetsAtPath(path)) { var cl = o as AnimationClip; if (cl != null && !cl.name.StartsWith("__preview")) Debug.Log("MkImport: " + file + " clip '" + cl.name + "' " + cl.length.ToString("0.00") + "s legacy=" + cl.legacy); }
            }
            // lighter copy for crowds
            var model = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Resources/People/Walking.fbx");
            if (model != null)
            {
                var inst = UnityEngine.Object.Instantiate(model); inst.name = "Shopper"; int before = 0, after = 0; float height = 0;
                var rs = inst.GetComponentsInChildren<SkinnedMeshRenderer>(); foreach (var r in rs) if (r.sharedMesh != null) height = Mathf.Max(height, r.sharedMesh.bounds.size.y, r.sharedMesh.bounds.size.z);
                float cell = Mathf.Max(1e-5f, height / 62f);
                foreach (var r in rs)
                {
                    if (r.sharedMesh == null) continue; int t0 = 0; for (int k = 0; k < r.sharedMesh.subMeshCount; k++) t0 += (int)(r.sharedMesh.GetIndexCount(k) / 3); before += t0;
                    var lite = Thin(r.sharedMesh, cell, r.sharedMesh.name + "_lite");
                    if (lite == null) { after += t0; continue; }
                    int t1 = 0; for (int k = 0; k < lite.subMeshCount; k++) t1 += (int)(lite.GetIndexCount(k) / 3); after += t1;
                    AssetDatabase.CreateAsset(lite, "Assets/Art/PeopleLite/" + r.name.Replace(":", "_") + ".asset"); r.sharedMesh = lite;
                }
                PrefabUtility.SaveAsPrefabAsset(inst, "Assets/Resources/People/Shopper.prefab"); UnityEngine.Object.DestroyImmediate(inst);
                Debug.Log("MkImport: shopper mesh height=" + height.ToString("0.###") + " triangles " + before + " -> " + after);
            }
        }
        catch (Exception e) { Debug.LogWarning("MkImport: people setup failed: " + e); }
    }
}
