// The 3D store: builds the scene from kit models and simple shapes, and moves shoppers, staff and cars
// to wherever the rule core says they are. A plain class so the cloud build can also drive it for screenshots.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;

namespace Souq
{
    public static class Kit
    {
        static readonly Dictionary<string, Material> mats = new Dictionary<string, Material>();
        public static Material Lit, Emis;
        public static void Init()
        {
            mats.Clear();
            Lit = Resources.Load<Material>("BaseLit"); Emis = Resources.Load<Material>("BaseEmis");
            if (Emis == null) Emis = Lit;
        }
        public static Material PackMat(string prefix)
        {
            Material m; if (mats.TryGetValue(prefix, out m)) return m;
            m = new Material(Lit); var tex = Resources.Load<Texture2D>("Kit/" + prefix + "_tex");
            if (tex != null) { if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", tex); m.mainTexture = tex; }
            SetColor(m, Color.white); if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", 0.15f);
            mats[prefix] = m; return m;
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
        public static void Kill(UnityEngine.Object o) { if (o == null) return; if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o); }
        public static Bounds BoundsOf(GameObject g)
        {
            var rs = g.GetComponentsInChildren<Renderer>(); if (rs.Length == 0) return new Bounds(g.transform.position, Vector3.one * 0.1f);
            var b = rs[0].bounds; for (int i = 1; i < rs.Length; i++) b.Encapsulate(rs[i].bounds); return b;
        }
        /// Places a kit model with its base on the ground at `pos`, scaled so its widest side is `fit` units.
        public static GameObject Spawn(string name, Transform parent, Vector3 pos, float rotY, float fit, bool fitHeight = false)
        {
            var src = Resources.Load<GameObject>("Kit/" + name);
            GameObject g;
            if (src == null) { g = GameObject.CreatePrimitive(PrimitiveType.Cube); g.GetComponent<Renderer>().sharedMaterial = Mat(new Color(0.8f, 0.3f, 0.6f)); }
            else
            {
                g = UnityEngine.Object.Instantiate(src);
                var mat = PackMat(name.Substring(0, 1));
                foreach (var r in g.GetComponentsInChildren<Renderer>()) { var arr = new Material[r.sharedMaterials.Length]; for (int i = 0; i < arr.Length; i++) arr[i] = mat; r.sharedMaterials = arr; }
            }
            foreach (var c in g.GetComponentsInChildren<Collider>()) UnityEngine.Object.DestroyImmediate(c);
            g.name = name; g.transform.SetParent(parent, false);
            g.transform.position = Vector3.zero; g.transform.rotation = Quaternion.Euler(0, rotY, 0); g.transform.localScale = Vector3.one;
            var b = BoundsOf(g); float size = fitHeight ? b.size.y : Mathf.Max(b.size.x, b.size.z);
            float k = size > 1e-5f ? fit / size : 1; g.transform.localScale = Vector3.one * k;
            b = BoundsOf(g);
            g.transform.position = pos + new Vector3(-(b.center.x), -b.min.y, -(b.center.z));
            return g;
        }
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
    }

    public class DeptView
    {
        public int d; public Transform root, props; public Vector3 center; public Renderer pad, sign; public Material signMat;
        public GameObject[] staff = new GameObject[T.MaxStaff]; public int builtTier = -2; public bool builtOpen; public float pop;
        public BoxCollider hit;
    }

    public class Actor { public GameObject go; public Transform body; public Vector3 target; public bool moving; public float phase; public GameObject bag, gift, car; public Vector3 carPos; public float carYaw; }

