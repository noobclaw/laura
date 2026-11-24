// The 3D store: an American-style supermarket built from the market kit, with rigged shoppers and staff.
// It only shows what the rule core says; a plain class so the cloud build can also drive it for screenshots.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;

namespace Souq
{
    public static class Kit
    {
        static readonly Dictionary<string, Material> mk = new Dictionary<string, Material>();
        static readonly Dictionary<string, GameObject> src = new Dictionary<string, GameObject>();
        public static Material Lit, Emis, Fade;
        public static int Missing;
        public static void Init()
        {
            mk.Clear(); src.Clear(); Missing = 0;
            Lit = Resources.Load<Material>("BaseLit"); Emis = Resources.Load<Material>("BaseEmis"); Fade = Resources.Load<Material>("BaseFade");
            if (Emis == null) Emis = Lit; if (Fade == null) Fade = Lit;
        }
        public static void SetColor(Material m, Color c) { if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c); if (m.HasProperty("_Color")) m.SetColor("_Color", c); }
        public static Material Mat(Color c, float smooth = 0.2f)
        {
            var m = new Material(Lit); SetColor(m, c); if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smooth); return m;
        }
        public static Material Glow(Color c, float power = 1.7f)
        {
            var m = new Material(Emis); SetColor(m, c);
            m.EnableKeyword("_EMISSION"); if (m.HasProperty("_EmissionColor")) m.SetColor("_EmissionColor", c * power);
            return m;
        }
        public static Material Soft(Color c) { var m = new Material(Fade); SetColor(m, c); return m; }
        /// A kit or ground material by name; null when the build has none.
        public static Material MkMat(string name)
        {
            Material m; if (mk.TryGetValue(name, out m)) return m;
            m = Resources.Load<Material>("MkMat/" + name); mk[name] = m; return m;
        }
        /// A ground material repeated every `metres` across a surface of the given size.
        public static Material Tiled(string name, float sizeX, float sizeZ, float metres, Color fallback)
        {
            var b = MkMat(name); if (b == null) return Mat(fallback, 0.3f);
            var m = new Material(b); var sc = new Vector2(sizeX / metres, sizeZ / metres);
            if (m.HasProperty("_BaseMap")) m.SetTextureScale("_BaseMap", sc); m.mainTextureScale = sc; return m;
        }
        public static void Kill(UnityEngine.Object o) { if (o == null) return; if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o); }
        public static Bounds BoundsOf(GameObject g)
        {
            var rs = g.GetComponentsInChildren<Renderer>(); if (rs.Length == 0) return new Bounds(g.transform.position, Vector3.one * 0.1f);
            var b = rs[0].bounds; for (int i = 1; i < rs.Length; i++) b.Encapsulate(rs[i].bounds); return b;
        }
        static Material Resolve(Renderer r, Material current)
        {
            string n = r.gameObject.name; int i = n.IndexOf("__", StringComparison.Ordinal); Material m = null;
            if (i >= 0) m = MkMat(n.Substring(i + 2));
            if (m == null && current != null) { string cn = current.name.Replace(" (Instance)", ""); m = MkMat(cn); if (m == null && cn.EndsWith("Mat")) m = MkMat(cn.Substring(0, cn.Length - 3)); }
            return m ?? Lit;
        }
        /// Places a market-kit model at real size: its footprint centred on `pos`, its base on the ground there.
        public static GameObject Mk(string name, Transform parent, Vector3 pos, float rotY, float scale = 1f)
        {
            GameObject s; if (!src.TryGetValue(name, out s)) { s = Resources.Load<GameObject>("Mk/" + name); src[name] = s; if (s == null) { Missing++; Debug.LogWarning("Kit: no model " + name); } }
            GameObject g;
            if (s == null) { g = GameObject.CreatePrimitive(PrimitiveType.Cube); g.transform.localScale = Vector3.one * 0.6f; g.GetComponent<Renderer>().sharedMaterial = Mat(new Color(0.75f, 0.76f, 0.8f)); }
            else
            {
                g = UnityEngine.Object.Instantiate(s);
                foreach (var r in g.GetComponentsInChildren<Renderer>())
                {
                    var cur = r.sharedMaterials; var arr = new Material[cur.Length];
                    for (int i = 0; i < arr.Length; i++) arr[i] = Resolve(r, cur[i]);
                    r.sharedMaterials = arr;
                }
                g.transform.localScale = Vector3.one * scale;
            }
            foreach (var c in g.GetComponentsInChildren<Collider>()) UnityEngine.Object.DestroyImmediate(c);
            g.name = name; g.transform.SetParent(parent, false);
            g.transform.position = Vector3.zero; g.transform.rotation = Quaternion.Euler(0, rotY, 0);
            var b = BoundsOf(g);
            g.transform.position = pos + new Vector3(-b.center.x, -b.min.y, -b.center.z);
            return g;
        }
        public static Vector3 SizeOf(string name) { var g = Mk(name, null, Vector3.zero, 0); var s = BoundsOf(g).size; UnityEngine.Object.DestroyImmediate(g); return s; }
        public static GameObject Box(Transform parent, Vector3 center, Vector3 size, Material m, string name = "box")
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Cube); UnityEngine.Object.DestroyImmediate(g.GetComponent<Collider>());
            g.name = name; g.transform.SetParent(parent, false); g.transform.position = center; g.transform.localScale = size;
            g.GetComponent<Renderer>().sharedMaterial = m; return g;
        }
        public static GameObject Shape(PrimitiveType t, Transform parent, Vector3 center, Vector3 size, Material m)
        {
            var g = GameObject.CreatePrimitive(t); UnityEngine.Object.DestroyImmediate(g.GetComponent<Collider>());
            g.transform.SetParent(parent, false); g.transform.localPosition = center; g.transform.localScale = size;
            g.GetComponent<Renderer>().sharedMaterial = m; return g;
        }
        public static void Tint(GameObject g, Color c)
        {
            var pb = new MaterialPropertyBlock(); pb.SetColor("_BaseColor", c);
            foreach (var r in g.GetComponentsInChildren<Renderer>()) r.SetPropertyBlock(pb);
        }
    }

    /// One rigged person (or a simple stand-in when the character is not in the build).
    public class Person
    {
        public GameObject go; public Transform body; public Animation anim; public bool rig, walking; public float phase, speed = 1;
        static GameObject src; static AnimationClip walk, idle; static bool looked;
        static readonly Color[] Shirt = { new Color(0.86f,0.25f,0.25f), new Color(0.25f,0.50f,0.88f), new Color(0.96f,0.80f,0.30f), new Color(0.30f,0.70f,0.48f), new Color(0.62f,0.42f,0.85f), new Color(0.95f,0.55f,0.25f), new Color(0.92f,0.92f,0.95f), new Color(0.30f,0.34f,0.42f), new Color(0.95f,0.60f,0.72f), new Color(0.35f,0.75f,0.80f) };
        static readonly Color[] Pants = { new Color(0.75f,0.72f,0.62f), new Color(0.30f,0.38f,0.55f), new Color(0.25f,0.25f,0.28f), new Color(0.55f,0.45f,0.35f), new Color(0.50f,0.55f,0.50f) };
        static readonly Color[] Skin = { new Color(1f,0.86f,0.72f), new Color(0.93f,0.74f,0.58f), new Color(0.78f,0.57f,0.42f), new Color(0.58f,0.40f,0.28f), new Color(0.42f,0.28f,0.20f) };

        public static void Reset() { looked = false; src = null; walk = idle = null; }
        static AnimationClip FirstClip(string path) { foreach (var c in Resources.LoadAll<AnimationClip>(path)) if (c != null && !c.name.StartsWith("__preview")) return c; return null; }
        static void Look()
        {
            if (looked) return; looked = true;
            src = Resources.Load<GameObject>("People/Walking"); walk = FirstClip("People/Walking"); idle = FirstClip("People/Idle");
            if (src == null || walk == null || !walk.legacy) { Debug.LogWarning("Person: rigged character unavailable (model " + (src != null) + ", walk " + (walk != null) + "), using stand-ins"); src = null; }
            else Debug.Log("Person: rigged character ready, idle clip " + (idle != null));
        }
        public static bool Rigged { get { Look(); return src != null; } }

        public Person(Transform parent, int look, Color? uniform)
        {
            Look(); go = new GameObject("person"); go.transform.SetParent(parent, false); phase = (look % 97) * 0.13f;
            if (src == null) { Fallback(look, uniform); return; }
            rig = true; body = new GameObject("body").transform; body.SetParent(go.transform, false);
            var m = UnityEngine.Object.Instantiate(src); m.name = "model"; m.transform.SetParent(body, false);
            float sc = 0.95f + ((look * 7) % 11) * 0.011f; body.localScale = Vector3.one * sc;
            anim = m.GetComponent<Animation>(); if (anim == null) anim = m.AddComponent<Animation>();
            anim.playAutomatically = false; anim.cullingType = AnimationCullingType.BasedOnRenderers;
            anim.AddClip(walk, "walk"); anim.AddClip(idle != null ? idle : walk, "idle"); anim["walk"].wrapMode = WrapMode.Loop; anim["idle"].wrapMode = WrapMode.Loop;
            if (idle == null) anim["idle"].speed = 0;
            anim["idle"].time = phase; anim["walk"].time = phase; anim.Play("idle");
            // shirts and trousers vary per person; staff wear the department colour
            Color top = uniform ?? Shirt[look % Shirt.Length], bottom = uniform.HasValue ? new Color(0.20f, 0.22f, 0.28f) : Pants[(look / 3) % Pants.Length];
            foreach (var r in m.GetComponentsInChildren<Renderer>())
            {
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null) continue; string n = mats[i].name.ToLowerInvariant();
                    Color? c = n.Contains("top") || n.Contains("shirt") ? top : n.Contains("bottom") || n.Contains("pant") ? bottom : (Color?)null;
                    if (c.HasValue) { var pb = new MaterialPropertyBlock(); pb.SetColor("_BaseColor", Color.Lerp(Color.white, c.Value, 0.85f) * 1.25f); r.SetPropertyBlock(pb, i); }
                }
                var sk = r as SkinnedMeshRenderer; if (sk != null) { sk.updateWhenOffscreen = false; sk.quality = SkinQuality.Bone2; }
            }
            if (!Application.isPlaying) Sample(0);
        }

        void Fallback(int look, Color? uniform)
        {
            body = new GameObject("body").transform; body.SetParent(go.transform, false);
            var skin = Kit.Mat(Skin[look % Skin.Length], 0.3f); var cl = Kit.Mat(uniform ?? Shirt[look % Shirt.Length], 0.3f); var dark = Kit.Mat(new Color(0.16f, 0.13f, 0.14f), 0.4f);
            Kit.Shape(PrimitiveType.Capsule, body, new Vector3(0, 0.78f, 0), new Vector3(0.46f, 0.52f, 0.34f), cl);
            Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0, 1.52f, 0), new Vector3(0.30f, 0.34f, 0.30f), skin);
            Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0, 1.60f, -0.03f), new Vector3(0.32f, 0.26f, 0.32f), dark);
            Kit.Shape(PrimitiveType.Capsule, body, new Vector3(-0.11f, 0.3f, 0), new Vector3(0.16f, 0.3f, 0.16f), dark); Kit.Shape(PrimitiveType.Capsule, body, new Vector3(0.11f, 0.3f, 0), new Vector3(0.16f, 0.3f, 0.16f), dark);
        }

        public void Sample(float time)
        {
            if (!rig) return; string n = walking ? "walk" : "idle"; var st = anim[n]; if (st == null || st.clip == null) return;
            foreach (AnimationState s in anim) { s.enabled = false; s.weight = 0; }
            st.enabled = true; st.weight = 1; st.time = (time * (walking ? 1.9f : 1f) + phase) % Mathf.Max(0.05f, st.length); anim.Sample(); st.enabled = false;
        }

        /// Switches between walking and standing; `busy` adds a small working motion for staff.
        public void Set(bool walk, bool busy, float time, float dt)
        {
            if (rig)
            {
                if (Application.isPlaying)
                {
                    if (walk != walking || !anim.isPlaying) { walking = walk; anim.CrossFade(walk ? "walk" : "idle", 0.18f); }
                    anim["walk"].speed = 1.9f * speed;
                }
                else { walking = walk; Sample(time); }
                body.localRotation = Quaternion.Euler(busy ? 5f * Mathf.Sin(time * 8f + phase) : 0, busy ? 12f * Mathf.Sin(time * 5f + phase) : 0, 0);
                return;
            }
            walking = walk; float ph = time * 11f + phase;
            body.localPosition = new Vector3(0, walk ? 0.07f * Mathf.Abs(Mathf.Sin(ph)) : busy ? 0.03f * Mathf.Abs(Mathf.Sin(time * 6f)) : 0, 0);
            body.localRotation = Quaternion.Euler(walk ? 6f : busy ? 8f * Mathf.Sin(time * 9f + phase) : 0, 0, walk ? 5f * Mathf.Sin(ph) : 0);
        }
    }

    public class DeptView
    {
        public int d; public Transform root, props, stock; public Vector3 center; public Renderer sign; public Material signMat, tapeMat;
        public Person[] staff = new Person[T.MaxStaff]; public int builtTier = -2, builtRows = -1; public bool builtOpen; public float pop;
        public BoxCollider hit; public readonly List<Vector3> shelfPos = new List<Vector3>(); public readonly List<string> shelfFill = new List<string>();
    }

    public class Actor { public Person p; public GameObject go; public Vector3 target; public bool moving; public GameObject cart, goods, gift, car; public Vector3 carPos; public float carYaw; }

    public class World
    {
        public Transform root; public Camera cam; public Sim sim;
        public DeptView[] depts = new DeptView[T.ND];
        public GameObject[] cashDesk = new GameObject[T.NC]; public Person[] cashStaff = new Person[T.NC]; Renderer[] cashLamp = new Renderer[T.NC];
        public GameObject truck, vip; public Vector3 truckPos = new Vector3(6.4f, 0, -1.3f), vipPos = new Vector3(-6.4f, 0, -1.3f), busPos = new Vector3(8.3f, 0, -4.4f);
        public const float RoadZ = -4.4f;
        readonly Dictionary<int, Actor> actors = new Dictionary<int, Actor>(); readonly List<int> gone = new List<int>();
        Transform slotRoot; int slotsBuilt; float time; Light sun; Material bandMat; int bandStar = -1;
        class Pop { public Transform t; public float age, dur, delay; public Vector3 scale; }
        readonly List<Pop> pops = new List<Pop>();
        public float shake;

        public static readonly Color[] DeptColor =
        {
            new Color(0.30f,0.72f,0.32f), new Color(0.93f,0.62f,0.22f), new Color(0.84f,0.26f,0.28f), new Color(0.22f,0.62f,0.88f),
            new Color(0.30f,0.52f,0.92f), new Color(0.36f,0.78f,0.86f), new Color(0.92f,0.36f,0.56f), new Color(0.96f,0.74f,0.20f),
            new Color(0.72f,0.48f,0.26f), new Color(0.56f,0.42f,0.90f), new Color(0.90f,0.34f,0.72f),
        };
        static readonly Color[] CarTint = { Color.white, new Color(0.95f,0.45f,0.42f), new Color(0.55f,0.70f,1f), new Color(0.85f,0.85f,0.88f), new Color(0.45f,0.47f,0.52f), new Color(1f,0.88f,0.50f), new Color(0.60f,0.85f,0.65f) };
        static readonly Color[] GradeBand = { new Color(0.80f,0.13f,0.15f), new Color(0.12f,0.38f,0.72f), new Color(0.10f,0.55f,0.36f), new Color(0.56f,0.24f,0.70f), new Color(0.85f,0.55f,0.10f), new Color(0.10f,0.12f,0.18f) };

        // what each department is built from: the fixture along its back, and the stock that fills the shelves of the open-shelf kinds
        class Art { public string fixture; public string[] fills; public string[] items; }
        static readonly Art[] Arts =
        {
            new Art { fixture = "ProduceStand_A", items = new[]{ "CrateStack_A" } },
            new Art { fixture = "BreadRack_A", items = new[]{ "CrateStack_A" } },
            new Art { fixture = "ServiceCounter_A", items = new[]{ "CheeseBlock_A" } },
            new Art { fixture = "Freezer_A", items = new[]{ "IceCreamTub_A" } },
            new Art { fixture = "Fridge_A", items = new[]{ "MilkCarton_A" } },
            new Art { fixture = "Fridge_B", items = new[]{ "IceCreamTub_A" } },
            new Art { fixture = "Gondola_B", fills = new[]{ "ShelfFill_I", "ShelfFill_C", "ShelfFill_S", "ShelfFill_I" }, items = new[]{ "ColaCan_A", "JuiceCarton_A" } },
            new Art { fixture = "Gondola_B", fills = new[]{ "ShelfFill_D", "ShelfFill_A", "ShelfFill_K", "ShelfFill_D" }, items = new[]{ "ChipsBag_A", "CerealBox_A" } },
            new Art { fixture = "Gondola_B", fills = new[]{ "ShelfFill_A", "ShelfFill_K", "ShelfFill_E", "ShelfFill_Q", "ShelfFill_R" }, items = new[]{ "SoupCan_A", "CerealBox_A" } },
            new Art { fixture = "Gondola_B", fills = new[]{ "ShelfFill_J", "ShelfFill_S", "ShelfFill_H", "ShelfFill_J" }, items = new[]{ "DetergentJug_A" } },
            new Art { fixture = "Gondola_B", fills = new[]{ "ShelfFill_R", "ShelfFill_E", "ShelfFill_P", "ShelfFill_Q" }, items = new[]{ "DetergentJug_A", "EggCarton_A" } },
        };
        static readonly float[] ShelfY = { 0.17f, 0.59f, 1.01f, 1.44f, 1.87f };
        static readonly float[] SlotX = { -3.06f, -1.02f, 1.02f, 3.06f };
        public static string ItemOf(int d, int k) { var a = Arts[d].items; return a[k % a.Length]; }

        public const float HalfW = 9f, DeptRow0 = 13f, DeptRowGap = 9.5f, CashZ = 4.2f;
        public static Vector3 DeptCenter(int d) => new Vector3(d % 2 == 0 ? -4.5f : 4.5f, 0, DeptRow0 + (d / 2) * DeptRowGap);
        public static float StoreDepth => DeptRow0 + 5 * DeptRowGap + 6.5f;
        public static Vector3 StaffPos(int d, int k) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 1.9f);
        public static Vector3 QueuePos(int d, int k, int q) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 0.75f - q * 0.85f);
        public static Vector3 CashPos(int c) => new Vector3(-7.35f + c * 2.1f, 0, CashZ);
        public static Vector3 CashQueuePos(int c, int q) => CashPos(c) + new Vector3(0.78f, 0, 0.9f + q * 0.8f);
        public static Vector3 SlotPos(int i) => new Vector3(-7.5f + (i % 6) * 3f, 0, -9.0f - (i / 6) * 4.6f);
        public static Vector3 DeptFx(int d) => DeptCenter(d) + new Vector3(0, 1.4f, 3.0f);
        static readonly Vector3 Door = new Vector3(0, 0, 0.2f);

        public World(Sim s) { sim = s; }

        // ---------- build ----------
        public void Build()
        {
            Kit.Init(); Person.Reset();
            root = new GameObject("World").transform;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.86f, 0.90f, 1.00f); RenderSettings.ambientEquatorColor = new Color(0.74f, 0.74f, 0.76f); RenderSettings.ambientGroundColor = new Color(0.46f, 0.44f, 0.42f);
            RenderSettings.fog = false;
            sun = new GameObject("Sun").AddComponent<Light>(); sun.transform.SetParent(root, false);
            sun.type = LightType.Directional; sun.color = new Color(1f, 0.97f, 0.92f); sun.intensity = 1.2f; sun.shadows = LightShadows.Soft; sun.shadowStrength = 0.5f;
            sun.transform.rotation = Quaternion.Euler(52, 24, 0);

            float depth = StoreDepth, lotDepth = 70f;
            // ground: grass beyond, an asphalt lot, the road, a concrete walk and the shop floor
            Kit.Box(root, new Vector3(0, -0.36f, depth / 2 - 20), new Vector3(220, 0.5f, depth + 160), Kit.Mat(new Color(0.36f, 0.52f, 0.30f), 0.05f), "grass");
            Kit.Box(root, new Vector3(0, -0.3f, -lotDepth / 2 - 2.4f), new Vector3(44, 0.5f, lotDepth), Kit.Tiled("G_asphalt", 44, lotDepth, 6f, new Color(0.22f, 0.23f, 0.26f)), "lot");
            Kit.Box(root, new Vector3(0, -0.29f, RoadZ), new Vector3(220, 0.5f, 3.8f), Kit.Tiled("G_asphalt", 220, 3.8f, 6f, new Color(0.18f, 0.19f, 0.22f)), "road");
            var paint = Kit.Mat(new Color(0.93f, 0.90f, 0.80f), 0.1f); var yellow = Kit.Mat(new Color(0.95f, 0.78f, 0.22f), 0.1f);
            for (int i = -14; i <= 14; i++) Kit.Box(root, new Vector3(i * 3.6f, -0.035f, RoadZ), new Vector3(1.6f, 0.02f, 0.13f), yellow, "dash");
            Kit.Box(root, new Vector3(0, -0.2f, -1.25f), new Vector3(HalfW * 2 + 9, 0.5f, 2.5f), Kit.Tiled("G_concrete", HalfW * 2 + 9, 2.5f, 3f, new Color(0.72f, 0.71f, 0.70f)), "walk");
            Kit.Box(root, new Vector3(0, -0.25f, depth / 2), new Vector3(HalfW * 2, 0.5f, depth), Kit.Tiled("G_floor", HalfW * 2, depth, 2.4f, new Color(0.93f, 0.92f, 0.88f)), "floor");
            // walls: white plaster with the brand band; the front is left open so the checkouts stay in view
            var wallSide = Kit.Tiled("G_plaster", depth, 3.4f, 3f, new Color(0.96f, 0.95f, 0.92f)); var wallBack = Kit.Tiled("G_plaster", HalfW * 2, 5f, 3f, new Color(0.96f, 0.95f, 0.92f));
            bandMat = Kit.Mat(GradeBand[0], 0.35f); var trim = Kit.Mat(new Color(0.20f, 0.21f, 0.24f), 0.3f);
            Kit.Box(root, new Vector3(-HalfW - 0.2f, 1.7f, depth / 2), new Vector3(0.4f, 3.4f, depth), wallSide, "wallL");
            Kit.Box(root, new Vector3(HalfW + 0.2f, 1.7f, depth / 2), new Vector3(0.4f, 3.4f, depth), wallSide, "wallR");
            Kit.Box(root, new Vector3(0, 2.5f, depth + 0.2f), new Vector3(HalfW * 2 + 0.8f, 5f, 0.4f), wallBack, "wallBack");
            Kit.Box(root, new Vector3(-HalfW - 0.2f, 3.05f, depth / 2), new Vector3(0.46f, 0.5f, depth + 0.02f), bandMat, "bandL");
            Kit.Box(root, new Vector3(HalfW + 0.2f, 3.05f, depth / 2), new Vector3(0.46f, 0.5f, depth + 0.02f), bandMat, "bandR");
            Kit.Box(root, new Vector3(0, 4.3f, depth + 0.2f), new Vector3(HalfW * 2 + 0.86f, 0.7f, 0.46f), bandMat, "bandBack");
            Kit.Box(root, new Vector3(-HalfW - 0.2f, 3.45f, depth / 2), new Vector3(0.5f, 0.12f, depth + 0.04f), trim, "capL"); Kit.Box(root, new Vector3(HalfW + 0.2f, 3.45f, depth / 2), new Vector3(0.5f, 0.12f, depth + 0.04f), trim, "capR");
            // entrance: pillars, canopy and the store sign, door mats, cart bays
            foreach (float x in new[] { -HalfW - 0.2f, -2.6f, 2.6f, HalfW + 0.2f }) Kit.Box(root, new Vector3(x, 1.7f, 0), new Vector3(0.5f, 3.4f, 0.5f), wallBack, "pillar");
            Kit.Box(root, new Vector3(0, 3.05f, 0), new Vector3(5.7f, 0.9f, 0.5f), bandMat, "lintel");
            Kit.Mk("BrandSign_A", root, new Vector3(0, 3.5f, -0.1f), 180);
            Kit.Mk("DoorMat_A", root, new Vector3(0, 0.005f, 0.9f), 0); Kit.Mk("DoorMat_A", root, new Vector3(0, 0.005f, -0.9f), 0);
            for (int i = 0; i < 4; i++) { Kit.Mk("ShoppingCart_A", root, new Vector3(-3.6f, 0, -0.5f - i * 0.42f), 90); Kit.Mk("ShoppingCart_A", root, new Vector3(3.6f, 0, -0.5f - i * 0.42f), -90); }
            Kit.Mk("BasketStand_A", root, new Vector3(-1.9f, 0, 1.0f), 90); Kit.Mk("VendingMachine_A", root, new Vector3(-8.2f, 0, 1.2f), 90); Kit.Mk("Atm_A", root, new Vector3(8.3f, 0, 1.2f), -90);
            // street dressing
            foreach (float x in new[] { -12f, -4.6f, 4.6f, 12f }) Kit.Mk("StreetLamp_A", root, new Vector3(x, 0, -2.25f), 180);
            Kit.Mk("Bench_A", root, new Vector3(-9.6f, 0, -0.6f), 180); Kit.Mk("Bench_A", root, new Vector3(9.6f, 0, -0.6f), 180);
            Kit.Mk("StreetBin_A", root, new Vector3(-11.2f, 0, -0.6f), 180); Kit.Mk("Planter_A", root, new Vector3(-2.6f, 0, -0.8f), 0); Kit.Mk("Planter_A", root, new Vector3(2.6f, 0, -0.8f), 0);
            for (int i = 0; i < 9; i++) { float z = -8 + i * 9f; Kit.Mk("Tree_A", root, new Vector3(-14.5f - (i % 2) * 2.5f, 0, z), i * 67, 0.8f + (i % 3) * 0.1f); Kit.Mk("Tree_A", root, new Vector3(14.5f + (i % 2) * 2.5f, 0, z + 4), i * 41, 0.8f + ((i + 1) % 3) * 0.1f); }
            for (int i = 0; i < 4; i++) { Kit.Mk("Hedge_A", root, new Vector3(-11f, 0, -8.5f - i * 6f), 90); Kit.Mk("Hedge_A", root, new Vector3(11f, 0, -8.5f - i * 6f), 90); }
            for (int i = 0; i < 3; i++) { Kit.Mk("AreaLightPole_A", root, new Vector3(-9.6f, 0, -11.3f - i * 13.8f), 0); Kit.Mk("AreaLightPole_A", root, new Vector3(9.6f, 0, -11.3f - i * 13.8f), 0); }
            // delivery bay and VIP bay painted on the walk
            Kit.Box(root, new Vector3(truckPos.x, 0.06f, truckPos.z), new Vector3(5.0f, 0.02f, 2.3f), yellow, "truckBay"); Kit.Box(root, new Vector3(truckPos.x, 0.065f, truckPos.z), new Vector3(4.7f, 0.02f, 2.0f), Kit.Mat(new Color(0.55f, 0.54f, 0.53f), 0.1f), "truckBayIn");
            Kit.Box(root, new Vector3(vipPos.x, 0.06f, vipPos.z), new Vector3(5.0f, 0.02f, 2.3f), Kit.Mat(new Color(0.70f, 0.40f, 0.90f), 0.1f), "vipBay"); Kit.Box(root, new Vector3(vipPos.x, 0.065f, vipPos.z), new Vector3(4.7f, 0.02f, 2.0f), Kit.Mat(new Color(0.55f, 0.54f, 0.53f), 0.1f), "vipBayIn");
            Kit.Mk("TrafficCone_A", root, truckPos + new Vector3(-2.7f, 0, -1.0f), 0); Kit.Mk("TrafficCone_A", root, truckPos + new Vector3(2.7f, 0, -1.0f), 0);

            for (int c = 0; c < T.NC; c++) BuildCash(c);
            for (int d = 0; d < T.ND; d++) BuildDept(d);
            slotRoot = new GameObject("Slots").transform; slotRoot.SetParent(root, false);
            SyncStatic(true);
            Debug.Log("World: built, kit models missing = " + Kit.Missing + ", rigged people = " + Person.Rigged);
        }

        void BuildCash(int c)
        {
            var p = CashPos(c); var g = new GameObject("cash" + c); g.transform.SetParent(root, false);
            Kit.Mk(c % 2 == 0 ? "Checkout_A" : "Checkout_B", g.transform, p, 90);
            Kit.Box(g.transform, p + new Vector3(-0.2f, 1.35f, -1.05f), new Vector3(0.06f, 2.7f, 0.06f), Kit.Mat(new Color(0.75f, 0.76f, 0.80f), 0.6f), "pole");
            cashLamp[c] = Kit.Box(g.transform, p + new Vector3(-0.2f, 2.8f, -1.05f), new Vector3(0.5f, 0.5f, 0.12f), Kit.Glow(new Color(0.3f, 1f, 0.6f), 1.5f), "lamp").GetComponent<Renderer>();
            cashStaff[c] = new Person(g.transform, 31 + c * 5, new Color(0.80f, 0.13f, 0.15f)); cashStaff[c].go.transform.position = p + new Vector3(-0.72f, 0, 0.1f); cashStaff[c].go.transform.rotation = Quaternion.Euler(0, 90, 0);
            cashDesk[c] = g;
        }

        void BuildDept(int d)
        {
            var v = new DeptView { d = d, center = DeptCenter(d) }; var g = new GameObject("dept" + d); g.transform.SetParent(root, false); v.root = g.transform;
            var col = DeptColor[d];
            // floor tape around the department, and the hanging fascia that names it
            v.tapeMat = Kit.Mat(col, 0.3f); float w = 8.3f, dz = 7.4f; var c0 = v.center + new Vector3(0, 0.006f, 0.55f);
            Kit.Box(g.transform, c0 + new Vector3(0, 0, -dz / 2), new Vector3(w, 0.012f, 0.14f), v.tapeMat, "tape"); Kit.Box(g.transform, c0 + new Vector3(0, 0, dz / 2), new Vector3(w, 0.012f, 0.14f), v.tapeMat, "tape");
            Kit.Box(g.transform, c0 + new Vector3(-w / 2, 0, 0), new Vector3(0.14f, 0.012f, dz), v.tapeMat, "tape"); Kit.Box(g.transform, c0 + new Vector3(w / 2, 0, 0), new Vector3(0.14f, 0.012f, dz), v.tapeMat, "tape");
            v.signMat = Kit.Glow(col, 0.9f);
            v.sign = Kit.Box(g.transform, v.center + new Vector3(0, 2.95f, 4.0f), new Vector3(8.1f, 0.7f, 0.16f), v.signMat, "fascia").GetComponent<Renderer>();
            Kit.Box(g.transform, v.center + new Vector3(0, 3.36f, 4.0f), new Vector3(8.2f, 0.1f, 0.22f), Kit.Mat(new Color(0.96f, 0.96f, 0.96f), 0.4f), "fasciaTop");
            var pole = Kit.Mat(new Color(0.78f, 0.79f, 0.82f), 0.6f);
            Kit.Box(g.transform, v.center + new Vector3(-4.0f, 1.65f, 4.0f), new Vector3(0.1f, 3.3f, 0.1f), pole, "pole"); Kit.Box(g.transform, v.center + new Vector3(4.0f, 1.65f, 4.0f), new Vector3(0.1f, 3.3f, 0.1f), pole, "pole");
            v.props = new GameObject("props").transform; v.props.SetParent(g.transform, false);
            v.stock = new GameObject("stock").transform; v.stock.SetParent(g.transform, false);
            for (int k = 0; k < T.MaxStaff; k++)
            {
                v.staff[k] = new Person(g.transform, d * 7 + k, Color.Lerp(col, Color.black, 0.15f));
                v.staff[k].go.transform.position = StaffPos(d, k); v.staff[k].go.transform.rotation = Quaternion.Euler(0, 180, 0);
            }
            v.hit = g.AddComponent<BoxCollider>(); v.hit.center = v.center + new Vector3(0, 1.2f, 0.55f); v.hit.size = new Vector3(8.3f, 2.8f, 7.4f);
            depts[d] = v;
        }

        static void Clear(Transform t) { for (int i = t.childCount - 1; i >= 0; i--) UnityEngine.Object.DestroyImmediate(t.GetChild(i).gameObject); }
        void AddPop(GameObject g, float delay, float dur = 0.34f) { var t = g.transform; pops.Add(new Pop { t = t, scale = t.localScale, delay = delay, dur = dur }); t.localScale = t.localScale * 0.001f; }

        /// How many shelf rows show stock at this level: every shelf unit starts with two rows and fills as the level climbs to the next bonus.
        static int RowsFor(int level, int tier, int units)
        {
            int lo = tier == 0 ? 1 : T.TierLv[tier - 1]; int hi = tier >= T.TierLv.Length ? T.MaxLevel : T.TierLv[tier];
            float f = Mathf.Clamp01((level - lo) / (float)Mathf.Max(1, hi - lo)); if (tier >= 3) f = 1;
            return Mathf.Clamp(units * 2 + Mathf.FloorToInt(f * units * 3 + 0.001f), 0, units * 5);
        }
        static int UnitsFor(int tier) => Mathf.Min(4, 1 + tier);

        void RebuildProps(DeptView v, bool open, int tier, bool animate)
        {
            Clear(v.props); Clear(v.stock); v.shelfPos.Clear(); v.shelfFill.Clear(); pops.RemoveAll(p => p.t == null);
            v.builtOpen = open; v.builtTier = tier; v.builtRows = 0;
            var col = DeptColor[v.d]; var grey = new Color(0.55f, 0.56f, 0.60f);
            Kit.SetColor(v.tapeMat, open ? col : grey); Kit.SetColor(v.signMat, open ? col : grey); v.signMat.SetColor("_EmissionColor", open ? col * 0.9f : Color.black);
            if (!open)
            {
                // a space waiting for its fit-out
                Kit.Mk("PalletStack_A", v.props, v.center + new Vector3(-2.2f, 0, 2.6f), 15); Kit.Mk("CardboardBoxes_A", v.props, v.center + new Vector3(0.4f, 0, 3.0f), -20);
                Kit.Mk("RollCage_A", v.props, v.center + new Vector3(2.4f, 0, 2.4f), 70); Kit.Mk("WetFloorSign_A", v.props, v.center + new Vector3(-0.8f, 0, 0.6f), 30);
                Kit.Mk("TrafficCone_A", v.props, v.center + new Vector3(-3.2f, 0, -1.2f), 0); Kit.Mk("TrafficCone_A", v.props, v.center + new Vector3(3.2f, 0, -1.2f), 0);
                return;
            }
            var art = Arts[v.d]; int units = UnitsFor(tier); float backZ = v.center.z + 3.55f;
            for (int u = 0; u < units; u++)
            {
                var pos = new Vector3(v.center.x + SlotX[u], 0, backZ);
                var fx = Kit.Mk(art.fixture, v.props, pos, 180); var b = Kit.BoundsOf(fx);
                // push the unit back so its rear sits on the line, whatever its depth
                fx.transform.position += new Vector3(0, 0, backZ - b.max.z); b = Kit.BoundsOf(fx);
                if (animate) AddPop(fx, 0.06f * u, 0.42f);
                if (art.fills != null) for (int r = 0; r < ShelfY.Length; r++) { v.shelfPos.Add(new Vector3(b.center.x, ShelfY[r] + 0.012f, b.min.z + 0.30f)); v.shelfFill.Add(art.fills[(u + r) % art.fills.Length]); }
            }
            // extras that arrive with later bonus levels
            if (tier >= 1) Kit.Mk("CrateStack_A", v.props, v.center + new Vector3(-3.75f, 0, 2.2f), 0);
            if (tier >= 2) Kit.Mk("AisleSign_" + "ABCD"[v.d % 4], v.props, v.center + new Vector3(0, 3.5f, 2.2f), 180);
            if (tier >= 4) Kit.Mk("GondolaEnd_A", v.props, v.center + new Vector3(3.8f, 0, 1.6f), -90);
            if (tier >= 5) Kit.Mk(v.d % 2 == 0 ? "Poster_A" : "Poster_C", v.props, v.center + new Vector3(-2.0f, 3.5f, 3.95f), 180);
            if (tier >= 6) Kit.Mk("NeonSign_" + "ABC"[v.d % 3], v.props, v.center + new Vector3(2.0f, 3.5f, 3.9f), 180);
            v.pop = animate ? 1f : 0f;
        }

        /// Adds shelf rows up to the wanted count; each new row pops in.
        void SyncStock(DeptView v, int level, int tier, bool animate)
        {
            if (v.shelfPos.Count == 0) return; int units = UnitsFor(tier); int want = RowsFor(level, tier, units); int added = 0;
            while (v.builtRows < want && v.builtRows < v.shelfPos.Count)
            {
                // fill bottom rows of every unit first: row index runs across units, then up
                int i = v.builtRows; int u = i % units, r = i / units; int idx = u * ShelfY.Length + r; if (idx >= v.shelfPos.Count) break;
                var p = v.shelfPos[idx]; string name = v.shelfFill[idx];
                var g = Kit.Mk(name, v.stock, p, 180); var b = Kit.BoundsOf(g);
                if (b.size.x < 1.3f) { g.transform.position += new Vector3(-0.49f, 0, 0); var g2 = Kit.Mk(name, v.stock, p + new Vector3(0.49f, 0, 0), 180); if (animate) AddPop(g2, 0.05f * added + 0.04f, 0.3f); }
                if (animate) AddPop(g, 0.05f * added, 0.3f);
                v.builtRows++; added++;
            }
        }

        Actor MakeActor(Cust c)
        {
            var a = new Actor(); a.p = new Person(root, c.look, null); a.go = a.p.go;
            // a cart goes ahead of each shopper; goods appear in it once they have something to pay for
            a.cart = Kit.Mk("ShoppingCart_A", a.go.transform, new Vector3(0, 0, 0.82f), 180);
            a.goods = new GameObject("goods"); a.goods.transform.SetParent(a.cart.transform, false);
            for (int i = 0; i < 3; i++) { var it = Kit.Mk(ItemOf(c.look % T.ND, i + c.look), a.goods.transform, new Vector3(-0.1f + 0.1f * i, 0.45f, 0.70f + 0.14f * i), 30 * i, 1.25f); }
            a.goods.SetActive(false);
            a.gift = Kit.Shape(PrimitiveType.Cube, a.go.transform, new Vector3(0, 2.3f, 0), Vector3.one * 0.42f, Kit.Glow(new Color(1f, 0.35f, 0.6f), 1.8f)); a.gift.SetActive(false);
            a.gift.AddComponent<SphereCollider>().radius = 1.6f;
            if (c.slot >= 0)
            {
                a.car = new GameObject("car"); a.car.transform.SetParent(root, false);
                var body = Kit.Mk(c.look % 2 == 0 ? "Car_A" : "Car_B", a.car.transform, Vector3.zero, 0, 0.8f); Kit.Tint(body, CarTint[c.look % CarTint.Length]);
                a.carPos = new Vector3(-30, 0, RoadZ); a.car.transform.position = a.carPos; a.carYaw = 90;
            }
            a.go.transform.position = c.slot >= 0 ? new Vector3(-30, 0, RoadZ) : busPos; a.go.SetActive(c.slot < 0);
            return a;
        }

        // ---------- per frame ----------
        public void SyncStatic(bool force = false, bool animate = true)
        {
            var s = sim.s;
            for (int d = 0; d < T.ND; d++)
            {
                var v = depts[d]; int tier = T.Tier(s.dLevel[d]); bool fresh = force || v.builtOpen != s.dOpen[d] || v.builtTier != tier;
                if (fresh) RebuildProps(v, s.dOpen[d], tier, animate && !force);
                if (s.dOpen[d]) SyncStock(v, s.dLevel[d], tier, animate && !force);
                for (int k = 0; k < T.MaxStaff; k++) v.staff[k].go.SetActive(s.dOpen[d] && k < s.dStaff[d]);
            }
            for (int c = 0; c < T.NC; c++) cashDesk[c].SetActive(s.cLevel[c] > 0);
            if (s.star != bandStar) { bandStar = s.star; Kit.SetColor(bandMat, GradeBand[Mathf.Clamp(s.star, 0, GradeBand.Length - 1) % GradeBand.Length]); }
            int want = sim.ParkSpaces;
            if (want != slotsBuilt)
            {
                var line = Kit.Mat(new Color(0.93f, 0.92f, 0.86f), 0.1f);
                for (int i = slotsBuilt; i < want; i++)
                {
                    var p = SlotPos(i);
                    Kit.Box(slotRoot, p + new Vector3(-1.5f, -0.04f, 0), new Vector3(0.1f, 0.02f, 4.2f), line, "line"); Kit.Box(slotRoot, p + new Vector3(1.5f, -0.04f, 0), new Vector3(0.1f, 0.02f, 4.2f), line, "line");
                    var ws = Kit.Mk("WheelStop_A", slotRoot, p + new Vector3(0, -0.05f, -1.85f), 0); if (!force && animate) AddPop(ws, 0.03f * (i - slotsBuilt));
                }
                slotsBuilt = want;
            }
        }

        static Vector3 Along(Vector3 a, Vector3 b, Vector3 c, float t)
        {
            float l1 = Vector3.Distance(a, b), l2 = Vector3.Distance(b, c); float d = t * (l1 + l2);
            return d <= l1 ? Vector3.Lerp(a, b, l1 > 0 ? d / l1 : 1) : Vector3.Lerp(b, c, l2 > 0 ? (d - l1) / l2 : 1);
        }

        Vector3 Target(Cust c, out bool busy)
        {
            busy = false; float t = c.dur > 0 ? Mathf.Clamp01(c.t / c.dur) : 1;
            Vector3 slot = c.slot >= 0 ? SlotPos(c.slot) + new Vector3(1.15f, 0, 0.6f) : busPos; var lane = new Vector3(slot.x, 0, -2.4f);
            switch (c.st)
            {
                case CS.CarIn: return slot;
                case CS.WalkIn: return Along(slot, lane, Door + new Vector3(0, 0, 1.5f), t);
                case CS.ToDept: case CS.Queue: case CS.Served: busy = c.st == CS.Served; return QueuePos(c.dept, c.staff, Mathf.Max(0, sim.dq[c.dept][c.staff].IndexOf(c)));
                case CS.ToCash: case CS.CashQueue: case CS.Paying: busy = c.st == CS.Paying; return CashQueuePos(c.cash, Mathf.Max(0, sim.cq[c.cash].IndexOf(c)));
                case CS.WalkOut: return Along(Door + new Vector3(0, 0, 1.5f), lane, slot, t);
                default: return slot;
            }
        }

        static float OutBack(float k) { float c = 2.2f; k -= 1; return 1 + k * k * ((c + 1) * k + c); }

        public void Update(float dt)
        {
            time += dt; SyncStatic();
            // things that pop into place
            for (int i = pops.Count - 1; i >= 0; i--)
            {
                var p = pops[i]; if (p.t == null) { pops.RemoveAt(i); continue; }
                if (p.delay > 0) { p.delay -= dt; continue; }
                p.age += dt; float k = Mathf.Clamp01(p.age / p.dur); p.t.localScale = p.scale * Mathf.Max(0.001f, OutBack(k)); if (k >= 1) { p.t.localScale = p.scale; pops.RemoveAt(i); }
            }
            shake = Mathf.Max(0, shake - dt * 2.6f);
            bool ad = sim.AdActive;
            for (int d = 0; d < T.ND; d++)
            {
                var v = depts[d];
                if (v.pop > 0)
                {
                    v.pop = Mathf.Max(0, v.pop - dt * 2.2f); float k = 1 + 0.10f * Mathf.Sin(v.pop * Mathf.PI) * v.pop;
                    v.stock.localScale = new Vector3(1, k, 1); v.signMat.SetColor("_EmissionColor", DeptColor[d] * (0.9f + 2.2f * v.pop));
                }
                else if (sim.s.dOpen[d]) v.signMat.SetColor("_EmissionColor", DeptColor[d] * (ad ? 1.1f + 0.3f * Mathf.Sin(time * 3f + d) : 0.9f));
                if (!sim.s.dOpen[d]) continue;
                for (int k = 0; k < sim.s.dStaff[d]; k++)
                {
                    bool serving = sim.dq[d][k].Count > 0 && sim.dq[d][k][0].st == CS.Served;
                    v.staff[k].Set(false, serving, time, dt);
                }
            }
            for (int c = 0; c < T.NC; c++)
            {
                if (sim.s.cLevel[c] <= 0) continue; bool paying = sim.cq[c].Count > 0 && sim.cq[c][0].st == CS.Paying;
                cashStaff[c].Set(false, paying, time, dt);
                cashLamp[c].sharedMaterial.SetColor("_EmissionColor", (paying ? new Color(0.3f, 1f, 0.6f) : new Color(0.25f, 0.55f, 0.95f)) * (paying ? 1.5f + 0.5f * Mathf.Sin(time * 14f) : 1.0f));
            }

            foreach (var c in sim.custs)
            {
                Actor a; if (!actors.TryGetValue(c.id, out a)) { a = MakeActor(c); actors[c.id] = a; }
                float t = c.dur > 0 ? Mathf.Clamp01(c.t / c.dur) : 1;
                if (a.car != null)
                {
                    var slot = SlotPos(c.slot); Vector3 from = new Vector3(-30, 0, RoadZ), turn = new Vector3(slot.x, 0, RoadZ), exit = new Vector3(30, 0, RoadZ);
                    Vector3 cp = c.st == CS.CarIn ? Along(from, turn, slot, Mathf.SmoothStep(0, 1, t)) : c.st == CS.CarOut ? Along(slot, turn, exit, t * t) : slot;
                    var dir = cp - a.carPos; if (dir.sqrMagnitude > 1e-5f) a.carYaw = Mathf.LerpAngle(a.carYaw, Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg, 0.35f);
                    else if (c.st != CS.CarIn && c.st != CS.CarOut) a.carYaw = Mathf.LerpAngle(a.carYaw, 0, 0.2f);
                    a.carPos = cp; a.car.transform.position = cp; a.car.transform.rotation = Quaternion.Euler(0, a.carYaw, 0);
                }
                bool inCar = c.st == CS.CarIn || c.st == CS.CarOut; a.go.SetActive(!inCar);
                if (inCar) { a.go.transform.position = c.slot >= 0 ? SlotPos(c.slot) + new Vector3(1.15f, 0, 0.6f) : busPos; continue; }
                bool busy; var target = Target(c, out busy); var pos = a.go.transform.position; var delta = target - pos; delta.y = 0;
                float speed = 3.8f * (float)sim.WalkMult; float step = speed * dt; a.moving = delta.magnitude > 0.05f;
                if (delta.magnitude <= step) pos = target; else pos += delta.normalized * step;
                a.go.transform.position = pos;
                if (a.moving) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.LookRotation(delta.normalized, Vector3.up), 0.25f);
                else if (c.st == CS.Queue || c.st == CS.Served) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.identity, 0.2f);
                else if (c.st == CS.CashQueue || c.st == CS.Paying) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.Euler(0, 180, 0), 0.2f);
                a.p.speed = (float)sim.WalkMult; a.p.Set(a.moving, false, time, dt);
                bool inStore = c.st != CS.WalkIn || t > 0.75f; a.cart.SetActive(inStore && c.st != CS.WalkOut || c.st == CS.WalkOut && t < 0.35f);
                a.goods.SetActive(c.bill > 0);
                a.gift.SetActive(c.gift); if (c.gift) { a.gift.transform.localPosition = new Vector3(0, 2.3f + 0.12f * Mathf.Sin(time * 5f), 0); a.gift.transform.localRotation = Quaternion.Euler(0, time * 120f, 0); }
            }
            gone.Clear(); foreach (var kv in actors) { bool live = false; foreach (var c in sim.custs) if (c.id == kv.Key) { live = true; break; } if (!live) gone.Add(kv.Key); }
            foreach (int id in gone) { var a = actors[id]; Kit.Kill(a.go); Kit.Kill(a.car); actors.Remove(id); }

            // delivery truck and VIP car wait in their bays until tapped
            if (sim.truckHere && truck == null) { truck = Kit.Mk("BoxTruck_A", root, truckPos + Vector3.up * 0.07f, 90, 0.42f); AddMarker(truck, new Color(1f, 0.8f, 0.2f)); AddPop(truck, 0, 0.4f); }
            if (!sim.truckHere && truck != null) { Kit.Kill(truck); truck = null; }
            if (sim.vipHere && vip == null) { vip = Kit.Mk("Car_B", root, vipPos + Vector3.up * 0.07f, 90, 0.86f); Kit.Tint(vip, new Color(0.35f, 0.30f, 0.42f)); AddMarker(vip, new Color(0.85f, 0.4f, 1f)); AddPop(vip, 0, 0.4f); }
            if (!sim.vipHere && vip != null) { Kit.Kill(vip); vip = null; }
            Bob(truck); Bob(vip);
        }

        void AddMarker(GameObject g, Color c)
        {
            var b = Kit.BoundsOf(g); float ls = Mathf.Max(1e-4f, g.transform.lossyScale.x);
            var m = Kit.Shape(PrimitiveType.Sphere, g.transform, Vector3.zero, Vector3.one, Kit.Glow(c, 1.9f)); m.name = "marker";
            m.transform.position = b.center + Vector3.up * (b.extents.y + 1.0f); m.transform.localScale = Vector3.one * (0.6f / ls);
            var col = g.AddComponent<BoxCollider>(); col.center = g.transform.InverseTransformPoint(b.center); var sz = g.transform.InverseTransformVector(b.size); col.size = new Vector3(Mathf.Abs(sz.x) * 1.25f, Mathf.Abs(sz.y) * 2.2f, Mathf.Abs(sz.z) * 1.25f);
        }
        void Bob(GameObject g) { if (g == null) return; var m = g.transform.Find("marker"); if (m != null) { var p = m.localPosition; m.localPosition = new Vector3(p.x, p.y + Mathf.Sin(time * 5f) * 0.02f / Mathf.Max(1e-4f, g.transform.lossyScale.x), p.z); } }

        public void PopDept(int d) { depts[d].pop = 1f; }
        public Actor ActorOf(Cust c) { Actor a; return actors.TryGetValue(c.id, out a) ? a : null; }
        public Cust CustAt(GameObject go) { foreach (var c in sim.custs) { Actor a; if (actors.TryGetValue(c.id, out a) && a.go == go) return c; } return null; }
        public int ActorCount => actors.Count;
    }
}
