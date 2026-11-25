// 別吃壽司 - 新主體：整間壽司店當舞台。躲的人是飯糰小人，第三人稱走動、擺姿勢、把自己塗成環境；
// 找的人第一人稱拿醬油槍在店裡搜。單人可練習或打電腦，多人用主機直連。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public class HouseGame : MonoBehaviour
    {
        enum Ph { Menu, Lobby, Hide, Seek, Reveal, End }
        class Hider { public GameObject go; public Paintable paint; public int pose = -1; public Vector3 pos; public float yaw, gloss = -1f; public bool caught; public float speed; }
        class Clone { public GameObject go; public Paintable paint; public int owner; }

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

        // 規則設定（房主可改）。原版的預設值查不到，這些數字是我們自己定的。
        int mode, cfgHide = 60, cfgSeek = 180, cfgReveal = 15, cfgAmmo = 5, cfgWhistle = 30;
        static readonly string[] modeNames = { "基本", "越抓越多", "雙重（全員先躲再全員找）" };
        float fireT, score, whistleT, fcYaw, fcPitch = 20f;
        bool cling, freeCam;
        int myClones;
        Vector3 fcPos;
        readonly float[] cloneCd = new float[2];
        readonly List<Clone> clones = new List<Clone>();
        readonly Dictionary<int, int> hunterAmmo = new Dictionary<int, int>();
        int MyId { get { return net != null ? net.myId : 0; } }

        // ---------- 單人：電腦食客。沿固定路線巡邏，到點就環顧；靠「畫面裡有你和沒你差多少」判斷有沒有看出來 ----------
        GameObject ai; Camera aiCam; RenderTexture aiRt; Texture2D aiRead; Color32[] bufA, bufB;
        int aiWp; float aiScanT, aiPerT, aiSus, aiYaw; bool aiScan;
        static readonly Vector3[] aiPath =
        {
            new Vector3(0f, 0f, -7f), new Vector3(-8.5f, 0f, -5f), new Vector3(-9.5f, 0f, 1.5f), new Vector3(-9f, 0f, 4f), new Vector3(-3f, 0f, 3f),
            new Vector3(3.5f, 0f, 3f), new Vector3(8.5f, 0f, 6.5f), new Vector3(11f, 0f, 2.5f), new Vector3(4.5f, 0f, -1f), new Vector3(4.5f, 0f, -6f)
        };

        void SpawnAi()
        {
            ai = new GameObject("AiSeeker"); ai.transform.SetParent(root, false); ai.transform.position = aiPath[0];
            var pt = ai.AddComponent<Paintable>(); pt.Init(SushiShapes.Get(ShapeKind.Stand), SushiKind.Blank, false);
            pt.Fill(new Color32(150, 34, 30, 255)); pt.Flush();
            hunterAv[-99] = ai;
            var eye = new GameObject("Eye"); eye.transform.SetParent(ai.transform, false); eye.transform.localPosition = new Vector3(0f, 1.55f, 0.3f);
            aiCam = eye.AddComponent<Camera>(); aiCam.enabled = false; aiCam.fieldOfView = 62f; aiCam.nearClipPlane = 0.2f; aiCam.farClipPlane = 40f;
            aiCam.clearFlags = CameraClearFlags.SolidColor; aiCam.backgroundColor = Color.black;
            if (aiRt == null) aiRt = new RenderTexture(128, 96, 16, RenderTextureFormat.ARGB32);
            aiCam.targetTexture = aiRt;
            if (aiRead == null) { aiRead = new Texture2D(128, 96, TextureFormat.RGBA32, false); bufA = new Color32[128 * 96]; bufB = new Color32[128 * 96]; }
            aiWp = 1; aiSus = 0f; aiScan = false; aiYaw = 0f; aiPerT = 1f;
        }

        void AiShot(bool showMe, Color32[] buf)
        {
            body.rend.enabled = showMe; aiCam.Render();
            var prev = RenderTexture.active; RenderTexture.active = aiRt;
            aiRead.ReadPixels(new Rect(0, 0, 128, 96), 0, 0, false); RenderTexture.active = prev;
            aiRead.GetPixelData<Color32>(0).CopyTo(buf);
        }

        float AiPerceive()
        {
            Bounds b = body.rend.bounds; float x0 = 9f, x1 = -9f, y0 = 9f, y1 = -9f;
            for (int i = 0; i < 8; i++)
            {
                Vector3 v = aiCam.WorldToViewportPoint(b.center + Vector3.Scale(b.extents, new Vector3((i & 1) == 0 ? -1f : 1f, (i & 2) == 0 ? -1f : 1f, (i & 4) == 0 ? -1f : 1f)));
                if (v.z <= 0f) return -1f;
                x0 = Mathf.Min(x0, v.x); x1 = Mathf.Max(x1, v.x); y0 = Mathf.Min(y0, v.y); y1 = Mathf.Max(y1, v.y);
            }
            if (x1 < 0f || x0 > 1f || y1 < 0f || y0 > 1f) return -1f;
            int ax = Mathf.Clamp((int)(x0 * 128f) - 1, 0, 127), bx = Mathf.Clamp((int)(x1 * 128f) + 1, 0, 127), ay = Mathf.Clamp((int)(y0 * 96f) - 1, 0, 95), by = Mathf.Clamp((int)(y1 * 96f) + 1, 0, 95);
            AiShot(true, bufA); AiShot(false, bufB); body.rend.enabled = true;
            float sum = 0f;
            for (int y = ay; y <= by; y++) for (int x = ax; x <= bx; x++)
            {
                Color32 p = bufA[y * 128 + x], q = bufB[y * 128 + x];
                float dr = (p.r - q.r) / 255f, dg = (p.g - q.g) / 255f, db = (p.b - q.b) / 255f, d = Mathf.Sqrt(dr * dr * 0.3f + dg * dg * 0.59f + db * db * 0.11f);
                if (d > 0.05f) sum += d - 0.05f;
            }
            return sum;
        }

        void AiTick(float dt)
        {
            if (ai == null || caught) return;
            Vector3 toMe = me.position - ai.transform.position; toMe.y = 0f;
            if (!aiScan)
            {
                Vector3 d = aiPath[aiWp] - ai.transform.position; d.y = 0f;
                if (d.magnitude < 0.15f) { aiScan = true; aiScanT = 4.5f; }
                else { ai.transform.position += d.normalized * Mathf.Min(d.magnitude, 2.4f * dt); aiYaw = Mathf.MoveTowardsAngle(aiYaw, Mathf.Atan2(d.x, d.z) * Mathf.Rad2Deg, 240f * dt); }
            }
            else
            {
                aiScanT -= dt;
                if (aiSus > 0.35f) aiYaw = Mathf.MoveTowardsAngle(aiYaw, Mathf.Atan2(toMe.x, toMe.z) * Mathf.Rad2Deg, 200f * dt); else aiYaw += 80f * dt;
                if (aiScanT <= 0f && aiSus < 0.35f) { aiScan = false; aiWp = (aiWp + 1) % aiPath.Length; }
            }
            ai.transform.rotation = Quaternion.Euler(0f, aiYaw, 0f);
            aiPerT -= dt;
            if (aiPerT > 0f) return;
            aiPerT = 0.35f;
            float s = AiPerceive(), gain = s < 0f ? 0f : s / 40f;
            if (s >= 0f && (Wish(camYaw).sqrMagnitude > 0f || stroke)) gain += 0.5f;
            aiSus = Mathf.Clamp(aiSus + (Mathf.Min(gain, 0.6f) - 0.06f) * 0.35f, 0f, 1.2f);
            if (aiSus < 1f) return;
            Vector3 eye = aiCam.transform.position, aim = me.position + Vector3.up * 0.9f - eye; RaycastHit h;
            Sfx.Beep(240f, 0.08f, 0.35f);
            if (Physics.Raycast(eye, aim.normalized, out h, 40f) && h.collider.transform.IsChildOf(me))
            {
                body.Dab(h.point, h.normal, 0.3f, (Color32)Color.HSVToRGB(Random.value, 0.9f, 1f)); body.Flush();
                caught = true; End("電腦食客找到你了。");
            }
            else aiSus = 0.5f;
        }

        void Start() { BuildWorld(); SpawnMe(false, new Vector3(0f, 0f, -6f)); SetPaint(paintColor); }
        void OnDestroy() { if (net != null) net.Close(); }

        static void Kill(Object o) { if (o == null) return; if (Application.isPlaying) Destroy(o); else DestroyImmediate(o); }
        void Toast(string s) { toast = s; toastT = 5f; }
        static string F(float v) { return v.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture); }
        static float P(string v) { return float.Parse(v, System.Globalization.CultureInfo.InvariantCulture); }

        // ================= 場景 =================

        static Color Rgb(float r, float g, float b) { return new Color(r, g, b, 1f); }
        static float Fr(float x) { return x - Mathf.Floor(x); }
        static float Hash(float x, float y) { return Fr(Mathf.Sin(x * 127.1f + y * 311.7f + 1.7f) * 43758.5453f); }

        // 可以無縫重複的雜訊：四個角落的 Perlin 混在一起
        static float TNoise(float u, float v, float fx, float fy)
        {
            u = Fr(u); v = Fr(v);
            float n00 = Mathf.PerlinNoise(u * fx + 200f, v * fy + 200f), n10 = Mathf.PerlinNoise((u - 1f) * fx + 200f, v * fy + 200f);
            float n01 = Mathf.PerlinNoise(u * fx + 200f, (v - 1f) * fy + 200f), n11 = Mathf.PerlinNoise((u - 1f) * fx + 200f, (v - 1f) * fy + 200f);
            return Mathf.Lerp(Mathf.Lerp(n00, n10, u), Mathf.Lerp(n01, n11, u), v);
        }

        static float Seg(float px, float py, float ax, float ay, float bx, float by)
        {
            float dx = bx - ax, dy = by - ay, t = Mathf.Clamp01(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy + 0.000001f));
            float ex = px - ax - dx * t, ey = py - ay - dy * t;
            return Mathf.Sqrt(ex * ex + ey * ey);
        }
        static float St(float d, float x, float y, float ax, float ay, float bx, float by) { return Mathf.Min(d, Seg(x, y, ax, ay, bx, by)); }
        static float GBox(float d, float x, float y, float x0, float y0, float x1, float y1)
        {
            d = St(d, x, y, x0, y0, x1, y0); d = St(d, x, y, x1, y0, x1, y1); d = St(d, x, y, x1, y1, x0, y1); d = St(d, x, y, x0, y1, x0, y0);
            return d;
        }

        // 幾個筆畫簡單的字（米大山日本上中田王司），回傳到最近筆畫的距離。x、y 在 0..1，y 朝上
        static float Glyph(int id, float x, float y)
        {
            float d = 9f;
            if (x < -0.15f || x > 1.15f || y < -0.15f || y > 1.15f) return d;
            switch (((id % 10) + 10) % 10)
            {
                case 0:
                    d = St(d, x, y, 0.1f, 0.5f, 0.9f, 0.5f); d = St(d, x, y, 0.5f, 0.92f, 0.5f, 0.08f); d = St(d, x, y, 0.24f, 0.86f, 0.38f, 0.64f);
                    d = St(d, x, y, 0.76f, 0.86f, 0.62f, 0.64f); d = St(d, x, y, 0.5f, 0.5f, 0.14f, 0.12f); d = St(d, x, y, 0.5f, 0.5f, 0.86f, 0.12f); break;
                case 1:
                    d = St(d, x, y, 0.1f, 0.64f, 0.9f, 0.64f); d = St(d, x, y, 0.5f, 0.92f, 0.5f, 0.62f); d = St(d, x, y, 0.5f, 0.62f, 0.14f, 0.1f); d = St(d, x, y, 0.5f, 0.62f, 0.86f, 0.1f); break;
                case 2:
                    d = St(d, x, y, 0.5f, 0.9f, 0.5f, 0.14f); d = St(d, x, y, 0.14f, 0.6f, 0.14f, 0.14f); d = St(d, x, y, 0.86f, 0.6f, 0.86f, 0.14f); d = St(d, x, y, 0.14f, 0.14f, 0.86f, 0.14f); break;
                case 3:
                    d = GBox(d, x, y, 0.26f, 0.1f, 0.74f, 0.9f); d = St(d, x, y, 0.26f, 0.5f, 0.74f, 0.5f); break;
                case 4:
                    d = St(d, x, y, 0.1f, 0.66f, 0.9f, 0.66f); d = St(d, x, y, 0.5f, 0.92f, 0.5f, 0.08f); d = St(d, x, y, 0.5f, 0.66f, 0.12f, 0.22f);
                    d = St(d, x, y, 0.5f, 0.66f, 0.88f, 0.22f); d = St(d, x, y, 0.34f, 0.3f, 0.66f, 0.3f); break;
                case 5:
                    d = St(d, x, y, 0.46f, 0.9f, 0.46f, 0.12f); d = St(d, x, y, 0.46f, 0.56f, 0.82f, 0.56f); d = St(d, x, y, 0.1f, 0.12f, 0.9f, 0.12f); break;
                case 6:
                    d = GBox(d, x, y, 0.16f, 0.36f, 0.84f, 0.72f); d = St(d, x, y, 0.5f, 0.95f, 0.5f, 0.05f); break;
                case 7:
                    d = GBox(d, x, y, 0.14f, 0.14f, 0.86f, 0.86f); d = St(d, x, y, 0.5f, 0.86f, 0.5f, 0.14f); d = St(d, x, y, 0.14f, 0.5f, 0.86f, 0.5f); break;
                case 8:
                    d = St(d, x, y, 0.16f, 0.86f, 0.84f, 0.86f); d = St(d, x, y, 0.22f, 0.5f, 0.78f, 0.5f); d = St(d, x, y, 0.1f, 0.12f, 0.9f, 0.12f); d = St(d, x, y, 0.5f, 0.86f, 0.5f, 0.12f); break;
                default:
                    d = St(d, x, y, 0.2f, 0.86f, 0.8f, 0.86f); d = St(d, x, y, 0.8f, 0.86f, 0.8f, 0.12f); d = St(d, x, y, 0.8f, 0.12f, 0.66f, 0.2f);
                    d = St(d, x, y, 0.2f, 0.66f, 0.62f, 0.66f); d = GBox(d, x, y, 0.22f, 0.2f, 0.6f, 0.48f); break;
            }
            return d;
        }
        static bool Ink(int id, float u, float v, float x0, float y0, float w, float h, float thick) { return Glyph(id, (u - x0) / w, (v - y0) / h) < thick; }

        // 麻葉：正三角格，每個三角形從中心連到三個頂點
        static float Asa(float x, float y)
        {
            const float s = 1.732f; float Y = y * s, d = 9f, h = s * 0.5f;
            d = St(d, x, Y, 0f, 0f, 1f, 0f); d = St(d, x, Y, 0f, s, 1f, s); d = St(d, x, Y, 0f, h, 1f, h);
            d = St(d, x, Y, 0f, 0f, 0.5f, h); d = St(d, x, Y, 1f, 0f, 0.5f, h); d = St(d, x, Y, 0f, s, 0.5f, h); d = St(d, x, Y, 1f, s, 0.5f, h);
            d = St(d, x, Y, 0.5f, s / 6f, 0f, 0f); d = St(d, x, Y, 0.5f, s / 6f, 1f, 0f); d = St(d, x, Y, 0.5f, s / 6f, 0.5f, h);
            d = St(d, x, Y, 0.5f, s * 5f / 6f, 0f, s); d = St(d, x, Y, 0.5f, s * 5f / 6f, 1f, s); d = St(d, x, Y, 0.5f, s * 5f / 6f, 0.5f, h);
            d = St(d, x, Y, 0f, s / 3f, 0f, 0f); d = St(d, x, Y, 0f, s / 3f, 0.5f, h); d = St(d, x, Y, 1f, s / 3f, 1f, 0f); d = St(d, x, Y, 1f, s / 3f, 0.5f, h);
            d = St(d, x, Y, 0f, s * 2f / 3f, 0f, s); d = St(d, x, Y, 0f, s * 2f / 3f, 0.5f, h); d = St(d, x, Y, 1f, s * 2f / 3f, 1f, s); d = St(d, x, Y, 1f, s * 2f / 3f, 0.5f, h);
            return d;
        }

        // 一個像素的顏色。a 是底色、b 是花紋色、c3 是第三色（落款、邊、標籤字）
        static Color Px(int type, float u, float v, int x, int y, Color a, Color b, Color c3, int seed)
        {
            float k = 0f; Color c = a; bool direct = false; float grain = 0.05f;
            Color red = Rgb(0.78f, 0.13f, 0.10f), paperC = Rgb(0.95f, 0.92f, 0.82f);
            switch (type)
            {
                case 0: k = TNoise(u, v, 6f, 6f) * 0.6f + TNoise(u, v, 23f, 23f) * 0.4f; grain = 0.07f; break;                 // 灰泥
                case 1: k = TNoise(u, v, 2f, 26f) * 0.7f + TNoise(u, v, 9f, 60f) * 0.3f; break;                                 // 木紋（橫）
                case 38: k = TNoise(u, v, 26f, 2f) * 0.7f + TNoise(u, v, 60f, 9f) * 0.3f; break;                                // 木紋（直）
                case 2: k = ((int)(u * 4f) + (int)(v * 4f)) % 2; break;                                                         // 市松
                case 3:                                                                                                         // 青海波
                {
                    const float r = 0.25f, h = 0.125f;
                    int j0 = Mathf.FloorToInt((v - r) / h);
                    for (int j = j0; j <= j0 + 6; j++)
                    {
                        float cy = j * h, off = (((j % 2) + 2) % 2 == 0) ? 0f : 0.25f;
                        float dx = (Fr((u - off) * 2f + 0.5f) - 0.5f) * 0.5f, dy = v - cy;
                        float d = Mathf.Sqrt(dx * dx + dy * dy);
                        if (d >= r) continue;
                        float ring = d / r;
                        k = (ring > 0.86f || (ring > 0.56f && ring < 0.70f) || (ring > 0.28f && ring < 0.42f) || ring < 0.12f) ? 1f : 0f;
                        break;
                    }
                    break;
                }
                case 4: k = Asa(Fr(u * 4f), Fr(v * 2f)) < 0.05f ? 1f : 0f; break;                                               // 麻葉
                case 5:                                                                                                         // 榻榻米
                {
                    k = (Fr(v * 48f) < 0.35f ? 0.3f : 0f) + TNoise(u, v, 5f, 5f) * 0.25f;
                    if (u < 0.05f || u > 0.95f) { direct = true; c = Color.Lerp(c3, b, (Fr(u * 80f) < 0.5f) == (Fr(v * 40f) < 0.5f) ? 0.25f : 0f); }
                    else if (v < 0.008f || v > 0.992f) k = 1f;
                    break;
                }
                case 6: k = Fr(u * 6f) < 0.5f ? 1f : 0f; break;                                                                 // 直條
                case 7: { float du = Fr(u * 5f) - 0.5f, dv = Fr(v * 5f) - 0.5f; k = du * du + dv * dv < 0.07f ? 1f : 0f; break; } // 圓點
                case 8:                                                                                                         // 障子格
                {
                    bool bar = Mathf.Abs(Fr(u * 2f + 0.5f) - 0.5f) < 0.03f || Mathf.Abs(Fr(v * 3f + 0.5f) - 0.5f) < 0.04f;
                    k = bar ? 1f : TNoise(u, v, 30f, 30f) * 0.07f; grain = 0.03f; break;
                }
                case 9:                                                                                                         // 直木板
                {
                    float pu = u * 4f, f = Fr(pu);
                    k = (f < 0.03f || f > 0.97f) ? 1f : Hash(Mathf.Floor(pu), seed) * 0.18f + TNoise(u, v, 40f, 3f) * 0.22f; break;
                }
                case 10:                                                                                                        // 矢絣
                {
                    float f = Fr(u * 4f); int col = (int)(u * 4f);
                    float s = Fr(v * 4f + (col % 2 == 0 ? 1f : -1f) * Mathf.Abs(f - 0.5f) * 1.6f);
                    k = s < 0.5f ? 1f : 0f; if (Mathf.Abs(f - 0.5f) < 0.03f) k = 0.5f; break;
                }
                case 11:                                                                                                        // 龜甲
                {
                    float X = u * 3f, Yn = v * 2f;
                    float ax = Fr(X) - 0.5f, ay = (Fr(Yn) - 0.5f) * 1.732f, bx = Fr(X + 0.5f) - 0.5f, by = (Fr(Yn + 0.5f) - 0.5f) * 1.732f;
                    float hx = ax, hy = ay; if (bx * bx + by * by < ax * ax + ay * ay) { hx = bx; hy = by; }
                    hx = Mathf.Abs(hx); hy = Mathf.Abs(hy);
                    float hd = Mathf.Max(hx, hx * 0.5f + hy * 0.866f);
                    k = (hd > 0.45f || (hd > 0.22f && hd < 0.29f) || hd < 0.07f) ? 1f : 0f; break;
                }
                case 12:                                                                                                        // 磚
                {
                    int row = (int)(v * 8f); float fu = u * 4f + (row % 2) * 0.5f, f = Fr(fu), fv = Fr(v * 8f);
                    k = (f < 0.04f || fv < 0.1f) ? 0f : 0.55f + 0.45f * Hash(Mathf.Floor(fu) % 4f, row); grain = 0.09f; break;
                }
                case 13:                                                                                                        // 磁磚
                {
                    float f = Fr(u * 4f), g = Fr(v * 4f);
                    k = (f < 0.045f || g < 0.045f) ? 0f : ((f > 0.9f || g < 0.11f) ? 0.84f : 1f) * (0.9f + 0.1f * Hash(Mathf.Floor(u * 4f), Mathf.Floor(v * 4f))); grain = 0.02f; break;
                }
                case 14: k = (((int)(u * 40f) + (int)(v * 40f)) % 2) * 0.22f; grain = 0.08f; break;                           // 布紋
                case 15:                                                                                                        // 竹簾
                {
                    float s = Fr(v * 20f);
                    k = s < 0.16f ? 0.75f : Mathf.Abs(s - 0.58f) * 0.4f;
                    if (Mathf.Abs(Fr(u * 3f + 0.5f) - 0.5f) < 0.025f) k = 1f; break;
                }
                case 16:                                                                                                        // 七寶
                {
                    float fx = Fr(u * 3f), fy = Fr(v * 3f);
                    float d0 = Mathf.Sqrt(fx * fx + fy * fy), d1 = Mathf.Sqrt((fx - 1f) * (fx - 1f) + fy * fy), d2 = Mathf.Sqrt(fx * fx + (fy - 1f) * (fy - 1f));
                    float d3 = Mathf.Sqrt((fx - 1f) * (fx - 1f) + (fy - 1f) * (fy - 1f)), d4 = Mathf.Sqrt((fx - 0.5f) * (fx - 0.5f) + (fy - 0.5f) * (fy - 0.5f));
                    const float w = 0.035f;
                    k = (Mathf.Abs(d0 - 0.5f) < w || Mathf.Abs(d1 - 0.5f) < w || Mathf.Abs(d2 - 0.5f) < w || Mathf.Abs(d3 - 0.5f) < w || Mathf.Abs(d4 - 0.5f) < w || d4 < 0.07f || d0 < 0.07f || d1 < 0.07f || d2 < 0.07f || d3 < 0.07f) ? 1f : 0f;
                    break;
                }
                case 17:                                                                                                        // 鱗
                {
                    int row = (int)(v * 6f); float fx = Fr(u * 6f + (row % 2) * 0.5f), fy = Fr(v * 6f);
                    k = fy < 1f - 2f * Mathf.Abs(fx - 0.5f) ? 1f : 0f; break;
                }
                case 18:                                                                                                        // 櫻花
                {
                    float cx = Mathf.Floor(u * 3f), cy = Mathf.Floor(v * 3f);
                    float dx = Fr(u * 3f) - 0.5f - (Hash(cx, cy + seed) - 0.5f) * 0.3f, dy = Fr(v * 3f) - 0.5f - (Hash(cy + 5f, cx + seed) - 0.5f) * 0.3f;
                    float r = Mathf.Sqrt(dx * dx + dy * dy), th = Mathf.Atan2(dy, dx) + Hash(cx + 9f, cy) * 6f;
                    float R = 0.31f * (0.5f + 0.5f * Mathf.Abs(Mathf.Cos(2.5f * th)));
                    k = r < 0.05f ? 0.35f : r < R ? 1f : 0f; break;
                }
                case 19: k = Fr(v * 6f + 0.2f * Mathf.Sin(u * 12.566f)) < 0.5f ? 1f : 0f; break;                                // 波紋
                case 20:                                                                                                        // 金地雲
                {
                    float n = TNoise(u, v, 3f, 9f);
                    k = n > 0.56f ? 0.9f : n > 0.53f ? 0.45f : TNoise(u, v, 40f, 40f) * 0.18f;
                    if (Fr(u * 4f) < 0.012f || Fr(v * 4f) < 0.012f) k += 0.12f; break;
                }
                case 21:                                                                                                        // 木格柵
                {
                    float f = Fr(u * 8f);
                    k = f < 0.6f ? TNoise(u, v, 50f, 3f) * 0.25f : 1f;
                    if (Mathf.Abs(v - 0.5f) < 0.03f || v < 0.03f || v > 0.97f) k = 0.12f; break;
                }
                case 22: k = Fr(u * 12f + v * 3f) < 0.5f ? 0.15f : 0.75f; break;                                                // 繩
                case 23:                                                                                                        // 石板
                {
                    float gx = u * 4f, gy = v * 4f, f1 = 9f, f2 = 9f, id = 0f;
                    int ix = Mathf.FloorToInt(gx), iy = Mathf.FloorToInt(gy);
                    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++)
                    {
                        int qx = ((ix + i) % 4 + 4) % 4, qy = ((iy + j) % 4 + 4) % 4;
                        float sx = ix + i + 0.2f + 0.6f * Hash(qx, qy + 3f), sy = iy + j + 0.2f + 0.6f * Hash(qy + 7f, qx);
                        float d = Mathf.Sqrt((gx - sx) * (gx - sx) + (gy - sy) * (gy - sy));
                        if (d < f1) { f2 = f1; f1 = d; id = qx * 4f + qy; } else if (d < f2) f2 = d;
                    }
                    k = f2 - f1 < 0.07f ? 0f : 0.55f + 0.45f * Hash(id, 2f); grain = 0.08f; break;
                }
                case 24:                                                                                                        // 暖簾（圓紋加字）
                {
                    float d = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.54f) * (v - 0.54f));
                    k = (Mathf.Abs(d - 0.3f) < 0.03f || Ink(seed, u, v, 0.31f, 0.35f, 0.38f, 0.38f, 0.085f) || v > 0.93f) ? 1f : (((int)(u * 40f) + (int)(v * 40f)) % 2) * 0.08f;
                    grain = 0.07f; break;
                }
                case 25:                                                                                                        // 掛軸
                {
                    direct = true;
                    if (u < 0.14f || u > 0.86f || v < 0.08f || v > 0.9f) c = Color.Lerp(c3, paperC, (Fr(u * 10f) < 0.5f) == (Fr(v * 26f) < 0.5f) ? 0.22f : 0f);
                    else
                    {
                        c = a;
                        float gv = (v - 0.15f) / 0.24f; int gi = Mathf.FloorToInt(gv);
                        if (gi >= 0 && gi < 3 && Ink(seed + (2 - gi) * 3, u, Fr(gv), 0.27f, 0.08f, 0.46f, 0.84f, 0.1f)) c = b;
                        if (u > 0.68f && u < 0.78f && v > 0.105f && v < 0.14f) c = red;
                    }
                    break;
                }
                case 26:                                                                                                        // 菜單
                {
                    direct = true; c = a;
                    float cu = u * 5f, gx = Fr(cu), gv = (v - 0.06f) / 0.21f; int ci = (int)cu, ri = Mathf.FloorToInt(gv);
                    if (v > 0.92f) c = red;
                    else if (gx < 0.035f) c = Color.Lerp(a, b, 0.5f);
                    else if (ri >= 0 && ri < 4 && Ink(seed + ci * 7 + ri * 3, gx, Fr(gv), 0.16f, 0.08f, 0.7f, 0.84f, 0.11f)) c = b;
                    break;
                }
                case 27:                                                                                                        // 菰樽（稻草包的酒樽）
                {
                    direct = true;
                    c = Color.Lerp(a, a * 0.78f, (((int)(u * 72f) + (int)(v * 20f)) % 2) * 0.5f + TNoise(u, v, 8f, 8f) * 0.4f);
                    float lu = Fr(u * 3f);
                    if ((v > 0.08f && v < 0.17f) || (v > 0.83f && v < 0.92f)) c = Color.Lerp(b * 0.55f, b, Fr(u * 30f + v * 8f) < 0.5f ? 1f : 0f);
                    else if (lu > 0.1f && lu < 0.9f && v > 0.24f && v < 0.76f)
                    {
                        c = paperC;
                        if (lu < 0.13f || lu > 0.87f || v < 0.265f || v > 0.735f) c = c3;
                        else if (Ink(seed + (int)(u * 3f), lu, v, 0.24f, 0.3f, 0.52f, 0.4f, 0.1f)) c = c3;
                    }
                    break;
                }
                case 28:                                                                                                        // 木箱
                {
                    float fv = Fr(v * 4f);
                    k = fv < 0.05f ? 0.8f : TNoise(u, v, 3f, 40f) * 0.25f + Hash(Mathf.Floor(v * 4f), seed) * 0.12f;
                    if (u < 0.09f || u > 0.91f) k = Mathf.Max(k, 0.38f);
                    float d = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f));
                    if (Mathf.Abs(d - 0.27f) < 0.022f || Ink(seed, u, v, 0.34f, 0.34f, 0.32f, 0.32f, 0.1f)) k = 1f;
                    break;
                }
                case 29:                                                                                                        // 提燈
                {
                    direct = true; c = Fr(v * 16f) < 0.14f ? a * 0.8f : a;
                    float lu = Fr(u * 2f);
                    if (v < 0.1f || v > 0.9f) c = b;
                    else if (Ink(seed, lu, v, 0.38f, 0.32f, 0.24f, 0.36f, 0.1f)) c = b;
                    grain = 0.02f; break;
                }
                case 30:                                                                                                        // 富士山畫
                {
                    direct = true; c = Color.Lerp(paperC, a, Mathf.Clamp01(v * 1.1f - 0.1f));
                    float ds = Mathf.Sqrt((u - 0.72f) * (u - 0.72f) + (v - 0.74f) * (v - 0.74f));
                    if (ds < 0.11f) c = red;
                    float top = 0.66f - Mathf.Abs(u - 0.42f) * 1.05f;
                    if (v < top && v > 0.2f) c = v > 0.5f + 0.03f * Mathf.Sin(u * 70f) ? Color.white : b;
                    if (v <= 0.24f) c = Fr(v * 34f + Mathf.Sin(u * 25.13f) * 0.3f) < 0.3f ? paperC : Color.Lerp(b, a, 0.25f);
                    if (u < 0.04f || u > 0.96f || v < 0.03f || v > 0.97f) c = c3;
                    break;
                }
                case 31:                                                                                                        // 米袋
                {
                    direct = true;
                    c = Color.Lerp(a, a * 0.8f, (((int)(u * 64f) + (int)(v * 40f)) % 2) * 0.5f);
                    float lu = Fr(u * 2f), d = Mathf.Sqrt((lu - 0.5f) * (lu - 0.5f) + (v - 0.5f) * (v - 0.5f));
                    if (Mathf.Abs(v - 0.24f) < 0.018f || Mathf.Abs(v - 0.76f) < 0.018f) c = b;
                    if (Mathf.Abs(d - 0.2f) < 0.022f || Ink(seed, lu, v, 0.37f, 0.37f, 0.26f, 0.26f, 0.1f)) c = c3;
                    grain = 0.08f; break;
                }
                case 32:                                                                                                        // 魚
                {
                    float bx = (u - 0.45f) / 0.27f, by = (v - 0.55f) / 0.16f;
                    bool bodyIn = bx * bx + by * by < 1f, tail = u > 0.66f && u < 0.9f && Mathf.Abs(v - 0.55f) < (u - 0.64f) * 0.75f;
                    if (bodyIn) k = (u > 0.36f && Fr(u * 16f + Mathf.Abs(v - 0.55f) * 6f) < 0.25f) ? 0.7f : 1f;
                    else if (tail) k = 1f;
                    else if (v < 0.24f) k = Fr(v * 22f + Mathf.Sin(u * 12.566f) * 0.3f) < 0.35f ? 0.55f : 0f;
                    if ((u - 0.29f) * (u - 0.29f) + (v - 0.58f) * (v - 0.58f) < 0.0006f) k = 0f;
                    break;
                }
                case 33:                                                                                                        // 抽屜櫃
                {
                    float fx = Fr(u * 2f), fy = Fr(v * 4f);
                    float d = Mathf.Sqrt((fx - 0.5f) * (fx - 0.5f) * 4f + (fy - 0.5f) * (fy - 0.5f));
                    k = (fx < 0.03f || fx > 0.97f || fy < 0.06f || fy > 0.94f) ? 1f : TNoise(u, v, 4f, 30f) * 0.3f;
                    if (Mathf.Abs(d - 0.2f) < 0.05f) k = 0.9f; break;
                }
                case 35:                                                                                                        // 格子布
                {
                    float bu = Fr(u * 3f), bv = Fr(v * 3f);
                    k = (bu < 0.35f ? 0.4f : 0f) + (bv < 0.35f ? 0.4f : 0f);
                    if (Mathf.Abs(bu - 0.68f) < 0.03f || Mathf.Abs(bv - 0.68f) < 0.03f) k = 1f; grain = 0.07f; break;
                }
                case 37: k = Hash(3f, y) * 0.4f + TNoise(u, v, 3f, 3f) * 0.3f; grain = 0.03f; break;                           // 髮絲紋不鏽鋼
                case 39:                                                                                                        // 障子門（一扇）
                {
                    if (u < 0.06f || u > 0.94f || v > 0.965f || v < 0.03f) k = 1f;
                    else if (v < 0.22f) k = 0.72f + TNoise(u, v, 30f, 3f) * 0.2f;
                    else if (v < 0.245f) k = 1f;
                    else k = (Mathf.Abs(Fr(u * 3f + 0.5f) - 0.5f) < 0.035f || Mathf.Abs(Fr((v - 0.245f) / 0.72f * 5f + 0.5f) - 0.5f) < 0.045f) ? 1f : TNoise(u, v, 30f, 30f) * 0.06f;
                    grain = 0.03f; break;
                }
                case 44:                                                                                                        // 酒瓶
                {
                    direct = true; c = a;
                    float lu = Fr(u * 2f);
                    if (v > 0.9f) c = c3;
                    else if (v > 0.22f && v < 0.66f && lu > 0.1f && lu < 0.9f) c = Ink(seed, lu, v, 0.28f, 0.27f, 0.44f, 0.34f, 0.11f) ? b : paperC;
                    grain = 0.02f; break;
                }
                default: k = (Fr(u * 8f) < 0.06f || Fr(v * 8f) < 0.06f) ? 1f : 0f; break;                                       // 格線
            }
            if (!direct) c = Color.Lerp(a, b, Mathf.Clamp01(k));
            float gr = 1f + (Hash(x, y + seed * 13f) - 0.5f) * 2f * grain;
            c.r = Mathf.Clamp01(c.r * gr); c.g = Mathf.Clamp01(c.g * gr); c.b = Mathf.Clamp01(c.b * gr); c.a = 1f;
            return c;
        }

        Texture2D Pattern(int type, Color a, Color b, Color c3 = default(Color), int seed = 0, int N = 128)
        {
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true);
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                    px[y * N + x] = Px(type, (x + 0.5f) / N, (y + 0.5f) / N, x, y, a, b, c3, seed);
            t.SetPixels32(px); t.Apply(true); t.wrapMode = TextureWrapMode.Repeat; t.anisoLevel = 4;
            return t;
        }

        Material Pat(int type, Color a, Color b, float tx, float ty, float smooth = 0.2f)
        {
            return Mt(Pattern(type, a, b), tx, ty, smooth);
        }
        Material Mt(Texture2D tex, float tx, float ty, float smooth = 0.15f)
        {
            var m = Mats.Lit(Color.white, smooth, tex);
            if (m.HasProperty("_BaseMap")) m.SetTextureScale("_BaseMap", new Vector2(tx, ty));
            return m;
        }
        // 自己發光的材質（燈籠、紙門），顏色超過 1 會被泛光暈開
        Material Glow(Color c, Texture2D tex, float tx, float ty)
        {
            var m = Mats.Unlit(c);
            if (tex != null && m.HasProperty("_BaseMap")) { m.SetTexture("_BaseMap", tex); m.SetTextureScale("_BaseMap", new Vector2(tx, ty)); }
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
        // 底面在 y0 的方塊、圓柱，和球
        GameObject Bx(float x, float y0, float z, float sx, float h, float sz, Material m, bool solid = true) { return W(new Vector3(x, y0 + h * 0.5f, z), new Vector3(sx, h, sz), m, solid); }
        GameObject Cy(float x, float y0, float z, float dia, float h, Material m, bool solid = true) { return Obj(PrimitiveType.Cylinder, new Vector3(x, y0 + h * 0.5f, z), new Vector3(dia, h * 0.5f, dia), m, solid); }
        GameObject Sp(float x, float y, float z, float sx, float sy, float sz, Material m, bool solid = true) { return Obj(PrimitiveType.Sphere, new Vector3(x, y, z), new Vector3(sx, sy, sz), m, solid); }
        GameObject Tilt(GameObject g, float rx, float ry, float rz) { g.transform.rotation = Quaternion.Euler(rx, ry, rz); return g; }
        GameObject Soft(GameObject g) { g.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off; return g; }
        // 沿牆的一塊板：alongX 表示牆沿 x 方向延伸
        GameObject WA(bool alongX, float along, float y, float across, float len, float h, float thick, Material m, bool solid = true)
        {
            return alongX ? W(new Vector3(along, y, across), new Vector3(len, h, thick), m, solid) : W(new Vector3(across, y, along), new Vector3(thick, h, len), m, solid);
        }
        // 一面牆：腰板、橫木、每格不同的壁紙、上方小壁、柱子
        void WallRun(bool alongX, float fix, float inw, float[] cuts, Material[] papers, Material wains, Material frieze, Material rail, Material post)
        {
            float a = cuts[0], b = cuts[cuts.Length - 1], len = b - a, mid = (a + b) * 0.5f;
            WA(alongX, mid, 0.5f, fix + inw * 0.04f, len, 1f, 0.08f, wains);
            WA(alongX, mid, 3.32f, fix + inw * 0.07f, len, 0.14f, 0.14f, rail);
            WA(alongX, mid, 3.695f, fix + inw * 0.02f, len, 0.61f, 0.04f, frieze);
            for (int i = 0; i < papers.Length && i < cuts.Length - 1; i++)
                if (papers[i] != null) WA(alongX, (cuts[i] + cuts[i + 1]) * 0.5f, 2.16f, fix + inw * 0.02f, cuts[i + 1] - cuts[i], 2.2f, 0.04f, papers[i]);
            for (int i = 0; i < cuts.Length; i++) WA(alongX, cuts[i], 2f, fix + inw * 0.08f, 0.2f, 4f, 0.16f, post);
        }
        Material Wp(Texture2D t, float w, float tile, float smooth = 0.08f) { return Mt(t, w / tile, 2.2f / tile, smooth); }
        // 牆上的畫：外框加畫心
        void Poster(bool alongX, float along, float y, float face, float inw, float w, float h, Material pic, Material frame)
        {
            if (w * h > 0.8f) WA(alongX, along, y, face + inw * 0.02f, w + 0.1f, h + 0.1f, 0.04f, frame, false);
            var p = WA(alongX, along, y, face + inw * 0.035f, w, h, 0.04f, pic);
            if (alongX && inw < 0f) Tilt(p, 0f, 0f, 180f);   // 方塊朝 -z 那面的貼圖是倒的，轉半圈擺正
        }
        void Pendant(float x, float y, float z, Material shade, Material bulb, Material cord)
        {
            Soft(Bx(x, y + 0.22f, z, 0.025f, 3.8f - y, 0.025f, cord, false));
            Soft(Cy(x, y, z, 0.46f, 0.24f, shade, false));
            Soft(Sp(x, y + 0.02f, z, 0.3f, 0.3f, 0.3f, bulb, false));
        }
        void Chochin(float x, float y, float z, float dia, float h, Material glow, Material cap, bool solid = false)
        {
            Soft(Sp(x, y, z, dia, h, dia, glow, solid));
            Soft(Cy(x, y + h * 0.44f, z, dia * 0.5f, h * 0.1f, cap, false));
        }
        void Andon(float x, float y0, float z, Material glow, Material wood)
        {
            Bx(x, y0, z, 0.32f, 0.12f, 0.32f, wood);
            Soft(Bx(x, y0 + 0.12f, z, 0.28f, 0.6f, 0.28f, glow));
        }
        // 椅子：dx、dz 指椅背朝哪一邊
        void Chair(float x, float z, float dx, float dz, Material seat, Material wood)
        {
            Bx(x, 0f, z, 0.38f, 0.42f, 0.38f, wood);
            Bx(x, 0.42f, z, 0.44f, 0.06f, 0.44f, seat);
            Bx(x + dx * 0.2f, 0.48f, z + dz * 0.2f, dx != 0f ? 0.05f : 0.44f, 0.5f, dz != 0f ? 0.05f : 0.44f, wood);
        }
        void Plant(float x, float y0, float z, Material pot, Material leaf)
        {
            Cy(x, y0, z, 0.5f, 0.45f, pot);
            Sp(x, y0 + 0.95f, z, 0.85f, 1.0f, 0.8f, leaf);
            Sp(x + 0.12f, y0 + 1.5f, z - 0.08f, 0.62f, 0.7f, 0.58f, leaf, false);
        }
        void Bottle(float x, float y0, float z, float h, Material body, Material neck)
        {
            Cy(x, y0, z, h * 0.3f, h * 0.7f, body, false);
            Cy(x, y0 + h * 0.7f, z, h * 0.11f, h * 0.3f, neck, false);
        }
        void Barrel(float x, float y0, float z, Material side, Material lid)
        {
            Cy(x, y0, z, 0.84f, 0.8f, side);
            Cy(x, y0 + 0.8f, z, 0.8f, 0.03f, lid, false);
        }
        // 門上的短暖簾：一根桿子加幾片布
        void Noren(bool alongX, float from, float to, float yTop, float h, float across, Material[] cloth, int first, Material rod, bool flip = false, float panel = 0.8f)
        {
            float len = to - from; int n = Mathf.Max(1, Mathf.RoundToInt(len / panel)); float w = len / n;
            WA(alongX, (from + to) * 0.5f, yTop + 0.03f, across, len + 0.2f, 0.05f, 0.05f, rod, false);
            for (int i = 0; i < n; i++) { var g = WA(alongX, from + (i + 0.5f) * w, yTop - h * 0.5f, across, w - 0.03f, h, 0.025f, cloth[(first + i) % cloth.Length]); if (flip) Tilt(g, 0f, 0f, 180f); }
        }

        void BuildWorld()
        {
            if (root != null)
            {
                // 上一個場景的花紋貼圖和材質一起清掉，不然每重建一次就多佔一份記憶體
                var oldM = new HashSet<Material>(); var oldT = new HashSet<Texture>();
                foreach (var r in root.GetComponentsInChildren<Renderer>(true))
                {
                    if (r.GetComponentInParent<Paintable>() != null) continue;
                    var m = r.sharedMaterial; if (m == null || !oldM.Add(m)) continue;
                    var tx = m.HasProperty("_BaseMap") ? m.GetTexture("_BaseMap") : null;
                    if (tx != null) oldT.Add(tx);
                }
                foreach (var tx in oldT) Kill(tx);
                foreach (var m in oldM) Kill(m);
                Kill(root.gameObject);
            }
            root = new GameObject("World").transform;
            others.Clear(); hunterAv.Clear(); clones.Clear(); hunterAmmo.Clear();
            myClones = 0; cloneCd[0] = 0f; cloneCd[1] = 0f; cling = false; freeCam = false; score = 0f; fireT = 0f;

            Color cream = Rgb(0.93f, 0.87f, 0.74f), dark = Rgb(0.24f, 0.14f, 0.09f), indigo = Rgb(0.13f, 0.20f, 0.45f), white = Rgb(0.95f, 0.94f, 0.9f);
            Color red = Rgb(0.72f, 0.14f, 0.12f), gold = Rgb(0.80f, 0.62f, 0.24f), moss = Rgb(0.30f, 0.42f, 0.22f), ink = Rgb(0.10f, 0.08f, 0.07f), paperC = Rgb(0.95f, 0.91f, 0.80f);

            // ---------- 花紋貼圖 ----------
            var tGrainD = Pattern(1, Rgb(0.20f, 0.11f, 0.07f), Rgb(0.36f, 0.21f, 0.12f));
            var tGrainDV = Pattern(38, Rgb(0.20f, 0.11f, 0.07f), Rgb(0.36f, 0.21f, 0.12f));
            var tGrainL = Pattern(1, Rgb(0.74f, 0.57f, 0.36f), Rgb(0.90f, 0.76f, 0.54f));
            var tGrainM = Pattern(1, Rgb(0.42f, 0.22f, 0.11f), Rgb(0.62f, 0.37f, 0.19f));
            var tPlanksD = Pattern(9, Rgb(0.36f, 0.22f, 0.13f), Rgb(0.10f, 0.06f, 0.04f), default(Color), 1);
            var tPlanksL = Pattern(9, Rgb(0.82f, 0.66f, 0.44f), Rgb(0.42f, 0.28f, 0.16f), default(Color), 2);
            var tFloor = Pattern(9, Rgb(0.60f, 0.45f, 0.27f), Rgb(0.24f, 0.15f, 0.08f), default(Color), 3);
            var tSteel = Pattern(37, Rgb(0.60f, 0.62f, 0.66f), Rgb(0.84f, 0.86f, 0.89f));
            var tPlaster = Pattern(0, cream, Rgb(0.78f, 0.70f, 0.56f));
            var tPlasterO = Pattern(0, Rgb(0.80f, 0.60f, 0.32f), Rgb(0.64f, 0.46f, 0.24f));
            var tConcrete = Pattern(0, Rgb(0.62f, 0.61f, 0.58f), Rgb(0.44f, 0.43f, 0.41f));
            var tBrick = Pattern(12, Rgb(0.74f, 0.70f, 0.64f), Rgb(0.62f, 0.27f, 0.18f));
            var tTileW = Pattern(13, Rgb(0.50f, 0.54f, 0.56f), Rgb(0.92f, 0.94f, 0.92f));
            var tTileG = Pattern(13, Rgb(0.78f, 0.80f, 0.78f), Rgb(0.16f, 0.42f, 0.46f));
            var tChecker = Pattern(2, Rgb(0.92f, 0.92f, 0.9f), Rgb(0.12f, 0.12f, 0.13f));
            var tStone = Pattern(23, Rgb(0.30f, 0.29f, 0.28f), Rgb(0.62f, 0.60f, 0.56f));
            var tSeig = Pattern(3, Rgb(0.93f, 0.90f, 0.80f), Rgb(0.16f, 0.28f, 0.55f));
            var tSeigR = Pattern(3, Rgb(0.95f, 0.93f, 0.88f), Rgb(0.70f, 0.20f, 0.16f));
            var tAsaG = Pattern(4, moss, Rgb(0.88f, 0.86f, 0.60f));
            var tAsaI = Pattern(4, indigo, Rgb(0.82f, 0.86f, 0.92f));
            var tAsaW = Pattern(4, Rgb(0.90f, 0.84f, 0.66f), Rgb(0.34f, 0.20f, 0.11f));
            var tAsaP = Pattern(4, Rgb(0.86f, 0.42f, 0.50f), white);
            var tYaga = Pattern(10, Rgb(0.93f, 0.88f, 0.80f), Rgb(0.52f, 0.16f, 0.30f));
            var tYagaI = Pattern(10, white, indigo);
            var tKikO = Pattern(11, Rgb(0.82f, 0.64f, 0.30f), Rgb(0.34f, 0.19f, 0.10f));
            var tKikG = Pattern(11, Rgb(0.22f, 0.36f, 0.30f), Rgb(0.80f, 0.76f, 0.48f));
            var tKumo = Pattern(20, gold, Rgb(0.97f, 0.88f, 0.58f));
            var tSakura = Pattern(18, Rgb(0.95f, 0.90f, 0.84f), Rgb(0.88f, 0.46f, 0.56f), default(Color), 1);
            var tSakuraN = Pattern(18, Rgb(0.15f, 0.14f, 0.32f), Rgb(0.96f, 0.74f, 0.80f), default(Color), 4);
            var tNami = Pattern(19, Rgb(0.84f, 0.90f, 0.92f), Rgb(0.24f, 0.42f, 0.60f));
            var tShippo = Pattern(16, red, Rgb(0.96f, 0.86f, 0.60f));
            var tShippoG = Pattern(16, Rgb(0.90f, 0.86f, 0.70f), Rgb(0.26f, 0.44f, 0.36f));
            var tUroko = Pattern(17, Rgb(0.94f, 0.88f, 0.72f), Rgb(0.82f, 0.56f, 0.20f));
            var tUrokoR = Pattern(17, Rgb(0.90f, 0.84f, 0.70f), red);
            var tStripe = Pattern(6, Rgb(0.93f, 0.88f, 0.76f), Rgb(0.64f, 0.16f, 0.14f));
            var tStripeI = Pattern(6, white, indigo);
            var tDotsI = Pattern(7, indigo, white);
            var tDotsR = Pattern(7, red, Rgb(0.96f, 0.88f, 0.72f));
            var tDotsY = Pattern(7, Rgb(0.90f, 0.72f, 0.22f), Rgb(0.36f, 0.20f, 0.10f));
            var tPlaid = Pattern(35, Rgb(0.90f, 0.86f, 0.72f), Rgb(0.20f, 0.38f, 0.30f));
            var tPlaidR = Pattern(35, Rgb(0.94f, 0.90f, 0.82f), red);
            var tPlaidB = Pattern(35, Rgb(0.84f, 0.88f, 0.92f), indigo);
            var tWeaveB = Pattern(14, Rgb(0.20f, 0.30f, 0.62f), Rgb(0.08f, 0.10f, 0.30f));
            var tWeaveW = Pattern(14, Rgb(0.94f, 0.93f, 0.90f), Rgb(0.60f, 0.60f, 0.62f));
            var tShoji = Pattern(8, Rgb(0.97f, 0.94f, 0.84f), dark);
            var tShojiDoor = Pattern(39, Rgb(0.97f, 0.94f, 0.84f), dark);
            var tKoshi = Pattern(21, Rgb(0.46f, 0.28f, 0.15f), Rgb(0.08f, 0.05f, 0.04f));
            var tSunoko = Pattern(21, Rgb(0.80f, 0.64f, 0.42f), Rgb(0.20f, 0.13f, 0.08f));
            var tSudare = Pattern(15, Rgb(0.80f, 0.66f, 0.38f), Rgb(0.34f, 0.22f, 0.10f));
            var tRope = Pattern(22, Rgb(0.86f, 0.74f, 0.46f), Rgb(0.50f, 0.36f, 0.16f));
            var tTatami = Pattern(5, Rgb(0.74f, 0.74f, 0.44f), Rgb(0.42f, 0.44f, 0.20f), Rgb(0.10f, 0.14f, 0.12f));
            var tDrawer = Pattern(33, Rgb(0.50f, 0.28f, 0.14f), Rgb(0.10f, 0.07f, 0.05f));
            var tDrawerL = Pattern(33, Rgb(0.84f, 0.70f, 0.48f), Rgb(0.30f, 0.19f, 0.10f));
            var tGrid = Pattern(99, Rgb(0.86f, 0.70f, 0.42f), ink);
            var tFish = Pattern(32, Rgb(0.40f, 0.78f, 0.86f), Rgb(0.95f, 0.45f, 0.12f));
            var tFishP = Pattern(32, paperC, red);
            var tFishI = Pattern(32, indigo, white);
            var tFuji = Pattern(30, Rgb(0.36f, 0.58f, 0.80f), Rgb(0.14f, 0.22f, 0.46f), dark, 0, 256);
            var tMenuP = Pattern(26, paperC, ink, default(Color), 1);
            var tMenuW = Pattern(26, Rgb(0.20f, 0.12f, 0.08f), Rgb(0.95f, 0.88f, 0.66f), default(Color), 4);
            var tMenuY = Pattern(26, Rgb(0.95f, 0.80f, 0.30f), ink, default(Color), 6);
            var tScrollA = Pattern(25, paperC, ink, Rgb(0.20f, 0.30f, 0.42f), 1);
            var tScrollB = Pattern(25, paperC, ink, Rgb(0.50f, 0.18f, 0.14f), 5);
            var tScrollC = Pattern(25, Rgb(0.92f, 0.84f, 0.62f), Rgb(0.45f, 0.10f, 0.08f), Rgb(0.26f, 0.36f, 0.22f), 8);
            var tBanner = Pattern(25, red, white, Rgb(0.95f, 0.80f, 0.30f), 9);
            var tKomoR = Pattern(27, Rgb(0.86f, 0.74f, 0.46f), Rgb(0.52f, 0.38f, 0.18f), red, 1);
            var tKomoK = Pattern(27, Rgb(0.84f, 0.72f, 0.44f), Rgb(0.52f, 0.38f, 0.18f), ink, 4);
            var tKomoB = Pattern(27, Rgb(0.88f, 0.78f, 0.52f), Rgb(0.52f, 0.38f, 0.18f), indigo, 8);
            var tCrateA = Pattern(28, Rgb(0.78f, 0.62f, 0.40f), Rgb(0.20f, 0.12f, 0.08f), default(Color), 8);
            var tCrateB = Pattern(28, Rgb(0.60f, 0.42f, 0.24f), Rgb(0.12f, 0.08f, 0.06f), default(Color), 0);
            var tCrateY = Pattern(28, Rgb(0.92f, 0.72f, 0.16f), Rgb(0.60f, 0.10f, 0.08f), default(Color), 3);
            var tCrateR = Pattern(28, Rgb(0.74f, 0.16f, 0.14f), Rgb(0.96f, 0.92f, 0.84f), default(Color), 6);
            var tCarton = Pattern(28, Rgb(0.72f, 0.56f, 0.36f), Rgb(0.30f, 0.20f, 0.12f), default(Color), 7);
            var tSack = Pattern(31, Rgb(0.86f, 0.80f, 0.64f), Rgb(0.18f, 0.28f, 0.58f), red, 0);
            var tSackB = Pattern(31, Rgb(0.74f, 0.64f, 0.44f), red, ink, 1);
            var tLantern = Pattern(29, Color.white, Rgb(0.12f, 0.04f, 0.03f), default(Color), 9);
            var tLanternB = Pattern(29, Color.white, Rgb(0.12f, 0.04f, 0.03f), default(Color), 0);
            var tBotG = Pattern(44, Rgb(0.14f, 0.32f, 0.20f), ink, gold, 1);
            var tBotB = Pattern(44, Rgb(0.42f, 0.22f, 0.10f), red, white, 2);
            var tBotI = Pattern(44, Rgb(0.12f, 0.18f, 0.40f), ink, red, 4);
            var tBotW = Pattern(44, Rgb(0.90f, 0.92f, 0.90f), indigo, indigo, 8);
            Texture2D[] tCrest =
            {
                Pattern(24, indigo, white, default(Color), 9), Pattern(24, red, Rgb(0.96f, 0.90f, 0.76f), default(Color), 0), Pattern(24, white, indigo, default(Color), 2),
                Pattern(24, moss, Rgb(0.94f, 0.90f, 0.70f), default(Color), 1), Pattern(24, Rgb(0.12f, 0.10f, 0.14f), gold, default(Color), 4), Pattern(24, Rgb(0.90f, 0.62f, 0.16f), ink, default(Color), 6)
            };

            // ---------- 常用材質 ----------
            var darkWood = Mt(tGrainD, 2f, 1f, 0.35f); var darkPost = Mt(tGrainDV, 1f, 3f, 0.3f);
            var lightWood = Mt(tGrainL, 2f, 1f, 0.35f); var midWood = Mt(tGrainM, 2f, 1f, 0.55f);
            var steel = Mt(tSteel, 2f, 1f, 0.75f);
            var plaster = Mt(tPlaster, 6f, 1f, 0.05f);
            var blackM = Mats.Lit(Rgb(0.08f, 0.08f, 0.09f), 0.6f); var whiteM = Mats.Lit(white, 0.6f); var redM = Mats.Lit(red, 0.5f); var goldM = Mats.Lit(gold, 0.7f);
            var ceramic = Mt(tSeig, 3f, 1f, 0.8f);
            var potM = Mats.Lit(Rgb(0.50f, 0.28f, 0.18f), 0.3f);
            var leafM = Mt(Pattern(0, Rgb(0.08f, 0.24f, 0.10f), Rgb(0.34f, 0.56f, 0.22f)), 3f, 3f, 0.2f);
            var bulbM = Mats.Unlit(new Color(2.6f, 1.9f, 1.0f));
            var lanternRed = Glow(new Color(2.0f, 0.42f, 0.20f), tLantern, 1f, 1f);
            var lanternWhite = Glow(new Color(1.7f, 1.38f, 0.92f), tLanternB, 1f, 1f);
            var shojiGlow = Glow(new Color(1.25f, 1.08f, 0.80f), tShoji, 1f, 1f);
            Material[] cloth = new Material[tCrest.Length];
            for (int i = 0; i < cloth.Length; i++) cloth[i] = Mt(tCrest[i], 1f, 1f, 0.05f);
            Material[] fabric =
            {
                Mt(tDotsR, 2f, 2f, 0.05f), Mt(tAsaI, 2f, 2f, 0.05f), Mt(tKikG, 2f, 2f, 0.05f), Mt(tYaga, 2f, 2f, 0.05f), Mt(tPlaidR, 2f, 2f, 0.05f), Mt(tSeigR, 3f, 3f, 0.05f),
                Mt(tSakuraN, 2f, 2f, 0.05f), Mt(tUroko, 2f, 2f, 0.05f), Mt(tPlaidB, 2f, 2f, 0.05f), Mt(tShippo, 2f, 2f, 0.05f), Mt(tStripeI, 2f, 1f, 0.05f), Mt(tAsaP, 2f, 2f, 0.05f)
            };
            Material[] bottles = { Mt(tBotG, 1f, 1f, 0.85f), Mt(tBotB, 1f, 1f, 0.85f), Mt(tBotI, 1f, 1f, 0.85f), Mt(tBotW, 1f, 1f, 0.85f) };
            Material[] crate = { Mt(tCrateA, 1f, 1f, 0.15f), Mt(tCrateB, 1f, 1f, 0.15f), Mt(tCarton, 1f, 1f, 0.1f) };
            Material[] bowl = { Mt(tSeig, 4f, 1f, 0.8f), Mats.Lit(Rgb(0.60f, 0.12f, 0.10f), 0.85f), Mats.Lit(Rgb(0.10f, 0.09f, 0.09f), 0.85f), Mt(tTileG, 4f, 1f, 0.8f) };

            // ---------- 地板 ----------
            W(new Vector3(0f, -0.1f, 0f), new Vector3(26f, 0.2f, 18f), Mt(tFloor, 32.5f, 6f, 0.45f));
            Bx(0f, 0f, 7f, 14f, 0.012f, 4f, Mt(tChecker, 7f, 2f, 0.6f));                                   // 廚房市松地磚
            Bx(-10.1f, 0f, 7.05f, 5.7f, 0.012f, 3.9f, Mt(tConcrete, 3f, 2f, 0.1f));                        // 倉庫水泥地
            Bx(0f, 0f, -7.9f, 5f, 0.012f, 2.2f, Mt(tStone, 2.5f, 1.1f, 0.3f));                             // 玄關石板
            Bx(0f, 0.012f, -7.6f, 1.8f, 0.02f, 0.9f, Mt(tUrokoR, 2f, 1f, 0.05f));                          // 踏墊

            // ---------- 外牆和內裝 ----------
            var shell = Mt(tPlanksD, 30f, 1f, 0.2f); var shellZ = Mt(tPlanksD, 20f, 1f, 0.2f);
            W(new Vector3(0f, 2f, 9.1f), new Vector3(26.4f, 4f, 0.2f), shell); W(new Vector3(0f, 2f, -9.1f), new Vector3(26.4f, 4f, 0.2f), shell);
            W(new Vector3(-13.1f, 2f, 0f), new Vector3(0.2f, 4f, 18f), shellZ); W(new Vector3(13.1f, 2f, 0f), new Vector3(0.2f, 4f, 18f), shellZ);
            var wainsX = Mt(tPlanksD, 32.5f, 1f, 0.3f); var wainsZ = Mt(tPlanksD, 22.5f, 1f, 0.3f);
            var friezeX = Mt(tPlaster, 12f, 0.4f, 0.05f); var friezeZ = Mt(tPlaster, 8f, 0.4f, 0.05f);
            float[] cutN = { -13f, -10.4f, -7.8f, -5.2f, -2.6f, 0f, 2.6f, 5.2f, 7.8f, 10.4f, 13f };
            var brickP = Wp(tBrick, 2.6f, 1.1f, 0.1f); var tileP = Wp(tTileW, 2.6f, 0.6f, 0.4f);
            WallRun(true, 9f, -1f, cutN, new[] { brickP, brickP, tileP, tileP, tileP, tileP, tileP, tileP, Wp(tSeig, 2.6f, 0.9f), Wp(tSeig, 2.6f, 0.9f) }, wainsX, friezeX, darkWood, darkPost);
            Bx(-10.4f, 0f, 8.95f, 5.2f, 1f, 0.1f, Mt(tBrick, 5.2f / 1.1f, 1f / 1.1f, 0.1f));
            Bx(0f, 0f, 8.95f, 15.4f, 1f, 0.1f, Mt(tTileG, 15.4f / 0.6f, 1f / 0.6f, 0.45f));
            float[] cutS = { -13f, -10.4f, -7.8f, -5.2f, -2.6f, 0f, 2.6f, 6f, 8.33f, 10.67f, 13f };
            WallRun(true, -9f, 1f, cutS, new[] { Wp(tAsaG, 2.6f, 1.0f), Wp(tAsaG, 2.6f, 1.0f), Wp(tYaga, 2.6f, 0.8f), Wp(tYaga, 2.6f, 0.8f), Wp(tPlaster, 2.6f, 2.2f), Wp(tPlaster, 2.6f, 2.2f),
                Wp(tKikO, 3.4f, 0.9f), Wp(tKumo, 2.33f, 2.2f), Wp(tSakura, 2.33f, 1.1f), Wp(tKumo, 2.33f, 2.2f) }, wainsX, friezeX, darkWood, darkPost);
            float[] cutE = { -9f, -5.4f, -3.6f, 0f, 3f, 5f, 7f, 9f };
            WallRun(false, 13f, -1f, cutE, new[] { Glow(new Color(1.08f, 0.98f, 0.80f), tShoji, 4f, 2f), Wp(tPlasterO, 1.8f, 2.2f), Glow(new Color(1.08f, 0.98f, 0.80f), tShoji, 4f, 2f),
                Wp(tNami, 3f, 1.0f), Wp(tShippo, 2f, 0.9f), Wp(tUroko, 2f, 0.8f), Wp(tPlaid, 2f, 1.0f) }, wainsZ, friezeZ, darkWood, darkPost);
            float[] cutW = { -9f, -6.4f, -3.8f, -1.2f, 1.4f, 4f, 5f, 9f };
            WallRun(false, -13f, 1f, cutW, new[] { Wp(tSakura, 2.6f, 1.1f), Wp(tDotsI, 2.6f, 1.0f), Wp(tStripe, 2.6f, 0.9f), Wp(tAsaI, 2.6f, 1.0f), Wp(tKikG, 2.6f, 0.9f), Wp(tPlaster, 1f, 2.2f),
                Wp(tBrick, 4f, 1.1f, 0.1f) }, wainsZ, friezeZ, darkWood, darkPost);
            Bx(-12.95f, 0f, 7f, 0.1f, 1f, 4f, Mt(tBrick, 4f / 1.1f, 1f / 1.1f, 0.1f));

            // ---------- 樑、椽、獨立柱（沒有天花板，樑不投影，免得地上一條條） ----------
            for (int i = -2; i <= 2; i++) Soft(W(new Vector3(i * 5.2f, 4.15f, 0f), new Vector3(0.3f, 0.3f, 18f), darkWood, false));
            foreach (float bz in new[] { -4.5f, 0f, 5f }) Soft(W(new Vector3(0f, 3.85f, bz), new Vector3(26f, 0.26f, 0.26f), darkWood, false));
            for (int i = 0; i < 8; i++) Soft(W(new Vector3(0f, 4.36f, -7.9f + i * 2.25f), new Vector3(26f, 0.12f, 0.1f), darkWood, false));
            foreach (var cp in new[] { new Vector2(-7f, 5f), new Vector2(7f, 5f), new Vector2(6f, 0f), new Vector2(1.3f, 0f), new Vector2(-7.15f, -4.35f) }) Bx(cp.x, 0f, cp.y, 0.3f, 4f, 0.3f, darkPost);
            // 兩串祭典小燈籠
            for (int i = 0; i < 9; i++) Soft(Sp(-10.4f + i * 2.6f, 3.46f, -4.5f, 0.32f, 0.42f, 0.32f, i % 2 == 0 ? lanternRed : lanternWhite, false));

            // ---------- 壽司吧台 ----------
            W(new Vector3(-3f, 0.55f, 0f), new Vector3(8f, 1.1f, 1.2f), Mt(tPlanksL, 10f, 1f, 0.3f));
            W(new Vector3(-6.4f, 0.55f, -2.3f), new Vector3(1.2f, 1.1f, 3.4f), Mt(tPlanksL, 4.25f, 1f, 0.3f));
            var counterTop = Mt(tGrainM, 4f, 1f, 0.65f);
            W(new Vector3(-3f, 1.13f, 0f), new Vector3(8.2f, 0.06f, 1.4f), counterTop);
            W(new Vector3(-6.4f, 1.13f, -2.4f), new Vector3(1.4f, 0.06f, 3.4f), counterTop);
            for (int i = 0; i < 6; i++)
            {
                float sx = -5f + i * 1.1f;
                Cy(sx, 0f, -1.3f, 0.1f, 0.68f, steel);
                Cy(sx, 0.68f, -1.3f, 0.42f, 0.08f, fabric[i % 3]);
            }
            SushiKind[] kinds = { SushiKind.Salmon, SushiKind.Tuna, SushiKind.Tamago, SushiKind.Shrimp, SushiKind.CucumberRoll };
            for (int i = 0; i < 5; i++)
            {
                Vector3 pp = new Vector3(-5.2f + i * 1.3f, 1.168f, -0.2f);
                Obj(PrimitiveType.Cylinder, pp, new Vector3(0.44f, 0.012f, 0.44f), Mats.Lit(Color.Lerp(white, i % 2 == 0 ? Rgb(0.8f, 0.3f, 0.25f) : indigo, 0.25f), 0.7f), false);
                for (int k = -1; k <= 1; k += 2)
                {
                    var su = new GameObject("Sushi"); su.transform.SetParent(root, false);
                    su.transform.position = pp + new Vector3(k * 0.1f, 0.014f, 0f); su.transform.localScale = Vector3.one * 0.2f; su.transform.rotation = Quaternion.Euler(0f, 90f, 0f);
                    su.AddComponent<Paintable>().Init(SushiShapes.Get(SushiShapes.ShapeOf(kinds[i])), kinds[i], false);
                }
            }
            Bx(-2.6f, 1.16f, 0.4f, 4.6f, 0.26f, 0.36f, Mt(tFish, 7f, 1f, 0.92f));                           // 玻璃魚料櫃
            for (int i = 0; i < 3; i++) Cy(-5.75f + i * 2.6f, 1.16f, -0.5f, 0.07f, 0.15f, blackM, false);
            var shadeM = Mt(tSudare, 3f, 1f, 0.1f);
            for (int i = 0; i < 4; i++) Pendant(-5.4f + i * 1.6f, 2.15f, -0.25f, shadeM, bulbM, blackM);
            Noren(true, -7f, 1f, 2.62f, 0.56f, 0.15f, cloth, 0, darkWood, true, 1f);
            Bx(-2.75f, 0f, 2.4f, 6.5f, 0.03f, 2.6f, Mt(tSunoko, 8f, 1f, 0.2f));                             // 師傅腳下的木踏板
            // 吧台內側的備料櫃和酒架
            Bx(-2.75f, 0f, 4.55f, 6.5f, 0.95f, 0.6f, Mt(tDrawer, 5f, 1f, 0.35f));
            Bx(-2.75f, 0.95f, 4.55f, 6.6f, 0.05f, 0.66f, midWood);
            for (int i = 0; i < 4; i++) Bx(-6f + i * 2.167f, 1f, 4.78f, 0.08f, 1.55f, 0.22f, darkWood);
            Bx(-2.75f, 1.55f, 4.72f, 6.58f, 0.05f, 0.34f, darkWood); Bx(-2.75f, 2.05f, 4.72f, 6.58f, 0.05f, 0.34f, darkWood); Bx(-2.75f, 2.55f, 4.72f, 6.7f, 0.06f, 0.4f, darkWood);
            Cy(-5.2f, 1f, 4.5f, 0.6f, 0.2f, lightWood); Cy(-5.2f, 1.19f, 4.5f, 0.52f, 0.025f, whiteM, false);
            Bx(-4.1f, 1f, 4.45f, 0.6f, 0.04f, 0.35f, lightWood, false); Bx(-4.05f, 1.04f, 4.45f, 0.3f, 0.05f, 0.1f, Mats.Lit(Rgb(0.92f, 0.45f, 0.30f), 0.6f), false);
            Cy(-3.1f, 1f, 4.5f, 0.3f, 0.2f, bowl[0], false); Cy(-2.6f, 1f, 4.5f, 0.26f, 0.14f, bowl[1], false);
            Cy(-1.6f, 1f, 4.5f, 0.3f, 0.42f, steel); Sp(-1.6f, 1.44f, 4.5f, 0.2f, 0.12f, 0.2f, blackM, false);
            for (int i = 0; i < 3; i++) Bottle(-0.7f + i * 0.32f, 1f, 4.5f, 0.42f, bottles[i], bottles[i]);
            for (int i = 0; i < 9; i++)
            {
                float bx = -5.6f + i * 0.7f;
                if (i % 3 == 2) Bottle(bx, 1.6f, 4.72f, 0.36f, bottles[(i + 1) % 4], bottles[(i + 1) % 4]);
                else Cy(bx, 1.6f, 4.72f, 0.26f, 0.1f + (i % 2) * 0.08f, bowl[i % 4], false);
            }
            for (int i = 0; i < 7; i++) Bottle(-5.6f + i * 0.92f, 2.1f, 4.72f, 0.4f, bottles[i % 4], bottles[(i + 2) % 4]);
            Sp(-4.6f, 2.76f, 4.72f, 0.3f, 0.3f, 0.3f, redM, false); Bx(-2.6f, 2.61f, 4.72f, 0.5f, 0.3f, 0.3f, crate[2], false);
            // 短吧台上：收銀機、招財貓、菜單立牌
            Bx(-6.4f, 1.16f, -3.4f, 0.5f, 0.28f, 0.45f, Mats.Lit(Rgb(0.20f, 0.20f, 0.22f), 0.6f)); Tilt(Bx(-6.4f, 1.44f, -3.5f, 0.4f, 0.26f, 0.03f, Mats.Unlit(new Color(0.5f, 0.9f, 1.1f)), false), -20f, 0f, 0f);
            Sp(-6.4f, 1.34f, -1.5f, 0.32f, 0.36f, 0.3f, whiteM); Sp(-6.4f, 1.6f, -1.5f, 0.27f, 0.25f, 0.25f, whiteM, false);
            Sp(-6.5f, 1.72f, -1.5f, 0.09f, 0.11f, 0.06f, whiteM, false); Sp(-6.3f, 1.72f, -1.5f, 0.09f, 0.11f, 0.06f, whiteM, false);
            Sp(-6.22f, 1.62f, -1.56f, 0.09f, 0.24f, 0.09f, whiteM, false); Cy(-6.4f, 1.47f, -1.5f, 0.22f, 0.03f, redM, false); Sp(-6.4f, 1.36f, -1.66f, 0.1f, 0.12f, 0.03f, goldM, false);
            Tilt(Bx(-6.4f, 1.16f, -2.4f, 0.04f, 0.4f, 0.32f, Mt(tMenuP, 1f, 1f, 0.2f), false), 0f, 0f, 12f);

            // ---------- 廚房 ----------
            W(new Vector3(0f, 0.6f, 5f), new Vector3(14f, 1.2f, 0.2f), Mt(tPlanksD, 17.5f, 1f, 0.3f));
            Bx(0f, 1.2f, 5f, 14.1f, 0.05f, 0.36f, midWood);
            W(new Vector3(0f, 2.72f, 5f), new Vector3(14f, 0.16f, 0.18f), darkWood);
            Material[] passCloth = { Mt(tYagaI, 3f, 1f, 0.05f), cloth[1], Mt(tSeig, 3f, 1f, 0.05f), cloth[5], Mt(tStripe, 2f, 1f, 0.05f), cloth[3], Mt(tDotsI, 4f, 1.2f, 0.05f) };
            for (int i = 0; i < 7; i++) Tilt(Bx(-6f + i * 2f, 2.06f, 5f, 1.9f, 0.58f, 0.025f, passCloth[i]), 0f, 0f, 180f);
            for (int i = 0; i < 3; i++)
            {
                float gx = -4.5f + i * 3.6f;
                Bx(gx, 1.25f, 5f, 0.42f, 0.05f, 0.22f, lightWood, false);
                Bx(gx, 1.3f, 5f, 0.24f, 0.06f, 0.07f, Mats.Lit(i == 1 ? Rgb(0.95f, 0.82f, 0.30f) : i == 2 ? Rgb(0.70f, 0.12f, 0.14f) : Rgb(0.93f, 0.42f, 0.28f), 0.6f), false);
            }
            W(new Vector3(-1f, 0.5f, 8.3f), new Vector3(9f, 1f, 1f), Mt(tSteel, 4f, 1f, 0.75f));
            Bx(-1.6f, 1f, 8.3f, 2.6f, 0.05f, 0.8f, blackM);
            for (int i = 0; i < 3; i++)
            {
                float px0 = -2.5f + i * 0.9f;
                Cy(px0, 1.05f, 8.3f, 0.5f, 0.24f + i * 0.06f, i == 1 ? Mt(tSteel, 2f, 1f, 0.8f) : Mats.Lit(Rgb(0.2f, 0.2f, 0.22f), 0.7f));
                Cy(px0, 1.29f + i * 0.06f, 8.3f, 0.52f, 0.025f, steel, false);
            }
            Cy(-4.7f, 1f, 8.3f, 0.5f, 0.36f, whiteM); Cy(-4.7f, 1.36f, 8.3f, 0.46f, 0.05f, Mats.Lit(Rgb(0.75f, 0.2f, 0.18f), 0.6f), false);
            Cy(-3.75f, 1f, 8.3f, 0.3f, 0.24f, bowl[0], false);
            Bx(0.6f, 1f, 8.25f, 0.7f, 0.04f, 0.42f, lightWood, false); Bx(0.6f, 1.04f, 8.25f, 0.4f, 0.07f, 0.14f, Mats.Lit(Rgb(0.90f, 0.36f, 0.26f), 0.6f), false);
            Bx(2.4f, 1f, 8.3f, 1.3f, 0.015f, 0.7f, Mats.Lit(Rgb(0.30f, 0.32f, 0.35f), 0.8f), false); Cy(2.4f, 1f, 8.68f, 0.05f, 0.36f, steel, false);
            Bx(-1.6f, 2.3f, 8.45f, 3f, 0.45f, 0.9f, steel); Bx(-1.6f, 2.75f, 8.6f, 0.6f, 1.25f, 0.5f, steel, false);
            Bx(-5.2f, 1.9f, 8.72f, 3.2f, 0.05f, 0.36f, darkWood); Bx(-5.2f, 2.45f, 8.72f, 3.2f, 0.05f, 0.36f, darkWood); Bx(2.4f, 1.95f, 8.72f, 4.2f, 0.05f, 0.36f, darkWood);
            for (int i = 0; i < 3; i++)
            {
                Cy(-6.3f + i * 1.05f, 1.95f, 8.72f, 0.28f, 0.1f + (i % 3) * 0.06f, bowl[(i + 1) % 4], false);
                Cy(-6.2f + i * 1.05f, 2.5f, 8.72f, 0.22f, 0.3f, i % 2 == 0 ? potM : ceramic, false);
            }
            for (int i = 0; i < 5; i++) Cy(0.7f + i * 0.85f, 2f, 8.72f, 0.12f, 0.34f + (i % 2) * 0.06f, bottles[(i + 1) % 4], false);
            Bx(2.4f, 1.6f, 8.86f, 3.6f, 0.03f, 0.03f, steel, false);
            for (int i = 0; i < 3; i++) { Bx(1.2f + i * 1.2f, 1.3f, 8.86f, 0.03f, 0.3f, 0.02f, steel, false); Cy(1.2f + i * 1.2f, 1.2f, 8.84f, 0.16f + (i % 2) * 0.1f, 0.03f, i % 2 == 0 ? steel : blackM, false); }
            W(new Vector3(5.6f, 1.1f, 8.3f), new Vector3(1.6f, 2.2f, 1.2f), Mt(tSteel, 1f, 2f, 0.7f));
            Bx(5.6f, 0.1f, 7.69f, 0.02f, 2f, 0.02f, blackM, false);
            Bx(5.5f, 2.2f, 8.3f, 0.7f, 0.4f, 0.5f, crate[2], false);
            Cy(4.2f, 0f, 5.5f, 0.46f, 0.62f, Mats.Lit(Rgb(0.16f, 0.36f, 0.62f), 0.5f));
            for (int i = 0; i < 2; i++)
            {
                float vx = -5.9f + i * 0.8f;
                Bx(vx, 0f, 5.55f, 0.62f, 0.34f, 0.44f, crate[i]);
                Sp(vx - 0.14f, 0.44f, 5.55f, 0.26f, 0.24f, 0.26f, Mats.Lit(i == 0 ? Rgb(0.55f, 0.74f, 0.36f) : Rgb(0.92f, 0.90f, 0.84f), 0.3f), false);
                Sp(vx + 0.15f, 0.43f, 5.6f, 0.24f, 0.22f, 0.24f, Mats.Lit(i == 0 ? Rgb(0.48f, 0.70f, 0.32f) : Rgb(0.86f, 0.38f, 0.16f), 0.3f), false);
            }
            // 廚房和倉庫之間的鐵架
            foreach (float rz in new[] { 6.15f, 8.85f }) { Bx(-7.42f, 0f, rz, 0.05f, 2.1f, 0.05f, steel); Bx(-6.98f, 0f, rz, 0.05f, 2.1f, 0.05f, steel); }
            for (int i = 0; i < 4; i++) Bx(-7.2f, 0.15f + i * 0.63f, 7.5f, 0.5f, 0.04f, 2.76f, steel);
            for (int i = 0; i < 3; i++)
            {
                Bx(-7.2f, 0.19f, 6.5f + i * 0.95f, 0.46f, 0.4f, 0.5f, crate[i % 3]);
                if (i % 2 == 0) Cy(-7.2f, 0.82f, 6.45f + i * 0.95f, 0.36f, 0.42f, i == 0 ? potM : ceramic); else Bx(-7.2f, 0.82f, 6.45f + i * 0.95f, 0.44f, 0.3f, 0.5f, crate[2]);
                Bx(-7.2f, 1.45f, 6.5f + i * 0.95f, 0.44f, 0.26f + (i % 2) * 0.14f, 0.52f, crate[(i + 2) % 3]);
            }
            Sp(-7.2f, 2.26f, 6.8f, 0.46f, 0.3f, 0.7f, Mt(tSackB, 1f, 1f, 0.05f)); Bx(-7.2f, 2.08f, 8.2f, 0.46f, 0.3f, 0.6f, crate[0]);

            // ---------- 倉庫 ----------
            Bx(-11.3f, 0f, 5f, 3.4f, 1f, 0.2f, Mt(tPlanksD, 4.25f, 1f, 0.3f)); Bx(-11.3f, 1f, 5f, 3.4f, 2.3f, 0.14f, Mt(tPlaster, 1.5f, 1f, 0.05f));
            Bx(-9.6f, 0f, 5f, 0.16f, 3.3f, 0.22f, darkPost);
            W(new Vector3(-8.35f, 2.42f, 5f), new Vector3(2.6f, 0.16f, 0.16f), darkWood); Bx(-8.35f, 2.5f, 5f, 2.4f, 0.8f, 0.05f, Mt(tAsaW, 3f, 1f, 0.1f));
            Noren(true, -9.5f, -7.2f, 2.34f, 0.56f, 5f, cloth, 2, darkWood, true);
            Poster(true, -11.3f, 2.1f, 4.93f, -1f, 1.2f, 0.9f, Mt(tMenuW, 1f, 1f, 0.2f), darkWood);
            foreach (float rx in new[] { -12.7f, -9.9f }) { Bx(rx, 0f, 8.3f, 0.06f, 2.2f, 0.06f, steel); Bx(rx, 0f, 8.8f, 0.06f, 2.2f, 0.06f, steel); }
            for (int i = 0; i < 3; i++) Bx(-11.3f, 0.2f + i * 0.75f, 8.55f, 2.9f, 0.04f, 0.56f, lightWood);
            for (int i = 0; i < 3; i++)
            {
                float rx = -12.3f + i * 0.95f;
                Bx(rx, 0.24f, 8.55f, 0.56f, 0.5f, 0.5f, crate[i % 2]);
                if (i % 2 == 0) Cy(rx, 0.99f, 8.55f, 0.34f, 0.44f, i == 0 ? ceramic : potM); else Bx(rx, 0.99f, 8.55f, 0.5f, 0.34f, 0.44f, crate[2]);
                Bx(rx, 1.74f, 8.55f, 0.52f, 0.3f + (i % 2) * 0.12f, 0.46f, crate[(i + 1) % 3]);
            }
            var sack = Mt(tSack, 1f, 1f, 0.05f); var sackB = Mt(tSackB, 1f, 1f, 0.05f);
            Vector3[] sacks = { new Vector3(-12.4f, 0.21f, 5.6f), new Vector3(-12.4f, 0.21f, 6.3f), new Vector3(-12.4f, 0.21f, 7f), new Vector3(-11.55f, 0.21f, 5.75f), new Vector3(-11.55f, 0.21f, 6.5f),
                new Vector3(-12.35f, 0.58f, 5.95f), new Vector3(-12.35f, 0.58f, 6.65f) };
            for (int i = 0; i < sacks.Length; i++) Sp(sacks[i].x, sacks[i].y, sacks[i].z, 0.95f, 0.44f, 0.64f, i % 3 == 1 ? sackB : sack);
            var komo = new[] { Mt(tKomoR, 1f, 1f, 0.1f), Mt(tKomoK, 1f, 1f, 0.1f), Mt(tKomoB, 1f, 1f, 0.1f) };
            var lidM = Mt(tGrainL, 1f, 1f, 0.3f);
            Barrel(-9.3f, 0f, 8.35f, komo[0], lidM); Barrel(-8.35f, 0f, 8.35f, komo[1], lidM); Barrel(-8.82f, 0.83f, 8.35f, komo[2], lidM);
            var crateY = Mt(tCrateY, 1f, 1f, 0.4f); var crateR = Mt(tCrateR, 1f, 1f, 0.4f);
            for (int i = 0; i < 5; i++) Bx(-10.35f + (i % 2) * 0.56f, (i / 2) * 0.33f, 5.4f, 0.52f, 0.32f, 0.38f, (i + i / 2) % 2 == 0 ? crateY : crateR);
            Tilt(Bx(-12.6f, 0f, 7.55f, 0.05f, 2.6f, 0.05f, lightWood, false), 0f, 0f, 12f); Tilt(Bx(-12.6f, 0f, 7.95f, 0.05f, 2.6f, 0.05f, lightWood, false), 0f, 0f, 12f);
            for (int i = 0; i < 4; i++) Bx(-12.33f - (0.4f + i * 0.55f) * 0.2126f - 0.02f, 0.4f + i * 0.55f, 7.75f, 0.04f, 0.04f, 0.4f, lightWood, false);
            Pendant(-10.2f, 2.5f, 6.9f, Mats.Lit(Rgb(0.16f, 0.30f, 0.26f), 0.6f), bulbM, blackM);

            // ---------- 西牆卡座、魚缸、冷藏櫃 ----------
            for (int bi = 0; bi < 2; bi++)
            {
                float z0 = -2.5f + bi * 2.6f;
                Bx(-11.95f, 0.7f, z0, 1.7f, 0.05f, 0.8f, midWood); Bx(-11.95f, 0f, z0, 0.5f, 0.7f, 0.3f, darkWood);
                for (int s = -1; s <= 1; s += 2)
                {
                    Bx(-11.95f, 0f, z0 + s * 0.78f, 1.7f, 0.42f, 0.5f, Mt(tPlanksD, 2f, 1f, 0.3f));
                    Bx(-11.95f, 0.42f, z0 + s * 0.78f, 1.6f, 0.07f, 0.44f, fabric[3 + bi * 2 + (s + 1) / 2]);
                    Bx(-11.95f, 0f, z0 + s * 1.08f, 1.7f, 1.25f, 0.1f, Mt(tKoshi, 2f, 1f, 0.3f));
                }
                Cy(-12.55f, 0.75f, z0, 0.07f, 0.14f, blackM, false); Tilt(Bx(-12.3f, 0.75f, z0, 0.04f, 0.3f, 0.24f, Mt(bi == 0 ? tMenuY : tMenuP, 1f, 1f, 0.2f), false), 0f, 0f, 12f);
                Chochin(-11.95f, 2.25f, z0, 0.5f, 0.5f, lanternWhite, blackM);
            }
            Bx(-12f, 0f, -3.84f, 2f, 1.9f, 0.08f, Mt(tKoshi, 2.5f, 1f, 0.3f)); Bx(-12f, 0f, 1.5f, 2f, 1.9f, 0.08f, Mt(tKoshi, 2.5f, 1f, 0.3f));
            Bx(-12.4f, 0f, -5.2f, 0.9f, 0.8f, 2.4f, Mt(tDrawer, 3f, 0.5f, 0.35f));
            Soft(Bx(-12.4f, 0.8f, -5.2f, 0.8f, 0.9f, 2.3f, Glow(new Color(0.66f, 0.92f, 1.02f), tFish, 3f, 1f)));
            Bx(-12.4f, 1.7f, -5.2f, 0.9f, 0.08f, 2.4f, darkWood);
            Bx(-12.55f, 0f, 4.5f, 0.8f, 1.95f, 0.86f, Mats.Lit(Rgb(0.18f, 0.20f, 0.24f), 0.6f));
            Soft(Bx(-12.13f, 0.3f, 4.5f, 0.04f, 1.5f, 0.7f, Glow(new Color(1.05f, 1.12f, 1.15f), Pattern(13, Rgb(0.92f, 0.96f, 1f), Rgb(0.22f, 0.52f, 0.34f)), 1.5f, 3f)));
            Poster(false, -5.1f, 2.2f, -12.92f, 1f, 0.8f, 1.1f, Mt(tFishP, 1f, 1f, 0.1f), darkWood);
            Poster(false, -2.5f, 2.3f, -12.92f, 1f, 0.9f, 0.7f, Mt(tMenuY, 1f, 1f, 0.1f), blackM);
            Poster(false, 0.1f, 2.3f, -12.92f, 1f, 0.55f, 1.3f, Mt(tScrollB, 1f, 1f, 0.1f), darkWood);
            Poster(false, 2.7f, 2.2f, -12.92f, 1f, 1.5f, 1.0f, Mt(tFuji, 1f, 1f, 0.2f), goldM);
            Plant(-12.3f, 0f, -8.3f, potM, leafM); Plant(-10.05f, 0f, 4.45f, ceramic, leafM);

            // ---------- 門口 ----------
            Bx(-1.34f, 0f, -8.9f, 0.14f, 2.25f, 0.16f, darkPost); Bx(1.34f, 0f, -8.9f, 0.14f, 2.25f, 0.16f, darkPost); Bx(0f, 2.2f, -8.9f, 2.9f, 0.14f, 0.18f, darkWood);
            var doorGlow = Glow(new Color(1.12f, 1.0f, 0.80f), tShojiDoor, 1f, 1f);
            Soft(Bx(-0.63f, 0.02f, -8.93f, 1.24f, 2.16f, 0.05f, doorGlow)); Soft(Bx(0.63f, 0.02f, -8.9f, 1.24f, 2.16f, 0.05f, doorGlow));
            Noren(true, -1.45f, 1.45f, 2.62f, 0.76f, -8.55f, new[] { cloth[0], cloth[1] }, 0, darkWood);
            Chochin(-1.95f, 2.3f, -8.5f, 0.6f, 0.8f, lanternRed, blackM); Chochin(1.95f, 2.3f, -8.5f, 0.6f, 0.8f, lanternRed, blackM);
            Bx(4f, 0f, -8.66f, 2.2f, 1f, 0.5f, Mt(tDrawerL, 3f, 1f, 0.3f)); Bx(4f, 1f, -8.66f, 2.3f, 0.04f, 0.56f, darkWood, false);
            Sp(3.3f, 1.2f, -8.66f, 0.34f, 0.36f, 0.32f, redM);
            Cy(4.05f, 1.04f, -8.66f, 0.26f, 0.12f, ceramic, false); Sp(4.05f, 1.38f, -8.66f, 0.42f, 0.34f, 0.36f, leafM, false);
            Andon(4.75f, 1.04f, -8.66f, shojiGlow, darkWood);
            Cy(2.3f, 0f, -8.6f, 0.36f, 0.5f, ceramic);
            Tilt(Cy(2.26f, 0.1f, -8.6f, 0.05f, 0.95f, redM, false), 6f, 0f, 8f); Tilt(Cy(2.36f, 0.1f, -8.56f, 0.05f, 0.9f, Mats.Lit(indigo, 0.4f), false), -7f, 0f, -6f);
            Bx(-4f, 0.38f, -8.6f, 1.8f, 0.07f, 0.45f, midWood); Bx(-4.7f, 0f, -8.6f, 0.1f, 0.38f, 0.4f, darkWood); Bx(-3.3f, 0f, -8.6f, 0.1f, 0.38f, 0.4f, darkWood);
            Bx(-4.42f, 0.45f, -8.6f, 0.6f, 0.07f, 0.42f, fabric[8]); Bx(-3.58f, 0.45f, -8.6f, 0.6f, 0.07f, 0.42f, fabric[9]);
            Tilt(Bx(-2.75f, 0f, -7.55f, 0.7f, 1.15f, 0.04f, Mt(tMenuW, 1f, 1f, 0.2f)), 14f, 0f, 180f); Tilt(Bx(-2.75f, 0f, -7.25f, 0.7f, 1.15f, 0.04f, Mt(tMenuP, 1f, 1f, 0.2f)), -14f, 0f, 0f);
            // 掛在牆上的法被（短外套）
            Bx(-6.4f, 1.86f, -8.8f, 2.4f, 0.04f, 0.04f, darkWood, false);
            for (int i = 0; i < 3; i++)
            {
                float hx = -7.2f + i * 0.8f; var hm = i == 0 ? Mt(tCrest[0], 1f, 1f, 0.05f) : i == 1 ? Mt(tYagaI, 2f, 2f, 0.05f) : Mt(tCrest[1], 1f, 1f, 0.05f);
                Bx(hx, 1.0f, -8.8f, 0.5f, 0.84f, 0.1f, hm); Bx(hx, 1.56f, -8.8f + (i % 2) * 0.03f, 0.78f, 0.28f, 0.08f, hm, false);
            }
            Poster(true, 3.3f, 2.2f, -8.92f, 1f, 0.8f, 1.1f, Mt(tFuji, 1f, 1f, 0.2f), darkWood);
            Poster(true, 4.4f, 2.1f, -8.92f, 1f, 0.7f, 0.7f, Mt(tFishP, 1f, 1f, 0.1f), blackM);
            Poster(true, 5.3f, 2.2f, -8.92f, 1f, 0.5f, 1.2f, Mt(tScrollA, 1f, 1f, 0.1f), darkWood);
            Poster(true, -3.9f, 2.2f, -8.92f, 1f, 0.55f, 1.3f, Mt(tScrollC, 1f, 1f, 0.1f), darkWood);
            Poster(true, -9.1f, 2.2f, -8.92f, 1f, 1.2f, 0.9f, Mt(tMenuP, 1f, 1f, 0.1f), darkWood);
            Poster(true, -11.6f, 2.2f, -8.92f, 1f, 0.55f, 1.3f, Mt(tScrollA, 1f, 1f, 0.1f), goldM);
            Plant(5.5f, 0f, -8.45f, ceramic, leafM);
            // 門口西側：堆著的酒樽和木箱
            Cy(-9.9f, 0f, -6.6f, 0.84f, 0.8f, komo[0]); Cy(-9.02f, 0f, -6.6f, 0.84f, 0.8f, komo[2]); Barrel(-9.46f, 0.8f, -6.6f, komo[1], lidM);
            Bx(-9.4f, 0f, -5.72f, 0.62f, 0.56f, 0.6f, crate[0]); Sp(-9.4f, 0.74f, -5.72f, 0.8f, 0.4f, 0.56f, sack);
            // 立旗
            Cy(-9.6f, 0f, -8.5f, 0.05f, 2.9f, darkWood, false); Bx(-9.6f, 0.7f, -8.3f, 0.03f, 2.1f, 0.5f, Mt(tBanner, 1f, 1f, 0.05f));

            // ---------- 中央散座 ----------
            for (int ti = 0; ti < 2; ti++)
            {
                float tz = ti == 0 ? -2.6f : 2.4f;
                Bx(3.8f, 0f, tz, 2.9f, 0.015f, 2.5f, ti == 0 ? Mt(tShippoG, 4f, 3.5f, 0.05f) : Mt(tKikO, 3f, 3f, 0.05f));
                Bx(3.8f, 0.7f, tz, 0.95f, 0.05f, 0.95f, lightWood); Bx(3.8f, 0f, tz, 0.4f, 0.7f, 0.4f, darkWood);
                Bx(3.8f, 0.75f, tz, 0.97f, 0.012f, 0.34f, fabric[ti == 0 ? 10 : 5], false);
                Chair(2.98f, tz, -1f, 0f, fabric[ti * 4], darkWood); Chair(4.62f, tz, 1f, 0f, fabric[ti * 4 + 1], darkWood);
                Chair(3.8f, tz - 0.82f, 0f, -1f, fabric[ti * 4 + 2], darkWood); Chair(3.8f, tz + 0.82f, 0f, 1f, fabric[ti * 4 + 3], darkWood);
                Cy(3.8f, 0.762f, tz, 0.07f, 0.14f, blackM, false);
                Pendant(3.8f, 2.2f, tz, shadeM, bulbM, blackM);
            }
            Bx(3.6f, 0.12f, -5.4f, 2.2f, 1.55f, 0.07f, Mt(tFuji, 1f, 1f, 0.25f)); Bx(3.6f, 1.67f, -5.4f, 2.3f, 0.07f, 0.1f, darkWood);
            Bx(2.65f, 0f, -5.4f, 0.1f, 0.12f, 0.5f, darkWood); Bx(4.55f, 0f, -5.4f, 0.1f, 0.12f, 0.5f, darkWood);

            // 大廳中央：石燈籠小景和紅地毯
            Bx(0f, 0.012f, -5.9f, 1.3f, 0.012f, 2.2f, Mt(tShippo, 2f, 3.4f, 0.05f));
            var stoneM = Mt(tConcrete, 1f, 1f, 0.15f);
            Cy(0.6f, 0f, -3.6f, 1.7f, 0.22f, Mt(tStone, 2f, 2f, 0.3f));
            Cy(0.6f, 0.22f, -3.6f, 0.2f, 0.7f, stoneM); Bx(0.6f, 0.92f, -3.6f, 0.46f, 0.07f, 0.46f, stoneM);
            Soft(Bx(0.6f, 0.99f, -3.6f, 0.32f, 0.3f, 0.32f, shojiGlow)); Bx(0.6f, 1.29f, -3.6f, 0.62f, 0.1f, 0.62f, stoneM);
            Sp(0.6f, 1.42f, -3.6f, 0.16f, 0.16f, 0.16f, stoneM, false);
            Sp(0.05f, 0.42f, -3.3f, 0.6f, 0.5f, 0.55f, leafM); Sp(1.1f, 0.4f, -3.95f, 0.5f, 0.44f, 0.5f, leafM);
            Sp(1.0f, 0.3f, -3.1f, 0.34f, 0.24f, 0.3f, stoneM, false);

            // ---------- 榻榻米包廂 ----------
            W(new Vector3(9.5f, 0.135f, -4.5f), new Vector3(7f, 0.27f, 9f), darkWood);
            Bx(9.52f, 0.27f, -4.52f, 6.92f, 0.03f, 8.92f, Mt(tTatami, 8f, 5f, 0.1f));
            Bx(5.6f, 0f, -3.2f, 0.7f, 0.15f, 1.4f, Mt(tStone, 0.5f, 1f, 0.3f));
            var shojiM = Glow(new Color(0.92f, 0.82f, 0.62f), tShojiDoor, 1f, 1f);   // 包廂裡亮著燈，紙門從外面看是透亮的
            foreach (float pz in new[] { -8.3f, -7.1f, -5.9f, -4.7f }) Bx(6f, 0.3f, pz, 0.06f, 2.06f, 1.2f, shojiM);
            foreach (float pz in new[] { -1.75f, -0.65f }) Bx(6f, 0.3f, pz, 0.06f, 2.06f, 1.1f, shojiM);
            W(new Vector3(6f, 2.43f, -4.5f), new Vector3(0.16f, 0.14f, 9f), darkWood); W(new Vector3(6f, 3.27f, -4.5f), new Vector3(0.16f, 0.14f, 9f), darkWood);
            W(new Vector3(6f, 2.85f, -4.5f), new Vector3(0.05f, 0.7f, 9f), Mt(tAsaW, 7.5f, 1f, 0.1f));
            foreach (float pz in new[] { -8.9f, -4.08f, -2.32f }) Bx(6f, 0f, pz, 0.16f, 3.3f, 0.16f, darkPost);
            W(new Vector3(9.6f, 2.95f, 0f), new Vector3(7f, 0.14f, 0.16f), darkWood);
            for (int i = 0; i < 3; i++) Bx(7.4f + i * 2.2f, 2.06f, 0f, 2f, 0.84f, 0.03f, Mt(tSudare, 3f, 2f, 0.1f));
            for (int i = 0; i < 4; i++) Tilt(Bx(8.3f + i * 0.78f, 0.3f, -0.55f, 0.86f, 1.6f, 0.04f, Mt(i % 2 == 0 ? tKumo : tSakuraN, 1f, 2f, 0.3f)), 0f, i % 2 == 0 ? 25f : -25f, 0f);
            var lacquer = Mt(tGrainD, 2f, 1f, 0.75f);
            for (int t = 0; t < 2; t++)
            {
                float z = t == 0 ? -2.4f : -6.5f;
                Bx(9.3f, 0.6f, z, 2.4f, 0.07f, 1.1f, lacquer); Bx(9.3f, 0.3f, z, 2f, 0.3f, 0.7f, darkWood);
                for (int i = 0; i < 4; i++) Bx(9.3f + (i % 2 == 0 ? -0.75f : 0.75f), 0.3f, z + (i / 2 == 0 ? -0.95f : 0.95f), 0.7f, 0.09f, 0.7f, fabric[(i + t * 6) % 12]);
                Sp(9.3f, 0.77f, z, 0.22f, 0.2f, 0.22f, t == 0 ? potM : blackM, false);
                Bx(8.6f, 0.67f, z - 0.2f, 0.4f, 0.05f, 0.22f, lightWood, false);
                Chochin(9.3f, 2.5f, z, 0.6f, 0.6f, lanternWhite, blackM);
            }
            // 床之間
            Bx(12.45f, 0.3f, -4.5f, 0.9f, 0.14f, 1.76f, lacquer);
            Cy(12.02f, 0.3f, -5.36f, 0.14f, 3f, Mt(tGrainL, 1f, 3f, 0.3f)); Cy(12.02f, 0.3f, -3.64f, 0.14f, 3f, Mt(tGrainL, 1f, 3f, 0.3f));
            Bx(12.88f, 1.2f, -4.5f, 0.03f, 1.8f, 0.64f, Mt(tScrollA, 1f, 1f, 0.05f));
            Cy(12.45f, 0.44f, -4f, 0.22f, 0.4f, ceramic); Tilt(Cy(12.45f, 0.8f, -4f, 0.03f, 0.8f, darkWood, false), 14f, 0f, 10f);
            Sp(12.35f, 1.45f, -3.85f, 0.2f, 0.18f, 0.2f, Mats.Lit(Rgb(0.95f, 0.62f, 0.70f), 0.2f), false);
            Sp(12.45f, 0.62f, -5f, 0.3f, 0.32f, 0.28f, redM);
            // 階梯櫃、被褥、坐墊堆、行燈、棋盤
            Bx(7f, 0.3f, -8.58f, 1f, 1.8f, 0.7f, Mt(tDrawer, 1f, 1.5f, 0.35f)); Bx(8f, 0.3f, -8.58f, 1f, 1.2f, 0.7f, Mt(tDrawer, 1f, 1f, 0.35f)); Bx(9f, 0.3f, -8.58f, 1f, 0.6f, 0.7f, Mt(tDrawer, 1f, 0.5f, 0.35f));
            Cy(9f, 0.9f, -8.58f, 0.24f, 0.34f, ceramic); Sp(8f, 1.66f, -8.58f, 0.3f, 0.32f, 0.28f, redM); Bx(7f, 2.1f, -8.58f, 0.5f, 0.24f, 0.36f, crate[0]);
            Material[] futon = { Mt(tWeaveB, 4f, 3f, 0.05f), Mt(tWeaveW, 4f, 3f, 0.05f), Mt(tAsaP, 3f, 2f, 0.05f), Mt(tPlaidB, 3f, 2f, 0.05f), Mt(tDotsY, 3f, 2f, 0.05f) };
            for (int i = 0; i < 5; i++) Bx(12.1f - (i % 2) * 0.05f, 0.3f + i * 0.17f, -8.2f + (i % 3) * 0.03f, 1.5f, 0.16f, 1.2f, futon[i]);
            Bx(12.1f, 1.15f, -8.2f, 0.6f, 0.12f, 0.34f, futon[1], false);
            for (int i = 0; i < 5; i++) Tilt(Bx(10.1f, 0.3f + i * 0.095f, -8.5f, 0.62f, 0.09f, 0.62f, fabric[(i * 5 + 1) % 12]), 0f, i * 7f - 14f, 0f);
            Andon(12.4f, 0.3f, -6.3f, shojiGlow, darkWood); Andon(6.6f, 0.3f, -0.7f, shojiGlow, darkWood); Andon(12.4f, 0.3f, -2.7f, shojiGlow, darkWood);
            Bx(11.6f, 0.3f, -1.7f, 0.5f, 0.26f, 0.5f, Mt(tGrid, 1f, 1f, 0.4f)); Cy(11.15f, 0.3f, -1.5f, 0.2f, 0.12f, blackM, false); Cy(12.05f, 0.3f, -1.9f, 0.2f, 0.12f, potM, false);

            // ---------- 東北：大桌和酒藏 ----------
            Bx(11.3f, 0f, 5f, 3.4f, 1f, 0.2f, Mt(tPlanksD, 4.25f, 1f, 0.3f)); Bx(11.3f, 1f, 5f, 3.4f, 2.3f, 0.14f, Mt(tPlaidR, 3f, 2f, 0.05f));
            Bx(9.6f, 0f, 5f, 0.16f, 3.3f, 0.22f, darkPost);
            W(new Vector3(8.35f, 2.42f, 5f), new Vector3(2.6f, 0.16f, 0.16f), darkWood); Bx(8.35f, 2.5f, 5f, 2.4f, 0.8f, 0.05f, Mt(tAsaW, 3f, 1f, 0.1f));
            Noren(true, 7.2f, 9.5f, 2.34f, 0.56f, 5f, cloth, 3, darkWood, true);
            Poster(true, 11.3f, 2.1f, 4.93f, -1f, 2.2f, 1.0f, Mt(tMenuW, 2f, 1f, 0.2f), darkWood);
            Bx(10.2f, 0.7f, 2.4f, 3f, 0.06f, 0.9f, lightWood); Bx(9.1f, 0f, 2.4f, 0.12f, 0.7f, 0.7f, darkWood); Bx(11.3f, 0f, 2.4f, 0.12f, 0.7f, 0.7f, darkWood);
            Bx(10.2f, 0.76f, 2.4f, 3f, 0.012f, 0.3f, fabric[11], false);
            for (int s = -1; s <= 1; s += 2)
            {
                float bz = 2.4f + s * 0.8f;
                Bx(10.2f, 0.38f, bz, 2.8f, 0.06f, 0.36f, midWood); Bx(9.1f, 0f, bz, 0.1f, 0.38f, 0.3f, darkWood); Bx(11.3f, 0f, bz, 0.1f, 0.38f, 0.3f, darkWood);
                for (int i = 0; i < 3; i++) Bx(9.3f + i * 0.9f, 0.44f, bz, 0.5f, 0.06f, 0.34f, fabric[(i * 3 + (s + 1) * 2 + 6) % 12]);
            }
            Bottle(9.6f, 0.77f, 2.4f, 0.3f, bottles[3], bottles[3]);
            Cy(10.25f, 0.77f, 2.4f, 0.4f, 0.14f, potM, false); Cy(10.25f, 0.91f, 2.4f, 0.42f, 0.04f, blackM, false);
            for (int i = 0; i < 2; i++) Cy(9.6f + i * 1.3f, 0.76f, 2.4f + (i % 2 == 0 ? -0.3f : 0.3f), 0.2f, 0.02f, bowl[i % 4], false);
            Pendant(9.5f, 2.2f, 2.4f, shadeM, bulbM, blackM); Pendant(10.9f, 2.2f, 2.4f, shadeM, bulbM, blackM);
            Bx(12.8f, 1.6f, 2.4f, 0.3f, 0.04f, 2.4f, darkWood);
            for (int i = 0; i < 5; i++)
            {
                if (i % 2 == 0) Sp(12.8f, 1.64f + 0.12f + i * 0.01f, 1.4f + i * 0.5f, 0.24f + i * 0.02f, 0.26f + i * 0.02f, 0.24f, redM, false);
                else Cy(12.8f, 1.64f, 1.4f + i * 0.5f, 0.2f, 0.24f, i == 1 ? ceramic : potM, false);
            }
            Poster(false, 1.5f, 2.6f, 12.92f, -1f, 0.7f, 0.7f, Mt(tFishI, 1f, 1f, 0.1f), goldM);
            Poster(false, 4f, 2.2f, 12.92f, -1f, 0.55f, 1.3f, Mt(tScrollB, 1f, 1f, 0.1f), darkWood);
            Plant(12.3f, 0f, 0.7f, potM, leafM);
            // 酒藏
            Bx(12.4f, 0f, 6.9f, 0.95f, 0.1f, 2.9f, darkWood);
            for (int i = 0; i < 3; i++) { Cy(12.4f, 0.1f, 6f + i * 0.9f, 0.84f, 0.8f, komo[i]); Barrel(12.4f, 0.92f, 6f + i * 0.9f, komo[(i + 1) % 3], lidM); }
            Bx(9.6f, 0f, 8.8f, 2.9f, 2.3f, 0.1f, Mt(tPlanksD, 3.6f, 1f, 0.3f)); Bx(8.2f, 0f, 8.6f, 0.06f, 2.3f, 0.44f, darkWood); Bx(11f, 0f, 8.6f, 0.06f, 2.3f, 0.44f, darkWood);
            for (int i = 0; i < 4; i++) Bx(9.6f, 0.5f + i * 0.6f, 8.6f, 2.8f, 0.04f, 0.42f, darkWood);
            for (int i = 0; i < 4; i++) Bx(8.6f + i * 0.68f, 0.54f, 8.6f, 0.42f, 0.34f, 0.34f, i % 2 == 0 ? crate[2] : Mt(tCrest[(i + 3) % 6], 1f, 1f, 0.2f));
            for (int i = 0; i < 4; i++) { Bottle(8.55f + i * 0.7f, 1.14f, 8.6f, 0.42f, bottles[i % 4], bottles[(i + 1) % 4]); Cy(8.7f + i * 0.62f, 1.74f, 8.6f, 0.13f, 0.4f, bottles[(i + 2) % 4], false); }
            Cy(9f, 0f, 6.6f, 0.8f, 0.9f, komo[1]); Cy(9f, 0.9f, 6.6f, 1f, 0.04f, lidM);
            Cy(8.2f, 0f, 6.3f, 0.36f, 0.5f, Mt(tRope, 2f, 1f, 0.1f)); Cy(9.7f, 0f, 7.1f, 0.36f, 0.5f, Mt(tRope, 2f, 1f, 0.1f));
            Bottle(9f, 0.94f, 6.6f, 0.36f, bottles[2], bottles[2]);
            for (int i = 0; i < 3; i++) Bx(7.65f, (i / 2) * 0.33f, 8.2f + (i % 2) * 0.42f, 0.52f, 0.32f, 0.38f, i % 3 == 0 ? crateR : crateY);
            Chochin(10.2f, 2.6f, 7f, 0.7f, 0.9f, lanternRed, blackM);
            Poster(true, 11.7f, 2.2f, 8.92f, -1f, 0.8f, 1.1f, Mt(tFuji, 1f, 1f, 0.2f), darkWood);
            Cy(7.9f, 0f, 0.9f, 0.05f, 2.9f, darkWood, false); Bx(7.9f, 0.7f, 1.1f, 0.03f, 2.1f, 0.5f, Mt(tBanner, 1f, 1f, 0.05f));

            // ---------- 光 ----------
            var sun = new GameObject("KeyLight"); sun.transform.SetParent(root, false);
            sun.transform.rotation = Quaternion.Euler(66f, -28f, 0f);
            var sl = sun.AddComponent<Light>(); sl.type = LightType.Directional; sl.color = new Color(1f, 0.90f, 0.76f); sl.intensity = 0.72f; sl.shadows = LightShadows.Soft; sl.shadowStrength = 0.72f;
            PointLamp(new Vector3(-2.8f, 3.3f, -0.6f), new Color(1f, 0.74f, 0.46f), 5.5f, 11f);
            PointLamp(new Vector3(9.5f, 3.2f, -4.5f), new Color(1f, 0.80f, 0.56f), 5f, 10f);
            PointLamp(new Vector3(0f, 3.3f, 7f), new Color(1f, 0.93f, 0.82f), 5f, 10f);
            PointLamp(new Vector3(10f, 3.2f, 4.4f), new Color(1f, 0.70f, 0.44f), 5f, 11f);

            var cg = new GameObject("MainCamera"); cg.tag = "MainCamera"; cg.transform.SetParent(root, false);
            cam = cg.AddComponent<Camera>(); cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.085f, 0.06f, 0.05f);
            cam.nearClipPlane = 0.05f; cam.farClipPlane = 120f; cg.AddComponent<AudioListener>();
            Sfx.Init(cg); Look.Apply(cam, root);
            gun = new GameObject("Gun"); gun.transform.SetParent(cg.transform, false);
            gun.transform.localPosition = new Vector3(0.24f, -0.2f, 0.45f); gun.transform.localRotation = Quaternion.Euler(-82f, 0f, 6f);
            var g1 = Obj(PrimitiveType.Cylinder, Vector3.zero, new Vector3(0.11f, 0.13f, 0.11f), Mats.Lit(new Color(0.12f, 0.06f, 0.04f), 0.9f), false);
            g1.transform.SetParent(gun.transform, false); g1.transform.localPosition = Vector3.zero; g1.transform.localRotation = Quaternion.identity;
            var g2 = Obj(PrimitiveType.Cylinder, Vector3.zero, new Vector3(0.06f, 0.04f, 0.06f), Mats.Lit(new Color(0.8f, 0.12f, 0.1f), 0.6f), false);
            g2.transform.SetParent(gun.transform, false); g2.transform.localPosition = new Vector3(0f, 0.16f, 0f); g2.transform.localRotation = Quaternion.identity;
            gun.SetActive(false);
            Debug.Log("World objects: " + root.GetComponentsInChildren<Renderer>(true).Length);
        }

        void PointLamp(Vector3 p, Color c, float intensity, float range)
        {
            var go = new GameObject("Lamp"); go.transform.SetParent(root, false); go.transform.position = p;
            var l = go.AddComponent<Light>(); l.type = LightType.Point; l.color = c; l.intensity = intensity; l.range = range; l.shadows = LightShadows.None;
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
                new[] { -12.5f, 0f, -7.4f, 90f, 0f }, new[] { 12.5f, 0f, 4.3f, 270f, 0f }, new[] { 4.15f, 0f, 8.5f, 180f, 0f }, new[] { -10.5f, 0f, 6.6f, 0f, 1f },
                new[] { 9.3f, 0.3f, -4.45f, 0f, 2f }, new[] { 10.88f, 0.3f, -8.45f, 0f, 1f }, new[] { -2f, 0f, 1.3f, 0f, 3f }, new[] { -1.95f, 0f, -8.6f, 0f, 4f },
                new[] { -7.9f, 0f, -4.3f, 90f, 0f }, new[] { 6.6f, 0f, 2.4f, 200f, 2f }, new[] { -12.45f, 0f, 2.7f, 90f, 4f }, new[] { 7.6f, 0f, 7f, 90f, 1f }
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
            if (asHunter) { SpawnBots(5); ammo = cfgAmmo; ph = Ph.Seek; timer = cfgSeek; whistleT = cfgWhistle; Lock(true); Toast("店裡藏了 5 個飯糰小人。打中加一發醬油，打空扣一發，用完就輸。"); }
            else { practice = false; ai = null; ph = Ph.Hide; timer = cfgHide; Toast("你有 " + cfgHide + " 秒躲藏和塗色，之後電腦食客會進來找你。按 T 可以提前開始。"); }
            Sfx.Beep(660f, 0.12f, 0.3f);
        }

        void StartMp(List<int> hids, List<int> ids)
        {
            mode = Mathf.Clamp(mode, 0, 2);
            solo = false; practice = false; result = "";
            hunterIds.Clear(); hunterIds.AddRange(hids); hiderIds.Clear();
            foreach (var id in ids) if (!hunterIds.Contains(id)) hiderIds.Add(id);
            caughtIds.Clear(); found = 0;
            bool h = hunterIds.Contains(net.myId);
            BuildWorld(); SpawnMe(h, new Vector3((net.myId % 5 - 2) * 1.2f, 0f, -6.5f));
            ammo = cfgAmmo; ph = Ph.Hide; timer = cfgHide; sendT = 0f; texT = 0f; whistleT = cfgWhistle;
            foreach (var id in hunterIds) hunterAmmo[id] = cfgAmmo;
            Toast(h ? "你是食客。飯糰們有 " + cfgHide + " 秒躲藏，這段時間你看不到。" : "你是飯糰。" + cfgHide + " 秒內找地方、擺姿勢、把自己塗成周圍的樣子。");
            Sfx.Beep(660f, 0.12f, 0.3f);
        }

        void Lock(bool on) { Cursor.lockState = on ? CursorLockMode.Locked : CursorLockMode.None; Cursor.visible = !on; }

        void ToMenu()
        {
            if (net != null) { net.Close(); net = null; }
            Lock(false); ph = Ph.Menu; solo = false; practice = false;
            BuildWorld(); SpawnMe(false, new Vector3(0f, 0f, -6f));
        }

        // 對答案：所有人的位置揭曉，沒被找到的立紅色光柱，被找到的立藍色光柱，大家可以自由移動鏡頭看
        void End(string text)
        {
            if (ph == Ph.Reveal || ph == Ph.End) return;
            ph = Ph.Reveal; timer = cfgReveal; result = text; Lock(false); Sfx.Beep(1040f, 0.4f, 0.3f);
            var red = Mats.Unlit(new Color(2.4f, 0.3f, 0.25f)); var blue = Mats.Unlit(new Color(0.3f, 0.7f, 2.4f));
            foreach (var kv in others) if (kv.Value.go != null && kv.Value.go.activeSelf) Beam(kv.Value.go.transform.position, kv.Value.caught ? blue : red);
            if (body != null && body.rend.enabled && !practice) Beam(body.transform.position, caught ? blue : red);
            StartFreeCam();
        }

        void Beam(Vector3 at, Material m)
        {
            Obj(PrimitiveType.Cylinder, at + Vector3.up * 3.2f, new Vector3(0.12f, 1.4f, 0.12f), m, false);
            Obj(PrimitiveType.Sphere, at + Vector3.up * 2.1f, new Vector3(0.35f, 0.35f, 0.35f), m, false);
        }

        void StartFreeCam()
        {
            if (freeCam) return;
            freeCam = true; fcPos = cam.transform.position; fcYaw = cam.transform.eulerAngles.y;
            fcPitch = cam.transform.eulerAngles.x; if (fcPitch > 180f) fcPitch -= 360f;
            Lock(false);
        }

        // 口哨：所有人都聽得到，越近越大聲
        void Whistle(Vector3 at)
        {
            float d = Vector3.Distance(cam.transform.position, at);
            Sfx.Beep(1568f, 0.18f, Mathf.Clamp01(1f - d / 28f) * 0.5f + 0.03f);
            Sfx.Beep(2093f, 0.22f, Mathf.Clamp01(1f - d / 28f) * 0.4f + 0.02f);
            if (hunter) Toast(d < 8f ? "口哨聲很近！" : d < 18f ? "聽到口哨聲。" : "遠處有口哨聲。");
        }

        void PlaceClone(int owner, Vector3 pos, float cyaw, int cpose, Color32[] px)
        {
            var c = new Clone { owner = owner, go = new GameObject("Clone" + owner) };
            c.go.transform.SetParent(root, false);
            c.go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, cyaw, 0f));
            c.paint = c.go.AddComponent<Paintable>();
            c.paint.Init(SushiShapes.Get(poses[Mathf.Clamp(cpose, 0, poses.Length - 1)]), SushiKind.Blank, true);
            if (px != null && px.Length == c.paint.px.Length) { c.paint.px = (Color32[])px.Clone(); c.paint.tex.SetPixels32(c.paint.px); c.paint.tex.Apply(false); }
            clones.Add(c);
        }

        void ClearClones(int owner)
        {
            for (int i = clones.Count - 1; i >= 0; i--) if (clones[i].owner == owner) { Kill(clones[i].go); clones.RemoveAt(i); }
        }

        bool AllOutOfAmmo()
        {
            if (hunter && ammo > 0) return false;
            foreach (var id in hunterIds) { if (id == MyId) continue; int n; if (!hunterAmmo.TryGetValue(id, out n) || n > 0) return false; }
            return true;
        }

        // 雙重模式：搜索開始時，身體留在原地當靶子，自己變成食客
        void BecomeSeeker(bool keepBody)
        {
            hunter = true; cling = false; freeCam = false;
            if (keepBody) { body.transform.SetParent(root, true); if (net != null) net.Send("tx|" + System.Convert.ToBase64String(body.tex.EncodeToPNG())); }
            else { body.rend.enabled = false; body.meshCol.enabled = false; }
            if (!hunterIds.Contains(MyId)) hunterIds.Add(MyId);
            ammo = cfgAmmo; fireT = 0f; fpPitch = 0f; Lock(true);
            if (net != null) net.Send("am|" + ammo);
        }

        int Alive() { int n = 0; foreach (var kv in others) if (!kv.Value.caught) n++; if (!hunter && !caught && !practice && ph != Ph.Menu) n++; return n; }

        void MarkCaught(int id)
        {
            if (net != null && id == net.myId)
            {
                if (caught) return; caught = true; Sfx.Beep(200f, 0.5f, 0.3f);
                if (mode == 1 && caughtIds.Count + 2 < hiderIds.Count + 1) { Toast("你被打中了，現在你也是食客！"); BecomeSeeker(false); }
                else if (mode == 2) Toast("你的身體被找到了，但你還能繼續找別人。");
                else { Toast("你被醬油打中，出局了。可以自由移動鏡頭觀戰。"); StartFreeCam(); }
            }
            else
            {
                Hider h; if (!others.TryGetValue(id, out h) || h.caught) return; h.caught = true; Sfx.Beep(880f, 0.12f, 0.3f);
                if (mode == 1 && !solo) { if (!hunterIds.Contains(id)) hunterIds.Add(id); hunterAmmo[id] = cfgAmmo; h.go.SetActive(false); }
            }
            caughtIds.Add(id);
            if (solo) { if (found >= others.Count) End("全部找到了！"); }
            else if (mode == 1) { if (hiderIds.Count > 1 && caughtIds.Count >= hiderIds.Count - 1) End("只剩最後一個飯糰，他贏了！"); else if (caughtIds.Count >= hiderIds.Count) End("全部被找到了。"); }
            else if (mode == 2) { if (caughtIds.Count >= hiderIds.Count - 1) End("只剩一個人沒被找到，他贏了！"); }
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
                    if (a.Length >= 8) { mode = int.Parse(a[3]); cfgHide = int.Parse(a[4]); cfgSeek = int.Parse(a[5]); cfgAmmo = int.Parse(a[6]); cfgWhistle = int.Parse(a[7]); }
                    StartMp(hids, ids); break;
                }
                case "am": { int n; if (a.Length >= 2 && int.TryParse(a[1], out n)) { hunterAmmo[from] = n; if ((ph == Ph.Seek) && AllOutOfAmmo()) End("食客的醬油全用完了，飯糰獲勝！"); } break; }
                case "w": if (a.Length >= 4 && cam != null) Whistle(new Vector3(P(a[1]), P(a[2]), P(a[3]))); break;
                case "cl":
                {
                    if (a.Length < 6 || root == null) break;
                    Hider src; Color32[] px = others.TryGetValue(from, out src) ? src.paint.px : null;
                    PlaceClone(from, new Vector3(P(a[1]), P(a[2]), P(a[3])), P(a[4]), int.Parse(a[5]), px); break;
                }
                case "cx": ClearClones(from); break;
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
                    if (!hunterIds.Contains(from)) hunterIds.Add(from);
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
                h.speed = Mathf.Lerp(h.speed, (h.pos - h.go.transform.position).magnitude / Mathf.Max(dt, 0.001f) * 0.1f, 0.2f);
                h.go.transform.position = Vector3.Lerp(h.go.transform.position, h.pos, Mathf.Min(1f, 12f * dt));
                h.go.transform.rotation = Quaternion.Euler(0f, h.yaw, 0f);
            }
            sendT -= dt;
            if (sendT <= 0f)
            {
                sendT = 0.1f; Vector3 p = me.position;
                if (hunter) net.Send("h|" + F(p.x) + "|" + F(p.y) + "|" + F(p.z) + "|" + F(yaw));
                else if (!caught) net.Send("s|" + F(p.x) + "|" + F(p.y) + "|" + F(p.z) + "|" + F(yaw) + "|" + pose + "|" + F(gloss));
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
            for (int i = 0; i < 2; i++) if (cloneCd[i] > 0f) cloneCd[i] -= dt;
            if (ph == Ph.Reveal) { timer -= dt; if (timer <= 0f) ph = Ph.End; return; }

            if (!practice)
            {
                timer -= dt;
                if (ph == Ph.Hide && timer <= 0f)
                {
                    ph = Ph.Seek; timer = cfgSeek; whistleT = cfgWhistle; Sfx.Beep(520f, 0.3f, 0.3f);
                    if (solo && !hunter) { SpawnAi(); Toast("電腦食客進來了。別動，動了最容易被看出來。"); }
                    else if (mode == 2 && !solo) { BecomeSeeker(true); Toast("換你找別人了！大家的身體都留在原地。"); }
                    else { if (hunter) Lock(true); Toast(hunter ? "開始找！打中加一發，打空扣一發。" : "食客進來了，別亂動。"); }
                }
                else if (ph == Ph.Seek && timer <= 0f) End(solo && hunter ? "時間到，還有 " + (others.Count - found) + " 個沒找到。" : solo ? "你撐到最後，贏了！" : (hunter ? "時間到，飯糰獲勝。" : (caught ? "時間到，飯糰隊獲勝（你出局了）。" : "你撐到最後，飯糰獲勝！")));
            }
            if (ph == Ph.End) return;
            if (hunter) HunterTick(dt); else if (!caught) HiderTick(dt);
            if (solo && !hunter && ph == Ph.Seek) AiTick(dt);
            // 單人打電腦時，電腦飯糰也會定時吹口哨
            if (solo && hunter && ph == Ph.Seek)
            {
                whistleT -= dt;
                if (whistleT <= 0f) { whistleT = cfgWhistle; var alive = new List<Hider>(); foreach (var kv in others) if (!kv.Value.caught) alive.Add(kv.Value); if (alive.Count > 0) Whistle(alive[Random.Range(0, alive.Count)].go.transform.position); }
            }
        }

        CollisionFlags Move(Vector3 dir, float speed, float dt)
        {
            if (cc.isGrounded && vy < 0f) vy = -1f; else vy -= 20f * dt;
            return cc.Move((dir * speed + Vector3.up * vy) * dt);
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
            if (In.Held(K.E)) yaw += 120f * dt;
            // 貼牆：跳起來撞到牆就黏住。空白鍵往上、Ctrl 往下、Shift 放開
            if (cling)
            {
                vy = 0f;
                float up = In.Held(K.Space) ? 1.6f : In.Held(K.Ctrl) ? -1.6f : 0f;
                cc.Move((dir * 1.2f + Vector3.up * up) * dt);
                if (In.Down(K.Shift) || (cc.isGrounded && up < 0f)) { cling = false; Toast("離開牆面。"); }
            }
            else
            {
                if (In.Down(K.Space) && cc.isGrounded) vy = 6.5f;
                var fl = Move(dir, In.Held(K.Shift) ? 5f : 3f, dt);
                if (!cc.isGrounded && (fl & CollisionFlags.Sides) != 0 && dir.sqrMagnitude > 0f) { cling = true; Toast("貼在牆上了。空白鍵往上、Ctrl 往下、Shift 放開。"); }
            }
            me.rotation = Quaternion.Euler(0f, yaw, 0f);

            // 口哨（按 1），以及房主設定的強制口哨
            bool blow = In.Down(K.Digit1);
            if (ph == Ph.Seek && !practice) { whistleT -= dt; if (whistleT <= 0f) { whistleT = cfgWhistle; blow = true; } }
            if (blow) { Whistle(me.position); if (net != null) net.Send("w|" + F(me.position.x) + "|" + F(me.position.y) + "|" + F(me.position.z)); }

            // 分身：Q 放一個（最多兩個，各 30 秒冷卻），X 全部收回。分身被打中，本尊也出局。
            if (In.Down(K.Q))
            {
                if (myClones >= 2) Toast("最多兩個分身。按 X 可以收回。");
                else if (cloneCd[myClones] > 0f) Toast("分身冷卻中，還要 " + Mathf.CeilToInt(cloneCd[myClones]) + " 秒。");
                else
                {
                    PlaceClone(MyId, me.position, yaw, pose, body.px); cloneCd[myClones] = 30f; myClones++;
                    if (net != null) net.Send("cl|" + F(me.position.x) + "|" + F(me.position.y) + "|" + F(me.position.z) + "|" + F(yaw) + "|" + pose);
                    Toast("放了一個分身。小心：分身被打中，你也會出局。");
                }
            }
            if (In.Down(K.X) && myClones > 0) { ClearClones(MyId); myClones = 0; if (net != null) net.Send("cx"); Toast("分身已收回。"); }

            // 看漏分數：不動、在食客視野裡、沒被打，就一直加分，越近加得越快
            if (ph == Ph.Seek && dir.sqrMagnitude == 0f && !stroke)
            {
                foreach (var kv in hunterAv)
                {
                    if (kv.Value == null) continue;
                    Vector3 eye = kv.Value.transform.position + Vector3.up * 1.55f, to = me.position + Vector3.up * 0.9f - eye;
                    float d = to.magnitude;
                    if (d > 12f || Vector3.Angle(kv.Value.transform.forward, to) > 38f) continue;
                    RaycastHit lh;
                    if (Physics.Raycast(eye, to.normalized, out lh, d - 0.4f) && !lh.collider.transform.IsChildOf(me) && lh.collider.GetComponentInParent<Paintable>() == null) continue;
                    score += (10f * (1f - d / 12f) + 2f) * dt;
                }
            }
            if (In.Down(K.R)) SetPose((pose + 1) % poses.Length);
            if (solo && ph == Ph.Hide && In.Down(K.T)) timer = 0f;
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
            if (fireT > 0f) fireT -= dt;
            if (!In.LmbDown) return;
            if (Cursor.lockState != CursorLockMode.Locked) { Lock(true); return; }
            if (fireT > 0f) return;
            if (ammo < 1) { Toast("醬油用完了。"); Sfx.Beep(180f, 0.1f, 0.25f); return; }
            fireT = 1.5f; Sfx.Beep(240f, 0.08f, 0.35f);
            Physics.SyncTransforms(); RaycastHit hit;
            if (!Physics.Raycast(cam.ViewportPointToRay(new Vector3(0.5f, 0.5f, 0f)), out hit, 60f)) return;
            Color col = Color.HSVToRGB(Random.value, 0.9f, 1f);
            var pt = hit.collider.GetComponent<Paintable>();
            int hitId = 0; bool isHider = false;
            foreach (var kv in others) if (kv.Value.paint == pt && pt != null && !kv.Value.caught) { hitId = kv.Key; isHider = true; }
            foreach (var c in clones) if (c.paint == pt && pt != null && c.owner != MyId) { Hider oh; if (others.TryGetValue(c.owner, out oh) && !oh.caught) { hitId = c.owner; isHider = true; } }
            if (pt != null && pt == body) { Toast("那是你自己的身體。"); fireT = 0.3f; return; }
            if (isHider)
            {
                pt.Dab(hit.point, hit.normal, 0.3f, col); pt.Flush(); found++; ammo++;
                if (net != null) net.Send("am|" + ammo);
                if (net != null) net.Send("hit|" + hitId + "|" + F(hit.point.x) + "|" + F(hit.point.y) + "|" + F(hit.point.z) + "|" + F(hit.normal.x) + "|" + F(hit.normal.y) + "|" + F(hit.normal.z) + "|" + F(col.r) + "|" + F(col.g) + "|" + F(col.b));
                Toast("找到一個！"); MarkCaught(hitId);
            }
            else
            {
                var s = Obj(PrimitiveType.Sphere, hit.point + hit.normal * 0.01f, new Vector3(0.45f, 0.45f, 0.03f), Mats.Lit(col, 0.7f), false);
                s.transform.rotation = Quaternion.LookRotation(hit.normal);
                if (Application.isPlaying) Destroy(s, 25f);
                ammo--;
                Toast(ammo > 0 ? "沒打中，扣一發。還剩 " + ammo + " 發。" : "沒打中，醬油用完了！");
                if (net != null) net.Send("am|" + ammo);
                if (ammo <= 0 && (solo || AllOutOfAmmo())) End(solo ? "醬油用完了，還有 " + (others.Count - found) + " 個沒找到。" : "食客的醬油全用完了，飯糰獲勝！");
            }
        }

        void LateUpdate()
        {
            if (!In.Ready || cam == null || me == null) return;
            if (freeCam)
            {
                // 自由鏡頭：WASD 飛、空白鍵上、Ctrl 下、右鍵拖曳轉向
                if (gun.activeSelf) gun.SetActive(false);
                cam.fieldOfView = 60f;
                if (In.RmbHeld) { Vector2 fd = In.MouseDelta; fcYaw += fd.x * 0.25f; fcPitch = Mathf.Clamp(fcPitch - fd.y * 0.2f, -85f, 85f); }
                Quaternion fr = Quaternion.Euler(fcPitch, fcYaw, 0f);
                Vector3 fm = Vector3.zero;
                if (In.Held(K.W)) fm += fr * Vector3.forward; if (In.Held(K.S)) fm -= fr * Vector3.forward;
                if (In.Held(K.D)) fm += fr * Vector3.right; if (In.Held(K.A)) fm -= fr * Vector3.right;
                if (In.Held(K.Space)) fm += Vector3.up; if (In.Held(K.Ctrl)) fm -= Vector3.up;
                fcPos += fm * (In.Held(K.Shift) ? 12f : 6f) * Time.deltaTime;
                fcPos = new Vector3(Mathf.Clamp(fcPos.x, -16f, 16f), Mathf.Clamp(fcPos.y, 0.3f, 12f), Mathf.Clamp(fcPos.z, -12f, 12f));
                cam.transform.position = fcPos; cam.transform.rotation = fr;
                return;
            }
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
                if (Btn(new Rect(cx - 290f, 270f, 280f, 80f), "單人：當飯糰躲電腦", new Color(0.80f, 0.30f, 0.20f))) StartSolo(false);
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
                Box(new Rect(cx - 310f, 210f, 620f, 310f), panel); Box(new Rect(cx - 310f, 210f, 620f, 3f), gold);
                GUI.Label(new Rect(cx - 300f, 218f, 600f, 44f), "房間", sB);
                GUI.Label(new Rect(cx - 290f, 264f, 580f, 60f), netMsg, sL);
                bool host = net != null && net.isHost;
                if (host)
                {
                    GUI.Label(new Rect(cx - 290f, 330f, 580f, 26f), "目前 " + lobby.Count + " 人（含你）。食客隨機選。", sL);
                    if (Btn(new Rect(cx - 290f, 362f, 580f, 30f), "模式：" + modeNames[mode] + "（點這裡切換）", new Color(0.18f, 0.28f, 0.52f))) mode = (mode + 1) % 3;
                    string[] names = { "躲藏秒數", "搜索秒數", "醬油發數", "口哨間隔" };
                    int[] vals = { cfgHide, cfgSeek, cfgAmmo, cfgWhistle }; int[] step = { 15, 30, 1, 5 }; int[] lo = { 15, 60, 1, 5 }; int[] hi = { 300, 600, 30, 120 };
                    for (int i = 0; i < 4; i++)
                    {
                        float bx = cx - 290f + i * 147f;
                        GUI.Label(new Rect(bx, 398f, 140f, 22f), names[i] + " " + vals[i], sS);
                        if (Btn(new Rect(bx, 420f, 66f, 26f), "－", new Color(0.3f, 0.3f, 0.3f))) vals[i] = Mathf.Max(lo[i], vals[i] - step[i]);
                        if (Btn(new Rect(bx + 70f, 420f, 66f, 26f), "＋", new Color(0.3f, 0.3f, 0.3f))) vals[i] = Mathf.Min(hi[i], vals[i] + step[i]);
                    }
                    cfgHide = vals[0]; cfgSeek = vals[1]; cfgAmmo = vals[2]; cfgWhistle = vals[3];
                    if (Btn(new Rect(cx - 220f, 456f, 200f, 46f), "開始遊戲", new Color(0.80f, 0.30f, 0.20f)))
                    {
                        if (lobby.Count < 2) netMsg = "至少要兩個人才能開始。";
                        else
                        {
                            var ids = new List<int>(lobby); var hids = new List<int>();
                            int want = mode == 2 ? 0 : ids.Count >= 12 ? 3 : ids.Count >= 6 ? 2 : 1;
                            while (hids.Count < want) { int c = ids[Random.Range(0, ids.Count)]; if (!hids.Contains(c)) hids.Add(c); }
                            net.Send("start|" + string.Join(",", hids) + "|" + string.Join(",", ids) + "|" + mode + "|" + cfgHide + "|" + cfgSeek + "|" + cfgAmmo + "|" + cfgWhistle);
                            StartMp(hids, ids);
                        }
                    }
                }
                if (Btn(new Rect(cx + 20f, 456f, 200f, 46f), "離開", new Color(0.3f, 0.3f, 0.3f))) ToMenu();
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
            string title = practice ? "練習模式" : ph == Ph.Hide ? "躲藏時間" : ph == Ph.Seek ? "搜索中" : ph == Ph.Reveal ? "對答案" : "結束";
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
            if (solo && !hunter && ph == Ph.Seek && ai != null)
            {
                Box(new Rect(cx + 240f, 20f, 204f, 16f), panel);
                Box(new Rect(cx + 242f, 22f, 200f * Mathf.Clamp01(aiSus), 12f), Color.Lerp(new Color(1f, 0.85f, 0.3f), new Color(1f, 0.2f, 0.15f), Mathf.Clamp01(aiSus)));
                GUI.Label(new Rect(cx + 240f, 36f, 204f, 20f), "食客注意力", sS);
            }
            if (toastT > 0f && toast.Length > 0) { Box(new Rect(cx - 300f, 108f, 600f, 36f), panel); GUI.Label(new Rect(cx - 300f, 108f, 600f, 36f), toast, sL); }

            if (ph == Ph.Hide || ph == Ph.Seek)
            {
                Box(new Rect(0f, H - 80f, W_, 80f), panel); Box(new Rect(0f, H - 80f, W_, 2f), gold);
                if (hunter)
                {
                    GUI.Label(new Rect(20f, H - 70f, 300f, 60f), "醬油 " + ammo + " 發", sB);
                    GUI.Label(new Rect(330f, H - 70f, W_ - 350f, 60f), "WASD 走動　Shift 跑　滑鼠 轉視角　左鍵 開槍（打中 +1，打空 -1，用完就輸）" + (solo ? "　Esc 回主選單" : ""), sL);
                    Box(new Rect(cx - 5f, H / 2f - 5f, 10f, 10f), new Color(0f, 0f, 0f, 0.6f)); Box(new Rect(cx - 3f, H / 2f - 3f, 6f, 6f), Color.white);
                }
                else if (!caught)
                {
                    GUI.Label(new Rect(20f, H - 72f, W_ - 40f, 64f), "WASD 走　Shift 跑　空白鍵 跳（撞牆會黏住）　R 換姿勢（" + poseNames[pose] + "）　1 口哨　Q 分身　X 收回分身　右鍵拖曳 轉鏡頭\n左鍵 往自己身上塗　C 吸顏色　F 塗滿　Z 撤銷　[ ] 筆刷　- = 光澤　　看漏分 " + Mathf.RoundToInt(score) + (solo ? "　Esc 回主選單" : ""), sL);
                    PaintPanel(panel, gold);
                }
            }
            if (ph == Ph.Reveal || (freeCam && ph == Ph.Seek))
            {
                Box(new Rect(cx - 420f, H - 60f, 840f, 44f), panel);
                GUI.Label(new Rect(cx - 412f, H - 60f, 824f, 44f), ph == Ph.Reveal ? "對答案：紅色光柱是沒被找到的，藍色是被找到的。WASD 飛、空白鍵上、Ctrl 下、右鍵拖曳轉向。" + result : "觀戰中：WASD 飛、空白鍵上、Ctrl 下、右鍵拖曳轉向。", sL);
            }
            if (ph == Ph.End)
            {
                Box(new Rect(cx - 300f, 250f, 600f, 200f), panel); Box(new Rect(cx - 300f, 250f, 600f, 3f), gold);
                GUI.Label(new Rect(cx - 290f, 262f, 580f, 70f), result, sB);
                GUI.Label(new Rect(cx - 290f, 332f, 580f, 34f), hunter ? "你找到 " + found + " 個" : "你的看漏分數 " + Mathf.RoundToInt(score), sL);
                if (Btn(new Rect(cx - 110f, 375f, 220f, 54f), "回主選單", new Color(0.80f, 0.30f, 0.20f))) ToMenu();
            }
        }
    }
}
