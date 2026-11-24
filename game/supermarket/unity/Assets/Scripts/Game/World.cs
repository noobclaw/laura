// The 3D store, built entirely from code: every fixture, person and car is a set of small coloured solids.
// No textures and no imported models, so the picture stays sharp at any screen size.
// It only shows what the rule core says; a plain class so the cloud build can also drive it for screenshots.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;

namespace Souq
{
    public static class Kit
    {
        public static Material Solid, Glow; public static int Missing;
        public static void Init()
        {
            Missing = 0; Solid = Resources.Load<Material>("Solid"); Glow = Resources.Load<Material>("SolidGlow");
            if (Solid == null) { var sh = Shader.Find("Souq/Solid"); if (sh == null) { Missing++; sh = Shader.Find("Universal Render Pipeline/Unlit"); } Solid = new Material(sh); }
            if (Glow == null) { Glow = new Material(Solid); if (Glow.HasProperty("_Glow")) Glow.SetFloat("_Glow", 1f); }
        }
        static Shader textShader; static bool textLooked;
        /// Lettering on a sign in the scene, `height` metres tall, readable from the camera side.
        public static TextMesh Label(string text, Transform parent, Vector3 pos, float height, Color color)
        {
            var go = new GameObject("label"); go.transform.SetParent(parent, false); go.transform.position = pos;
            var tm = go.AddComponent<TextMesh>(); tm.anchor = TextAnchor.MiddleCenter; tm.alignment = TextAlignment.Center; tm.fontSize = 110; tm.characterSize = height * 10f / 110f * 1.3f; tm.color = color;
            SetLabel(tm, text); return tm;
        }
        public static void SetLabel(TextMesh tm, string text)
        {
            var font = U.Font != null ? U.Font : Resources.Load<Font>("Font/Changa-Bold"); tm.font = font; tm.text = text; var mr = tm.GetComponent<MeshRenderer>(); if (font == null) return;
            if (!textLooked) { textLooked = true; textShader = Resources.Load<Shader>("Shaders/SouqText3D"); }
            if (textShader == null) { mr.sharedMaterial = font.material; return; }
            var m = new Material(textShader); m.mainTexture = font.material.mainTexture; mr.sharedMaterial = m;
            // a dynamic font may rebuild its glyph picture when new letters are asked for
            Font.textureRebuilt += f => { if (f == font && m != null) m.mainTexture = f.material.mainTexture; };
        }
        public static Material GlowTint(Color c) { var m = new Material(Glow); m.SetColor("_Tint", c.linear); return m; }
        public static void Kill(UnityEngine.Object o) { if (o == null) return; if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o); }
        public static Bounds BoundsOf(GameObject g)
        {
            var rs = g.GetComponentsInChildren<Renderer>(); if (rs.Length == 0) return new Bounds(g.transform.position, Vector3.one * 0.1f);
            var b = rs[0].bounds; for (int i = 1; i < rs.Length; i++) b.Encapsulate(rs[i].bounds); return b;
        }
    }

    /// Shapes shared by the store: palette and the builders for fixtures, carts, cars and trees.
    public static class Art
    {
        public const string Wood = "#c98a4b", Wood2 = "#a96d35", Steel = "#cfd6de", White = "#fbfbf6", Dark = "#2c3440", Red = "#d43b3b";
        static readonly string[][] Fruit = { new[] { "#e5352c", "#f0584a" }, new[] { "#ff9a1f", "#ffb347" }, new[] { "#7ac943", "#9bd95e" }, new[] { "#ffd93b", "#ffe873" }, new[] { "#8e44ad", "#a65fc2" }, new[] { "#f4f0e0", "#e8e0c8" } };
        static readonly string[][] Pal = { new[] { "#e5352c", "#ffd93b" }, new[] { "#2f8fe6", "#ffffff" }, new[] { "#ff9a1f", "#7a4a2a" }, new[] { "#39b54a", "#fff36b" }, new[] { "#8e44ad", "#ffd9e8" }, new[] { "#00b3b3", "#ffffff" } };
        public static readonly string[] Goods = { "#e5352c", "#ffd93b", "#2f8fe6", "#39b54a", "#ff9a1f", "#ffffff" };

        /// Striped canopy on two posts across a run of units.
        public static void Awning(Geo g, float x, float z, float w, string a, string b)
        {
            g.C(Steel).Box(0.09f, 2.5f, 0.09f, x - w / 2 + 0.1f, 0, z - 0.75f).Box(0.09f, 2.5f, 0.09f, x + w / 2 - 0.1f, 0, z - 0.75f);
            int n = Mathf.Max(2, Mathf.RoundToInt(w / 0.45f));
            for (int k = 0; k < n; k++) { float sx = x - w / 2 + (k + 0.5f) * (w / n); g.C(k % 2 == 1 ? a : b).At(sx, 2.72f, z - 0.3f, 0, 24).Box(w / n, 0.07f, 1.35f).At(sx, 2.36f, z - 0.86f).Box(w / n, 0.2f, 0.06f); }
            g.At();
        }
        /// Sloped fruit stand; `rows` of 2 are stocked.
        public static void Produce(Geo g, float x, float z, int rows, int seed)
        {
            g.C(Wood2).Box(1.75f, 0.5f, 1.2f, x, 0, z).C(Wood).Box(1.75f, 0.08f, 1.24f, x, 0.5f, z);
            for (int t = 0; t < 2; t++)
            {
                float y = 0.58f + t * 0.42f, zz = z + 0.42f - t * 0.42f - 0.12f; var f = Fruit[(seed * 2 + t) % Fruit.Length];
                g.C(Wood).Box(1.7f, 0.24f, 0.6f, x, y, zz).C(Wood2).Box(1.74f, 0.07f, 0.05f, x, y + 0.22f, zz - 0.3f).Box(0.05f, 0.3f, 0.6f, x - 0.86f, y, zz).Box(0.05f, 0.3f, 0.6f, x + 0.86f, y, zz).Box(0.04f, 0.26f, 0.6f, x, y, zz);
                if (t >= rows) continue;
                for (int a = 0; a < 2; a++) for (int i = 0; i < 4; i++) for (int j = 0; j < 3; j++)
                    g.C(f[(i + j) % 2]).Ball(0.115f, 0.11f, 0.115f, x - 0.63f + a * 0.86f + i * 0.14f + (j % 2) * 0.05f - 0.03f, y + 0.3f + (i % 2) * 0.05f + (j == 1 ? 0.06f : 0), zz - 0.17f + j * 0.17f, 10, 6);
                g.C("#fff36b").Box(0.26f, 0.17f, 0.03f, x - 0.42f, y + 0.22f, zz - 0.335f).Box(0.26f, 0.17f, 0.03f, x + 0.42f, y + 0.22f, zz - 0.335f);
            }
        }
        /// Open bread shelves; `rows` of 4 are stocked.
        public static void Bread(Geo g, float x, float z, int rows, int seed)
        {
            g.C(Wood2).Box(0.08f, 2.1f, 0.6f, x - 0.85f, 0, z).Box(0.08f, 2.1f, 0.6f, x + 0.85f, 0, z).C("#8a5628").Box(1.78f, 2.1f, 0.06f, x, 0, z + 0.3f);
            string[] crust = { "#d99a4e", "#c9833a", "#e6b06a", "#e0a85a", "#cf8f3f" };
            for (int s = 0; s < 4; s++)
            {
                float y = 0.3f + s * 0.5f; g.C(Wood).At(x, y, z, 0, -9).Box(1.66f, 0.06f, 0.6f).At(); if (s >= rows) continue;
                for (int i = 0; i < 5; i++)
                {
                    float bx = x - 0.62f + i * 0.31f; string c = crust[(i + s + seed) % crust.Length];
                    if (s % 2 == 1) g.C(c).Ball(0.13f, 0.11f, 0.2f, bx, y + 0.17f, z - 0.02f, 10, 6);
                    else g.C(c).At(bx, y + 0.08f, z - 0.02f, 0, -9).Box(0.2f, 0.2f, 0.42f).C("#f2cf8f").Box(0.16f, 0.05f, 0.36f, 0, 0.19f, 0).At();
                }
            }
        }
        /// Service counter with a slanted display: cuts of meat and cheese, or fish on ice.
        public static void Counter(Geo g, float x, float z, int rows, bool fish, string accent)
        {
            g.C(White).Box(1.9f, 0.9f, 0.9f, x, 0, z).C(accent).Box(1.94f, 0.14f, 0.94f, x, 0.36f, z).C(Steel).Box(1.94f, 0.05f, 0.94f, x, 0.9f, z);
            g.C(fish ? "#e6f4ff" : "#f1f1ee").At(x, 0.95f, z - 0.05f, 0, -12).Box(1.8f, 0.1f, 0.75f).At();
            g.C(Steel).Box(0.05f, 0.5f, 0.05f, x - 0.9f, 0.95f, z + 0.38f).Box(0.05f, 0.5f, 0.05f, x + 0.9f, 0.95f, z + 0.38f).Box(1.86f, 0.05f, 0.3f, x, 1.45f, z + 0.3f);
            string[] meat = { "#d9534f", "#f08a8a", "#ffd93b", "#c0392b", "#ffe9a8", "#e67e73" }, sea = { "#6fb7e8", "#ff9a6b", "#b9c7d6", "#4f9bd6", "#ffb38a", "#dfe7ee" };
            for (int r = 0; r < Mathf.Min(rows, 2); r++) for (int i = 0; i < 7; i++)
            {
                float bx = x - 0.75f + i * 0.25f, bz = z - 0.28f + r * 0.36f, by = 1.06f + r * 0.075f + 0.02f; string c = (fish ? sea : meat)[(i + r * 3) % 6];
                if (fish) g.C(c).Ball(0.1f, 0.05f, 0.17f, bx, by + 0.03f, bz, 9, 5).Box(0.02f, 0.06f, 0.1f, bx, by, bz + 0.18f);
                else if (i % 2 == 0) g.C(c).Box(0.2f, 0.09f, 0.26f, bx, by - 0.03f, bz); else g.C(c).Cyl(0.1f, 0.1f, 0.08f, bx, by - 0.03f, bz, 10);
            }
            g.C(Dark).Box(0.3f, 0.26f, 0.26f, x + 0.6f, 1.5f, z + 0.3f);
        }
        /// Upright chiller; `rows` of 4 shelves are stocked.
        public static void Fridge(Geo g, float x, float z, int rows, string accent, bool tubs, int seed)
        {
            g.C(White).Box(1.85f, 0.3f, 0.7f, x, 0, z).Box(0.07f, 2.0f, 0.7f, x - 0.89f, 0.3f, z).Box(0.07f, 2.0f, 0.7f, x + 0.89f, 0.3f, z).C(accent).Box(1.89f, 0.26f, 0.74f, x, 2.3f, z).C("#eaf6ff").Box(1.85f, 2.0f, 0.06f, x, 0.3f, z + 0.33f);
            string[][] pc = { new[] { "#ffffff", "#2f8fe6" }, new[] { "#fff3b0", "#f29b1d" }, new[] { "#ffd9e8", "#e8438b" }, new[] { "#d9f2cf", "#39b54a" } };
            for (int s = 0; s < 4; s++)
            {
                float y = 0.34f + s * 0.46f; g.C(Steel).Box(1.7f, 0.04f, 0.5f, x, y, z); if (s >= rows) continue;
                for (int i = 0; i < 8; i++)
                {
                    float bx = x - 0.74f + i * 0.21f; var c = pc[(s + seed) % 4];
                    if (tubs) g.C(c[1]).Cyl(0.085f, 0.075f, 0.16f, bx, y + 0.04f, z - 0.1f, 9).C(c[0]).Cyl(0.09f, 0.09f, 0.03f, bx, y + 0.2f, z - 0.1f, 9);
                    else if (s % 2 == 1) g.C(c[0]).Box(0.15f, 0.3f, 0.15f, bx, y + 0.04f, z - 0.1f).C(c[1]).Box(0.155f, 0.1f, 0.155f, bx, y + 0.14f, z - 0.1f).C(c[0]).Box(0.07f, 0.05f, 0.07f, bx, y + 0.34f, z - 0.1f);
                    else g.C(c[0]).Cyl(0.075f, 0.06f, 0.22f, bx, y + 0.04f, z - 0.1f, 9).C(c[1]).Cyl(0.078f, 0.078f, 0.03f, bx, y + 0.26f, z - 0.1f, 9);
                }
            }
            g.C(Steel).Box(0.05f, 1.94f, 0.05f, x - 0.88f, 0.28f, z - 0.34f).Box(0.05f, 1.94f, 0.05f, x + 0.88f, 0.28f, z - 0.34f).Box(0.04f, 1.94f, 0.04f, x, 0.28f, z - 0.34f).Box(1.8f, 0.05f, 0.05f, x, 2.2f, z - 0.34f);
        }
        /// Shelf unit; kind 0 boxes and cans, 1 cans, 2 bags, 3 bottles, 4 jugs. `rows` of 4 are stocked.
        public static void Gondola(Geo g, float x, float z, int rows, int kind, string accent, System.Random rnd)
        {
            g.C("#e9edf2").Box(1.86f, 2.15f, 0.1f, x, 0, z + 0.3f).C(Steel).Box(1.9f, 0.16f, 0.62f, x, 0, z).C(accent).Box(1.9f, 0.14f, 0.64f, x, 2.15f, z + 0.02f);
            for (int s = 0; s < 4; s++)
            {
                float y = 0.16f + s * 0.5f; g.C(White).Box(1.84f, 0.045f, 0.56f, x, y, z).C("#ffec5c").Box(1.84f, 0.07f, 0.02f, x, y - 0.02f, z - 0.28f); if (s >= rows) continue;
                float bx = x - 0.86f;
                while (bx < x + 0.8f)
                {
                    var pc = Pal[rnd.Next(Pal.Length)]; int k = kind == 0 ? (s % 2 == 0 ? 0 : 1) : kind; float w = k == 0 ? 0.2f : k == 1 ? 0.14f : k == 2 ? 0.17f : k == 3 ? 0.13f : 0.22f; int n = 2 + rnd.Next(3);
                    for (int i = 0; i < n && bx < x + 0.84f; i++)
                    {
                        float cx = bx + w / 2, by = y + 0.045f, bz = z - 0.14f;
                        if (k == 0) g.C(pc[0]).Box(w - 0.02f, 0.36f, 0.13f, cx, by, bz).C(pc[1]).Box(w - 0.015f, 0.12f, 0.135f, cx, by + 0.125f, bz);
                        else if (k == 1) g.C(pc[0]).Cyl(0.06f, 0.06f, 0.2f, cx, by, bz, 9).C(pc[1]).Cyl(0.062f, 0.062f, 0.07f, cx, by + 0.055f, bz, 9).C(Steel).Cyl(0.05f, 0.05f, 0.02f, cx, by + 0.2f, bz, 9);
                        else if (k == 2) g.C(pc[0]).Ball(0.085f, 0.16f, 0.06f, cx, by + 0.17f, bz, 9, 6).C(pc[1]).Box(0.1f, 0.08f, 0.065f, cx, by + 0.13f, bz);
                        else if (k == 3) g.C(pc[0]).Cyl(0.055f, 0.055f, 0.24f, cx, by, bz, 9).Cyl(0.055f, 0.025f, 0.08f, cx, by + 0.24f, bz, 9).C(pc[1]).Cyl(0.057f, 0.057f, 0.09f, cx, by + 0.07f, bz, 9).Cyl(0.03f, 0.03f, 0.04f, cx, by + 0.32f, bz, 8);
                        else g.C(pc[0]).Box(w - 0.03f, 0.3f, 0.15f, cx, by, bz).C(pc[1]).Box(w - 0.025f, 0.11f, 0.155f, cx, by + 0.09f, bz).C(Dark).Cyl(0.035f, 0.035f, 0.05f, cx - 0.04f, by + 0.3f, bz, 8);
                        bx += w;
                    }
                    bx += 0.03f;
                }
            }
        }
        public static void Checkout(Geo g, float x, float z, System.Random rnd)
        {
            g.C(White).Box(0.85f, 0.82f, 2.3f, x, 0, z).C(Red).Box(0.89f, 0.12f, 2.34f, x, 0.3f, z).C(Steel).Box(0.89f, 0.05f, 2.34f, x, 0.82f, z).C(Dark).Box(0.6f, 0.02f, 1.3f, x, 0.875f, z + 0.35f);
            g.C(Dark).Box(0.34f, 0.3f, 0.3f, x - 0.1f, 0.87f, z - 0.75f).C(Steel).Box(0.05f, 1.9f, 0.05f, x - 0.36f, 0.87f, z - 1.05f).C(White).Box(0.56f, 0.56f, 0.06f, x - 0.36f, 2.7f, z - 1.0f);
            for (int i = 0; i < 3; i++) g.C(Goods[rnd.Next(4)]).Box(0.16f, 0.2f, 0.14f, x - 0.12f + i * 0.13f, 0.895f, z + 0.6f - i * 0.3f);
            g.C("#c9a36b").Box(0.5f, 0.42f, 0.3f, x, 0.87f, z - 0.25f).C("#b58c52").Box(0.5f, 0.05f, 0.3f, x, 1.29f, z - 0.25f);
        }
        /// Trolley with its handle toward -z.
        public static void Cart(Geo g)
        {
            var keep = g.M;
            foreach (var w in new[] { new Vector2(-0.24f, -0.36f), new Vector2(0.24f, -0.36f), new Vector2(-0.24f, 0.36f), new Vector2(0.24f, 0.36f) }) g.C(Dark).Cyl(0.07f, 0.07f, 0.06f, w.x, 0, w.y, 8).C(Steel).Box(0.03f, 0.34f, 0.03f, w.x, 0.06f, w.y);
            g.C(Steel).Box(0.56f, 0.03f, 0.84f, 0, 0.4f, 0);
            for (int k = 0; k < 6; k++) g.Box(0.02f, 0.4f, 0.02f, -0.28f, 0.42f, -0.42f + k * 0.168f).Box(0.02f, 0.4f, 0.02f, 0.28f, 0.42f, -0.42f + k * 0.168f);
            for (int k = 0; k < 4; k++) g.Box(0.02f, 0.4f, 0.02f, -0.28f + k * 0.187f, 0.42f, 0.42f).Box(0.02f, 0.4f, 0.02f, -0.28f + k * 0.187f, 0.42f, -0.42f);
            g.Box(0.6f, 0.03f, 0.03f, 0, 0.82f, 0.42f).Box(0.6f, 0.03f, 0.03f, 0, 0.82f, -0.42f).Box(0.03f, 0.03f, 0.87f, -0.28f, 0.82f, 0).Box(0.03f, 0.03f, 0.87f, 0.28f, 0.82f, 0).C(Red).Box(0.62f, 0.05f, 0.05f, 0, 0.95f, -0.5f).C(Steel).Box(0.03f, 0.16f, 0.03f, -0.27f, 0.82f, -0.48f).Box(0.03f, 0.16f, 0.03f, 0.27f, 0.82f, -0.48f);
            g.At(keep);
        }
        public static void CartGoods(Geo g, System.Random rnd)
        {
            for (int i = 0; i < 7; i++)
            {
                string c = Goods[rnd.Next(Goods.Length)]; float y = 0.44f + (i > 3 ? 0.2f : 0);
                if (i % 2 == 1) g.C(c).Box(0.17f, 0.26f, 0.12f, -0.14f + (i % 3) * 0.14f, y, -0.25f + (i % 4) * 0.17f); else g.C(c).Ball(0.1f, 0.1f, 0.1f, -0.12f + (i % 3) * 0.13f, y + 0.12f, -0.22f + (i % 4) * 0.16f, 8, 5);
            }
        }
        /// Chunky car, nose toward +z.
        public static void Car(Geo g, Color body, bool lux = false)
        {
            Color d = body * 0.8f; d.a = 1; float len = lux ? 4.6f : 4.0f; var keep = g.M;
            g.C(body).Box(1.75f, 0.52f, len, 0, 0.3f, 0).C(d).Box(1.79f, 0.12f, len + 0.04f, 0, 0.3f, 0).C(body).Box(1.56f, 0.5f, 2.1f, 0, 0.82f, -0.15f).C("#bfe6ff").Box(1.58f, 0.36f, 1.7f, 0, 0.88f, -0.15f).C("#d9f1ff").Box(1.36f, 0.36f, 2.12f, 0, 0.88f, -0.15f).C(body).Box(1.6f, 0.06f, 2.14f, 0, 1.3f, -0.15f).Box(0.08f, 0.5f, 0.1f, -0.76f, 0.82f, -0.15f).Box(0.08f, 0.5f, 0.1f, 0.76f, 0.82f, -0.15f);
            foreach (var w in new[] { new Vector2(-0.82f, 1.25f), new Vector2(0.82f, 1.25f), new Vector2(-0.82f, -1.3f), new Vector2(0.82f, -1.3f) })
            {
                g.At(keep * Matrix4x4.TRS(new Vector3(w.x + (w.x < 0 ? -0.02f : 0.24f), 0.33f, w.y), Quaternion.Euler(0, 0, 90), Vector3.one)); g.C("#22262e").Cyl(0.33f, 0.33f, 0.22f, 0, 0, 0, 14).C(Steel).Cyl(0.17f, 0.17f, 0.24f, 0, 0, 0, 10);
            }
            g.At(keep).C("#fff7c2").Box(0.34f, 0.14f, 0.04f, -0.55f, 0.52f, len / 2).Box(0.34f, 0.14f, 0.04f, 0.55f, 0.52f, len / 2).C("#ff5a5a").Box(0.3f, 0.12f, 0.04f, -0.58f, 0.55f, -len / 2).Box(0.3f, 0.12f, 0.04f, 0.58f, 0.55f, -len / 2).C(Dark).Box(1.5f, 0.14f, 0.06f, 0, 0.34f, len / 2);
            if (lux) g.C("#ffd43b").Box(1.77f, 0.05f, len + 0.02f, 0, 0.56f, 0).Box(0.5f, 0.1f, 0.1f, 0, 0.82f, len / 2 - 0.3f);
        }
        /// Delivery truck, cab toward +z.
        public static void Truck(Geo g)
        {
            var keep = g.M;
            g.C(White).Box(2.0f, 2.1f, 3.6f, 0, 0.55f, -0.7f).C(Red).Box(2.04f, 0.5f, 3.64f, 0, 1.2f, -0.7f).C("#ffd43b").Box(1.9f, 1.5f, 1.4f, 0, 0.5f, 1.9f).C("#bfe6ff").Box(1.7f, 0.55f, 1.42f, 0, 1.3f, 1.92f).C(Dark).Box(2.0f, 0.2f, 5.2f, 0, 0.35f, 0.1f);
            foreach (var w in new[] { new Vector2(-1f, 1.8f), new Vector2(1f, 1.8f), new Vector2(-1f, -1.5f), new Vector2(1f, -1.5f) }) { g.At(keep * Matrix4x4.TRS(new Vector3(w.x + (w.x < 0 ? -0.02f : 0.26f), 0.4f, w.y), Quaternion.Euler(0, 0, 90), Vector3.one)); g.C("#22262e").Cyl(0.4f, 0.4f, 0.24f, 0, 0, 0, 14).C(Steel).Cyl(0.2f, 0.2f, 0.26f, 0, 0, 0, 10); }
            g.At(keep);
        }
        public static void Tree(Geo g, float x, float z, float s) { g.C("#8a5a34").Cyl(0.16f * s, 0.2f * s, 1.1f * s, x, 0, z, 8); g.C("#3fa652").Ball(1.0f * s, 0.9f * s, 1.0f * s, x, 1.9f * s, z, 12, 8).C("#57bf63").Ball(0.72f * s, 0.66f * s, 0.72f * s, x - 0.35f * s, 2.45f * s, z - 0.25f * s, 11, 7).C("#6fd072").Ball(0.5f * s, 0.46f * s, 0.5f * s, x + 0.4f * s, 2.6f * s, z + 0.1f * s, 10, 6); }
    }

    /// One toy-like person: large head, short body, limbs that swing when walking.
    public class Person
    {
        public GameObject go; public Transform body; public bool walking; public float phase, speed = 1; Transform legL, legR, armL, armR; bool push;
        static readonly string[] Shirt = { "#ff6b6b", "#4dabf7", "#ffd43b", "#69db7c", "#b197fc", "#ffa94d", "#f783ac", "#3bc9db", "#ffffff" };
        static readonly string[] Pants = { "#3b5b8c", "#2f4a78", "#55607a", "#7a5a3c", "#2f3642", "#c8b08a", "#6a8fbf" }, Skin = { "#f6c9a0", "#e9b184", "#c98d5e", "#8f5b3a", "#fbd6b5" }, Hair = { "#3a2a20", "#6b4423", "#111418", "#d9b45a", "#e8cf7a", "#a8452a", "#8a8f99", "#c98a4b" };
        public static bool Rigged => true;
        public static void Reset() { }

        Transform Limb(string name, Geo g, Vector3 pivot) { var t = g.Make(name, body, Kit.Solid).transform; t.localPosition = pivot; return t; }

        static readonly string[] Dress = { "#ff7aa8", "#7b5be6", "#22b8a5", "#f5a524", "#e5484d", "#3b82f6" }, Scarf = { "#e9c7a5", "#c94f7c", "#3b6fb5", "#2f9e8f", "#8a6fd1", "#f4f4f5" }, Pack = { "#e5484d", "#3b82f6", "#22b8a5", "#f5a524" };

        /// `uniform`: staff colour; null for a shopper. `pushing`: arms held forward on a trolley.
        /// Staff all wear the same full uniform. Shoppers vary: build, age, hair, clothes and what they carry.
        public Person(Transform parent, int look, Color? uniform, bool pushing = false)
        {
            go = new GameObject("person"); go.transform.SetParent(parent, false); body = new GameObject("body").transform; body.SetParent(go.transform, false);
            phase = (look % 97) * 0.13f; push = pushing; bool staff = uniform.HasValue;
            uint h = (uint)look * 2654435761u; h ^= h >> 15;
            int outfit = staff ? 0 : (int)(h % 10); if (!Loc.Ar && outfit >= 7) outfit = (int)(h % 5); else if (Loc.Ar && outfit == 9) outfit = 7; bool kid = !staff && outfit < 5 && (h / 10) % 6 == 0; int hairStyle = (int)((h / 60) % 6), acc = (int)((h / 360) % 6); float wide = staff ? 1f : 0.88f + ((h / 2160) % 5) * 0.07f;
            float tall = staff ? 1.06f : kid ? 0.70f : 0.92f + ((h / 10800) % 5) * 0.04f; body.localScale = new Vector3(tall, tall, tall);
            string skin = Skin[(int)((h / 7) % (uint)Skin.Length)], bot = Pants[(int)((h / 3) % (uint)Pants.Length)], hair = Hair[(int)((h / 5) % (uint)Hair.Length)];
            Color top = staff ? uniform.Value : Geo.Hex(Shirt[(int)(h % (uint)Shirt.Length)]); bool robe = false; string robeCol = null, cloth = null; int head = hairStyle;   // 0 short 1 long 2 ponytail 3 curly 4 bun 5 bald
            if (outfit == 5 || outfit == 6) { robe = true; robeCol = Dress[(int)((h / 11) % (uint)Dress.Length)]; top = Geo.Hex(robeCol); head = 1 + (int)((h / 13) % 3) % 3; if (head == 3) head = 4; }
            else if (outfit == 7) { robe = true; robeCol = (h / 17) % 2 == 0 ? "#2b2d3a" : "#4a3f6b"; top = Geo.Hex(robeCol); head = 6; cloth = Scarf[(int)((h / 19) % (uint)Scarf.Length)]; }
            else if (outfit == 8) { robe = true; robeCol = "#f7f5ee"; top = Geo.Hex(robeCol); head = 7; cloth = (h / 23) % 2 == 0 ? "#ffffff" : "#e8443c"; }
            var g = new Geo();
            g.C(top).Ball(0.3f * wide, 0.36f, 0.23f * wide, 0, 0.82f, 0, 14, 9);
            if (robe) g.C(robeCol).Cyl(0.33f * wide, 0.25f * wide, 0.62f, 0, 0.1f, 0, 14); else g.C(bot).Cyl(0.26f * wide, 0.27f * wide, 0.12f, 0, 0.44f, 0, 12);
            if (!staff && !robe)
            {
                int style = (int)((h / 41) % 4);
                if (style == 0) g.C(top * 0.82f).Ball(0.2f, 0.18f, 0.12f, 0, 1.12f, -0.2f, 9, 5).Box(0.26f * wide, 0.12f, 0.05f, 0, 0.62f, 0.21f * wide);                                             // hoodie: hood and pouch
                else if (style == 1) { g.C(Art.White).Box(0.16f * wide, 0.44f, 0.04f, 0, 0.62f, 0.215f * wide); g.C(top * 0.8f).Box(0.05f, 0.44f, 0.045f, -0.1f * wide, 0.62f, 0.22f * wide).Box(0.05f, 0.44f, 0.045f, 0.1f * wide, 0.62f, 0.22f * wide); }   // open jacket over a white tee
                else if (style == 2) g.C(Art.White).Ball(0.11f, 0.11f, 0.03f, 0, 0.9f, 0.215f * wide, 10, 5);                                                  // tee with a chest print
            }
            if (staff)
            {
                // uniform: section-coloured shirt, long white apron with a coloured pocket, name badge, peaked cap
                g.C(Art.White).Box(0.42f, 0.62f, 0.05f, 0, 0.36f, 0.2f).Box(0.06f, 0.3f, 0.04f, -0.15f, 0.9f, 0.2f).Box(0.06f, 0.3f, 0.04f, 0.15f, 0.9f, 0.2f).C(uniform.Value).Box(0.2f, 0.14f, 0.06f, 0, 0.5f, 0.2f).C("#ffd43b").Box(0.11f, 0.07f, 0.06f, 0.13f, 0.86f, 0.21f);
            }
            g.C(skin).Cyl(0.1f, 0.1f, 0.08f, 0, 1.12f, 0, 9).Ball(0.33f, 0.31f, 0.3f, 0, 1.47f, 0, 16, 11);
            if (staff) g.C(hair).Ball(0.335f, 0.2f, 0.31f, 0, 1.5f, -0.05f, 14, 7).C(uniform.Value).Ball(0.35f, 0.16f, 0.33f, 0, 1.68f, 0, 16, 6).Box(0.42f, 0.04f, 0.26f, 0, 1.6f, 0.34f).C(Art.White).Box(0.16f, 0.1f, 0.03f, 0, 1.7f, 0.32f);
            else switch (head)
            {
                case 0: g.C(hair).Ball(0.345f, 0.26f, 0.32f, 0, 1.56f, -0.035f, 16, 8); break;
                case 1: g.C(hair).Ball(0.345f, 0.26f, 0.32f, 0, 1.56f, -0.035f, 16, 8).Ball(0.3f, 0.34f, 0.16f, 0, 1.26f, -0.2f, 12, 7); break;
                case 2: g.C(hair).Ball(0.345f, 0.26f, 0.32f, 0, 1.56f, -0.035f, 16, 8).Ball(0.11f, 0.24f, 0.11f, 0, 1.36f, -0.36f, 9, 6).C("#ff4f8b").Ball(0.07f, 0.05f, 0.07f, 0, 1.56f, -0.33f, 7, 4); break;
                case 3: g.C(hair); for (int k = 0; k < 9; k++) { float a = k / 9f * Mathf.PI * 2; g.Ball(0.15f, 0.15f, 0.15f, Mathf.Cos(a) * 0.24f, 1.66f + (k % 2) * 0.04f, Mathf.Sin(a) * 0.22f - 0.04f, 8, 5); } g.Ball(0.22f, 0.16f, 0.22f, 0, 1.74f, -0.03f, 9, 5); break;
                case 4: g.C(hair).Ball(0.345f, 0.26f, 0.32f, 0, 1.56f, -0.035f, 16, 8).Ball(0.15f, 0.15f, 0.15f, 0, 1.85f, -0.06f, 9, 6); break;
                case 5: g.C(hair).Ball(0.21f, 0.13f, 0.1f, 0, 1.3f, 0.19f, 9, 5); break;     // bald, with a beard
                case 6: g.C(cloth).Ball(0.37f, 0.35f, 0.33f, 0, 1.5f, -0.08f, 16, 9).Cyl(0.31f, 0.2f, 0.28f, 0, 0.98f, -0.02f, 12); break;      // headscarf
                default: g.C("#fbfbf6").Ball(0.36f, 0.3f, 0.33f, 0, 1.55f, -0.07f, 16, 8).Box(0.6f, 0.52f, 0.07f, 0, 0.98f, -0.23f).C(cloth == "#ffffff" ? "#20242c" : "#20242c").Cyl(0.31f, 0.31f, 0.045f, 0, 1.69f, -0.04f, 14); break;   // head cloth with band
            }
            g.C("#20242c").Ball(0.04f, 0.055f, 0.03f, -0.12f, 1.45f, 0.28f, 8, 5).Ball(0.04f, 0.055f, 0.03f, 0.12f, 1.45f, 0.28f, 8, 5).C("#f08a8a").Ball(0.05f, 0.03f, 0.02f, -0.2f, 1.36f, 0.24f, 8, 4).Ball(0.05f, 0.03f, 0.02f, 0.2f, 1.36f, 0.24f, 8, 4);
            if (!staff)
            {
                if (acc == 0) g.C("#1f2430").Box(0.16f, 0.1f, 0.03f, -0.12f, 1.4f, 0.3f).Box(0.16f, 0.1f, 0.03f, 0.12f, 1.4f, 0.3f).Box(0.1f, 0.03f, 0.03f, 0, 1.46f, 0.3f);                         // glasses
                else if (acc == 1 && head < 5) g.C("#e8cf8f").Cyl(0.46f, 0.46f, 0.03f, 0, 1.7f, 0, 16).Cyl(0.27f, 0.25f, 0.15f, 0, 1.73f, 0, 14).C("#d9483b").Cyl(0.275f, 0.275f, 0.04f, 0, 1.74f, 0, 14);     // sun hat
                else if (acc == 2) g.C(Pack[(int)((h / 29) % (uint)Pack.Length)]).Box(0.36f, 0.42f, 0.17f, 0, 0.6f, -0.28f * wide).C("#20242c").Box(0.2f, 0.12f, 0.03f, 0, 0.72f, -0.38f * wide);      // backpack
                else if (acc == 3 && head < 6) g.C(Pack[(int)((h / 31) % (uint)Pack.Length)]).Ball(0.35f, 0.17f, 0.33f, 0, 1.67f, 0, 16, 6).Box(0.4f, 0.04f, 0.28f, 0, 1.6f, 0.33f);        // baseball cap
                else if (acc == 4 && !robe) g.C(Art.Dark).Box(0.06f, 0.2f, 0.16f, -0.34f, 1.42f, 0).Box(0.06f, 0.2f, 0.16f, 0.34f, 1.42f, 0).Box(0.7f, 0.05f, 0.08f, 0, 1.78f, 0);                                              // headphones                                              // scarf round the shoulders
            }
            g.Make("torso", body, Kit.Solid);
            // limbs hang from their pivots so a turn at the hip or shoulder swings them
            string legCol = robe ? robeCol : bot; Color sleeve = top;
            for (int s = -1; s <= 1; s += 2)
            {
                var leg = new Geo(); leg.C(legCol).Cyl(0.1f, 0.11f, 0.4f, 0, -0.4f, 0, 10).C(robe ? "#6b4a2c" : "#2a2f38").Box(0.17f, 0.09f, 0.3f, 0, -0.48f, 0.03f);
                var lt = Limb("leg", leg, new Vector3(s * 0.13f * wide, 0.48f, 0)); if (s < 0) legL = lt; else legR = lt;
                var arm = new Geo(); arm.C(sleeve).Cyl(0.085f, 0.09f, 0.26f, 0, -0.26f, 0, 9).C(robe ? sleeve : Geo.Hex(skin)).Cyl(0.07f, 0.08f, 0.2f, 0, -0.46f, 0, 9).C(skin).Ball(0.085f, 0.085f, 0.085f, 0, -0.5f, 0, 9, 6);
                var at = Limb("arm", arm, new Vector3(s * 0.33f * wide, 1.0f, 0)); if (s < 0) armL = at; else armR = at;
            }
            Pose(0, false);
        }

        void Pose(float time, bool busy)
        {
            float ph = time * 9f * speed + phase, sw = walking ? Mathf.Sin(ph) : 0;
            legL.localRotation = Quaternion.Euler(-32f * sw, 0, 0); legR.localRotation = Quaternion.Euler(32f * sw, 0, 0);
            float hold = push ? -62f : 0, work = busy ? 28f * Mathf.Sin(time * 9f + phase) : 0;
            armL.localRotation = Quaternion.Euler(hold + (push ? 0 : 26f * sw) - Mathf.Max(0, work) * 1.6f, 0, -9f); armR.localRotation = Quaternion.Euler(hold - (push ? 0 : 26f * sw) - Mathf.Max(0, -work) * 1.6f, 0, 9f);
            body.localPosition = new Vector3(0, walking ? 0.045f * Mathf.Abs(Mathf.Sin(ph)) : 0.012f * Mathf.Sin(time * 2.2f + phase), 0);
            body.localRotation = Quaternion.Euler(walking ? 4f : busy ? 3f * Mathf.Sin(time * 9f + phase) : 0, busy ? 8f * Mathf.Sin(time * 4.5f + phase) : 0, walking ? 2.5f * sw : 0);
        }
        public void Set(bool walk, bool busy, float time, float dt) { walking = walk; Pose(time, busy); }
    }

    public class DeptView
    {
        public int d; public Transform root, props; public Vector3 center; public Material tapeMat, signMat; public TextMesh name;
        public Person[] staff = new Person[T.MaxStaff]; public int builtTier = -2, builtRows = -1; public bool builtOpen; public float pop; public BoxCollider hit;
    }

    public class Actor { public Person p; public GameObject go; public bool moving; public GameObject cart, goods, gift, car; public Vector3 carPos; public float carYaw; }

    public class World
    {
        public Transform root; public Camera cam; public Sim sim;
        public DeptView[] depts = new DeptView[T.ND];
        public GameObject[] cashDesk = new GameObject[T.NC]; public Person[] cashStaff = new Person[T.NC]; Material[] cashLamp = new Material[T.NC];
        public GameObject truck, vip; public Vector3 truckPos = new Vector3(6.4f, 0, -1.3f), vipPos = new Vector3(-6.4f, 0, -1.3f), busPos = new Vector3(8.3f, 0, -4.4f);
        public const float RoadZ = -4.4f;
        readonly Dictionary<int, Actor> actors = new Dictionary<int, Actor>(); readonly List<int> gone = new List<int>();
        Transform slotRoot; int slotsBuilt; float time; Light sun; Material bandMat; int bandStar = -1; Mesh cartMesh; readonly System.Random rnd = new System.Random(7);
        class Pop { public Transform t; public float age, dur, delay; public Vector3 scale; }
        readonly List<Pop> pops = new List<Pop>();
        public float shake;

        public static readonly Color[] DeptColor =
        {
            Geo.Hex("#39b54a"), Geo.Hex("#f29b1d"), Geo.Hex("#d9483b"), Geo.Hex("#1fa3c8"), Geo.Hex("#2f8fe6"), Geo.Hex("#5bc8d8"),
            Geo.Hex("#7b5be6"), Geo.Hex("#e8438b"), Geo.Hex("#b87333"), Geo.Hex("#00a88f"), Geo.Hex("#d94fb0"),
        };
        static readonly string[] CarCol = { "#e5484d", "#3b82f6", "#f4f4f5", "#f5a524", "#22b8a5", "#8b5cf6", "#1f2937", "#f783ac" };
        static readonly string[] GradeBand = { "#d43b3b", "#1f6fd1", "#16905c", "#8e3fb5", "#d98a12", "#1b2030" };
        static readonly float[] SlotX = { -3.06f, -1.02f, 1.02f, 3.06f };

        public const float HalfW = 9f, DeptRow0 = 13f, DeptRowGap = 9.5f, CashZ = 4.2f;
        public static Vector3 DeptCenter(int d) => new Vector3(d % 2 == 0 ? -4.5f : 4.5f, 0, DeptRow0 + (d / 2) * DeptRowGap);
        public static float StoreDepth => DeptRow0 + 5 * DeptRowGap + 6.5f;
        public static Vector3 StaffPos(int d, int k) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 2.15f);
        public static Vector3 QueuePos(int d, int k, int q) => DeptCenter(d) + new Vector3((k - 2) * 1.3f, 0, 0.2f - q * 1.05f);
        public static Vector3 CashPos(int c) => new Vector3(-7.35f + c * 2.1f, 0, CashZ);
        public static Vector3 CashQueuePos(int c, int q) => CashPos(c) + new Vector3(0.82f, 0, 0.4f + q * 1.05f);
        public static Vector3 SlotPos(int i) => new Vector3(-7.5f + (i % 6) * 3f, 0, -9.0f - (i / 6) * 4.6f);
        public static Vector3 DeptFx(int d) => DeptCenter(d) + new Vector3(0, 1.4f, 3.0f);
        static readonly Vector3 Door = new Vector3(0, 0, 0.2f);

        public World(Sim s) { sim = s; }

        // ---------- build ----------
        public void Build()
        {
            Kit.Init(); root = new GameObject("World").transform;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat; RenderSettings.ambientLight = Color.white; RenderSettings.fog = false;
            sun = new GameObject("Sun").AddComponent<Light>(); sun.transform.SetParent(root, false);
            sun.type = LightType.Directional; sun.color = new Color(1f, 0.96f, 0.88f); sun.intensity = 1f; sun.shadows = LightShadows.Soft; sun.shadowStrength = 1f;
            sun.transform.rotation = Quaternion.Euler(58, 22, 0);

            float depth = StoreDepth; var g = new Geo(); g.Shade = 0;
            // ground, all drawn as flat coloured pieces: grass, asphalt, pavement, cream tiles on a grout base
            g.C("#7cc45a").Box(240, 0.4f, depth + 220, 0, -0.52f, depth / 2 - 40);
            for (int k = 0; k < 420; k++) { float x = (float)rnd.NextDouble() * 150 - 75, z = (float)rnd.NextDouble() * (depth + 150) - 120; if (Mathf.Abs(x) < 13.5f && z < depth + 2) continue; g.C(k % 3 == 0 ? "#86cc62" : k % 3 == 1 ? "#72bb52" : "#8fd26a").Slab(1.2f + (float)rnd.NextDouble() * 1.4f, 0.7f + (float)rnd.NextDouble() * 0.8f, 0.34f, x, -0.125f, z, 0.004f); }
            g.C("#4b5263").Slab(27, 128, 1.2f, 0, -0.13f, -2.4f - 62);
            g.C("#ffd24a"); for (float x = -12; x < 12; x += 3) g.Slab(1.5f, 0.16f, 0.07f, x + 1, -0.118f, RoadZ, 0.004f);
            g.C("#d9d4c8").Slab(27, 2.6f, 0.3f, 0, -0.118f, -1.3f, 0.02f).C("#c7c1b3"); for (float x = -13; x <= 13; x += 1.3f) g.Box(0.03f, 0.004f, 2.5f, x, -0.098f, -1.3f);
            g.C("#d9cdb6").Box(HalfW * 2, 0.1f, depth, 0, -0.1f, depth / 2);
            for (int ix = 0; ix < 18; ix++) for (int iz = 0; iz < Mathf.CeilToInt(depth); iz++) g.C((ix + iz) % 2 == 0 ? "#f6efdf" : "#efe6d2").Box(0.975f, 0.004f, 0.975f, -HalfW + 0.5f + ix, 0, 0.5f + iz);
            // entrance mat and lane arrows
            g.C(Art.Red).Slab(3.4f, 1.3f, 0.2f, 0, 0.004f, 0.9f).C(Art.White).Slab(3.1f, 1.0f, 0.14f, 0, 0.018f, 0.9f, 0.002f).C(Art.Red).Slab(3.0f, 0.9f, 0.12f, 0, 0.021f, 0.9f, 0.002f);
            for (int c = 0; c < T.NC; c++) { float x = CashPos(c).x + 0.82f; g.C("#3ca05a").Box(0.18f, 0.004f, 0.5f, x, 0.004f, 2.1f).Box(0.5f, 0.004f, 0.16f, x, 0.004f, 1.85f).Box(0.3f, 0.004f, 0.16f, x, 0.004f, 1.72f); }
            g.Make("ground", root, Kit.Solid, false);

            // shell: low side walls and a tall back wall with the brand band; open front with a portal
            var w = new Geo(); bandMat = new Material(Kit.Solid);
            w.C(Art.White).Box(0.6f, 2.8f, depth, -HalfW - 0.3f, 0, depth / 2).Box(0.6f, 2.8f, depth, HalfW + 0.3f, 0, depth / 2).Box(HalfW * 2 + 1.2f, 4.2f, 0.6f, 0, 0, depth + 0.3f);
            w.C("#d9d2c3").Box(0.7f, 0.14f, depth + 0.1f, -HalfW - 0.3f, 2.8f, depth / 2).Box(0.7f, 0.14f, depth + 0.1f, HalfW + 0.3f, 2.8f, depth / 2).Box(HalfW * 2 + 1.3f, 0.14f, 0.7f, 0, 4.2f, depth + 0.3f);
            // shop front: a low wall with window frames either side of the doorway, and two glass doors slid open
            foreach (float sx in new[] { -1f, 1f })
            {
                float x0 = sx * 2.85f, x1 = sx * (HalfW + 0.05f), mid = (x0 + x1) / 2, len = Mathf.Abs(x1 - x0);
                w.C(Art.White).Box(len, 0.9f, 0.3f, mid, 0, -0.05f).C("#d9d2c3").Box(len + 0.04f, 0.08f, 0.36f, mid, 0.9f, -0.05f).C(Art.Steel).Box(len, 0.07f, 0.1f, mid, 2.3f, -0.05f);
                for (float x = Mathf.Min(x0, x1) + 0.05f; x <= Mathf.Max(x0, x1) + 0.01f; x += (len - 0.1f) / 4f) w.C(Art.Steel).Box(0.07f, 1.4f, 0.1f, x, 0.9f, -0.05f);
                w.C(Art.Steel).Box(0.08f, 2.5f, 0.1f, sx * 2.25f, 0, -0.2f).Box(0.08f, 2.5f, 0.1f, sx * 1.25f, 0, -0.2f).Box(1.08f, 0.08f, 0.1f, sx * 1.75f, 2.5f, -0.2f).Box(1.08f, 0.12f, 0.1f, sx * 1.75f, 0, -0.2f).C("#bfe6ff").Box(0.9f, 0.05f, 0.04f, sx * 1.75f, 1.2f, -0.2f);
            }
            foreach (float x in new[] { -HalfW - 0.3f, -2.85f, 2.85f, HalfW + 0.3f }) w.C(Art.White).Box(0.6f, 3.0f, 0.6f, x, 0, -0.05f);
            w.C(Art.White).Box(6.0f, 0.08f, 0.5f, 0, 3.08f, -0.05f).Box(6.0f, 0.08f, 0.5f, 0, 4.14f, -0.05f);
            // the store emblem: three fruits between two cream bars
            w.C("#ffd43b").Ball(0.2f, 0.2f, 0.07f, -2.72f, 3.62f, -0.3f).C("#7ac943").Ball(0.2f, 0.2f, 0.07f, -2.46f, 3.7f, -0.31f).C("#ff9a1f").Ball(0.2f, 0.2f, 0.07f, 2.72f, 3.62f, -0.3f).C("#e5352c").Ball(0.2f, 0.2f, 0.07f, 2.46f, 3.7f, -0.31f);
            w.Make("shell", root, Kit.Solid);
            var b = new Geo(); b.C(Color.white).Box(0.64f, 0.46f, depth + 0.04f, -HalfW - 0.3f, 2.1f, depth / 2).Box(0.64f, 0.46f, depth + 0.04f, HalfW + 0.3f, 2.1f, depth / 2).Box(HalfW * 2 + 1.24f, 0.6f, 0.64f, 0, 3.3f, depth + 0.3f).Box(6.4f, 1.22f, 0.44f, 0, 3.0f, -0.05f);
            foreach (float x in new[] { -HalfW - 0.3f, -2.85f, 2.85f, HalfW + 0.3f }) b.Box(0.64f, 0.3f, 0.64f, x, 0, -0.05f);
            b.Make("band", root, bandMat);
            Kit.Label("SOUQ MARKET", root, new Vector3(0, 3.62f, -0.29f), 0.56f, new Color(1f, 0.97f, 0.84f));

            // street: cart bay, planters, lamps, trees, bays for the truck and the VIP car
            var s = new Geo();
            for (int i = 0; i < 5; i++) { s.At(-4.4f, 0, -0.7f - i * 0.3f, 90); Art.Cart(s); }
            s.At().C(Art.Steel).Box(1.9f, 0.9f, 0.06f, -4.6f, 0, -0.2f).Box(1.9f, 0.9f, 0.06f, -4.6f, 0, -2.25f);
            foreach (float x in new[] { -3.3f, 3.3f }) { s.C("#b9b2a2").Box(1.0f, 0.5f, 1.0f, x, 0, -1.1f).C("#6b4a2c").Box(0.86f, 0.06f, 0.86f, x, 0.5f, -1.1f).C("#3fa652").Ball(0.5f, 0.42f, 0.5f, x, 0.9f, -1.1f, 12, 7).C("#ff7aa8"); for (int i = 0; i < 6; i++) s.Ball(0.09f, 0.09f, 0.09f, x + Mathf.Cos(i) * 0.3f, 1.15f + (i % 2) * 0.08f, -1.1f + Mathf.Sin(i) * 0.3f, 7, 5); }
            foreach (float x in new[] { -10.5f, 10.5f }) s.C(Art.Dark).Cyl(0.07f, 0.09f, 4.2f, x, 0, -2.2f, 8).Box(0.9f, 0.08f, 0.3f, x + (x < 0 ? 0.4f : -0.4f), 4.2f, -2.2f).C("#fff6c8").Box(0.6f, 0.05f, 0.22f, x + (x < 0 ? 0.5f : -0.5f), 4.14f, -2.2f);
            for (int i = 0; i < 12; i++) { float z = -30 + i * 9f; Art.Tree(s, -14.5f - (i % 2) * 2.2f, z, 1.1f + (i % 3) * 0.15f); Art.Tree(s, 14.5f + (i % 2) * 2.2f, z + 4, 1.1f + ((i + 1) % 3) * 0.15f); }
            s.C("#ffd24a").Slab(5.6f, 2.3f, 0.2f, truckPos.x, -0.09f, truckPos.z, 0.004f).C("#d9d4c8").Slab(5.3f, 2.0f, 0.14f, truckPos.x, -0.086f, truckPos.z, 0.004f).C("#b06be0").Slab(5.6f, 2.3f, 0.2f, vipPos.x, -0.09f, vipPos.z, 0.004f).C("#d9d4c8").Slab(5.3f, 2.0f, 0.14f, vipPos.x, -0.086f, vipPos.z, 0.004f);
            s.Make("street", root, Kit.Solid);

            var cg = new Geo(); Art.Cart(cg); cartMesh = cg.ToMesh("cart");
            for (int c = 0; c < T.NC; c++) BuildCash(c);
            for (int d = 0; d < T.ND; d++) BuildDept(d);
            slotRoot = new GameObject("Slots").transform; slotRoot.SetParent(root, false);
            SyncStatic(true);
            Debug.Log("World: built from code, shader ok = " + (Kit.Missing == 0));
        }

        void BuildCash(int c)
        {
            var p = CashPos(c); var holder = new GameObject("cash" + c); holder.transform.SetParent(root, false);
            var g = new Geo(); Art.Checkout(g, p.x, p.z, rnd); g.Make("desk", holder.transform, Kit.Solid);
            cashLamp[c] = Kit.GlowTint(new Color(0.32f, 0.88f, 0.48f)); var lamp = new Geo(); lamp.C(Color.white).Box(0.46f, 0.46f, 0.08f, p.x - 0.36f, 2.75f, p.z - 1.05f).At(p.x - 0.1f, 1.2f, p.z - 0.75f, 0, 17).Box(0.4f, 0.3f, 0.04f); lamp.Make("lamp", holder.transform, cashLamp[c], false);
            cashStaff[c] = new Person(holder.transform, 31 + c * 5, Geo.Hex(Art.Red)); cashStaff[c].go.transform.position = p + new Vector3(-0.78f, 0, -0.3f); cashStaff[c].go.transform.rotation = Quaternion.Euler(0, 90, 0);
            cashDesk[c] = holder;
        }

        void BuildDept(int d)
        {
            var v = new DeptView { d = d, center = DeptCenter(d) }; var g = new GameObject("dept" + d); g.transform.SetParent(root, false); v.root = g.transform;
            v.tapeMat = new Material(Kit.Solid); v.signMat = Kit.GlowTint(DeptColor[d]);
            // floor mat: a pale field with a coloured keyline and a dashed inner line
            var m = new Geo(); m.Shade = 0; float mx = v.center.x, mz = v.center.z + 0.7f;
            m.C(Color.white).Slab(8.3f, 8.0f, 0.5f, mx, 0.004f, mz, 0.004f); m.Make("line", g.transform, v.tapeMat, false);
            var f = new Geo(); f.Shade = 0; f.C(Color.Lerp(DeptColor[d], Color.white, 0.80f)).Slab(8.0f, 7.7f, 0.4f, mx, 0.009f, mz, 0.003f).C(Art.White);
            for (float x = -3.4f; x <= 3.4f; x += 0.62f) f.Box(0.36f, 0.003f, 0.05f, mx + x, 0.012f, mz - 3.55f).Box(0.36f, 0.003f, 0.05f, mx + x, 0.012f, mz + 3.55f);
            for (float z = -3.2f; z <= 3.2f; z += 0.62f) f.Box(0.05f, 0.003f, 0.36f, mx - 3.7f, 0.012f, mz + z).Box(0.05f, 0.003f, 0.36f, mx + 3.7f, 0.012f, mz + z);
            f.Make("field", g.transform, Kit.Solid, false);
            // the section's name on a board mounted above its own fixtures
            float bz = v.center.z + 4.02f; var post = new Geo(); post.C(Art.Steel).Box(0.09f, 3.2f, 0.09f, mx - 4.0f, 0, bz).Box(0.09f, 3.2f, 0.09f, mx + 4.0f, 0, bz).C(Art.White).Box(8.1f, 0.07f, 0.2f, mx, 3.2f, bz).Box(8.1f, 0.07f, 0.2f, mx, 2.56f, bz); post.Make("boardFrame", g.transform, Kit.Solid);
            var board = new Geo(); board.C(Color.white).Box(8.0f, 0.58f, 0.14f, mx, 2.62f, bz); board.Make("board", g.transform, v.signMat, false);
            v.name = Kit.Label(Loc.G(T.DeptKey[d]), g.transform, new Vector3(mx, 2.91f, bz - 0.09f), 0.34f, Color.white);
            v.props = new GameObject("props").transform; v.props.SetParent(g.transform, false);
            for (int k = 0; k < T.MaxStaff; k++)
            {
                v.staff[k] = new Person(g.transform, d * 7 + k, DeptColor[d]);
                v.staff[k].go.transform.position = StaffPos(d, k); v.staff[k].go.transform.rotation = Quaternion.Euler(0, 180, 0);
            }
            v.hit = g.AddComponent<BoxCollider>(); v.hit.center = v.center + new Vector3(0, 1.2f, 0.7f); v.hit.size = new Vector3(8.3f, 2.8f, 8.0f);
            depts[d] = v;
        }

        static void Clear(Transform t) { for (int i = t.childCount - 1; i >= 0; i--) UnityEngine.Object.DestroyImmediate(t.GetChild(i).gameObject); }
        void AddPop(GameObject g, float delay, float dur = 0.34f) { var t = g.transform; pops.Add(new Pop { t = t, scale = t.localScale, delay = delay, dur = dur }); t.localScale = t.localScale * 0.001f; }
        static int UnitsFor(int tier) => Mathf.Min(4, 1 + tier);
        /// Stocked shelf rows across the section: every unit starts with one row and fills as the level climbs to the next bonus.
        static int RowsFor(int level, int tier, int units)
        {
            int lo = tier == 0 ? 1 : T.TierLv[tier - 1]; int hi = tier >= T.TierLv.Length ? T.MaxLevel : T.TierLv[tier];
            float f = Mathf.Clamp01((level - lo) / (float)Mathf.Max(1, hi - lo)); if (tier >= 3) f = 1;
            return Mathf.Clamp(units + Mathf.FloorToInt(f * units * 3 + 0.001f), 0, units * 4);
        }

        void RebuildProps(DeptView v, bool open, int tier, int rows, bool animate)
        {
            Clear(v.props); pops.RemoveAll(p => p.t == null);
            bool wasOpen = v.builtOpen; v.builtOpen = open; v.builtTier = tier; v.builtRows = rows; int d = v.d;
            Color col = DeptColor[d], grey = new Color(0.62f, 0.63f, 0.66f);
            v.tapeMat.SetColor("_Tint", (open ? col : grey).linear); v.signMat.SetColor("_Tint", (open ? col : grey).linear);
            float cx = v.center.x, z = v.center.z + 3.55f; string hex = "#" + ColorUtility.ToHtmlStringRGB(col);
            if (!open)
            {
                // a space waiting for its fit-out: pallets of boxes and two cones
                var e = new Geo(); var r = new System.Random(d * 31 + 5);
                for (int i = 0; i < 3; i++) { float x = cx - 2.2f + i * 2.1f, zz = v.center.z + 2.4f + (i % 2) * 0.5f; e.C(Art.Wood2).Box(1.2f, 0.14f, 1.0f, x, 0, zz); for (int k = 0; k < 4; k++) e.C(k % 2 == 0 ? "#c9a36b" : "#b58c52").Box(0.5f, 0.42f, 0.44f, x - 0.28f + (k % 2) * 0.56f, 0.14f + (k / 2) * 0.43f, zz + (float)r.NextDouble() * 0.2f - 0.1f); }
                foreach (float x in new[] { -3.2f, 3.2f }) e.C("#ff7a1a").Cyl(0.2f, 0.03f, 0.6f, cx + x, 0, v.center.z - 1.6f, 10).C(Art.White).Cyl(0.13f, 0.1f, 0.1f, cx + x, 0.22f, v.center.z - 1.6f, 10).C("#ff7a1a").Box(0.46f, 0.04f, 0.46f, cx + x, 0, v.center.z - 1.6f);
                e.Make("waiting", v.props, Kit.Solid); return;
            }
            int units = UnitsFor(tier); var g = new Geo(); var rr = new System.Random(d * 131 + 17);
            for (int u = 0; u < units; u++)
            {
                float x = cx + SlotX[u]; int mine = Mathf.Clamp(rows / units + (u < rows % units ? 1 : 0), 0, 4);
                switch (d)
                {
                    case 0: Art.Produce(g, x, z - 0.25f, Mathf.Min(2, (mine + 1) / 2), u); break;
                    case 1: Art.Bread(g, x, z, mine, u); break;
                    case 2: Art.Counter(g, x, z - 0.15f, Mathf.Min(2, (mine + 1) / 2), false, hex); break;
                    case 3: Art.Counter(g, x, z - 0.15f, Mathf.Min(2, (mine + 1) / 2), true, hex); break;
                    case 4: Art.Fridge(g, x, z, mine, hex, false, u); break;
                    case 5: Art.Fridge(g, x, z, mine, hex, true, u); break;
                    default: Art.Gondola(g, x, z, mine, d == 6 ? 3 : d == 7 ? 2 : d == 8 ? 0 : d == 9 ? 4 : 1, hex, rr); break;
                }
            }
            float span = units * 2.04f, mid = cx + (SlotX[0] + SlotX[units - 1]) / 2;
            if (d <= 1) Art.Awning(g, mid, z + 0.2f, span, hex, Art.White);
            // extras that arrive with later bonus levels: a promo stack, a crate display, bunting
            if (tier >= 1) { g.C(hex).Box(0.7f, 1.1f, 0.7f, cx - 3.7f, 0, v.center.z + 1.3f).C(Art.White).Box(0.74f, 0.1f, 0.74f, cx - 3.7f, 0.5f, v.center.z + 1.3f); for (int i = 0; i < 9; i++) g.C(Art.Goods[rr.Next(Art.Goods.Length)]).Ball(0.1f, 0.13f, 0.07f, cx - 3.9f + (i % 3) * 0.2f, 1.22f, v.center.z + 1.1f + (i / 3) * 0.2f, 8, 5); }
            if (tier >= 2) { g.C(Art.Wood2).Box(0.75f, 0.42f, 0.55f, cx + 3.7f, 0, v.center.z + 1.3f).C(Art.Wood).Box(0.79f, 0.07f, 0.59f, cx + 3.7f, 0.36f, v.center.z + 1.3f); for (int i = 0; i < 6; i++) g.C(Art.Goods[rr.Next(Art.Goods.Length)]).Ball(0.13f, 0.11f, 0.13f, cx + 3.48f + (i % 3) * 0.22f, 0.5f, v.center.z + 1.2f + (i / 3) * 0.2f, 9, 6); }
            if (tier >= 4) { for (int i = 0; i < 12; i++) g.C(i % 2 == 0 ? hex : "#ffd43b").At(cx - 3.6f + i * 0.65f, 3.2f - 0.25f * Mathf.Sin(i / 11f * Mathf.PI), v.center.z + 2.4f, 0, 0, 45).Box(0.26f, 0.26f, 0.02f); g.At(); }
            var go = g.Make("fixtures", v.props, Kit.Solid);
            if (animate) { v.pop = 1f; if (!wasOpen) AddPop(go, 0, 0.45f); }
        }

        Actor MakeActor(Cust c)
        {
            var a = new Actor(); a.p = new Person(root, c.look, null, true); a.go = a.p.go;
            // a trolley goes ahead of each shopper; goods appear in it once they have something to pay for
            a.cart = new GameObject("cart"); a.cart.transform.SetParent(a.go.transform, false); a.cart.transform.localPosition = new Vector3(0, 0, 0.85f);
            a.cart.AddComponent<MeshFilter>().sharedMesh = cartMesh; a.cart.AddComponent<MeshRenderer>().sharedMaterial = Kit.Solid;
            var gg = new Geo(); Art.CartGoods(gg, new System.Random(c.look)); a.goods = gg.Make("goods", a.cart.transform, Kit.Solid); a.goods.SetActive(false);
            var gift = new Geo(); gift.C("#ff4f8b").Box(0.42f, 0.36f, 0.42f, 0, 0, 0).C("#ffd43b").Box(0.44f, 0.37f, 0.1f, 0, 0, 0).Box(0.1f, 0.37f, 0.44f, 0, 0, 0).Ball(0.12f, 0.1f, 0.12f, 0, 0.42f, 0, 8, 5);
            a.gift = gift.Make("gift", a.go.transform, Kit.Glow, false); a.gift.transform.localPosition = new Vector3(0, 2.3f, 0); a.gift.SetActive(false); a.gift.AddComponent<SphereCollider>().radius = 1.6f;
            if (c.slot >= 0)
            {
                var cg = new Geo(); Art.Car(cg, Geo.Hex(CarCol[c.look % CarCol.Length])); a.car = cg.Make("car", root, Kit.Solid);
                a.carPos = new Vector3(-30, -0.12f, RoadZ); a.car.transform.position = a.carPos; a.carYaw = 90;
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
                var v = depts[d]; int tier = T.Tier(s.dLevel[d]); int rows = s.dOpen[d] ? RowsFor(s.dLevel[d], tier, UnitsFor(tier)) : 0;
                if (force || v.builtOpen != s.dOpen[d] || v.builtTier != tier || v.builtRows != rows) RebuildProps(v, s.dOpen[d], tier, rows, animate && !force);
                for (int k = 0; k < T.MaxStaff; k++) v.staff[k].go.SetActive(s.dOpen[d] && k < s.dStaff[d]);
            }
            for (int c = 0; c < T.NC; c++) cashDesk[c].SetActive(s.cLevel[c] > 0);
            if (s.star != bandStar) { bandStar = s.star; bandMat.SetColor("_Tint", Geo.Hex(GradeBand[Mathf.Clamp(s.star, 0, GradeBand.Length - 1)]).linear); }
            int want = sim.ParkSpaces;
            if (want != slotsBuilt)
            {
                var g = new Geo(); g.Shade = 0;
                for (int i = slotsBuilt; i < want; i++)
                {
                    var p = SlotPos(i); g.C("#f4f6fb").Slab(0.13f, 4.3f, 0.06f, p.x - 1.5f, -0.118f, p.z, 0.004f).Slab(0.13f, 4.3f, 0.06f, p.x + 1.5f, -0.118f, p.z, 0.004f).C("#c7c1b3").Box(1.6f, 0.12f, 0.22f, p.x, -0.12f, p.z - 2.0f);
                }
                g.Make("bays", slotRoot, Kit.Solid, false);
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
                    // a squash-and-stretch bounce of the whole section
                    v.pop = Mathf.Max(0, v.pop - dt * 2.4f); float k = 1 + 0.08f * Mathf.Sin(v.pop * Mathf.PI * 2) * v.pop;
                    v.props.localScale = new Vector3(2 - k, k, 1); v.props.localPosition = new Vector3(v.center.x * (k - 1), 0, 0);
                    if (sim.s.dOpen[d]) v.signMat.SetColor("_Tint", (DeptColor[d] * (1f + 1.2f * v.pop)).linear);
                    if (v.pop <= 0) { v.props.localScale = Vector3.one; v.props.localPosition = Vector3.zero; }
                }
                else if (sim.s.dOpen[d] && ad) v.signMat.SetColor("_Tint", (DeptColor[d] * (1.05f + 0.2f * Mathf.Sin(time * 3f + d))).linear);
                if (!sim.s.dOpen[d]) continue;
                for (int k = 0; k < sim.s.dStaff[d]; k++) { bool serving = sim.dq[d][k].Count > 0 && sim.dq[d][k][0].st == CS.Served; v.staff[k].Set(false, serving, time, dt); }
            }
            for (int c = 0; c < T.NC; c++)
            {
                if (sim.s.cLevel[c] <= 0) continue; bool paying = sim.cq[c].Count > 0 && sim.cq[c][0].st == CS.Paying;
                cashStaff[c].Set(false, paying, time, dt);
                cashLamp[c].SetColor("_Tint", ((paying ? new Color(0.32f, 0.92f, 0.5f) : new Color(0.45f, 0.72f, 1f)) * (paying ? 0.9f + 0.25f * Mathf.Sin(time * 14f) : 0.85f)).linear);
            }

            foreach (var c in sim.custs)
            {
                Actor a; if (!actors.TryGetValue(c.id, out a)) { a = MakeActor(c); actors[c.id] = a; }
                float t = c.dur > 0 ? Mathf.Clamp01(c.t / c.dur) : 1;
                if (a.car != null)
                {
                    var slot = SlotPos(c.slot) + new Vector3(0, -0.12f, 0); Vector3 from = new Vector3(-30, -0.12f, RoadZ), turn = new Vector3(slot.x, -0.12f, RoadZ), exit = new Vector3(30, -0.12f, RoadZ);
                    Vector3 cp = c.st == CS.CarIn ? Along(from, turn, slot, Mathf.SmoothStep(0, 1, t)) : c.st == CS.CarOut ? Along(slot, turn, exit, t * t) : slot;
                    var dir = cp - a.carPos; if (dir.sqrMagnitude > 1e-5f) a.carYaw = Mathf.LerpAngle(a.carYaw, Mathf.Atan2(dir.x, dir.z) * Mathf.Rad2Deg, 0.35f);
                    else if (c.st != CS.CarIn && c.st != CS.CarOut) a.carYaw = Mathf.LerpAngle(a.carYaw, 180, 0.2f);
                    a.carPos = cp; a.car.transform.position = cp; a.car.transform.rotation = Quaternion.Euler(0, a.carYaw, 0);
                }
                bool inCar = c.st == CS.CarIn || c.st == CS.CarOut; a.go.SetActive(!inCar);
                if (inCar) { a.go.transform.position = c.slot >= 0 ? SlotPos(c.slot) + new Vector3(1.15f, 0, 0.6f) : busPos; continue; }
                bool busy; var target = Target(c, out busy); var pos = a.go.transform.position; var delta = target - pos; delta.y = 0;
                float speed = 3.6f * (float)sim.WalkMult; float step = speed * dt; a.moving = delta.magnitude > 0.05f;
                if (delta.magnitude <= step) pos = target; else pos += delta.normalized * step;
                a.go.transform.position = pos;
                if (a.moving) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.LookRotation(delta.normalized, Vector3.up), 0.25f);
                else if (c.st == CS.Queue || c.st == CS.Served) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.identity, 0.2f);
                else if (c.st == CS.CashQueue || c.st == CS.Paying) a.go.transform.rotation = Quaternion.Slerp(a.go.transform.rotation, Quaternion.Euler(0, 180, 0), 0.2f);
                a.p.speed = (float)sim.WalkMult; a.p.Set(a.moving, false, time, dt);
                a.goods.SetActive(c.bill > 0);
                a.gift.SetActive(c.gift); if (c.gift) { a.gift.transform.localPosition = new Vector3(0, 2.3f + 0.12f * Mathf.Sin(time * 5f), 0); a.gift.transform.localRotation = Quaternion.Euler(0, time * 120f, 0); }
            }
            gone.Clear(); foreach (var kv in actors) { bool live = false; foreach (var c in sim.custs) if (c.id == kv.Key) { live = true; break; } if (!live) gone.Add(kv.Key); }
            foreach (int id in gone) { var a = actors[id]; Kit.Kill(a.go); Kit.Kill(a.car); actors.Remove(id); }

            // delivery truck and VIP car wait in their bays until tapped
            if (sim.truckHere && truck == null) { var g = new Geo(); Art.Truck(g); truck = g.Make("truck", root, Kit.Solid); truck.transform.position = truckPos + new Vector3(0, -0.1f, 0); truck.transform.rotation = Quaternion.Euler(0, -90, 0); AddMarker(truck, new Color(1f, 0.8f, 0.2f)); AddPop(truck, 0, 0.4f); }
            if (!sim.truckHere && truck != null) { Kit.Kill(truck); truck = null; }
            if (sim.vipHere && vip == null) { var g = new Geo(); Art.Car(g, new Color(0.16f, 0.14f, 0.2f), true); vip = g.Make("vip", root, Kit.Solid); vip.transform.position = vipPos + new Vector3(0, -0.1f, 0); vip.transform.rotation = Quaternion.Euler(0, 90, 0); AddMarker(vip, new Color(0.85f, 0.45f, 1f)); AddPop(vip, 0, 0.4f); }
            if (!sim.vipHere && vip != null) { Kit.Kill(vip); vip = null; }
            Spin(truck); Spin(vip);
        }

        /// A floating beacon over something worth tapping: a gem with two rings turning round it.
        void AddMarker(GameObject g, Color c)
        {
            var b = Kit.BoundsOf(g); var holder = new GameObject("marker"); holder.transform.SetParent(g.transform, false); holder.transform.position = b.center + Vector3.up * (b.extents.y + 1.1f);
            var mat = Kit.GlowTint(c); var gem = new Geo(); gem.C(Color.white).Cyl(0.3f, 0, 0.42f, 0, 0, 0, 6).At(0, 0, 0, 0, 180).Cyl(0.3f, 0, 0.3f, 0, 0, 0, 6); gem.Make("gem", holder.transform, mat, false);
            for (int r = 0; r < 2; r++)
            {
                var ring = new Geo(); int n = 28; for (int i = 0; i < n; i++) { float a = i / (float)n * 360f; ring.C(Color.white).At(Mathf.Cos(a * Mathf.Deg2Rad) * 0.62f, 0, Mathf.Sin(a * Mathf.Deg2Rad) * 0.62f, -a).Box(0.05f, 0.05f, 0.15f, 0, -0.025f, 0); }
                ring.Make("ring" + r, holder.transform, mat, false);
            }
            var col = g.AddComponent<BoxCollider>(); col.center = g.transform.InverseTransformPoint(b.center); var sz = g.transform.InverseTransformVector(b.size); col.size = new Vector3(Mathf.Abs(sz.x) * 1.25f, Mathf.Abs(sz.y) * 2.4f, Mathf.Abs(sz.z) * 1.25f);
        }
        void Spin(GameObject g)
        {
            if (g == null) return; var m = g.transform.Find("marker"); if (m == null || m.childCount < 3) return;
            m.rotation = Quaternion.identity; var gem = m.GetChild(0); gem.localRotation = Quaternion.Euler(0, time * 90f, 0); gem.localPosition = new Vector3(0, 0.1f * Mathf.Sin(time * 3f), 0);
            m.GetChild(1).localRotation = Quaternion.Euler(62, time * 140f, 0); m.GetChild(2).localRotation = Quaternion.Euler(-58, -time * 110f, 40);
        }

        public void PopDept(int d) { depts[d].pop = 1f; }
        /// After a change of language.
        public void RefreshSigns() { for (int d = 0; d < T.ND; d++) if (depts[d] != null && depts[d].name != null) Kit.SetLabel(depts[d].name, Loc.G(T.DeptKey[d])); }
        public Actor ActorOf(Cust c) { Actor a; return actors.TryGetValue(c.id, out a) ? a : null; }
        public Cust CustAt(GameObject go) { foreach (var c in sim.custs) { Actor a; if (actors.TryGetValue(c.id, out a) && a.go == go) return c; } return null; }
        public int ActorCount => actors.Count;
    }
}
