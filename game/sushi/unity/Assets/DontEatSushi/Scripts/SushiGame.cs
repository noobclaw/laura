// 別吃壽司 - 第一個可玩版本。場景、玩家、鏡頭、回合和介面都在這裡用程式搭出來。
// 用法：選單 Tools > 別吃壽司 > 建立並開啟場景，然後按播放。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public enum Phase { Menu, Prep, Hunt, Win, Lose }
    public enum Role { Hider, Hunter }

    public class Bot
    {
        public GameObject go;
        public Slot slot;
        public bool caught;
    }

    public class Slot
    {
        public Transform tr;
        public GameObject sushi;
        public LineRenderer marker;
        public Plate plate;
    }

    public class Plate
    {
        public Transform tr;
        public float d;
        public Vector3 vel;
        public Slot[] slots;
        public SushiKind kind;
    }

    public class SushiGame : MonoBehaviour
    {
        public const float A = 11f, B = 4.5f, BeltHalf = 1.6f, BeltTop = 0.1f, PlateTop = 0.22f;
        public float beltSpeed = 0.9f;
        public float prepTime = 60f, huntTime = 150f;

        [System.NonSerialized] public Phase phase;
        [System.NonSerialized] public Role role = Role.Hider;
        [System.NonSerialized] public List<Bot> bots = new List<Bot>();
        int ammo, found;
        float ammoT, whistleT, hintT;
        LineRenderer hintRing;
        public const int MaxAmmo = 6;
        public float hunterTime = 120f;
        [System.NonSerialized] public List<Plate> plates = new List<Plate>();
        [System.NonSerialized] public Transform player;
        [System.NonSerialized] public Paintable playerPaint;
        [System.NonSerialized] public MeshRenderer playerRenderer;
        [System.NonSerialized] public bool playerAttached, playerMoving;
        [System.NonSerialized] public float maxSuspicion;
        [System.NonSerialized] public Color bgColor = new Color(0.17f, 0.12f, 0.09f);

        Transform root;
        Camera cam;
        Diner diner;
        Slot attached;
        ShapeKind playerShape = ShapeKind.Nigiri;
        float playerYaw, timer, survived;
        float camYaw = 0f, camPitch = 42f, camDist = 6f;
        Vector3 camTarget;

        Color32 paintColor = new Color32(250, 128, 66, 255);
        float brush = 0.1f;
        bool stroke;
        Vector2 lastMouse;
        string toast = "";
        float toastT;
        bool debugView;

        Font font;
        GUIStyle sLabel, sBig, sSmall;

        static readonly Color32[] palette =
        {
            new Color32(245, 243, 235, 255), new Color32(250, 128, 66, 255), new Color32(255, 209, 173, 255),
            new Color32(184, 28, 38, 255), new Color32(250, 214, 82, 255), new Color32(18, 28, 22, 255),
            new Color32(100, 176, 72, 255), new Color32(199, 230, 153, 255), new Color32(245, 115, 64, 255),
            new Color32(252, 230, 214, 255), new Color32(170, 120, 70, 255), new Color32(34, 34, 38, 255),
            new Color32(60, 110, 170, 255), new Color32(200, 60, 50, 255)
        };

        void Start() { Build(); phase = Phase.Menu; }

        static void Kill(Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) Destroy(o); else DestroyImmediate(o);
        }

        void StartRound(Role r)
        {
            if (root != null) Kill(root.gameObject);
            player = null;
            role = r;
            Build();
            Sfx.Beep(660f, 0.12f, 0.3f);
            if (r == Role.Hunter)
            {
                timer = 8f;
                player.gameObject.SetActive(false);
                diner.gameObject.SetActive(false);   // 玩家自己就是食客，不需要再顯示一個
                SpawnBots(4);
                ammo = MaxAmmo; found = 0; ammoT = 0f; whistleT = 22f;
                camTarget = new Vector3(0f, 0.3f, -3f); camDist = 13f; camPitch = 50f; camYaw = 0f;
                Toast("壽司們正在躲藏，請稍候。");
            }
        }

        // ---------------- 電腦壽司（玩家當食客時） ----------------

        void SpawnBots(int count)
        {
            bots.Clear();
            var empty = new List<Slot>();
            foreach (var p in plates) foreach (var s in p.slots) if (s.sushi == null) empty.Add(s);
            for (int i = 0; i < count; i++)
            {
                var b = new Bot();
                int skill = Random.Range(0, 3);
                bool onPlate = i < count - 1 && empty.Count > 0;
                if (onPlate)
                {
                    int k = Random.Range(0, empty.Count);
                    var slot = empty[k]; empty.RemoveAt(k);
                    var go = new GameObject("Bot");
                    go.transform.SetParent(slot.tr, false);
                    var pt = go.AddComponent<Paintable>();
                    pt.Init(SushiShapes.Get(SushiShapes.ShapeOf(slot.plate.kind)), slot.plate.kind, false);
                    pt.Degrade(skill == 0 ? 0.75f : skill == 1 ? 0.45f : 0.2f, skill == 0 ? 0.14f : skill == 1 ? 0.08f : 0.04f, skill == 0 ? 0.2f : skill == 1 ? 0.11f : 0f);
                    slot.sushi = go;
                    if (slot.marker != null) slot.marker.gameObject.SetActive(false);
                    b.go = go; b.slot = slot;
                }
                else
                {
                    bool island = Random.value < 0.4f;
                    Vector3 pos = island ? new Vector3(Random.Range(-7f, 7f), 0.5f, Random.Range(-1.5f, 1.5f)) : new Vector3(Random.Range(-15f, 15f), 0f, Random.Range(-9.6f, -7.2f));
                    Color col = island ? new Color(0.90f, 0.86f, 0.78f) : new Color(0.74f, 0.54f, 0.32f);
                    var go = new GameObject("Bot");
                    go.transform.SetParent(root, false);
                    go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
                    var pt = go.AddComponent<Paintable>();
                    pt.Init(SushiShapes.Get(Random.value < 0.5f ? ShapeKind.Nigiri : ShapeKind.Maki), SushiKind.Blank, false);
                    pt.FillNoisy(col, 0.05f);
                    pt.Degrade(0f, 0.03f, skill == 0 ? 0.16f : 0f);
                    b.go = go;
                }
                bots.Add(b);
            }
        }

        void HunterControl(float dt)
        {
            Vector3 mv = Vector3.zero;
            if (In.Held(K.W)) mv.z += 1f;
            if (In.Held(K.S)) mv.z -= 1f;
            if (In.Held(K.D)) mv.x += 1f;
            if (In.Held(K.A)) mv.x -= 1f;
            if (mv.sqrMagnitude > 0f)
            {
                camTarget += Quaternion.Euler(0f, camYaw, 0f) * mv.normalized * 8f * dt;
                camTarget.x = Mathf.Clamp(camTarget.x, -17f, 17f);
                camTarget.z = Mathf.Clamp(camTarget.z, -10f, 9f);
            }
            if (phase != Phase.Hunt) return;

            if (ammo < MaxAmmo) { ammoT += dt; if (ammoT >= 7f) { ammoT = 0f; ammo++; } }
            if (hintT > 0f) { hintT -= dt; if (hintT <= 0f && hintRing != null) hintRing.gameObject.SetActive(false); }
            whistleT -= dt;
            if (whistleT <= 0f)
            {
                whistleT = 25f;
                var alive = bots.FindAll(x => !x.caught && x.go != null);
                if (alive.Count > 0)
                {
                    var b = alive[Random.Range(0, alive.Count)];
                    if (hintRing == null) hintRing = Ring(root, 3.5f, 0.09f, new Color(0.3f, 0.9f, 1f));
                    Vector2 off = Random.insideUnitCircle * 2.5f;
                    hintRing.transform.position = new Vector3(b.go.transform.position.x + off.x, 0.6f, b.go.transform.position.z + off.y);
                    hintRing.gameObject.SetActive(true);
                    hintT = 3.5f;
                    Sfx.Beep(1320f, 0.25f, 0.25f);
                    Toast("有壽司吹口哨了，就在藍圈裡。");
                }
            }

            Vector2 mp = In.MousePos;
            bool overHud = mp.y < 118f * (Screen.height / 720f);
            if (In.LmbDown && !overHud)
            {
                if (ammo < 1) { Toast("醬油用完了，等它補充。"); Sfx.Beep(180f, 0.1f, 0.25f); return; }
                ammo--;
                Sfx.Beep(240f, 0.08f, 0.35f);
                Physics.SyncTransforms();
                RaycastHit hit;
                if (!Physics.Raycast(cam.ScreenPointToRay(mp), out hit, 300f)) return;
                var stain = Prim(PrimitiveType.Sphere, "Stain", hit.point, new Vector3(0.35f, 0.04f, 0.35f), Mats.Lit(new Color(0.12f, 0.06f, 0.04f), 0.8f), false);
                if (Application.isPlaying) Destroy(stain, 8f);
                Bot hitBot = null;
                foreach (var b in bots) if (!b.caught && b.go != null && hit.collider.gameObject == b.go) hitBot = b;
                if (hitBot != null)
                {
                    hitBot.caught = true; found++;
                    if (hitBot.slot != null) hitBot.slot.sushi = null;
                    Kill(hitBot.go);
                    Sfx.Beep(880f, 0.1f, 0.35f); Sfx.Beep(1320f, 0.18f, 0.3f);
                    Toast("抓到一個假壽司！還剩 " + (bots.Count - found) + " 個。");
                    if (found >= bots.Count) { phase = Phase.Win; Sfx.Beep(1040f, 0.4f, 0.35f); }
                }
                else if (hit.collider.GetComponent<Paintable>() != null) Toast("那是真壽司，浪費了一發。");
                else Toast("沒打中。");
            }
        }

        // ---------------- 搭場景 ----------------

        public GameObject Prim(PrimitiveType type, string name, Vector3 pos, Vector3 scale, Material m, bool keepCollider, Transform parent = null)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            go.transform.SetParent(parent != null ? parent : root, false);
            go.transform.position = pos;
            go.transform.localScale = scale;
            go.GetComponent<Renderer>().sharedMaterial = m;
            var col = go.GetComponent<Collider>();
            if (col != null)
            {
                if (!keepCollider) Kill(col);
                else if (type == PrimitiveType.Cylinder) { Kill(col); go.AddComponent<BoxCollider>(); }
            }
            return go;
        }

        public LineRenderer Ring(Transform parent, float radius, float width, Color c)
        {
            var go = new GameObject("Ring");
            go.transform.SetParent(parent, false);
            var lr = go.AddComponent<LineRenderer>();
            lr.useWorldSpace = false;
            lr.loop = true;
            lr.positionCount = 40;
            for (int i = 0; i < 40; i++)
            {
                float a = i / 40f * Mathf.PI * 2f;
                lr.SetPosition(i, new Vector3(Mathf.Cos(a) * radius, 0f, Mathf.Sin(a) * radius));
            }
            lr.startWidth = width; lr.endWidth = width;
            lr.sharedMaterial = Mats.Unlit(c);
            lr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            lr.receiveShadows = false;
            return lr;
        }

        Texture2D WoodTexture()
        {
            const int N = 256;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true);
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
            {
                for (int x = 0; x < N; x++)
                {
                    float g = Mathf.PerlinNoise(x * 0.012f, y * 0.22f);
                    float f = Mathf.PerlinNoise(x * 0.3f + 40f, y * 0.9f + 12f);
                    Color c = Color.Lerp(new Color(0.60f, 0.40f, 0.22f), new Color(0.84f, 0.64f, 0.40f), g);
                    c *= 0.94f + 0.06f * f;
                    c.a = 1f;
                    px[y * N + x] = c;
                }
            }
            t.SetPixels32(px);
            t.Apply(true);
            t.wrapMode = TextureWrapMode.Repeat;
            return t;
        }

        void Build()
        {
            root = new GameObject("World").transform;
            plates.Clear(); bots.Clear(); hintRing = null;
            attached = null; playerAttached = false; playerMoving = false;
            maxSuspicion = 0f; survived = 0f; stroke = false;
            phase = Phase.Prep; timer = prepTime;

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.46f, 0.40f, 0.34f);

            // 燈
            var sun = new GameObject("KeyLight");
            sun.transform.SetParent(root, false);
            sun.transform.rotation = Quaternion.Euler(52f, -28f, 0f);
            var sl = sun.AddComponent<Light>();
            sl.type = LightType.Directional;
            sl.color = new Color(1f, 0.93f, 0.82f);
            sl.intensity = 1.15f;
            sl.shadows = LightShadows.Hard;

            var wood = WoodTexture();
            var counterMat = Mats.Lit(Color.white, 0.35f, wood);
            if (counterMat.HasProperty("_BaseMap")) counterMat.SetTextureScale("_BaseMap", new Vector2(4f, 3f));
            var darkWood = Mats.Lit(new Color(0.30f, 0.18f, 0.10f), 0.3f);
            var beltMat = Mats.Lit(new Color(0.14f, 0.14f, 0.16f), 0.45f);
            var islandMat = Mats.Lit(new Color(0.90f, 0.86f, 0.78f), 0.25f);

            // 吧台、傳送帶、中島
            Prim(PrimitiveType.Cube, "Counter", new Vector3(0f, -0.5f, 0f), new Vector3(40f, 1f, 22f), counterMat, true);
            Prim(PrimitiveType.Cube, "CounterEdge", new Vector3(0f, -0.2f, -11.2f), new Vector3(40f, 0.6f, 0.5f), darkWood, true);
            Prim(PrimitiveType.Cube, "BeltNear", new Vector3(0f, 0.05f, -B), new Vector3(2f * A + 3.2f, 0.1f, 3.2f), beltMat, true);
            Prim(PrimitiveType.Cube, "BeltFar", new Vector3(0f, 0.05f, B), new Vector3(2f * A + 3.2f, 0.1f, 3.2f), beltMat, true);
            Prim(PrimitiveType.Cube, "BeltLeft", new Vector3(-A, 0.05f, 0f), new Vector3(3.2f, 0.1f, 2f * B - 3.2f), beltMat, true);
            Prim(PrimitiveType.Cube, "BeltRight", new Vector3(A, 0.05f, 0f), new Vector3(3.2f, 0.1f, 2f * B - 3.2f), beltMat, true);
            Prim(PrimitiveType.Cube, "Island", new Vector3(0f, 0.25f, 0f), new Vector3(2f * A - 3.6f, 0.5f, 2f * B - 3.6f), islandMat, true);

            // 背景
            Prim(PrimitiveType.Cube, "Floor", new Vector3(0f, -7f, 0f), new Vector3(140f, 0.2f, 140f), Mats.Lit(new Color(0.22f, 0.16f, 0.12f), 0.1f), true);
            Prim(PrimitiveType.Cube, "BackWall", new Vector3(0f, 5f, 17f), new Vector3(70f, 26f, 0.5f), Mats.Lit(new Color(0.86f, 0.78f, 0.64f), 0.05f), true);
            for (int i = -3; i <= 3; i++)
                Prim(PrimitiveType.Cube, "Beam", new Vector3(i * 9f, 5f, 16.6f), new Vector3(0.5f, 26f, 0.4f), darkWood, true);
            Prim(PrimitiveType.Cube, "BeamTop", new Vector3(0f, 13.2f, 16.6f), new Vector3(70f, 0.6f, 0.5f), darkWood, true);
            var noren = Mats.Lit(new Color(0.13f, 0.20f, 0.42f), 0.05f);
            for (int i = -2; i <= 2; i++)
                Prim(PrimitiveType.Cube, "Noren", new Vector3(i * 5.2f, 11f, 16.2f), new Vector3(4.9f, 3.6f, 0.08f), noren, true);
            var lanternMat = Mats.Unlit(new Color(1f, 0.55f, 0.25f));
            for (int i = -1; i <= 1; i++)
            {
                var lp = new Vector3(i * 10f, 8.5f, 7f);
                Prim(PrimitiveType.Sphere, "Lantern", lp, new Vector3(1.6f, 2.1f, 1.6f), lanternMat, false);
                var lg = new GameObject("LanternLight");
                lg.transform.SetParent(root, false);
                lg.transform.position = lp + Vector3.down * 1.2f;
                var l = lg.AddComponent<Light>();
                l.type = LightType.Point;
                l.color = new Color(1f, 0.72f, 0.42f);
                l.range = 22f;
                l.intensity = 2.2f;
            }

            // 桌上小物
            var soy = Mats.Lit(new Color(0.10f, 0.05f, 0.04f), 0.8f);
            Prim(PrimitiveType.Cylinder, "SoyBottle", new Vector3(-6f, 0.7f, -8.6f), new Vector3(0.7f, 0.7f, 0.7f), soy, true);
            Prim(PrimitiveType.Cylinder, "SoyCap", new Vector3(-6f, 1.5f, -8.6f), new Vector3(0.4f, 0.12f, 0.4f), Mats.Lit(new Color(0.78f, 0.12f, 0.10f), 0.5f), true);
            Prim(PrimitiveType.Cylinder, "TeaCup", new Vector3(5.5f, 0.45f, -8.4f), new Vector3(0.9f, 0.45f, 0.9f), Mats.Lit(new Color(0.36f, 0.50f, 0.34f), 0.4f), true);
            Prim(PrimitiveType.Cube, "ChopstickBox", new Vector3(9.5f, 0.3f, -8.6f), new Vector3(2.4f, 0.6f, 0.9f), Mats.Lit(new Color(0.12f, 0.10f, 0.10f), 0.6f), true);
            Prim(PrimitiveType.Cube, "GingerBox", new Vector3(-10f, 0.35f, -8.5f), new Vector3(1.2f, 0.7f, 1.2f), Mats.Lit(new Color(0.75f, 0.14f, 0.12f), 0.6f), true);
            Prim(PrimitiveType.Sphere, "Wasabi", new Vector3(-2.5f, 0.2f, -8.2f), new Vector3(0.5f, 0.4f, 0.5f), Mats.Lit(new Color(0.55f, 0.72f, 0.30f), 0.15f), true);

            // 盤子和壽司
            SushiKind[] kinds = { SushiKind.Salmon, SushiKind.CucumberRoll, SushiKind.Tuna, SushiKind.Tamago, SushiKind.TunaRoll, SushiKind.Shrimp };
            Color[] plateCols =
            {
                new Color(0.86f, 0.30f, 0.24f), new Color(0.30f, 0.52f, 0.72f), new Color(0.90f, 0.72f, 0.24f),
                new Color(0.36f, 0.62f, 0.44f), new Color(0.56f, 0.38f, 0.66f), new Color(0.86f, 0.52f, 0.60f)
            };
            float L = Perimeter();
            const int count = 12;
            for (int i = 0; i < count; i++)
            {
                var p = new Plate();
                p.kind = kinds[i % kinds.Length];
                p.d = i * L / count;
                var pg = new GameObject("Plate" + i);
                pg.transform.SetParent(root, false);
                p.tr = pg.transform;
                Vector3 pos; float yaw;
                PathPoint(p.d, out pos, out yaw);
                p.tr.SetPositionAndRotation(pos, Quaternion.Euler(0f, yaw, 0f));
                var disc = Prim(PrimitiveType.Cylinder, "Disc", Vector3.zero, new Vector3(2.8f, 0.06f, 2.8f), Mats.Lit(plateCols[i % plateCols.Length], 0.6f), true, p.tr);
                disc.transform.localPosition = new Vector3(0f, 0.06f, 0f);
                bool oneEmpty = (i == 0 || i == 1 || i == 3 || i == 4 || i == 8 || i == 10);
                p.slots = new Slot[2];
                for (int s = 0; s < 2; s++)
                {
                    var sg = new GameObject("Slot" + s);
                    sg.transform.SetParent(p.tr, false);
                    sg.transform.localPosition = new Vector3(s == 0 ? -0.5f : 0.5f, 0.12f, 0f);
                    sg.transform.localRotation = Quaternion.Euler(0f, 90f, 0f);
                    var slot = new Slot { tr = sg.transform, plate = p };
                    if (s == 1 && oneEmpty)
                    {
                        slot.marker = Ring(sg.transform, 0.5f, 0.04f, new Color(1f, 1f, 1f));
                        slot.marker.transform.localPosition = new Vector3(0f, 0.03f, 0f);
                    }
                    else
                    {
                        var su = new GameObject("Sushi_" + p.kind);
                        su.transform.SetParent(sg.transform, false);
                        su.AddComponent<Paintable>().Init(SushiShapes.Get(SushiShapes.ShapeOf(p.kind)), p.kind, false);
                        slot.sushi = su;
                    }
                    p.slots[s] = slot;
                }
                plates.Add(p);
            }

            // 鏡頭
            var cg = new GameObject("MainCamera");
            cg.tag = "MainCamera";
            cg.transform.SetParent(root, false);
            cam = cg.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = bgColor;
            cam.fieldOfView = 50f;
            cam.nearClipPlane = 0.05f;
            cam.farClipPlane = 200f;
            cg.AddComponent<AudioListener>();
            Sfx.Init(cg);

            SpawnPlayer(new Vector3(0f, 0f, -7.6f));
            camTarget = player.position;

            var dg = new GameObject("Diner");
            dg.transform.SetParent(root, false);
            diner = dg.AddComponent<Diner>();
            diner.Setup(this);

            Toast("準備時間：選身形（1 握壽司 / 2 卷），找個缺一個的盤子，把自己塗成旁邊那個壽司。");
        }

        void SpawnPlayer(Vector3 pos)
        {
            if (player != null) Kill(player.gameObject);
            var go = new GameObject("Player");
            go.transform.SetParent(root, false);
            go.transform.position = pos;
            playerPaint = go.AddComponent<Paintable>();
            playerPaint.Init(SushiShapes.Get(playerShape), SushiKind.Blank, true);
            playerRenderer = playerPaint.rend;
            player = go.transform;
        }

        void Restart()
        {
            if (root != null) Kill(root.gameObject);
            player = null;
            role = Role.Hider;
            Build();
            phase = Phase.Menu;
        }

        // 給雲端截圖用：不進播放模式也能把場景搭出來
        public Camera EditorSetup(bool hunterView)
        {
            Build();
            phase = Phase.Hunt;
            if (hunterView) { role = Role.Hunter; player.gameObject.SetActive(false); diner.gameObject.SetActive(false); SpawnBots(4); }
            for (int i = 0; i < 160; i++) MovePlates(0.05f);
            return cam;
        }

        public void EditorCam(Vector3 target, float yaw, float pitch, float dist)
        {
            Quaternion rot = Quaternion.Euler(pitch, yaw, 0f);
            cam.transform.position = target + rot * new Vector3(0f, 0f, -dist);
            cam.transform.rotation = rot;
        }

        // ---------------- 傳送帶 ----------------

        float Perimeter() { return 4f * A + 4f * B; }

        void PathPoint(float d, out Vector3 pos, out float yaw)
        {
            float L = Perimeter();
            d = Mathf.Repeat(d, L);
            if (d < 2f * A) { pos = new Vector3(-A + d, BeltTop, -B); yaw = 90f; return; }
            d -= 2f * A;
            if (d < 2f * B) { pos = new Vector3(A, BeltTop, -B + d); yaw = 0f; return; }
            d -= 2f * B;
            if (d < 2f * A) { pos = new Vector3(A - d, BeltTop, B); yaw = 270f; return; }
            d -= 2f * A;
            pos = new Vector3(-A, BeltTop, B - d); yaw = 180f;
        }

        void MovePlates(float dt)
        {
            foreach (var p in plates)
            {
                Vector3 old = p.tr.position;
                p.d += beltSpeed * dt;
                Vector3 pos; float yaw;
                PathPoint(p.d, out pos, out yaw);
                p.vel = dt > 0f ? (pos - old) / dt : Vector3.zero;
                p.tr.position = pos;
                p.tr.rotation = Quaternion.RotateTowards(p.tr.rotation, Quaternion.Euler(0f, yaw, 0f), 120f * dt);
            }
        }

        bool OnBelt(float x, float z)
        {
            bool outer = Mathf.Abs(x) <= A + BeltHalf && Mathf.Abs(z) <= B + BeltHalf;
            bool inner = Mathf.Abs(x) < A - BeltHalf && Mathf.Abs(z) < B - BeltHalf;
            return outer && !inner;
        }

        Vector3 BeltVel(float x, float z)
        {
            if (z < -(B - BeltHalf)) return new Vector3(beltSpeed, 0f, 0f);
            if (x > A - BeltHalf) return new Vector3(0f, 0f, beltSpeed);
            if (z > B - BeltHalf) return new Vector3(-beltSpeed, 0f, 0f);
            return new Vector3(0f, 0f, -beltSpeed);
        }

        Plate PlateUnder(Vector3 p)
        {
            foreach (var pl in plates)
            {
                float dx = pl.tr.position.x - p.x, dz = pl.tr.position.z - p.z;
                if (dx * dx + dz * dz < 1.35f * 1.35f) return pl;
            }
            return null;
        }

        float GroundY(Vector3 p, Plate under)
        {
            if (under != null) return PlateTop;
            if (OnBelt(p.x, p.z)) return BeltTop;
            if (Mathf.Abs(p.x) < A - 1.8f && Mathf.Abs(p.z) < B - 1.8f) return 0.5f;
            return 0f;
        }

        // ---------------- 每幀 ----------------

        void Update()
        {
            if (!In.Ready || root == null) return;
            In.Tick();
            float dt = Time.deltaTime;
            if (toastT > 0f) toastT -= dt;
            if (In.Down(K.F1)) debugView = !debugView;

            MovePlates(dt);

            if (phase == Phase.Menu)
            {
                if (In.Down(K.Digit1)) StartRound(Role.Hider);
                else if (In.Down(K.Digit2)) StartRound(Role.Hunter);
                return;
            }
            if (role == Role.Hunter && (phase == Phase.Prep || phase == Phase.Hunt))
            {
                timer -= dt;
                if (phase == Phase.Hunt) survived += dt;
                HunterControl(dt);
                if (phase == Phase.Prep && timer <= 0f)
                {
                    phase = Phase.Hunt; timer = hunterTime;
                    foreach (var p in plates) foreach (var s in p.slots) if (s.marker != null) s.marker.gameObject.SetActive(false);
                    Toast("開吃！左鍵擠醬油打假壽司，打錯會浪費醬油。");
                }
                else if (phase == Phase.Hunt && timer <= 0f) { phase = Phase.Lose; Sfx.Beep(200f, 0.5f, 0.3f); }
                return;
            }

            if (phase == Phase.Prep || phase == Phase.Hunt)
            {
                timer -= dt;
                if (phase == Phase.Hunt) survived += dt;
                PlayerControl(dt);
                PaintControl();
                if (phase == Phase.Prep && (timer <= 0f || In.Down(K.Space)))
                {
                    phase = Phase.Hunt; timer = huntTime; Sfx.Beep(520f, 0.3f, 0.3f);
                    foreach (var p in plates) foreach (var s in p.slots) if (s.marker != null) s.marker.gameObject.SetActive(false);
                    Toast("食客入座了！黃圈是他正在看的地方。");
                }
                else if (phase == Phase.Hunt && timer <= 0f)
                {
                    phase = Phase.Win; Sfx.Beep(1040f, 0.4f, 0.35f);
                    Toast("");
                }
            }
            else if (In.Down(K.R))
            {
                Restart();
            }
        }

        void PlayerControl(float dt)
        {
            if (phase == Phase.Prep)
            {
                if (In.Down(K.Digit1) && playerShape != ShapeKind.Nigiri) { playerShape = ShapeKind.Nigiri; Detach(); SpawnPlayer(player.position); }
                if (In.Down(K.Digit2) && playerShape != ShapeKind.Maki) { playerShape = ShapeKind.Maki; Detach(); SpawnPlayer(player.position); }
            }

            Vector3 mv = Vector3.zero;
            if (In.Held(K.W)) mv.z += 1f;
            if (In.Held(K.S)) mv.z -= 1f;
            if (In.Held(K.D)) mv.x += 1f;
            if (In.Held(K.A)) mv.x -= 1f;
            playerMoving = mv.sqrMagnitude > 0f;
            Vector3 pos = player.position;

            if (playerMoving)
            {
                Detach();
                Vector3 f = Quaternion.Euler(0f, camYaw, 0f) * mv.normalized;
                float sp = In.Held(K.Shift) ? 3.6f : 2.2f;
                pos += f * sp * dt;
                float want = Mathf.Atan2(-f.z, f.x) * Mathf.Rad2Deg;
                playerYaw = Mathf.MoveTowardsAngle(playerYaw, want, 540f * dt);
            }
            if (attached == null)
            {
                if (In.Held(K.Q)) playerYaw -= 120f * dt;
                if (In.Held(K.E)) playerYaw += 120f * dt;
            }

            if (In.Down(K.G) && attached == null)
            {
                Slot best = null; float bd = 1.0f;
                foreach (var p in plates) foreach (var s in p.slots)
                {
                    if (s.sushi != null) continue;
                    float d = Vector3.Distance(new Vector3(s.tr.position.x, 0f, s.tr.position.z), new Vector3(pos.x, 0f, pos.z));
                    if (d < bd) { bd = d; best = s; }
                }
                if (best != null) { attached = best; Toast("補位成功。動一下就會離開盤子。"); }
                else Toast("附近沒有空位。靠近缺一個壽司的盤子再按 G。");
            }

            if (attached != null)
            {
                if (attached.sushi != null) { Detach(); }
                else
                {
                    player.SetPositionAndRotation(attached.tr.position, attached.tr.rotation);
                    playerYaw = player.eulerAngles.y;
                    playerAttached = true;
                    return;
                }
            }
            playerAttached = false;

            Plate under = PlateUnder(pos);
            if (under != null) pos += under.vel * dt;
            else if (OnBelt(pos.x, pos.z)) pos += BeltVel(pos.x, pos.z) * dt;
            pos.x = Mathf.Clamp(pos.x, -18.5f, 18.5f);
            pos.z = Mathf.Clamp(pos.z, -10.3f, 10.3f);
            pos.y = Mathf.Lerp(pos.y, GroundY(pos, under), Mathf.Min(1f, 14f * dt));
            player.SetPositionAndRotation(pos, Quaternion.Euler(0f, playerYaw, 0f));
        }

        void Detach() { attached = null; playerAttached = false; }

        void PaintControl()
        {
            Vector2 mp = In.MousePos;
            bool overHud = mp.y < 118f * (Screen.height / 720f);
            if (In.Down(K.LeftBracket)) brush = Mathf.Max(0.03f, brush - 0.02f);
            if (In.Down(K.RightBracket)) brush = Mathf.Min(0.4f, brush + 0.02f);
            if (In.Down(K.Z)) { if (!playerPaint.Undo()) Toast("沒有可以撤銷的了。"); }
            if (In.Down(K.F)) { playerPaint.PushUndo(); playerPaint.Fill(paintColor); }

            if (In.Down(K.C) && !overHud)
            {
                Physics.SyncTransforms();
                RaycastHit hit;
                if (Physics.Raycast(cam.ScreenPointToRay(mp), out hit, 300f))
                {
                    var pt = hit.collider.GetComponentInParent<Paintable>();
                    if (pt != null) paintColor = pt.Sample(hit.point);
                    else
                    {
                        var r = hit.collider.GetComponent<Renderer>();
                        if (r != null) { Color c = Mats.GetColor(r.sharedMaterial); c.a = 1f; paintColor = c; }
                    }
                    Toast("已取色。");
                }
            }

            if (In.LmbDown && !overHud)
            {
                stroke = true; lastMouse = mp;
                Sfx.Beep(700f, 0.03f, 0.12f);
                playerPaint.PushUndo();
                Physics.SyncTransforms();
                DabAt(mp);
            }
            else if (stroke && In.LmbHeld)
            {
                Physics.SyncTransforms();
                float dist = (mp - lastMouse).magnitude;
                int steps = Mathf.Clamp(Mathf.CeilToInt(dist / 6f), 1, 24);
                for (int i = 1; i <= steps; i++) DabAt(Vector2.Lerp(lastMouse, mp, i / (float)steps));
                lastMouse = mp;
            }
            if (!In.LmbHeld) stroke = false;
            playerPaint.Flush();
        }

        void DabAt(Vector2 sp)
        {
            RaycastHit hit;
            if (playerPaint.meshCol != null && playerPaint.meshCol.Raycast(cam.ScreenPointToRay(sp), out hit, 300f))
                playerPaint.Dab(hit.point, hit.normal, brush, paintColor);
        }

        void LateUpdate()
        {
            if (!In.Ready || cam == null || root == null) return;
            if (phase == Phase.Win || phase == Phase.Lose) camYaw += 35f * Time.deltaTime;
            else if (In.RmbHeld)
            {
                Vector2 d = In.MouseDelta;
                camYaw += d.x * 0.25f;
                camPitch = Mathf.Clamp(camPitch - d.y * 0.2f, 6f, 86f);
            }
            float sc = In.Scroll;
            if (Mathf.Abs(sc) > 0.01f) camDist = Mathf.Clamp(camDist - Mathf.Sign(sc) * 0.7f, 1.6f, 16f);
            if (role == Role.Hider && player != null && player.gameObject.activeSelf) camTarget = player.position + Vector3.up * 0.3f;
            Quaternion rot = Quaternion.Euler(camPitch, camYaw, 0f);
            cam.transform.position = camTarget + rot * new Vector3(0f, 0f, -camDist);
            cam.transform.rotation = rot;
        }

        // ---------------- 給食客呼叫 ----------------

        public void Toast(string s) { toast = s; toastT = 5f; }

        public void Caught()
        {
            if (phase != Phase.Hunt) return;
            phase = Phase.Lose; Sfx.Beep(200f, 0.5f, 0.3f);
            if (player != null) player.gameObject.SetActive(false);
            Toast("");
        }

        // ---------------- 介面 ----------------

        void EnsureStyles()
        {
            if (sLabel != null) return;
            font = Font.CreateDynamicFontFromOSFont(new[] { "Microsoft JhengHei", "Microsoft YaHei", "PingFang TC", "PingFang SC", "Heiti TC", "Hiragino Sans", "Noto Sans CJK TC", "Arial" }, 18);
            sLabel = new GUIStyle(GUI.skin.label) { font = font, fontSize = 18, richText = true, wordWrap = true };
            sLabel.normal.textColor = Color.white;
            sSmall = new GUIStyle(sLabel) { fontSize = 14 };
            sSmall.normal.textColor = new Color(1f, 0.95f, 0.85f);
            sBig = new GUIStyle(sLabel) { fontSize = 40, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
        }

        void Box(Rect r, Color c)
        {
            var old = GUI.color; GUI.color = c;
            GUI.DrawTexture(r, Texture2D.whiteTexture);
            GUI.color = old;
        }

        void OnGUI()
        {
            if (root == null) return;
            EnsureStyles();
            float sc = Screen.height / 720f;
            GUI.matrix = Matrix4x4.Scale(new Vector3(sc, sc, 1f));
            float W = Screen.width / sc, H = 720f;
            Color panel = new Color(0.13f, 0.08f, 0.06f, 0.88f);
            Color gold = new Color(0.92f, 0.74f, 0.36f);

            if (phase == Phase.Menu)
            {
                Box(new Rect(W / 2f - 320f, H / 2f - 190f, 640f, 380f), panel);
                Box(new Rect(W / 2f - 320f, H / 2f - 190f, 640f, 3f), gold);
                Box(new Rect(W / 2f - 320f, H / 2f + 187f, 640f, 3f), gold);
                GUI.Label(new Rect(W / 2f - 320f, H / 2f - 170f, 640f, 70f), "別吃壽司", sBig);
                var mc = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter, fontSize = 22 };
                var ms2 = new GUIStyle(sSmall) { alignment = TextAnchor.MiddleCenter };
                Rect r1 = new Rect(W / 2f - 270f, H / 2f - 70f, 250f, 150f), r2 = new Rect(W / 2f + 20f, H / 2f - 70f, 250f, 150f);
                Box(r1, new Color(0.80f, 0.30f, 0.20f, 0.95f)); Box(r2, new Color(0.18f, 0.28f, 0.52f, 0.95f));
                GUI.Label(new Rect(r1.x, r1.y + 20f, r1.width, 50f), "當壽司", mc);
                GUI.Label(new Rect(r1.x + 10f, r1.y + 70f, r1.width - 20f, 70f), "把自己塗成周圍的樣子，別被食客發現（按 1）", ms2);
                GUI.Label(new Rect(r2.x, r2.y + 20f, r2.width, 50f), "當食客", mc);
                GUI.Label(new Rect(r2.x + 10f, r2.y + 70f, r2.width - 20f, 70f), "找出混在裡面的假壽司，擠醬油打它（按 2）", ms2);
                if (GUI.Button(r1, GUIContent.none, GUIStyle.none)) StartRound(Role.Hider);
                if (GUI.Button(r2, GUIContent.none, GUIStyle.none)) StartRound(Role.Hunter);
                GUI.Label(new Rect(W / 2f - 320f, H / 2f + 120f, 640f, 40f), "單人練習版：對手由電腦控制", ms2);
                return;
            }
            if (role == Role.Hunter && phase == Phase.Prep)
            {
                Box(new Rect(0f, 0f, W, H), new Color(0.05f, 0.03f, 0.02f, 0.97f));
                GUI.Label(new Rect(0f, H / 2f - 60f, W, 70f), "壽司們正在躲藏…", sBig);
                var pc = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter, fontSize = 26 };
                GUI.Label(new Rect(0f, H / 2f + 20f, W, 40f), Mathf.Max(0, Mathf.CeilToInt(timer)).ToString(), pc);
                return;
            }

            // 頂部
            Box(new Rect(W / 2f - 190f, 10f, 380f, 46f), panel);
            Box(new Rect(W / 2f - 190f, 54f, 380f, 2f), gold);
            string title = phase == Phase.Prep ? "準備中" : phase == Phase.Hunt ? "用餐中" : phase == Phase.Win ? "結束" : "結束";
            int t = Mathf.Max(0, Mathf.CeilToInt(timer));
            var mid = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter, fontSize = 22 };
            GUI.Label(new Rect(W / 2f - 190f, 10f, 380f, 44f), title + "　" + (t / 60) + ":" + (t % 60).ToString("00"), mid);

            if (phase == Phase.Hunt && diner != null && role == Role.Hider)
            {
                float s = Mathf.Clamp01(diner.suspicion);
                Box(new Rect(W / 2f - 150f, 64f, 300f, 14f), panel);
                Box(new Rect(W / 2f - 148f, 66f, 296f * s, 10f), Color.Lerp(new Color(1f, 0.85f, 0.3f), new Color(1f, 0.2f, 0.15f), s));
                GUI.Label(new Rect(W / 2f + 158f, 58f, 120f, 26f), "食客注意力 " + diner.stateLabel, sSmall);
            }

            if (toastT > 0f && toast.Length > 0)
            {
                Box(new Rect(W / 2f - 330f, 92f, 660f, 40f), panel);
                var c = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter };
                GUI.Label(new Rect(W / 2f - 330f, 92f, 660f, 40f), toast, c);
            }

            if (role == Role.Hunter && phase == Phase.Hunt)
            {
                Box(new Rect(0f, H - 118f, W, 118f), panel);
                Box(new Rect(0f, H - 118f, W, 2f), gold);
                GUI.Label(new Rect(20f, H - 106f, 120f, 30f), "醬油", sLabel);
                for (int i = 0; i < MaxAmmo; i++)
                    Box(new Rect(90f + i * 34f, H - 104f, 26f, 26f), i < ammo ? new Color(0.35f, 0.16f, 0.08f) : new Color(1f, 1f, 1f, 0.15f));
                GUI.Label(new Rect(320f, H - 106f, 400f, 30f), "已找到 " + found + " / " + bots.Count, sLabel);
                GUI.Label(new Rect(20f, H - 62f, W - 40f, 50f), "WASD 移動視角　右鍵拖曳 轉鏡頭　滾輪 縮放　左鍵 擠醬油\n假壽司的顏色、花紋會有破綻，仔細看。每 25 秒會有一個壽司吹口哨。", sSmall);
            }

            // 底部：調色盤
            if (role == Role.Hider && (phase == Phase.Prep || phase == Phase.Hunt))
            {
                Box(new Rect(0f, H - 118f, W, 118f), panel);
                Box(new Rect(0f, H - 118f, W, 2f), gold);
                float x = 20f, y = H - 104f;
                Box(new Rect(x - 3f, y - 3f, 62f, 62f), gold);
                Box(new Rect(x, y, 56f, 56f), paintColor);
                x += 78f;
                for (int i = 0; i < palette.Length; i++)
                {
                    var r = new Rect(x + i * 44f, y + 8f, 38f, 38f);
                    Box(new Rect(r.x - 1f, r.y - 1f, r.width + 2f, r.height + 2f), new Color(0f, 0f, 0f, 0.6f));
                    Box(r, palette[i]);
                    if (GUI.Button(r, GUIContent.none, GUIStyle.none)) paintColor = palette[i];
                }
                GUI.Label(new Rect(x + palette.Length * 44f + 16f, y + 12f, 260f, 30f), "筆刷 " + Mathf.RoundToInt(brush * 100f) + "　身形 " + (playerShape == ShapeKind.Nigiri ? "握壽司" : "卷"), sLabel);
                string help = "WASD 移動　Shift 跑　Q/E 轉身　右鍵拖曳 轉鏡頭　滾輪 縮放　左鍵 塗色　C 取色　[ ] 筆刷大小　F 整個塗滿　Z 撤銷　G 補位";
                if (phase == Phase.Prep) help += "　1/2 換身形　空白鍵 提前開始";
                GUI.Label(new Rect(20f, H - 38f, W - 40f, 30f), help, sSmall);
            }

            // 結算
            if (phase == Phase.Win || phase == Phase.Lose)
            {
                Box(new Rect(W / 2f - 280f, H / 2f - 130f, 560f, 260f), panel);
                Box(new Rect(W / 2f - 280f, H / 2f - 130f, 560f, 3f), gold);
                Box(new Rect(W / 2f - 280f, H / 2f + 127f, 560f, 3f), gold);
                string endTitle = role == Role.Hider ? (phase == Phase.Win ? "你活下來了！" : "被吃掉了…") : (phase == Phase.Win ? "全部找到了！" : "時間到，壽司贏了");
                GUI.Label(new Rect(W / 2f - 280f, H / 2f - 115f, 560f, 70f), endTitle, sBig);
                var c = new GUIStyle(sLabel) { alignment = TextAnchor.MiddleCenter, fontSize = 20 };
                int score = Mathf.RoundToInt(survived * 10f);
                if (role == Role.Hider)
                {
                    GUI.Label(new Rect(W / 2f - 280f, H / 2f - 30f, 560f, 34f), "存活 " + Mathf.FloorToInt(survived) + " 秒　得分 " + score, c);
                    GUI.Label(new Rect(W / 2f - 280f, H / 2f + 6f, 560f, 34f), "最危險的一刻：食客注意力 " + Mathf.RoundToInt(Mathf.Clamp01(maxSuspicion) * 100f) + "%", c);
                }
                else GUI.Label(new Rect(W / 2f - 280f, H / 2f - 30f, 560f, 34f), "找到 " + found + " / " + bots.Count + "　用時 " + Mathf.FloorToInt(survived) + " 秒", c);
                GUI.Label(new Rect(W / 2f - 280f, H / 2f + 60f, 560f, 34f), "按 R 回到選單", c);
            }

            if (debugView && diner != null && diner.rt != null)
            {
                GUI.DrawTexture(new Rect(W - 330f, 70f, 320f, 240f), diner.rt);
                GUI.Label(new Rect(W - 330f, 312f, 320f, 26f), "食客視角　差異值 " + diner.lastDiff.ToString("0.0"), sSmall);
            }
        }
    }
}