    public class World
    {
        public Transform root; public Camera cam; public Sim sim;
        public DeptView[] depts = new DeptView[T.ND];
        public GameObject[] cashDesk = new GameObject[T.NC]; public GameObject[] cashStaff = new GameObject[T.NC]; Renderer[] cashScreen = new Renderer[T.NC];
        public GameObject truck, vip; public Vector3 truckPos = new Vector3(6.3f, 0, -1.25f), vipPos = new Vector3(-6.3f, 0, -1.25f), busPos = new Vector3(8.3f, 0, -4.4f);
        public const float RoadZ = -4.4f;
        readonly Dictionary<int, Actor> actors = new Dictionary<int, Actor>(); readonly List<int> gone = new List<int>();
        Transform slotRoot; int slotsBuilt; float time; Light sun; Material neonA, neonB; Renderer[] roofLights = new Renderer[0];
        public static readonly Color[] DeptColor =
        {
            new Color(0.36f,0.80f,0.36f), new Color(0.98f,0.72f,0.30f), new Color(0.92f,0.36f,0.36f), new Color(0.30f,0.72f,0.95f),
            new Color(0.85f,0.52f,0.22f), new Color(0.93f,0.42f,0.75f), new Color(0.68f,0.48f,0.96f), new Color(0.25f,0.85f,0.85f),
            new Color(0.40f,0.55f,1.00f), new Color(1.00f,0.84f,0.30f), new Color(0.95f,0.30f,0.45f),
        };
        static readonly Color[] Skin = { new Color(1f,0.86f,0.72f), new Color(0.93f,0.74f,0.58f), new Color(0.78f,0.57f,0.42f), new Color(0.58f,0.40f,0.28f), new Color(0.42f,0.28f,0.20f) };
        static readonly Color[] Cloth = { new Color(0.95f,0.35f,0.35f), new Color(0.30f,0.60f,0.95f), new Color(0.98f,0.80f,0.25f), new Color(0.35f,0.80f,0.55f), new Color(0.70f,0.45f,0.95f), new Color(0.95f,0.55f,0.25f), new Color(0.92f,0.92f,0.95f), new Color(0.25f,0.30f,0.40f) };
        static readonly string[] CarKit = { "c_car_hatchback", "c_car_sedan", "c_car_stationwagon", "c_car_taxi" };

        public const float HalfW = 9f, DeptRow0 = 13f, DeptRowGap = 9.5f, CashZ = 4.2f;
        public static Vector3 DeptCenter(int d) => new Vector3(d % 2 == 0 ? -4.5f : 4.5f, 0, DeptRow0 + (d / 2) * DeptRowGap);
        public static float StoreDepth => DeptRow0 + 5 * DeptRowGap + 6.5f;
        public static Vector3 StaffPos(int d, int k) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 2.0f);
        public static Vector3 QueuePos(int d, int k, int q) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 0.75f - q * 0.85f);
        public static Vector3 CashPos(int c) => new Vector3(-7.35f + c * 2.1f, 0, CashZ);
        public static Vector3 CashQueuePos(int c, int q) => CashPos(c) + new Vector3(0.75f, 0, 1.0f + q * 0.8f);
        public static Vector3 SlotPos(int i) => new Vector3(-7.5f + (i % 6) * 3f, 0, -9.0f - (i / 6) * 4.4f);
        static readonly Vector3 Door = new Vector3(0, 0, 0.2f);

        public World(Sim s) { sim = s; }

        // ---------- build ----------
        public void Build()
        {
            Kit.Init();
            root = new GameObject("World").transform;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.66f, 0.72f, 0.92f); RenderSettings.ambientEquatorColor = new Color(0.62f, 0.62f, 0.66f); RenderSettings.ambientGroundColor = new Color(0.40f, 0.37f, 0.36f);
            RenderSettings.fog = false;
            sun = new GameObject("Sun").AddComponent<Light>(); sun.transform.SetParent(root, false);
            sun.type = LightType.Directional; sun.color = new Color(1f, 0.95f, 0.86f); sun.intensity = 1.15f; sun.shadows = LightShadows.Soft; sun.shadowStrength = 0.55f;
            sun.transform.rotation = Quaternion.Euler(50, 28, 0);

