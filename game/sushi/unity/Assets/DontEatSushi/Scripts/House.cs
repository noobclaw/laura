// 別吃壽司 - 新主體：整間壽司店當舞台。躲的人是飯糰小人，第三人稱走動、擺姿勢、把自己塗成環境；
// 找的人第一人稱拿醬油槍在店裡搜。單人可練習或打電腦，多人用主機直連。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public class HouseGame : MonoBehaviour
    {
        enum Ph { Menu, Lobby, Hide, Seek, End }
        class Hider { public GameObject go; public Paintable paint; public int pose = -1; public Vector3 pos; public float yaw, gloss = -1f; public bool caught; }

        static readonly ShapeKind[] poses = { ShapeKind.Stand, ShapeKind.Sit, ShapeKind.Prone, ShapeKind.Side, ShapeKind.Star };
        static readonly string[] poseNames = { "站立", "坐下", "趴下", "側躺", "大字" };

        Transform root; Camera cam; GameObject gun;
        CharacterController cc; Transform me; Paintable body;
        bool hunter, solo, practice, caught, stroke, texDirty;
        int pose, ammo, found;
        float yaw, vy, camYaw, camPitch = 22f, camDist = 4.5f, fpPitch, timer, toastT, ammoT, sendT, texT;
        Ph ph = Ph.Menu;
        string toast = "", result = "", ip = "127.0.0.1", netMsg = "";
        Vector2 lastMouse;

        Color32 paintColor = new Color32(240, 236, 226, 255);
        float pickH, pickS, pickV = 1f, brush = 0.12f, gloss = 0.3f;
        readonly List<Color32> recent = new List<Color32>();
        Texture2D wheelTex;

        readonly Dictionary<int, Hider> others = new Dictionary<int, Hider>();
        readonly Dictionary<int, GameObject> hunterAv = new Dictionary<int, GameObject>();
        Net net;
        readonly List<int> lobby = new List<int>(), hiderIds = new List<int>(), hunterIds = new List<int>();
        readonly HashSet<int> caughtIds = new HashSet<int>();

        Font font; GUIStyle sL, sB, sS;

        void Start() { BuildWorld(); SpawnMe(false, new Vector3(0f, 0f, -6f)); SetPaint(paintColor); }
        void OnDestroy() { if (net != null) net.Close(); }

        static void Kill(Object o) { if (o == null) return; if (Application.isPlaying) Destroy(o); else DestroyImmediate(o); }
        void Toast(string s) { toast = s; toastT = 5f; }
        static string F(float v) { return v.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture); }
        static float P(string v) { return float.Parse(v, System.Globalization.CultureInfo.InvariantCulture); }

        // ================= 場景 =================

        Texture2D Pattern(int type, Color a, Color b)
        {
            const int N = 128;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true);
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
            {
                for (int x = 0; x < N; x++)
                {
                    float u = (x + 0.5f) / N, v = (y + 0.5f) / N, k = 0f;
                    switch (type)
                    {
                        case 0: k = Mathf.PerlinNoise(u * 9f, v * 9f) * 0.5f; break;                                              // 灰泥
                        case 1: k = Mathf.PerlinNoise(u * 2f, v * 30f) * 0.8f + Mathf.PerlinNoise(u * 40f, v * 90f) * 0.2f; break; // 木紋
                        case 2: k = ((int)(u * 4f) + (int)(v * 4f)) % 2; break;                                                    // 棋盤
                        case 3:                                                                                                    // 青海波
                        {
                            float best = 9f;
                            for (int j = -1; j <= 2; j++) for (int i = -1; i <= 2; i++)
                            {
                                float cx = (i + (j % 2 == 0 ? 0f : 0.5f)) * 0.5f, cy = j * 0.25f;
                                float d = Mathf.Sqrt((u - cx) * (u - cx) + (v - cy) * (v - cy));
                                if (v >= cy && d < 0.27f) best = Mathf.Min(best, cy * 100f + 0f) == best ? best : best;
                                if (v >= cy && d < 0.27f && cy > -1f) { float ring = Mathf.Repeat(d * 16f, 1f); k = ring < 0.35f ? 1f : 0f; }
                            }
                            break;
                        }
                        case 4:                                                                                                    // 麻葉（菱格）
                        {
                            float p = Mathf.Abs(Mathf.Repeat((u + v) * 4f, 1f) - 0.5f), q = Mathf.Abs(Mathf.Repeat((u - v) * 4f, 1f) - 0.5f), h = Mathf.Abs(Mathf.Repeat(v * 8f, 1f) - 0.5f);
                            k = (p < 0.06f || q < 0.06f || h < 0.05f) ? 1f : 0f; break;
                        }
                        case 5: k = Mathf.Repeat(v * 40f, 1f) < 0.3f ? 0.6f : 0f; if (u < 0.04f || u > 0.96f) k = 1f; break;       // 榻榻米
                        case 6: k = Mathf.Repeat(u * 6f, 1f) < 0.5f ? 1f : 0f; break;                                               // 直條
                        case 7: { float du = Mathf.Repeat(u * 5f, 1f) - 0.5f, dv = Mathf.Repeat(v * 5f, 1f) - 0.5f; k = du * du + dv * dv < 0.07f ? 1f : 0f; break; } // 圓點
                        default: k = (Mathf.Repeat(u * 4f, 1f) < 0.06f || Mathf.Repeat(v * 4f, 1f) < 0.06f) ? 1f : 0f; break;      // 格線
                    }
                    Color c = Color.Lerp(a, b, k); c.a = 1f;
                    px[y * N + x] = c;
                }
            }
            t.SetPixels32(px); t.Apply(true); t.wrapMode = TextureWrapMode.Repeat;
            return t;
        }

        Material Pat(int type, Color a, Color b, float tx, float ty, float smooth = 0.2f)
        {
            var m = Mats.Lit(Color.white, smooth, Pattern(type, a, b));
            if (m.HasProperty("_BaseMap")) m.SetTextureScale("_BaseMap", new Vector2(tx, ty));
            return m;
        }

        GameObject Obj(PrimitiveType type, Vector3 c, Vector3 size, Material m, bool solid = true)
        {
            var go = GameObject.CreatePrimitive(type);
            go.transform.SetParent(root, false);
            go.transform.position = c; go.transform.localScale = size;
            go.GetComponent<Renderer>().sharedMaterial = m;
            var col = go.GetComponent<Collider>();
            if (col != null) Kill(col);
            if (solid) go.AddComponent<MeshCollider>();   // 用網格碰撞體，取色時才讀得到貼圖座標
            return go;
        }
        GameObject W(Vector3 c, Vector3 size, Material m, bool solid = true) { return Obj(PrimitiveType.Cube, c, size, m, solid); }

        void BuildWorld()
        {
            if (root != null) Kill(root.gameObject);
            root = new GameObject("World").transform;
            others.Clear(); hunterAv.Clear();
            Color cream = new Color(0.93f, 0.87f, 0.74f), dark = new Color(0.24f, 0.14f, 0.09f), indigo = new Color(0.13f, 0.20f, 0.45f), white = new Color(0.95f, 0.94f, 0.9f);
            var woodFloor = Pat(1, new Color(0.55f, 0.36f, 0.20f), new Color(0.78f, 0.58f, 0.36f), 6f, 4f, 0.4f);
            var lightWood = Pat(1, new Color(0.80f, 0.64f, 0.42f), new Color(0.92f, 0.80f, 0.60f), 2f, 1f, 0.35f);
            var darkWood = Pat(1, new Color(0.20f, 0.11f, 0.07f), new Color(0.34f, 0.20f, 0.12f), 2f, 1f, 0.35f);
            var steel = Mats.Lit(new Color(0.75f, 0.77f, 0.80f), 0.8f);
            var paper = Pat(8, new Color(0.97f, 0.94f, 0.84f), dark, 2f, 3f, 0.05f);

            // 地板、牆
            W(new Vector3(0f, -0.1f, 0f), new Vector3(26f, 0.2f, 18f), woodFloor);
            W(new Vector3(0f, -0.09f, 7f), new Vector3(14f, 0.2f, 4f), Pat(2, new Color(0.92f, 0.92f, 0.9f), new Color(0.12f, 0.12f, 0.13f), 7f, 2f, 0.6f));
            W(new Vector3(9.5f, 0.15f, -4.5f), new Vector3(7f, 0.3f, 9f), Pat(5, new Color(0.72f, 0.74f, 0.44f), new Color(0.30f, 0.34f, 0.16f), 3f, 2f, 0.1f));
            W(new Vector3(0f, 2f, 9.1f), new Vector3(26.4f, 4f, 0.2f), Pat(3, new Color(0.90f, 0.93f, 0.96f), new Color(0.18f, 0.36f, 0.62f), 10f, 3f, 0.05f));
            W(new Vector3(0f, 2f, -9.1f), new Vector3(26.4f, 4f, 0.2f), Pat(0, cream, new Color(0.80f, 0.72f, 0.58f), 6f, 2f, 0.05f));
            W(new Vector3(-13.1f, 2f, 0f), new Vector3(0.2f, 4f, 18f), Pat(6, new Color(0.46f, 0.30f, 0.18f), new Color(0.56f, 0.38f, 0.22f), 9f, 1f, 0.3f));
            W(new Vector3(13.1f, 2f, 0f), new Vector3(0.2f, 4f, 18f), Pat(4, new Color(0.30f, 0.50f, 0.28f), new Color(0.66f, 0.80f, 0.46f), 8f, 2f, 0.05f));
            for (int i = -2; i <= 2; i++) W(new Vector3(i * 5.2f, 4.15f, 0f), new Vector3(0.3f, 0.3f, 18f), darkWood, false);

            // 壽司吧台和高腳凳
            W(new Vector3(-3f, 0.55f, 0f), new Vector3(8f, 1.1f, 1.2f), lightWood);
            W(new Vector3(-6.4f, 0.55f, -2f), new Vector3(1.2f, 1.1f, 4f), lightWood);
            W(new Vector3(-3f, 1.12f, 0f), new Vector3(8.2f, 0.06f, 1.4f), darkWood, false);
            for (int i = 0; i < 6; i++)
            {
                Obj(PrimitiveType.Cylinder, new Vector3(-6f + i * 1.2f, 0.35f, -1.3f), new Vector3(0.12f, 0.35f, 0.12f), steel);
                Obj(PrimitiveType.Cylinder, new Vector3(-6f + i * 1.2f, 0.74f, -1.3f), new Vector3(0.5f, 0.05f, 0.5f), Mats.Lit(new Color(0.75f, 0.14f, 0.12f), 0.4f));
            }
            SushiKind[] kinds = { SushiKind.Salmon, SushiKind.Tuna, SushiKind.Tamago, SushiKind.Shrimp, SushiKind.CucumberRoll };
            for (int i = 0; i < 5; i++)
            {
                Vector3 pp = new Vector3(-6f + i * 1.5f, 1.16f, 0.1f);
                Obj(PrimitiveType.Cylinder, pp, new Vector3(0.5f, 0.015f, 0.5f), Mats.Lit(Color.Lerp(white, i % 2 == 0 ? new Color(0.8f, 0.3f, 0.25f) : indigo, 0.25f), 0.7f), false);
                for (int k = -1; k <= 1; k += 2)
                {
                    var su = new GameObject("Sushi"); su.transform.SetParent(root, false);
                    su.transform.position = pp + new Vector3(k * 0.1f, 0.016f, 0f); su.transform.localScale = Vector3.one * 0.2f; su.transform.rotation = Quaternion.Euler(0f, 90f, 0f);
                    su.AddComponent<Paintable>().Init(SushiShapes.Get(SushiShapes.ShapeOf(kinds[i])), kinds[i], false);
                }
            }

            // 廚房
            W(new Vector3(0f, 0.6f, 5f), new Vector3(14f, 1.2f, 0.2f), darkWood);
            W(new Vector3(-7f, 2f, 5f), new Vector3(0.3f, 4f, 0.3f), darkWood); W(new Vector3(7f, 2f, 5f), new Vector3(0.3f, 4f, 0.3f), darkWood);
            W(new Vector3(-1f, 0.5f, 8.3f), new Vector3(9f, 1f, 1f), steel);
            W(new Vector3(5.6f, 1.1f, 8.3f), new Vector3(1.6f, 2.2f, 1.2f), Mats.Lit(new Color(0.86f, 0.88f, 0.9f), 0.7f));
            W(new Vector3(-1f, 2.3f, 8.8f), new Vector3(9f, 0.08f, 0.5f), darkWood, false);
            Color[] bottle = { new Color(0.16f, 0.36f, 0.24f), new Color(0.50f, 0.26f, 0.12f), white, indigo, new Color(0.62f, 0.14f, 0.14f) };
            for (int i = 0; i < 12; i++) Obj(PrimitiveType.Cylinder, new Vector3(-5f + i * 0.7f, 2.34f + 0.22f, 8.8f), new Vector3(0.18f, 0.22f, 0.18f), Mats.Lit(bottle[i % 5], 0.85f), false);
            for (int i = 0; i < 3; i++) Obj(PrimitiveType.Cylinder, new Vector3(-3f + i * 1.4f, 1.18f, 8.3f), new Vector3(0.6f, 0.18f, 0.6f), Mats.Lit(new Color(0.2f, 0.2f, 0.22f), 0.7f));

            // 倉庫角落：木箱、米袋、酒樽
            Vector3[] crates = { new Vector3(-11.8f, 0.5f, 8f), new Vector3(-10.7f, 0.5f, 8.1f), new Vector3(-11.3f, 1.5f, 8f), new Vector3(-12f, 0.4f, 6.6f), new Vector3(-9.4f, 0.35f, 8.2f) };
            for (int i = 0; i < crates.Length; i++) { float s = crates[i].y * 2f; W(crates[i], new Vector3(s, s, s), i % 2 == 0 ? lightWood : Pat(8, new Color(0.62f, 0.44f, 0.26f), dark, 2f, 2f)); }
            var sack = Pat(0, new Color(0.86f, 0.80f, 0.66f), new Color(0.70f, 0.62f, 0.46f), 2f, 2f, 0.05f);
            for (int i = 0; i < 5; i++) Obj(PrimitiveType.Sphere, new Vector3(-12f + (i % 3) * 0.9f, 0.3f + (i / 3) * 0.5f, 5.2f + (i % 2) * 0.3f), new Vector3(1f, 0.6f, 0.7f), sack);
            var barrel = Pat(7, new Color(0.82f, 0.70f, 0.42f), new Color(0.70f, 0.16f, 0.14f), 3f, 1f, 0.1f);
            for (int i = 0; i < 3; i++) Obj(PrimitiveType.Cylinder, new Vector3(-8.6f + i * 1.1f, 0.6f, 6.2f), new Vector3(1f, 0.6f, 1f), barrel);

            // 榻榻米包廂：矮桌、坐墊、障子
            Color[] cush = { new Color(0.75f, 0.16f, 0.14f), indigo, new Color(0.30f, 0.50f, 0.28f), new Color(0.86f, 0.66f, 0.20f) };
            for (int t = 0; t < 2; t++)
            {
                float z = -2.3f - t * 4.2f;
                W(new Vector3(9.5f, 0.62f, z), new Vector3(2.6f, 0.1f, 1.3f), darkWood);
                W(new Vector3(9.5f, 0.45f, z), new Vector3(2.2f, 0.3f, 0.9f), darkWood, false);
                for (int i = 0; i < 4; i++) W(new Vector3(8.6f + (i % 2) * 1.8f, 0.36f, z + (i / 2 == 0 ? -1.1f : 1.1f)), new Vector3(0.8f, 0.12f, 0.8f), Pat(i % 2 == 0 ? 7 : 6, cush[(i + t) % 4], Color.Lerp(cush[(i + t) % 4], white, 0.5f), 2f, 2f, 0.1f));
            }
            W(new Vector3(6f, 1.6f, -6.5f), new Vector3(0.08f, 2.6f, 4.8f), paper);
            W(new Vector3(6f, 1.6f, -1.2f), new Vector3(0.08f, 2.6f, 2.2f), paper);

            // 門口：暖簾、燈籠、踏墊
            for (int i = -2; i <= 2; i++) W(new Vector3(i * 1.05f, 3.1f, -8.9f), new Vector3(1f, 1.5f, 0.05f), Pat(i % 2 == 0 ? 7 : 6, indigo, white, 2f, 2f, 0.05f), false);
            W(new Vector3(0f, 0.02f, -7.8f), new Vector3(2.4f, 0.04f, 1.2f), Pat(2, new Color(0.60f, 0.20f, 0.16f), new Color(0.86f, 0.74f, 0.50f), 3f, 1.5f, 0.05f), false);
            var lantern = Mats.Unlit(new Color(2.2f, 0.7f, 0.28f));
            for (int i = -2; i <= 2; i++) Obj(PrimitiveType.Sphere, new Vector3(i * 5.2f, 3.4f, -3f + (i % 2) * 5f), new Vector3(0.6f, 0.8f, 0.6f), lantern, false);

            // 擺設：魚缸、盆栽、菜單木牌、掛軸
            W(new Vector3(-11.4f, 0.5f, -6f), new Vector3(2.4f, 1f, 1f), darkWood);
            W(new Vector3(-11.4f, 1.55f, -6f), new Vector3(2.4f, 1.1f, 1f), Mats.Lit(new Color(0.25f, 0.62f, 0.82f), 0.9f));
            for (int i = 0; i < 3; i++)
            {
                Vector3 pp = new Vector3(i == 0 ? -12f : i == 1 ? 4.6f : 12f, 0.3f, i == 0 ? -1.5f : i == 1 ? -8f : 2f);
                Obj(PrimitiveType.Cylinder, pp, new Vector3(0.6f, 0.3f, 0.6f), Mats.Lit(new Color(0.55f, 0.30f, 0.20f), 0.3f));
                Obj(PrimitiveType.Sphere, pp + Vector3.up * 0.9f, new Vector3(1.1f, 1.3f, 1.1f), Pat(7, new Color(0.20f, 0.46f, 0.20f), new Color(0.36f, 0.62f, 0.28f), 4f, 4f, 0.1f));
            }
            for (int i = 0; i < 7; i++) W(new Vector3(-9f + i * 1.3f, 3.1f, 8.95f), new Vector3(0.9f, 0.4f, 0.06f), i % 3 == 0 ? darkWood : lightWood, false);
            W(new Vector3(12.95f, 2.1f, 5f), new Vector3(0.05f, 2.2f, 1f), Pat(6, white, new Color(0.75f, 0.16f, 0.14f), 1f, 1f, 0.05f), false);
            W(new Vector3(-12.95f, 2.2f, 2f), new Vector3(0.05f, 1.4f, 2f), Pat(3, new Color(0.96f, 0.90f, 0.72f), new Color(0.78f, 0.36f, 0.20f), 4f, 3f, 0.05f), false);

            // 光
            var sun = new GameObject("KeyLight"); sun.transform.SetParent(root, false);
            sun.transform.rotation = Quaternion.Euler(58f, -32f, 0f);
            var sl = sun.AddComponent<Light>(); sl.type = LightType.Directional; sl.color = new Color(1f, 0.93f, 0.82f); sl.intensity = 1.05f; sl.shadows = LightShadows.Soft; sl.shadowStrength = 0.6f;

            var cg = new GameObject("MainCamera"); cg.tag = "MainCamera"; cg.transform.SetParent(root, false);
            cam = cg.AddComponent<Camera>(); cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.20f, 0.14f, 0.11f);
            cam.nearClipPlane = 0.05f; cam.farClipPlane = 120f; cg.AddComponent<AudioListener>();
            Sfx.Init(cg); Look.Apply(cam, root);
            gun = new GameObject("Gun"); gun.transform.SetParent(cg.transform, false);
            gun.transform.localPosition = new Vector3(0.24f, -0.2f, 0.45f); gun.transform.localRotation = Quaternion.Euler(-82f, 0f, 6f);
            var g1 = Obj(PrimitiveType.Cylinder, Vector3.zero, new Vector3(0.11f, 0.13f, 0.11f), Mats.Lit(new Color(0.12f, 0.06f, 0.04f), 0.9f), false);
            g1.transform.SetParent(gun.transform, false); g1.transform.localPosition = Vector3.zero; g1.transform.localRotation = Quaternion.identity;
            var g2 = Obj(PrimitiveType.Cylinder, Vector3.zero, new Vector3(0.06f, 0.04f, 0.06f), Mats.Lit(new Color(0.8f, 0.12f, 0.1f), 0.6f), false);
            g2.transform.SetParent(gun.transform, false); g2.transform.localPosition = new Vector3(0f, 0.16f, 0f); g2.transform.localRotation = Quaternion.identity;
            gun.SetActive(false);
        }

        // 讀取被射線打到的表面顏色：有貼圖讀貼圖，沒有就讀材質顏色
        Color Surface(RaycastHit hit)
        {
            var pt = hit.collider.GetComponent<Paintable>();
            if (pt != null) return pt.Sample(hit.point);
            var r = hit.collider.GetComponent<Renderer>();
            if (r == null || r.sharedMaterial == null) return Color.gray;
            var m = r.sharedMaterial;
            Color c = Mats.GetColor(m);
            var tex = m.HasProperty("_BaseMap") ? m.GetTexture("_BaseMap") as Texture2D : null;
            if (tex != null && tex.isReadable)
            {
                Vector2 uv = hit.textureCoord, sc = m.GetTextureScale("_BaseMap");
                c *= tex.GetPixelBilinear(uv.x * sc.x, uv.y * sc.y);
            }
            c.a = 1f; return c;
        }

        // ================= 角色 =================

        void SpawnMe(bool asHunter, Vector3 at)
        {
            if (me != null) Kill(me.gameObject);
            var go = new GameObject("Me"); go.transform.SetParent(root, false); go.transform.position = at;
            cc = go.AddComponent<CharacterController>(); cc.height = 1.7f; cc.radius = 0.3f; cc.center = new Vector3(0f, 0.86f, 0f); cc.stepOffset = 0.35f;
            me = go.transform; hunter = asHunter; caught = false; pose = 0; vy = 0f; yaw = 0f; fpPitch = 0f;
            var b = new GameObject("Body"); b.transform.SetParent(me, false);
            body = b.AddComponent<Paintable>(); body.Init(SushiShapes.Get(ShapeKind.Stand), SushiKind.Blank, true);
            if (asHunter) { body.rend.enabled = false; body.meshCol.enabled = false; }
            texDirty = true; gloss = 0.3f;
        }

        void SetPose(int p) { pose = p; body.SetShape(SushiShapes.Get(poses[p])); Toast("姿勢：" + poseNames[p]); }

        void SetPaint(Color c) { c.a = 1f; paintColor = c; Color.RGBToHSV(c, out pickH, out pickS, out pickV); }

        Hider MakeHider(int id)
        {
            var h = new Hider();
            h.go = new GameObject("Hider" + id); h.go.transform.SetParent(root, false);
            h.paint = h.go.AddComponent<Paintable>(); h.paint.Init(SushiShapes.Get(ShapeKind.Stand), SushiKind.Blank, true);
            h.pose = 0; others[id] = h;
            return h;
        }

        // 電腦壽司：站到預設的藏身點，把附近地板和牆的顏色抹到身上
        void SpawnBots(int count)
        {
            float[][] spots =
            {
                new[] { -12.4f, 0f, -3.5f, 90f, 0f }, new[] { 12.4f, 0f, 6.5f, 270f, 0f }, new[] { 3f, 0f, 8.6f, 180f, 0f }, new[] { -9.9f, 0f, 7.2f, 0f, 1f },
                new[] { 9.5f, 0.3f, -4.4f, 0f, 2f }, new[] { 11.8f, 0.3f, -8.2f, 300f, 1f }, new[] { -2f, 0f, 1.2f, 0f, 3f }, new[] { 0f, 0f, -8.6f, 0f, 4f },
                new[] { -7.6f, 0f, -4.2f, 90f, 0f }, new[] { 6.6f, 0f, 2f, 200f, 2f }, new[] { -12.3f, 0f, 3.2f, 90f, 4f }, new[] { 4f, 0f, 5.6f, 0f, 1f }
            };
            var idx = new List<int>(); for (int i = 0; i < spots.Length; i++) idx.Add(i);
            Physics.SyncTransforms();
            for (int n = 0; n < count && idx.Count > 0; n++)
            {
                int k = Random.Range(0, idx.Count); var sp = spots[idx[k]]; idx.RemoveAt(k);
                var h = MakeHider(-1 - n);
                h.pose = (int)sp[4]; h.paint.SetShape(SushiShapes.Get(poses[h.pose]));
                Vector3 p = new Vector3(sp[0], sp[1], sp[2]);
                h.go.transform.SetPositionAndRotation(p, Quaternion.Euler(0f, sp[3], 0f));
                h.paint.meshCol.enabled = false;
                Color floor = new Color(0.66f, 0.47f, 0.28f), wall = floor; RaycastHit hit; float best = 3f;
                if (Physics.Raycast(p + Vector3.up * 0.5f, Vector3.down, out hit, 2f)) floor = Surface(hit);
                wall = floor;
                foreach (var d in new[] { Vector3.forward, Vector3.back, Vector3.left, Vector3.right })
                    if (Physics.Raycast(p + Vector3.up * 1.0f, d, out hit, best)) { best = hit.distance; wall = Surface(hit); }
                h.paint.meshCol.enabled = true;
                var tp = h.paint.shape.texPos; var px = h.paint.px;
                for (int i = 0; i < px.Length; i++)
                {
                    float g = 1f + (Mathf.PerlinNoise(tp[i].x * 11f + n, tp[i].y * 11f + tp[i].z * 7f) - 0.5f) * 0.12f;
                    Color c = (tp[i].y < 0.28f ? floor : wall) * g; c.a = 1f; px[i] = c;
                }
                int skill = Random.Range(0, 3);
                h.paint.Degrade(0f, skill == 0 ? 0.12f : 0.05f, skill == 0 ? 0.22f : skill == 1 ? 0.1f : 0f);
            }
        }

        // ================= 回合 =================

        void StartSolo(bool asHunter)
        {
            solo = true; practice = !asHunter; result = "";
            BuildWorld(); SpawnMe(asHunter, new Vector3(0f, 0f, -6.5f));
            hiderIds.Clear(); hunterIds.Clear(); caughtIds.Clear(); found = 0;
            if (asHunter) { SpawnBots(5); ammo = 6; ammoT = 0f; ph = Ph.Seek; timer = 150f; Lock(true); Toast("店裡藏了 5 個塗了偽裝的飯糰小人，找出來用醬油打。"); }
            else { ph = Ph.Hide; timer = 0f; Toast("練習模式：隨便走、隨便塗，按 Esc 回主選單。"); }
            Sfx.Beep(660f, 0.12f, 0.3f);
        }

        void StartMp(List<int> hids, List<int> ids)
        {
            solo = false; practice = false; result = "";
            hunterIds.Clear(); hunterIds.AddRange(hids); hiderIds.Clear();
            foreach (var id in ids) if (!hunterIds.Contains(id)) hiderIds.Add(id);
            caughtIds.Clear(); found = 0;
            bool h = hunterIds.Contains(net.myId);
            BuildWorld(); SpawnMe(h, new Vector3((net.myId % 5 - 2) * 1.2f, 0f, -6.5f));
            ammo = 6; ammoT = 0f; ph = Ph.Hide; timer = 60f; sendT = 0f; texT = 0f;
            Toast(h ? "你是食客。飯糰們有 60 秒躲藏，這段時間你看不到。" : "你是飯糰。60 秒內找地方、擺姿勢、把自己塗成周圍的樣子。");
            Sfx.Beep(660f, 0.12f, 0.3f);
        }

        void Lock(bool on) { Cursor.lockState = on ? CursorLockMode.Locked : CursorLockMode.None; Cursor.visible = !on; }

        void ToMenu()
        {
            if (net != null) { net.Close(); net = null; }
            Lock(false); ph = Ph.Menu; solo = false; practice = false;
            BuildWorld(); SpawnMe(false, new Vector3(0f, 0f, -6f));
        }

        void End(string text) { if (ph == Ph.End) return; ph = Ph.End; result = text; Lock(false); Sfx.Beep(1040f, 0.4f, 0.3f); }

        int Alive() { int n = 0; foreach (var kv in others) if (!kv.Value.caught) n++; if (!hunter && !caught && !practice && ph != Ph.Menu) n++; return n; }

        void MarkCaught(int id)
        {
            if (net != null && id == net.myId) { if (caught) return; caught = true; Toast("你被醬油打中，出局了。"); Sfx.Beep(200f, 0.5f, 0.3f); }
            else { Hider h; if (!others.TryGetValue(id, out h) || h.caught) return; h.caught = true; Sfx.Beep(880f, 0.12f, 0.3f); }
            caughtIds.Add(id);
            if (solo) { if (found >= others.Count) End("全部找到了！"); }
            else if (caughtIds.Count >= hiderIds.Count) End(hunter ? "全部找到了，食客獲勝！" : "飯糰全被找到了，食客獲勝。");
        }

        // ================= 連線 =================

        void HandleNet(string m)
        {
            int bar = m.IndexOf('|'); int from;
            if (bar < 0 || !int.TryParse(m.Substring(0, bar), out from)) return;
            string bodyText = m.Substring(bar + 1); string[] a = bodyText.Split('|');
            switch (a[0])
            {
                case "join": if (net.isHost && !lobby.Contains(from)) lobby.Add(from); break;
                case "leave":
                    lobby.Remove(from);
                    if (ph == Ph.Hide || ph == Ph.Seek) { if (hunterIds.Remove(from) && hunterIds.Count == 0) End("食客離開了。"); else if (hiderIds.Contains(from)) MarkCaught(from); }
                    break;
                case "closed": ToMenu(); netMsg = "和房主的連線斷了。"; break;
                case "start":
                {
                    if (a.Length < 3) break;
                    var hids = new List<int>(); var ids = new List<int>();
                    foreach (var t in a[1].Split(',')) hids.Add(int.Parse(t));
                    foreach (var t in a[2].Split(',')) ids.Add(int.Parse(t));
                    StartMp(hids, ids); break;
                }
                case "s":
                {
                    if (a.Length < 7 || root == null || !hiderIds.Contains(from)) break;
                    Hider h; if (!others.TryGetValue(from, out h)) h = MakeHider(from);
                    h.pos = new Vector3(P(a[1]), P(a[2]), P(a[3])); h.yaw = P(a[4]);
                    int np = Mathf.Clamp(int.Parse(a[5]), 0, poses.Length - 1);
                    if (np != h.pose) { h.pose = np; h.paint.SetShape(SushiShapes.Get(poses[np])); }
                    float gl = P(a[6]);
                    if (Mathf.Abs(gl - h.gloss) > 0.01f) { h.gloss = gl; if (h.paint.rend.sharedMaterial.HasProperty("_Smoothness")) h.paint.rend.sharedMaterial.SetFloat("_Smoothness", gl); }
                    break;
                }
                case "tx":
                {
                    Hider h; if (!others.TryGetValue(from, out h)) break;
                    try { h.paint.tex.LoadImage(System.Convert.FromBase64String(bodyText.Substring(3))); h.paint.px = h.paint.tex.GetPixels32(); } catch (System.Exception) { }
                    break;
                }
                case "h":
                {
                    if (a.Length < 5 || root == null) break;
                    GameObject av;
                    if (!hunterAv.TryGetValue(from, out av) || av == null)
                    {
                        av = new GameObject("Hunter" + from); av.transform.SetParent(root, false);
                        var pt = av.AddComponent<Paintable>(); pt.Init(SushiShapes.Get(ShapeKind.Stand), SushiKind.Blank, false);
                        pt.Fill(new Color32(150, 34, 30, 255)); pt.Flush();
                        hunterAv[from] = av;
                    }
                    av.transform.SetPositionAndRotation(new Vector3(P(a[1]), P(a[2]), P(a[3])), Quaternion.Euler(0f, P(a[4]), 0f));
                    break;
                }
                case "hit":
                {
                    if (a.Length < 11) break;
                    int id = int.Parse(a[1]);
                    Vector3 hp = new Vector3(P(a[2]), P(a[3]), P(a[4])), hn = new Vector3(P(a[5]), P(a[6]), P(a[7]));
                    Color32 col = new Color(P(a[8]), P(a[9]), P(a[10]));
                    Hider h;
                    if (id == net.myId) { body.Dab(hp, hn, 0.3f, col); body.Flush(); }
                    else if (others.TryGetValue(id, out h)) { h.paint.Dab(hp, hn, 0.3f, col); h.paint.Flush(); }
                    MarkCaught(id); break;
                }
            }
        }

        void NetTick(float dt)
        {
            if (net == null) return;
            string m;
            while (net != null && net.inbox.TryDequeue(out m)) HandleNet(m);
            if (net == null || root == null || (ph != Ph.Hide && ph != Ph.Seek)) return;
            foreach (var kv in others)
            {
                var h = kv.Value; if (h.go == null) continue;
                h.go.transform.position = Vector3.Lerp(h.go.transform.position, h.pos, Mathf.Min(1f, 12f * dt));
                h.go.transform.rotation = Quaternion.Euler(0f, h.yaw, 0f);
            }
            sendT -= dt;
            if (sendT <= 0f)
            {
                sendT = 0.1f; Vector3 p = me.position;
                if (hunter) net.Send("h|" + F(p.x) + "|" + F(p.y) + "|" + F(p.z) + "|" + F(yaw));
                else net.Send("s|" + F(p.x) + "|" + F(p.y) + "|" + F(p.z) + "|" + F(yaw) + "|" + pose + "|" + F(gloss));
            }
            texT -= dt;
            if (!hunter && texDirty && texT <= 0f) { texT = 0.9f; texDirty = false; net.Send("tx|" + System.Convert.ToBase64String(body.tex.EncodeToPNG())); }
        }

        // ================= 每幀 =================

        void Update()
        {
            if (!In.Ready || root == null) return;
            In.Tick();
            float dt = Time.deltaTime;
            if (toastT > 0f) toastT -= dt;
            NetTick(dt);
            if (root == null || ph == Ph.Menu || ph == Ph.Lobby) return;
            if (Input.GetKeyDown(KeyCode.Escape) && (solo || ph == Ph.End)) { ToMenu(); return; }
            if (ph == Ph.End) return;

            if (!practice)
            {
                timer -= dt;
                if (ph == Ph.Hide && timer <= 0f) { ph = Ph.Seek; timer = 180f; if (hunter) Lock(true); Toast(hunter ? "開始找！準星對準可疑的地方按左鍵。" : "食客進來了，別亂動。"); Sfx.Beep(520f, 0.3f, 0.3f); }
                else if (ph == Ph.Seek && timer <= 0f) End(solo ? "時間到，還有 " + (others.Count - found) + " 個沒找到。" : (hunter ? "時間到，飯糰獲勝。" : (caught ? "時間到，飯糰隊獲勝（你出局了）。" : "你撐到最後，飯糰獲勝！")));
            }
            if (ph == Ph.End) return;
            if (hunter) HunterTick(dt); else if (!caught) HiderTick(dt);
        }

        void Move(Vector3 dir, float speed, float dt)
        {
            if (cc.isGrounded && vy < 0f) vy = -1f; else vy -= 20f * dt;
            cc.Move((dir * speed + Vector3.up * vy) * dt);
        }

        Vector3 Wish(float basisYaw)
        {
            Vector3 mv = Vector3.zero;
            if (In.Held(K.W)) mv.z += 1f; if (In.Held(K.S)) mv.z -= 1f; if (In.Held(K.D)) mv.x += 1f; if (In.Held(K.A)) mv.x -= 1f;
            return mv.sqrMagnitude > 0f ? Quaternion.Euler(0f, basisYaw, 0f) * mv.normalized : Vector3.zero;
        }

        void HiderTick(float dt)
        {
            Vector3 dir = Wish(camYaw);
            if (dir.sqrMagnitude > 0f) yaw = Mathf.MoveTowardsAngle(yaw, Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg, 540f * dt);
            if (In.Held(K.Q)) yaw -= 120f * dt; if (In.Held(K.E)) yaw += 120f * dt;
            Move(dir, In.Held(K.Shift) ? 5f : 3f, dt);
            me.rotation = Quaternion.Euler(0f, yaw, 0f);
            if (In.Down(K.R) || In.Down(K.T)) SetPose((pose + 1) % poses.Length);
            if (In.Down(K.Minus)) SetGloss(gloss - 0.1f); if (In.Down(K.Equals)) SetGloss(gloss + 0.1f);
            if (In.Down(K.LeftBracket)) brush = Mathf.Max(0.03f, brush - 0.02f); if (In.Down(K.RightBracket)) brush = Mathf.Min(0.5f, brush + 0.02f);

            Vector2 mp = In.MousePos; float sc = Screen.height / 720f, gx = mp.x / sc, gy = (Screen.height - mp.y) / sc;
            bool overUi = gy > 640f || (gx < 270f && gy > 150f && gy < 560f);
            if (In.Down(K.Z)) { body.Undo(); texDirty = true; }
            if (In.Down(K.F)) { body.PushUndo(); body.Fill(paintColor); body.Flush(); texDirty = true; }
            if (In.Down(K.C) && !overUi)
            {
                Physics.SyncTransforms(); RaycastHit hit;
                if (Physics.Raycast(cam.ScreenPointToRay(mp), out hit, 100f)) { SetPaint(Surface(hit)); Toast("已吸取顏色。"); }
            }
            if (In.LmbDown && !overUi)
            {
                stroke = true; lastMouse = mp; body.PushUndo(); Physics.SyncTransforms(); DabAt(mp);
                if (recent.Count == 0 || recent[0].r != paintColor.r || recent[0].g != paintColor.g || recent[0].b != paintColor.b) { recent.Insert(0, paintColor); if (recent.Count > 24) recent.RemoveAt(24); }
            }
            else if (stroke && In.LmbHeld)
            {
                Physics.SyncTransforms();
                int steps = Mathf.Clamp(Mathf.CeilToInt((mp - lastMouse).magnitude / 6f), 1, 20);
                for (int i = 1; i <= steps; i++) DabAt(Vector2.Lerp(lastMouse, mp, i / (float)steps));
                lastMouse = mp; texDirty = true;
            }
            if (!In.LmbHeld) stroke = false;
            body.Flush();
        }

        void SetGloss(float v) { gloss = Mathf.Clamp(v, 0f, 0.9f); if (body.rend.sharedMaterial.HasProperty("_Smoothness")) body.rend.sharedMaterial.SetFloat("_Smoothness", gloss); }

        void DabAt(Vector2 sp)
        {
            RaycastHit hit;
            if (body.meshCol.Raycast(cam.ScreenPointToRay(sp), out hit, 100f)) body.Dab(hit.point, hit.normal, brush, paintColor);
        }

        void HunterTick(float dt)
        {
            if (Cursor.lockState == CursorLockMode.Locked)
            {
                Vector2 md = In.MouseDelta;
                yaw += md.x * 0.12f; fpPitch = Mathf.Clamp(fpPitch - md.y * 0.12f, -80f, 80f);
            }
            Move(Wish(yaw), In.Held(K.Shift) ? 5.5f : 3.6f, dt);
            me.rotation = Quaternion.Euler(0f, yaw, 0f);
            if (ph != Ph.Seek) return;
            if (ammo < 6) { ammoT += dt; if (ammoT >= 6f) { ammoT = 0f; ammo++; } }
            if (!In.LmbDown) return;
            if (Cursor.lockState != CursorLockMode.Locked) { Lock(true); return; }
            if (ammo < 1) { Toast("醬油用完了，等它補充。"); Sfx.Beep(180f, 0.1f, 0.25f); return; }
            ammo--; Sfx.Beep(240f, 0.08f, 0.35f);
            Physics.SyncTransforms(); RaycastHit hit;
            if (!Physics.Raycast(cam.ViewportPointToRay(new Vector3(0.5f, 0.5f, 0f)), out hit, 60f)) return;
            Color col = Color.HSVToRGB(Random.value, 0.9f, 1f);
            var pt = hit.collider.GetComponent<Paintable>();
            int hitId = 0; bool isHider = false;
            foreach (var kv in others) if (kv.Value.paint == pt && pt != null && !kv.Value.caught) { hitId = kv.Key; isHider = true; }
            if (isHider)
            {
                pt.Dab(hit.point, hit.normal, 0.3f, col); pt.Flush(); found++;
                if (net != null) net.Send("hit|" + hitId + "|" + F(hit.point.x) + "|" + F(hit.point.y) + "|" + F(hit.point.z) + "|" + F(hit.normal.x) + "|" + F(hit.normal.y) + "|" + F(hit.normal.z) + "|" + F(col.r) + "|" + F(col.g) + "|" + F(col.b));
                Toast("找到一個！"); MarkCaught(hitId);
            }
            else
            {
                var s = Obj(PrimitiveType.Sphere, hit.point + hit.normal * 0.01f, new Vector3(0.45f, 0.45f, 0.03f), Mats.Lit(col, 0.7f), false);
                s.transform.rotation = Quaternion.LookRotation(hit.normal);
                if (Application.isPlaying) Destroy(s, 25f);
                Toast("沒打中，浪費了一發。");
            }
        }

        void LateUpdate()
        {
            if (!In.Ready || cam == null || me == null) return;
            bool fp = hunter && (ph == Ph.Hide || ph == Ph.Seek);
            if (gun.activeSelf != fp) gun.SetActive(fp);
            cam.fieldOfView = fp ? 70f : 55f;
            if (fp) { cam.transform.position = me.position + Vector3.up * 1.55f; cam.transform.rotation = Quaternion.Euler(fpPitch, yaw, 0f); return; }
            if (ph == Ph.Menu || ph == Ph.Lobby || ph == Ph.End) camYaw += 12f * Time.deltaTime;
            else if (In.RmbHeld) { Vector2 d = In.MouseDelta; camYaw += d.x * 0.25f; camPitch = Mathf.Clamp(camPitch - d.y * 0.2f, -10f, 80f); }
            float scr = In.Scroll; if (Mathf.Abs(scr) > 0.01f) camDist = Mathf.Clamp(camDist - Mathf.Sign(scr) * 0.5f, 1.5f, 9f);
            Vector3 target = me.position + Vector3.up * 1.0f;
            Quaternion rot = Quaternion.Euler(camPitch, camYaw, 0f);
            Vector3 back = rot * Vector3.back; float dist = camDist; RaycastHit hit;
            if (Physics.Raycast(target, back, out hit, camDist) && hit.collider.transform.root != me.root && hit.collider.GetComponentInParent<CharacterController>() == null) dist = Mathf.Max(0.6f, hit.distance - 0.15f);
            cam.transform.position = target + back * dist; cam.transform.rotation = rot;
        }

        // 給雲端截圖用
        public Camera EditorSetup(bool hunterView)
        {
            BuildWorld(); SpawnMe(false, new Vector3(-2f, 0f, -4f)); ph = Ph.Seek; practice = true;
            Physics.SyncTransforms();
            if (hunterView) SpawnBots(6);
            else { SetPose(4); body.Fill(new Color32(214, 150, 92, 255)); body.Flush(); }
            return cam;
        }
        public void EditorCam(Vector3 target, float camYawDeg, float pitch, float dist)
        {
            Quaternion rot = Quaternion.Euler(pitch, camYawDeg, 0f);
            cam.transform.position = target + rot * new Vector3(0f, 0f, -dist); cam.transform.rotation = rot;
        }

        // ================= 介面 =================

        void Box(Rect r, Color c) { var old = GUI.color; GUI.color = c; GUI.DrawTexture(r, Texture2D.whiteTexture); GUI.color = old; }
        bool Btn(Rect r, string text, Color c) { Box(r, c); GUI.Label(r, text, sB); return GUI.Button(r, GUIContent.none, GUIStyle.none); }

        Texture2D Wheel()
        {
            if (wheelTex != null) return wheelTex;
            const int N = 160; wheelTex = new Texture2D(N, N, TextureFormat.RGBA32, false);
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++) for (int x = 0; x < N; x++)
            {
                float dx = (x + 0.5f) / N * 2f - 1f, dy = (y + 0.5f) / N * 2f - 1f, r = Mathf.Sqrt(dx * dx + dy * dy);
                if (r > 1f) { px[y * N + x] = new Color32(0, 0, 0, 0); continue; }
                float h = Mathf.Atan2(dy, dx) / (2f * Mathf.PI); if (h < 0f) h += 1f;
                Color c = Color.HSVToRGB(h, r, 1f); c.a = Mathf.Clamp01((1f - r) * 40f); px[y * N + x] = c;
            }
            wheelTex.SetPixels32(px); wheelTex.Apply(false); wheelTex.wrapMode = TextureWrapMode.Clamp;
            return wheelTex;
        }

        void PaintPanel(Color panel, Color gold)
        {
            Box(new Rect(12f, 160f, 252f, 392f), panel); Box(new Rect(12f, 160f, 252f, 2f), gold);
            Rect w = new Rect(24f, 174f, 150f, 150f); GUI.DrawTexture(w, Wheel());
            var e = Event.current;
            if ((e.type == EventType.MouseDown || e.type == EventType.MouseDrag) && e.button == 0 && w.Contains(e.mousePosition))
            {
                float dx = (e.mousePosition.x - w.center.x) / 75f, dy = -(e.mousePosition.y - w.center.y) / 75f;
                float h = Mathf.Atan2(dy, dx) / (2f * Mathf.PI); if (h < 0f) h += 1f;
                pickH = h; pickS = Mathf.Min(1f, Mathf.Sqrt(dx * dx + dy * dy)); paintColor = Color.HSVToRGB(pickH, pickS, pickV); e.Use();
            }
            float ang = pickH * 2f * Mathf.PI; Vector2 mk = w.center + new Vector2(Mathf.Cos(ang), -Mathf.Sin(ang)) * pickS * 75f;
            Box(new Rect(mk.x - 5f, mk.y - 5f, 10f, 10f), Color.black); Box(new Rect(mk.x - 3f, mk.y - 3f, 6f, 6f), Color.white);
            float nv = GUI.VerticalSlider(new Rect(188f, 174f, 20f, 150f), pickV, 1f, 0f);
            if (Mathf.Abs(nv - pickV) > 0.001f) { pickV = nv; paintColor = Color.HSVToRGB(pickH, pickS, pickV); }
            Box(new Rect(216f, 174f, 38f, 150f), paintColor);
            GUI.Label(new Rect(24f, 330f, 90f, 22f), "光澤 " + Mathf.RoundToInt(gloss * 100f), sS);
            float ng = GUI.HorizontalSlider(new Rect(104f, 337f, 150f, 16f), gloss, 0f, 0.9f); if (Mathf.Abs(ng - gloss) > 0.001f) SetGloss(ng);
            GUI.Label(new Rect(24f, 356f, 90f, 22f), "筆刷 " + Mathf.RoundToInt(brush * 100f), sS);
            brush = GUI.HorizontalSlider(new Rect(104f, 363f, 150f, 16f), brush, 0.03f, 0.5f);
            GUI.Label(new Rect(24f, 382f, 230f, 22f), "用過的顏色", sS);
            for (int i = 0; i < recent.Count; i++)
            {
                Rect r = new Rect(24f + (i % 8) * 29f, 406f + (i / 8) * 29f, 25f, 25f);
                Box(r, recent[i]); if (GUI.Button(r, GUIContent.none, GUIStyle.none)) SetPaint(recent[i]);
            }
            GUI.Label(new Rect(24f, 498f, 236f, 50f), "C 吸取滑鼠指著的顏色\nF 全身塗滿　Z 撤銷", sS);
        }

        void OnGUI()
        {
            if (root == null) return;
            if (sL == null)
            {
                font = Resources.Load<Font>("Font/NotoSansTC-Regular");
                if (font == null) font = Font.CreateDynamicFontFromOSFont(new[] { "Microsoft JhengHei", "PingFang TC", "Heiti TC", "Arial" }, 18);
                sL = new GUIStyle(GUI.skin.label) { font = font, fontSize = 18, wordWrap = true, alignment = TextAnchor.MiddleCenter }; sL.normal.textColor = Color.white;
                sB = new GUIStyle(sL) { fontSize = 22, fontStyle = FontStyle.Bold };
                sS = new GUIStyle(sL) { fontSize = 14, alignment = TextAnchor.UpperLeft }; sS.normal.textColor = new Color(1f, 0.95f, 0.85f);
            }
            if (ph != Ph.Menu && GUIUtility.keyboardControl != 0) GUIUtility.keyboardControl = 0;
            float sc = Screen.height / 720f; GUI.matrix = Matrix4x4.Scale(new Vector3(sc, sc, 1f));
            float W_ = Screen.width / sc, H = 720f, cx = W_ / 2f;
            Color panel = new Color(0.13f, 0.08f, 0.06f, 0.9f), gold = new Color(0.92f, 0.74f, 0.36f);

            if (ph == Ph.Menu)
            {
                Box(new Rect(cx - 330f, 120f, 660f, 470f), panel); Box(new Rect(cx - 330f, 120f, 660f, 3f), gold); Box(new Rect(cx - 330f, 587f, 660f, 3f), gold);
                var big = new GUIStyle(sB) { fontSize = 44 }; GUI.Label(new Rect(cx - 330f, 135f, 660f, 70f), "別吃壽司", big);
                GUI.Label(new Rect(cx - 310f, 205f, 620f, 50f), "躲的人把自己塗成店裡的樣子，找的人拿醬油槍把他們找出來。", sL);
                if (Btn(new Rect(cx - 290f, 270f, 280f, 80f), "練習：當飯糰", new Color(0.80f, 0.30f, 0.20f))) StartSolo(false);
                if (Btn(new Rect(cx + 10f, 270f, 280f, 80f), "單人：當食客找電腦", new Color(0.18f, 0.28f, 0.52f))) StartSolo(true);
                GUI.Label(new Rect(cx - 310f, 365f, 620f, 30f), "多人連線：一個人開房間，其他人填他的位址後按加入", sL);
                if (Btn(new Rect(cx - 290f, 405f, 180f, 56f), "開房間", new Color(0.20f, 0.45f, 0.30f)))
                {
                    net = new Net();
                    if (net.Host()) { lobby.Clear(); lobby.Add(0); ph = Ph.Lobby; netMsg = "房間已開。把這個位址告訴朋友：" + Net.LocalIP(); } else { netMsg = "開房失敗：" + net.error; net = null; }
                }
                var tf = new GUIStyle(GUI.skin.textField) { font = font, fontSize = 20, alignment = TextAnchor.MiddleCenter };
                ip = GUI.TextField(new Rect(cx - 100f, 412f, 200f, 42f), ip, 40, tf);
                if (Btn(new Rect(cx + 110f, 405f, 180f, 56f), "加入", new Color(0.45f, 0.30f, 0.55f)))
                {
                    net = new Net();
                    if (net.Join(ip.Trim())) { ph = Ph.Lobby; netMsg = "已加入，等房主按開始。"; } else { netMsg = "加入失敗：" + net.error; net = null; }
                }
                GUI.Label(new Rect(cx - 310f, 475f, 620f, 30f), netMsg, sL);
                GUI.Label(new Rect(cx - 310f, 520f, 620f, 60f), "飯糰：WASD 走　R 換姿勢　左鍵往自己身上塗　C 吸顏色　右鍵拖曳轉鏡頭\n食客：WASD 走　滑鼠轉視角　左鍵開槍", sL);
                return;
            }
            if (ph == Ph.Lobby)
            {
                Box(new Rect(cx - 300f, 210f, 600f, 300f), panel); Box(new Rect(cx - 300f, 210f, 600f, 3f), gold);
                GUI.Label(new Rect(cx - 300f, 225f, 600f, 50f), "房間", sB);
                GUI.Label(new Rect(cx - 290f, 285f, 580f, 60f), netMsg, sL);
                bool host = net != null && net.isHost;
                if (host)
                {
                    GUI.Label(new Rect(cx - 290f, 350f, 580f, 30f), "目前 " + lobby.Count + " 人（含你）。會隨機選一個人當食客。", sL);
                    if (Btn(new Rect(cx - 220f, 410f, 200f, 60f), "開始遊戲", new Color(0.80f, 0.30f, 0.20f)))
                    {
                        if (lobby.Count < 2) netMsg = "至少要兩個人才能開始。";
                        else
                        {
                            var ids = new List<int>(lobby); var hids = new List<int> { ids[Random.Range(0, ids.Count)] };
                            net.Send("start|" + string.Join(",", hids) + "|" + string.Join(",", ids)); StartMp(hids, ids);
                        }
                    }
                }
                if (Btn(new Rect(cx + 20f, 410f, 200f, 60f), "離開", new Color(0.3f, 0.3f, 0.3f))) ToMenu();
                return;
            }

            if (hunter && ph == Ph.Hide)
            {
                Box(new Rect(0f, 0f, W_, H), new Color(0.05f, 0.03f, 0.02f, 0.98f));
                var big = new GUIStyle(sB) { fontSize = 40 }; GUI.Label(new Rect(0f, 300f, W_, 60f), "飯糰們正在躲藏…", big);
                GUI.Label(new Rect(0f, 370f, W_, 40f), Mathf.Max(0, Mathf.CeilToInt(timer)).ToString(), sB);
                return;
            }

            // 頂部：階段、時間、人數
            Box(new Rect(cx - 230f, 10f, 460f, 50f), panel); Box(new Rect(cx - 230f, 58f, 460f, 2f), gold);
            string title = practice ? "練習模式" : ph == Ph.Hide ? "躲藏時間" : ph == Ph.Seek ? "搜索中" : "結束";
            int tt = Mathf.Max(0, Mathf.CeilToInt(timer));
            string counts = practice ? "" : "　飯糰 " + (solo ? others.Count - found : hiderIds.Count - caughtIds.Count) + "　食客 " + (solo ? 1 : hunterIds.Count);
            GUI.Label(new Rect(cx - 230f, 10f, 460f, 48f), title + (practice ? "" : "　" + (tt / 60) + ":" + (tt % 60).ToString("00")) + counts, sB);

            string guide = "";
            if (ph == Ph.Hide || ph == Ph.Seek)
            {
                if (hunter) guide = Cursor.lockState == CursorLockMode.Locked ? "看起來怪怪的牆、地板、家具可能就是人。準星對準按左鍵，打錯會浪費醬油。" : "先按一下滑鼠左鍵，才能用滑鼠轉視角。";
                else if (caught) guide = "你出局了，可以留在原地看。";
                else if (ph == Ph.Hide) guide = "找個地方 → 按 R 擺姿勢 → 對著牆或地板按 C 吸顏色 → 按住左鍵往自己身上塗。";
                else guide = "食客在找了。現在還能補塗和換位置，但動作會暴露你。";
            }
            if (guide.Length > 0) { Box(new Rect(cx - 420f, 68f, 840f, 34f), new Color(0.10f, 0.20f, 0.30f, 0.9f)); GUI.Label(new Rect(cx - 412f, 68f, 824f, 34f), guide, sL); }
            if (toastT > 0f && toast.Length > 0) { Box(new Rect(cx - 300f, 108f, 600f, 36f), panel); GUI.Label(new Rect(cx - 300f, 108f, 600f, 36f), toast, sL); }

            if (ph == Ph.Hide || ph == Ph.Seek)
            {
                Box(new Rect(0f, H - 80f, W_, 80f), panel); Box(new Rect(0f, H - 80f, W_, 2f), gold);
                if (hunter)
                {
                    GUI.Label(new Rect(20f, H - 66f, 80f, 30f), "醬油", sL);
                    for (int i = 0; i < 6; i++) Box(new Rect(100f + i * 34f, H - 62f, 26f, 26f), i < ammo ? new Color(0.35f, 0.16f, 0.08f) : new Color(1f, 1f, 1f, 0.15f));
                    GUI.Label(new Rect(330f, H - 70f, W_ - 350f, 60f), "WASD 走動　Shift 跑　滑鼠 轉視角　左鍵 開槍" + (solo ? "　Esc 回主選單" : ""), sL);
                    Box(new Rect(cx - 5f, H / 2f - 5f, 10f, 10f), new Color(0f, 0f, 0f, 0.6f)); Box(new Rect(cx - 3f, H / 2f - 3f, 6f, 6f), Color.white);
                }
                else if (!caught)
                {
                    GUI.Label(new Rect(20f, H - 72f, W_ - 40f, 64f), "WASD 走　Shift 跑　Q/E 轉身　R 換姿勢（" + poseNames[pose] + "）　右鍵拖曳 轉鏡頭　滾輪 縮放\n左鍵 往自己身上塗　C 吸顏色　F 塗滿　Z 撤銷　[ ] 筆刷　- = 光澤" + (solo ? "　Esc 回主選單" : ""), sL);
                    PaintPanel(panel, gold);
                }
            }
            if (ph == Ph.End)
            {
                Box(new Rect(cx - 300f, 250f, 600f, 200f), panel); Box(new Rect(cx - 300f, 250f, 600f, 3f), gold);
                GUI.Label(new Rect(cx - 290f, 270f, 580f, 90f), result, sB);
                if (Btn(new Rect(cx - 110f, 375f, 220f, 54f), "回主選單", new Color(0.80f, 0.30f, 0.20f))) ToMenu();
            }
        }
    }
}