            float depth = StoreDepth;
            // ground: asphalt lot, pavement, shop floor in a two-tone checker
            Kit.Box(root, new Vector3(0, -0.3f, depth / 2 - 22), new Vector3(120, 0.5f, depth + 110), Kit.Mat(new Color(0.20f, 0.21f, 0.30f), 0.05f), "asphalt");
            Kit.Box(root, new Vector3(0, -0.14f, RoadZ), new Vector3(120, 0.3f, 3.6f), Kit.Mat(new Color(0.16f, 0.17f, 0.24f), 0.3f), "road");
            for (int i = -14; i <= 14; i++) Kit.Box(root, new Vector3(i * 3.6f, 0.02f, RoadZ), new Vector3(1.6f, 0.02f, 0.14f), Kit.Mat(new Color(0.95f, 0.85f, 0.45f)), "dash");
            Kit.Box(root, new Vector3(0, -0.1f, -1.25f), new Vector3(HalfW * 2 + 5, 0.3f, 2.5f), Kit.Mat(new Color(0.74f, 0.72f, 0.78f)), "pavement");
            var tileA = Kit.Mat(new Color(0.97f, 0.95f, 0.90f), 0.45f); var tileB = Kit.Mat(new Color(0.91f, 0.89f, 0.85f), 0.45f);
            for (int ix = 0; ix < 6; ix++) for (int iz = 0; iz < Mathf.CeilToInt(depth / 3f); iz++)
                Kit.Box(root, new Vector3(-HalfW + 1.5f + ix * 3f, -0.05f, 1.5f + iz * 3f), new Vector3(3f, 0.1f, 3f), (ix + iz) % 2 == 0 ? tileA : tileB, "tile");
            // walls: low enough to see over from the camera side
            var wall = Kit.Mat(new Color(0.98f, 0.96f, 0.92f)); var trim = Kit.Mat(new Color(0.16f, 0.36f, 0.62f));
            neonA = Kit.Glow(new Color(1f, 0.72f, 0.20f), 1.8f); neonB = Kit.Glow(new Color(0.20f, 0.80f, 1f), 1.8f);
            Kit.Box(root, new Vector3(-HalfW - 0.25f, 1.6f, depth / 2), new Vector3(0.5f, 3.2f, depth), wall, "wallL");
            Kit.Box(root, new Vector3(HalfW + 0.25f, 1.6f, depth / 2), new Vector3(0.5f, 3.2f, depth), wall, "wallR");
            Kit.Box(root, new Vector3(0, 2.4f, depth + 0.25f), new Vector3(HalfW * 2 + 1, 4.8f, 0.5f), wall, "wallBack");
            Kit.Box(root, new Vector3(0, 4.9f, depth + 0.25f), new Vector3(HalfW * 2 + 1.4f, 0.5f, 0.7f), trim, "trimBack");
            Kit.Box(root, new Vector3(-HalfW - 0.25f, 3.3f, depth / 2), new Vector3(0.6f, 0.3f, depth), neonB, "neonL");
            Kit.Box(root, new Vector3(HalfW + 0.25f, 3.3f, depth / 2), new Vector3(0.6f, 0.3f, depth), neonB, "neonR");
            // front: two short walls with a lit doorway between them
            Kit.Box(root, new Vector3(-(HalfW + 2.2f) / 2 - 0.0f, 0.6f, 0), new Vector3(HalfW - 2.2f, 1.2f, 0.4f), wall, "frontL");
            Kit.Box(root, new Vector3((HalfW + 2.2f) / 2, 0.6f, 0), new Vector3(HalfW - 2.2f, 1.2f, 0.4f), wall, "frontR");
            Kit.Box(root, new Vector3(-2.3f, 1.7f, 0), new Vector3(0.35f, 3.4f, 0.5f), trim, "postL"); Kit.Box(root, new Vector3(2.3f, 1.7f, 0), new Vector3(0.35f, 3.4f, 0.5f), trim, "postR");
            Kit.Box(root, new Vector3(0, 3.6f, 0), new Vector3(5.6f, 1.0f, 0.6f), trim, "lintel");
            Kit.Box(root, new Vector3(0, 3.6f, -0.34f), new Vector3(4.8f, 0.55f, 0.1f), neonA, "signGlow");
            Kit.Box(root, new Vector3(0, 0.03f, 0.9f), new Vector3(3.6f, 0.04f, 1.6f), Kit.Mat(new Color(0.75f, 0.2f, 0.25f)), "mat");
            // ceiling light strips floating above the aisle
            var strips = new List<Renderer>();
            for (float z = 8; z < depth - 2; z += DeptRowGap) strips.Add(Kit.Box(root, new Vector3(0, 0.03f, z + 4.6f), new Vector3(0.5f, 0.03f, 5.5f), neonA, "aisle").GetComponent<Renderer>());
            roofLights = strips.ToArray();
            // street dressing
            for (int i = 0; i < 6; i++)
            {
                float x = -12.5f + i * 5f;
                Kit.Spawn("c_streetlight", root, new Vector3(x, 0, -2.3f), 180, 3.4f, true);
                Kit.Shape(PrimitiveType.Sphere, root, new Vector3(x, 3.25f, -2.9f), Vector3.one * 0.35f, neonA);
            }
            for (int i = 0; i < 3; i++) { Kit.Spawn("c_bush", root, new Vector3(-9.6f - i * 1.3f, 0, -1.2f), i * 40, 1.1f); Kit.Spawn("c_bush", root, new Vector3(9.6f + i * 1.3f, 0, -1.2f), i * 70, 1.1f); }
            Kit.Spawn("c_bench", root, new Vector3(-3.4f, 0, -1.0f), 180, 1.5f); Kit.Spawn("c_bench", root, new Vector3(3.4f, 0, -1.0f), 180, 1.5f);
            string[] bl = { "c_building_A", "c_building_B", "c_building_C", "c_building_D" };
            for (int i = 0; i < 7; i++) { Kit.Spawn(bl[i % 4], root, new Vector3(-17.5f, 0, 2 + i * 8.5f), 90, 7.5f); Kit.Spawn(bl[(i + 2) % 4], root, new Vector3(17.5f, 0, 10 + i * 8.5f), -90, 7.5f); }
            for (int i = 0; i < 5; i++) Kit.Spawn(bl[(i + 1) % 4], root, new Vector3(-16 + i * 8f, 0, depth + 6f), 180, 7.5f);
            // delivery bay and VIP bay
            Kit.Box(root, new Vector3(truckPos.x, 0.07f, truckPos.z), new Vector3(4.2f, 0.04f, 2.2f), Kit.Mat(new Color(0.95f, 0.75f, 0.2f)), "truckBay");
            Kit.Box(root, new Vector3(vipPos.x, 0.07f, vipPos.z), new Vector3(4.2f, 0.04f, 2.2f), Kit.Mat(new Color(0.75f, 0.35f, 0.95f)), "vipBay");

            for (int c = 0; c < T.NC; c++) BuildCash(c);
            for (int d = 0; d < T.ND; d++) BuildDept(d);
            slotRoot = new GameObject("Slots").transform; slotRoot.SetParent(root, false);
            SyncStatic(true);
        }

        void BuildCash(int c)
        {
            var p = CashPos(c); var g = new GameObject("cash" + c); g.transform.SetParent(root, false);
            Kit.Spawn("r_kitchencounter_straight_A", g.transform, p, 90, 1.7f);
            cashScreen[c] = Kit.Box(g.transform, p + new Vector3(0, 1.25f, -0.35f), new Vector3(0.55f, 0.4f, 0.08f), Kit.Glow(new Color(0.3f, 1f, 0.6f), 1.6f), "screen").GetComponent<Renderer>();
            Kit.Box(g.transform, p + new Vector3(0, 0.95f, -0.35f), new Vector3(0.12f, 0.3f, 0.08f), Kit.Mat(new Color(0.2f, 0.2f, 0.25f)), "stand");
            cashStaff[c] = MakePerson(g.transform, 3, new Color(0.15f, 0.55f, 0.75f), true); cashStaff[c].transform.position = p + new Vector3(-0.75f, 0, 0.1f); cashStaff[c].transform.rotation = Quaternion.Euler(0, 90, 0);
            cashDesk[c] = g;
        }

        void BuildDept(int d)
        {
            var v = new DeptView { d = d, center = DeptCenter(d) }; var g = new GameObject("dept" + d); g.transform.SetParent(root, false); v.root = g.transform;
            var col = DeptColor[d];
            v.pad = Kit.Box(g.transform, v.center + new Vector3(0, 0.02f, 0.4f), new Vector3(8.2f, 0.05f, 7.6f), Kit.Mat(Color.Lerp(col, Color.white, 0.55f), 0.4f), "pad").GetComponent<Renderer>();
            Kit.Box(g.transform, v.center + new Vector3(0, 0.03f, 0.4f), new Vector3(7.6f, 0.06f, 7.0f), Kit.Mat(Color.Lerp(col, Color.white, 0.80f), 0.5f), "padIn");
            v.signMat = Kit.Glow(col, 1.6f);
            v.sign = Kit.Box(g.transform, v.center + new Vector3(0, 3.0f, 4.1f), new Vector3(6.4f, 0.9f, 0.25f), v.signMat, "sign").GetComponent<Renderer>();
            Kit.Box(g.transform, v.center + new Vector3(-3.0f, 1.5f, 4.1f), new Vector3(0.22f, 3.0f, 0.22f), Kit.Mat(new Color(0.25f, 0.27f, 0.35f)), "pole");
            Kit.Box(g.transform, v.center + new Vector3(3.0f, 1.5f, 4.1f), new Vector3(0.22f, 3.0f, 0.22f), Kit.Mat(new Color(0.25f, 0.27f, 0.35f)), "pole");
            v.props = new GameObject("props").transform; v.props.SetParent(g.transform, false);
            for (int k = 0; k < T.MaxStaff; k++)
            {
                v.staff[k] = MakePerson(g.transform, d * 7 + k, Color.Lerp(col, Color.black, 0.25f), true);
                v.staff[k].transform.position = StaffPos(d, k); v.staff[k].transform.rotation = Quaternion.Euler(0, 180, 0);
            }
            v.hit = g.AddComponent<BoxCollider>(); v.hit.center = v.center + new Vector3(0, 1f, 0.4f); v.hit.size = new Vector3(8.2f, 2.5f, 7.6f);
            depts[d] = v;
        }

        // what stands on each department's floor; more of it appears as the level tier rises
        static readonly string[][] PropSet =
        {
            new[]{"r_crate_tomatoes","r_crate_carrots","r_crate_lettuce","r_crate_potatoes","r_crate_onions","r_kitchentable_A_large"},
            new[]{"r_crate_buns","r_oven","r_food_burger","r_crate_buns","r_kitchentable_B_large","r_crate_cheese"},
            new[]{"r_crate_steak","r_crate_ham","r_fridge_A_decorated","r_crate_steak","r_kitchencounter_straight_B","r_crate_ham"},
            new[]{"r_fridge_B","r_crate","r_fridge_A_decorated","r_crate","r_fridge_B","r_kitchencounter_straight_B"},
            new[]{"r_jar_A_large","r_jar_B_large","p_Barrel_A","r_jar_C_large","r_jar_D_large","f_shelf_B_large_decorated"},
            new[]{"f_shelf_A_big","f_rug_rectangle_A","f_armchair_pillows","f_shelf_B_large_decorated","f_couch_pillows","f_lamp_standing"},
            new[]{"f_cabinet_small_decorated","r_jar_B_large","f_lamp_standing","r_jar_D_large","f_cabinet_medium_decorated","f_rug_oval_A"},
            new[]{"f_cabinet_medium_decorated","c_box_A","f_table_medium_long","c_box_B","f_shelf_B_large","p_Box_A"},
            new[]{"f_table_low","f_table_medium_long","f_cabinet_small_decorated","f_table_low","f_shelf_B_large","p_Box_B"},
            new[]{"f_cabinet_small_decorated","p_Coin_A","f_cabinet_medium_decorated","p_Coin_A","f_rug_oval_A","f_lamp_standing"},
            new[]{"c_car_sedan","c_car_taxi","c_car_hatchback","c_car_stationwagon","f_rug_oval_A","f_lamp_standing"},
        };
        static readonly float[] PropFit = { 1.25f, 1.3f, 1.3f, 1.35f, 1.0f, 1.7f, 1.2f, 1.6f, 1.6f, 1.2f, 3.0f };

        void RebuildProps(DeptView v, bool open, int tier)
        {
            for (int i = v.props.childCount - 1; i >= 0; i--) UnityEngine.Object.DestroyImmediate(v.props.GetChild(i).gameObject);
            v.builtOpen = open; v.builtTier = tier;
            var col = DeptColor[v.d];
            Kit.SetColor(v.pad.sharedMaterial, open ? Color.Lerp(col, Color.white, 0.55f) : new Color(0.55f, 0.56f, 0.62f));
            v.signMat.SetColor("_EmissionColor", open ? col * 1.6f : new Color(0.05f, 0.05f, 0.07f)); Kit.SetColor(v.signMat, open ? col : new Color(0.3f, 0.3f, 0.35f));
            if (!open)
            {
                Kit.Spawn("p_Pallet_Large", v.props, v.center + new Vector3(-1.2f, 0, 1.2f), 15, 2.2f);
                Kit.Spawn("p_Box_A", v.props, v.center + new Vector3(-1.2f, 0.35f, 1.2f), 30, 1.1f);
                Kit.Spawn("p_Box_B", v.props, v.center + new Vector3(1.3f, 0, 0.6f), -20, 1.3f);
                Kit.Spawn("p_Pallet_Small_Decorated_A", v.props, v.center + new Vector3(0.6f, 0, 2.3f), 50, 1.6f);
                return;
            }
            // back counter the staff stand behind, then stock: one more piece per tier, in two rows along the back wall
            for (int k = -2; k <= 2; k++) Kit.Spawn(v.d == 10 ? "f_table_low" : "r_kitchencounter_straight_B", v.props, v.center + new Vector3(k * 1.45f, 0, 1.25f), 0, 1.45f);
            var set = PropSet[v.d]; int count = Mathf.Min(4 + tier * 2, 16); float fit = PropFit[v.d];
            for (int i = 0; i < count; i++)
            {
                int row = i / 6, colI = i % 6; string n = set[i % set.Length];
                float f = n.StartsWith("c_car") ? 3.0f : n.StartsWith("f_rug") ? 2.2f : n.StartsWith("p_Coin") ? 0.7f : fit;
                var pos = v.center + new Vector3(-3.3f + colI * 1.32f, row * 0.95f, 3.3f);
                if (v.d == 10) pos = v.center + new Vector3(-2.2f + (i % 2) * 4.4f, 0, 3.0f);
                if (v.d == 10 && i >= 2) break;
                var g = Kit.Spawn(n, v.props, pos, (i * 37) % 4 * 90 + (v.d == 10 ? 160 : 0), f);
                if (row >= 1 && v.d != 10) g.transform.localScale *= 0.8f;
            }
            if (tier >= 3) for (int k = 0; k < 4; k++) Kit.Shape(PrimitiveType.Sphere, v.props, v.center + new Vector3(-2.7f + k * 1.8f, 3.75f, 4.1f), Vector3.one * 0.28f, k % 2 == 0 ? neonA : neonB);
            v.pop = 1f;
        }

        GameObject MakePerson(Transform parent, int look, Color cloth, bool staffLook)
        {
            var g = new GameObject("person"); g.transform.SetParent(parent, false);
            var body = new GameObject("body").transform; body.SetParent(g.transform, false);
            var skin = Kit.Mat(Skin[look % Skin.Length], 0.3f); var cl = Kit.Mat(cloth, 0.3f);
            Kit.Shape(PrimitiveType.Capsule, body, new Vector3(0, 0.52f, 0), new Vector3(0.5f, 0.42f, 0.42f), cl);
            Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0, 1.12f, 0), new Vector3(0.42f, 0.42f, 0.42f), skin);
            var dark = Kit.Mat(new Color(0.16f, 0.13f, 0.14f), 0.4f);
            if (staffLook) Kit.Shape(PrimitiveType.Cylinder, body, new Vector3(0, 1.34f, 0), new Vector3(0.36f, 0.06f, 0.36f), Kit.Mat(Color.white));
            else if (look % 3 == 0) Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0, 1.2f, -0.04f), new Vector3(0.46f, 0.36f, 0.46f), dark);
            else if (look % 3 == 1) Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0, 1.17f, -0.03f), new Vector3(0.5f, 0.46f, 0.5f), Kit.Mat(Cloth[(look / 3) % Cloth.Length], 0.3f));
            Kit.Shape(PrimitiveType.Sphere, body, new Vector3(-0.09f, 1.14f, 0.19f), Vector3.one * 0.06f, dark); Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0.09f, 1.14f, 0.19f), Vector3.one * 0.06f, dark);
            Kit.Shape(PrimitiveType.Sphere, body, new Vector3(-0.14f, 0.1f, 0.03f), new Vector3(0.18f, 0.16f, 0.26f), dark); Kit.Shape(PrimitiveType.Sphere, body, new Vector3(0.14f, 0.1f, 0.03f), new Vector3(0.18f, 0.16f, 0.26f), dark);
            return g;
        }

        Actor MakeActor(Cust c)
        {
            var a = new Actor(); a.go = MakePerson(root, c.look, Cloth[(c.look / 5) % Cloth.Length], false); a.body = a.go.transform.GetChild(0); a.phase = (c.look % 100) * 0.1f;
            a.bag = Kit.Box(a.body, Vector3.zero, new Vector3(0.3f, 0.34f, 0.2f), Kit.Mat(DeptColor[c.look % T.ND], 0.3f), "bag"); a.bag.transform.localPosition = new Vector3(0.36f, 0.45f, 0.05f); a.bag.SetActive(false);
            a.gift = Kit.Shape(PrimitiveType.Cube, a.go.transform, new Vector3(0, 1.9f, 0), Vector3.one * 0.42f, Kit.Glow(new Color(1f, 0.35f, 0.6f), 1.8f)); a.gift.SetActive(false);
            a.gift.AddComponent<SphereCollider>().radius = 1.6f;
            if (c.slot >= 0)
            {
                a.car = new GameObject("car"); a.car.transform.SetParent(root, false);
                Kit.Spawn(CarKit[c.look % CarKit.Length], a.car.transform, Vector3.zero, 0, 2.6f);
                a.carPos = new Vector3(-30, 0, RoadZ); a.car.transform.position = a.carPos; a.carYaw = 90;
            }
            a.go.transform.position = c.slot >= 0 ? new Vector3(-30, 0, RoadZ) : busPos; a.go.SetActive(c.slot < 0);
            return a;
        }

        // ---------- per frame ----------
        public void SyncStatic(bool force = false)
        {
            var s = sim.s;
            for (int d = 0; d < T.ND; d++)
            {
                var v = depts[d]; int tier = T.Tier(s.dLevel[d]);
                if (force || v.builtOpen != s.dOpen[d] || v.builtTier != tier) RebuildProps(v, s.dOpen[d], tier);
                for (int k = 0; k < T.MaxStaff; k++) v.staff[k].SetActive(s.dOpen[d] && k < s.dStaff[d]);
            }
            for (int c = 0; c < T.NC; c++) cashDesk[c].SetActive(s.cLevel[c] > 0);
            int want = sim.ParkSpaces;
            if (want != slotsBuilt)
            {
                var line = Kit.Mat(new Color(0.9f, 0.9f, 0.95f));
                for (int i = slotsBuilt; i < want; i++)
                {
                    var p = SlotPos(i);
                    Kit.Box(slotRoot, p + new Vector3(-1.4f, 0.02f, 0), new Vector3(0.1f, 0.02f, 3.6f), line, "line"); Kit.Box(slotRoot, p + new Vector3(1.4f, 0.02f, 0), new Vector3(0.1f, 0.02f, 3.6f), line, "line");
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
            Vector3 slot = c.slot >= 0 ? SlotPos(c.slot) + new Vector3(0.9f, 0, 0.6f) : busPos; var lane = new Vector3(slot.x, 0, -2.4f);
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

        public void Update(float dt)
        {
            time += dt; SyncStatic();
            // neon breathing; brighter and warmer while an ad campaign doubles profit
            float pulse = 0.75f + 0.25f * Mathf.Sin(time * 2.2f); bool ad = sim.AdActive;
            neonA.SetColor("_EmissionColor", (ad ? new Color(1f, 0.50f, 0.12f) : new Color(1f, 0.72f, 0.20f)) * (1.4f + (ad ? 1.3f : 0.5f) * pulse));
            neonB.SetColor("_EmissionColor", new Color(0.20f, 0.80f, 1f) * (1.5f + 0.5f * Mathf.Sin(time * 1.7f + 1f)));
            for (int d = 0; d < T.ND; d++)
            {
                var v = depts[d];
                if (v.pop > 0) { Kit.SetColor(v.pad.sharedMaterial, Color.Lerp(sim.s.dOpen[d] ? Color.Lerp(DeptColor[d], Color.white, 0.55f) : new Color(0.55f, 0.56f, 0.62f), Color.white, v.pop)); v.pop = Mathf.Max(0, v.pop - dt * 1.6f); float k = 1 + 0.22f * Mathf.Sin(v.pop * Mathf.PI) * v.pop; v.props.localScale = new Vector3(k, 1 + 0.5f * (k - 1), k); v.props.position = v.center * (1 - k) ; }
                if (!sim.s.dOpen[d]) continue;
                for (int k = 0; k < sim.s.dStaff[d]; k++)
                {
                    bool serving = sim.dq[d][k].Count > 0 && sim.dq[d][k][0].st == CS.Served;
                    var b = v.staff[k].transform.GetChild(0); b.localPosition = new Vector3(0, serving ? 0.06f * Mathf.Abs(Mathf.Sin(time * 9f + k)) : 0, 0);
                    b.localRotation = Quaternion.Euler(serving ? 10f * Mathf.Sin(time * 9f + k) : 0, 0, 0);
                }
            }
            for (int c = 0; c < T.NC; c++)
            {
                if (sim.s.cLevel[c] <= 0) continue; bool paying = sim.cq[c].Count > 0 && sim.cq[c][0].st == CS.Paying;
                cashStaff[c].transform.GetChild(0).localRotation = Quaternion.Euler(0, paying ? 20f * Mathf.Sin(time * 10f + c) : 0, 0);
                cashScreen[c].sharedMaterial.SetColor("_EmissionColor", (paying ? new Color(0.3f, 1f, 0.6f) : new Color(0.2f, 0.5f, 0.9f)) * (paying ? 1.5f + 0.5f * Mathf.Sin(time * 14f) : 1.1f));
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
                    a.carPos = cp; a.car.transform.position = cp; a.car.transform.rotation = Quaternion.Euler(0, a.carYaw, 0);
                }
                bool inCar = c.st == CS.CarIn || c.st == CS.CarOut; a.go.SetActive(!inCar);
                if (inCar) { a.go.transform.position = c.slot >= 0 ? SlotPos(c.slot) + new Vector3(0.9f, 0, 0.6f) : busPos; continue; }
                bool busy; var target = Target(c, out busy); var pos = a.go.transform.position; var delta = target - pos; delta.y = 0;
                float speed = 4.2f * (float)sim.WalkMult; float step = speed * dt; a.moving = delta.magnitude > 0.05f;
                if (delta.magnitude <= step) pos = target; else pos += delta.normalized * step;
                a.go.transform.position = pos;
                if (a.moving) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.LookRotation(delta.normalized, Vector3.up), 0.25f);
                else if (c.st == CS.Queue || c.st == CS.Served) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.identity, 0.2f);
                else if (c.st == CS.CashQueue || c.st == CS.Paying) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.Euler(0, 180, 0), 0.2f);
                float ph = time * 11f + a.phase;
                a.body.localPosition = new Vector3(0, a.moving ? 0.07f * Mathf.Abs(Mathf.Sin(ph)) : busy ? 0.03f * Mathf.Abs(Mathf.Sin(time * 6f)) : 0, 0);
                a.body.localRotation = Quaternion.Euler(a.moving ? 6f : 0, 0, a.moving ? 5f * Mathf.Sin(ph) : 0);
                a.bag.SetActive(c.bill > 0);
                a.gift.SetActive(c.gift); if (c.gift) { a.gift.transform.localPosition = new Vector3(0, 1.9f + 0.12f * Mathf.Sin(time * 5f), 0); a.gift.transform.localRotation = Quaternion.Euler(0, time * 120f, 0); }
            }
            gone.Clear(); foreach (var kv in actors) { bool live = false; foreach (var c in sim.custs) if (c.id == kv.Key) { live = true; break; } if (!live) gone.Add(kv.Key); }
            foreach (int id in gone) { var a = actors[id]; Kit.Kill(a.go); Kit.Kill(a.car); actors.Remove(id); }

            // delivery truck and VIP car wait in their bays until tapped
            if (sim.truckHere && truck == null) { truck = Kit.Spawn("c_car_stationwagon", root, truckPos + Vector3.up * 0.09f, 90, 3.4f); AddMarker(truck, new Color(1f, 0.8f, 0.2f)); }
            if (!sim.truckHere && truck != null) { Kit.Kill(truck); truck = null; }
            if (sim.vipHere && vip == null) { vip = Kit.Spawn("c_car_sedan", root, vipPos + Vector3.up * 0.09f, 90, 3.2f); AddMarker(vip, new Color(0.85f, 0.4f, 1f)); }
            if (!sim.vipHere && vip != null) { Kit.Kill(vip); vip = null; }
            Bob(truck); Bob(vip);
        }

        void AddMarker(GameObject g, Color c)
        {
            var m = Kit.Shape(PrimitiveType.Sphere, g.transform, Vector3.zero, Vector3.one, Kit.Glow(c, 1.9f)); m.name = "marker";
            m.transform.position = Kit.BoundsOf(g).center + Vector3.up * 2.2f; m.transform.localScale = Vector3.one * (0.7f / g.transform.lossyScale.x);
            var col = g.AddComponent<BoxCollider>(); var b = Kit.BoundsOf(g); col.center = g.transform.InverseTransformPoint(b.center); var sz = b.size / g.transform.lossyScale.x; col.size = new Vector3(sz.x * 1.3f, sz.y * 2.5f, sz.z * 1.3f);
        }
        void Bob(GameObject g) { if (g == null) return; var m = g.transform.Find("marker"); if (m != null) { var p = m.localPosition; m.localPosition = new Vector3(p.x, p.y + Mathf.Sin(time * 5f) * 0.02f / g.transform.lossyScale.x, p.z); } }

        public void PopDept(int d) { depts[d].pop = 1f; }
        public Actor ActorOf(Cust c) { Actor a; return actors.TryGetValue(c.id, out a) ? a : null; }
        public Cust CustAt(GameObject go) { foreach (var c in sim.custs) { Actor a; if (actors.TryGetValue(c.id, out a) && a.go == go) return c; } return null; }
    }
}
