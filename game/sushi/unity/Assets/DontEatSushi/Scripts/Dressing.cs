// 別吃壽司 - 場景佈置：和風壽司店的牆、燈籠、師傅的工作台、每個座位的餐具。全部用基本形狀拼出來。
using UnityEngine;

namespace DontEatSushi
{
    public static class Dressing
    {
        static SushiGame g;
        static Transform root;

        static GameObject B(string n, Vector3 pos, Vector3 scale, Material m, bool col = false) { return g.Prim(PrimitiveType.Cube, n, pos, scale, m, col, root); }
        static GameObject C(string n, Vector3 pos, Vector3 scale, Material m, bool col = false) { return g.Prim(PrimitiveType.Cylinder, n, pos, scale, m, col, root); }
        static GameObject S(string n, Vector3 pos, Vector3 scale, Material m, bool col = false) { return g.Prim(PrimitiveType.Sphere, n, pos, scale, m, col, root); }

        public static void Build(SushiGame game, Transform parent)
        {
            g = game; root = parent;
            float A = SushiGame.A, Bz = SushiGame.B;
            var darkWood = Mats.Lit(new Color(0.26f, 0.15f, 0.09f), 0.35f);
            var midWood = Mats.Lit(new Color(0.62f, 0.42f, 0.25f), 0.3f);
            var lightWood = Mats.Lit(new Color(0.86f, 0.70f, 0.48f), 0.3f);
            var lacquer = Mats.Lit(new Color(0.16f, 0.05f, 0.05f), 0.85f);
            var plaster = Mats.Lit(new Color(0.93f, 0.86f, 0.72f), 0.05f);
            var paper = Mats.Unlit(new Color(1.35f, 1.18f, 0.88f));
            var steel = Mats.Lit(new Color(0.78f, 0.80f, 0.83f), 0.8f);
            var white = Mats.Lit(new Color(0.96f, 0.95f, 0.92f), 0.6f);
            var indigo = Mats.Lit(new Color(0.12f, 0.19f, 0.42f), 0.05f);
            var black = Mats.Lit(new Color(0.07f, 0.06f, 0.06f), 0.5f);

            // 地板與後牆
            B("Floor", new Vector3(0f, -7f, 4f), new Vector3(160f, 0.2f, 160f), Mats.Lit(new Color(0.40f, 0.28f, 0.20f), 0.15f), true);
            B("BackWall", new Vector3(0f, 6f, 17.4f), new Vector3(90f, 30f, 0.5f), plaster, true);
            B("Wainscot", new Vector3(0f, -2f, 17f), new Vector3(90f, 9f, 0.4f), midWood, true);
            B("WainscotCap", new Vector3(0f, 2.6f, 16.9f), new Vector3(90f, 0.35f, 0.7f), darkWood);
            B("TopBeam", new Vector3(0f, 14.2f, 16.8f), new Vector3(90f, 0.8f, 0.8f), darkWood);

            // 障子：發亮的紙面加木格
            for (int i = -2; i <= 2; i++)
            {
                float x = i * 10.5f;
                B("Shoji", new Vector3(x, 8.3f, 17.05f), new Vector3(8.6f, 10.6f, 0.1f), paper);
                for (int k = -2; k <= 2; k++) B("LatV", new Vector3(x + k * 2.15f, 8.3f, 16.95f), new Vector3(k == -2 || k == 2 ? 0.3f : 0.12f, 10.8f, 0.14f), darkWood);
                for (int k = 0; k <= 4; k++) B("LatH", new Vector3(x, 3.0f + k * 2.65f, 16.95f), new Vector3(8.8f, k == 0 || k == 4 ? 0.3f : 0.12f, 0.14f), darkWood);
                B("Post", new Vector3(x + 5.25f, 6f, 16.8f), new Vector3(0.7f, 30f, 0.7f), darkWood);
            }

            // 暖簾：藏青布條加白色圓紋
            for (int i = -3; i <= 3; i++)
            {
                B("Noren", new Vector3(i * 3.3f, 12.3f, 15.6f), new Vector3(3.1f, 3.0f, 0.06f), indigo);
                var crest = C("Crest", new Vector3(i * 3.3f, 12.4f, 15.55f), new Vector3(1.1f, 0.02f, 1.1f), white);
                crest.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            }
            B("NorenRod", new Vector3(0f, 13.9f, 15.6f), new Vector3(24f, 0.18f, 0.18f), darkWood);

            // 燈籠：發光的身體、上下黑蓋、吊繩
            var lantern = Mats.Unlit(new Color(2.3f, 0.75f, 0.28f));
            for (int i = -2; i <= 2; i++)
            {
                var lp = new Vector3(i * 7.5f, 9.6f, 7.5f + (i % 2 == 0 ? 0f : 1.5f));
                S("Lantern", lp, new Vector3(1.7f, 2.2f, 1.7f), lantern);
                C("LanternTop", lp + Vector3.up * 1.05f, new Vector3(0.9f, 0.1f, 0.9f), black);
                C("LanternBottom", lp - Vector3.up * 1.05f, new Vector3(0.9f, 0.1f, 0.9f), black);
                C("LanternString", lp + Vector3.up * 4f, new Vector3(0.04f, 3f, 0.04f), black);
                if (i % 2 == 0)
                {
                    var lg = new GameObject("LanternLight");
                    lg.transform.SetParent(root, false);
                    lg.transform.position = lp + Vector3.down * 1.6f;
                    var l = lg.AddComponent<Light>();
                    l.type = LightType.Point; l.color = new Color(1f, 0.70f, 0.40f); l.range = 24f; l.intensity = 2.4f;
                }
            }

            // 後方的酒架和招財貓
            B("Shelf", new Vector3(0f, 4.2f, 15.6f), new Vector3(30f, 0.3f, 2f), darkWood);
            Color[] bottle = { new Color(0.16f, 0.36f, 0.24f), new Color(0.50f, 0.26f, 0.12f), new Color(0.90f, 0.90f, 0.86f), new Color(0.14f, 0.22f, 0.40f), new Color(0.62f, 0.14f, 0.14f) };
            for (int i = 0; i < 16; i++)
            {
                float x = -13.5f + i * 1.45f; if (Mathf.Abs(x) < 2.6f) continue;
                var bm = Mats.Lit(bottle[i % bottle.Length], 0.85f);
                float h = 0.9f + (i % 3) * 0.2f;
                C("Bottle", new Vector3(x, 4.35f + h, 15.6f), new Vector3(0.75f, h, 0.75f), bm);
                C("BottleNeck", new Vector3(x, 4.35f + h * 2f + 0.3f, 15.6f), new Vector3(0.28f, 0.32f, 0.28f), bm);
                B("Label", new Vector3(x, 4.35f + h, 15.2f), new Vector3(0.5f, 0.7f, 0.04f), white);
            }
            var gold = Mats.Lit(new Color(0.95f, 0.74f, 0.22f), 0.8f);
            var red = Mats.Lit(new Color(0.80f, 0.12f, 0.10f), 0.5f);
            Vector3 cat = new Vector3(0f, 4.35f, 15.5f);
            S("CatBody", cat + new Vector3(0f, 0.95f, 0f), new Vector3(1.9f, 1.9f, 1.6f), white);
            S("CatHead", cat + new Vector3(0f, 2.35f, -0.05f), new Vector3(1.7f, 1.45f, 1.4f), white);
            S("CatEarL", cat + new Vector3(-0.6f, 3.05f, 0f), new Vector3(0.5f, 0.6f, 0.3f), white);
            S("CatEarR", cat + new Vector3(0.6f, 3.05f, 0f), new Vector3(0.5f, 0.6f, 0.3f), white);
            S("CatEyeL", cat + new Vector3(-0.35f, 2.45f, -0.68f), new Vector3(0.16f, 0.2f, 0.08f), black);
            S("CatEyeR", cat + new Vector3(0.35f, 2.45f, -0.68f), new Vector3(0.16f, 0.2f, 0.08f), black);
            S("CatNose", cat + new Vector3(0f, 2.22f, -0.72f), new Vector3(0.14f, 0.1f, 0.08f), red);
            var arm = g.Prim(PrimitiveType.Capsule, "CatArm", cat + new Vector3(0.95f, 2.2f, -0.2f), new Vector3(0.45f, 0.75f, 0.45f), white, false, root);
            arm.transform.rotation = Quaternion.Euler(0f, 0f, -12f);
            C("CatCollar", cat + new Vector3(0f, 1.78f, 0f), new Vector3(1.25f, 0.09f, 1.1f), red);
            var coin = C("CatCoin", cat + new Vector3(0f, 1.1f, -0.82f), new Vector3(0.75f, 0.05f, 0.75f), gold);
            coin.transform.rotation = Quaternion.Euler(90f, 0f, 0f);

            // 吧台邊緣的漆條
            B("CounterLip", new Vector3(0f, 0.02f, -10.75f), new Vector3(40f, 0.12f, 0.5f), lacquer);
            B("CounterFront", new Vector3(0f, -3.6f, -11.1f), new Vector3(40f, 6.2f, 0.3f), midWood);

            // 傳送帶：兩側不鏽鋼護欄、帶面上的橫紋
            float o = SushiGame.BeltHalf;
            B("RailN1", new Vector3(0f, 0.14f, -Bz - o), new Vector3(2f * A + 2f * o + 0.2f, 0.2f, 0.12f), steel);
            B("RailN2", new Vector3(0f, 0.14f, -Bz + o), new Vector3(2f * A - 2f * o, 0.2f, 0.12f), steel);
            B("RailF1", new Vector3(0f, 0.14f, Bz + o), new Vector3(2f * A + 2f * o + 0.2f, 0.2f, 0.12f), steel);
            B("RailF2", new Vector3(0f, 0.14f, Bz - o), new Vector3(2f * A - 2f * o, 0.2f, 0.12f), steel);
            B("RailL1", new Vector3(-A - o, 0.14f, 0f), new Vector3(0.12f, 0.2f, 2f * Bz + 2f * o), steel);
            B("RailL2", new Vector3(-A + o, 0.14f, 0f), new Vector3(0.12f, 0.2f, 2f * Bz - 2f * o), steel);
            B("RailR1", new Vector3(A + o, 0.14f, 0f), new Vector3(0.12f, 0.2f, 2f * Bz + 2f * o), steel);
            B("RailR2", new Vector3(A - o, 0.14f, 0f), new Vector3(0.12f, 0.2f, 2f * Bz - 2f * o), steel);
            var slat = Mats.Lit(new Color(0.24f, 0.24f, 0.27f), 0.5f);
            for (float x = -A - 1.2f; x <= A + 1.2f; x += 1.2f)
            {
                B("Slat", new Vector3(x, 0.102f, -Bz), new Vector3(0.06f, 0.01f, 2f * o - 0.2f), slat);
                B("Slat", new Vector3(x, 0.102f, Bz), new Vector3(0.06f, 0.01f, 2f * o - 0.2f), slat);
            }
            for (float z = -Bz + o + 0.6f; z <= Bz - o - 0.6f; z += 1.2f)
            {
                B("Slat", new Vector3(-A, 0.102f, z), new Vector3(2f * o - 0.2f, 0.01f, 0.06f), slat);
                B("Slat", new Vector3(A, 0.102f, z), new Vector3(2f * o - 0.2f, 0.01f, 0.06f), slat);
            }

            // 師傅的工作台（中島上）
            float y = 0.5f;
            B("Board", new Vector3(-4.5f, y + 0.09f, 0f), new Vector3(4.2f, 0.18f, 2.2f), lightWood, true);
            B("Salmon", new Vector3(-5.2f, y + 0.45f, 0.1f), new Vector3(1.9f, 0.55f, 0.8f), Mats.Lit(new Color(0.98f, 0.50f, 0.27f), 0.6f), true);
            for (int i = 0; i < 5; i++) B("SalmonLine", new Vector3(-5.95f + i * 0.38f, y + 0.45f, 0.1f), new Vector3(0.05f, 0.57f, 0.82f), Mats.Lit(new Color(1f, 0.82f, 0.68f), 0.6f));
            var knife = B("Knife", new Vector3(-3.4f, y + 0.21f, -0.3f), new Vector3(1.5f, 0.03f, 0.26f), steel);
            knife.transform.rotation = Quaternion.Euler(0f, 18f, 0f);
            var handle = B("KnifeHandle", new Vector3(-2.52f, y + 0.23f, -0.59f), new Vector3(0.65f, 0.1f, 0.16f), darkWood);
            handle.transform.rotation = Quaternion.Euler(0f, 18f, 0f);
            C("Hangiri", new Vector3(1.2f, y + 0.4f, 0.2f), new Vector3(2.8f, 0.4f, 2.8f), midWood, true);
            C("HangiriBand", new Vector3(1.2f, y + 0.5f, 0.2f), new Vector3(2.86f, 0.05f, 2.86f), Mats.Lit(new Color(0.72f, 0.45f, 0.20f), 0.7f));
            C("Rice", new Vector3(1.2f, y + 0.76f, 0.2f), new Vector3(2.5f, 0.06f, 2.5f), white);
            var mat = Mats.Lit(new Color(0.46f, 0.58f, 0.28f), 0.3f);
            B("Makisu", new Vector3(5.6f, y + 0.04f, 0.2f), new Vector3(2.4f, 0.06f, 1.9f), mat, true);
            for (int i = 0; i < 9; i++) B("MakisuLine", new Vector3(4.56f + i * 0.26f, y + 0.075f, 0.2f), new Vector3(0.03f, 0.01f, 1.9f), Mats.Lit(new Color(0.30f, 0.42f, 0.18f), 0.3f));
            Color[] stack = { new Color(0.86f, 0.30f, 0.24f), new Color(0.30f, 0.52f, 0.72f), new Color(0.90f, 0.72f, 0.24f), new Color(0.36f, 0.62f, 0.44f), new Color(0.56f, 0.38f, 0.66f) };
            for (int i = 0; i < 7; i++) C("PlateStack", new Vector3(8.2f, y + 0.06f + i * 0.13f, -0.6f), new Vector3(2.2f, 0.05f, 2.2f), Mats.Lit(stack[i % stack.Length], 0.6f), true);
            C("WasabiBowl", new Vector3(-8.2f, y + 0.2f, 0.8f), new Vector3(1.1f, 0.2f, 1.1f), black, true);
            S("WasabiPile", new Vector3(-8.2f, y + 0.42f, 0.8f), new Vector3(0.8f, 0.45f, 0.8f), Mats.Lit(new Color(0.56f, 0.74f, 0.30f), 0.2f));
            C("GingerBowl", new Vector3(-8.2f, y + 0.2f, -0.7f), new Vector3(1.1f, 0.2f, 1.1f), black, true);
            S("GingerPile", new Vector3(-8.2f, y + 0.42f, -0.7f), new Vector3(0.8f, 0.4f, 0.8f), Mats.Lit(new Color(0.98f, 0.72f, 0.74f), 0.4f));

            // 每個座位一套餐具
            var tea = Mats.Lit(new Color(0.34f, 0.42f, 0.36f), 0.5f);
            var teaTop = Mats.Lit(new Color(0.62f, 0.66f, 0.22f), 0.9f);
            var soy = Mats.Lit(new Color(0.10f, 0.05f, 0.04f), 0.9f);
            for (int i = -2; i <= 2; i++)
            {
                float x = i * 6.4f;
                C("TeaCup", new Vector3(x + 1.9f, 0.42f, -8.3f), new Vector3(0.85f, 0.42f, 0.85f), tea, true);
                C("Tea", new Vector3(x + 1.9f, 0.8f, -8.3f), new Vector3(0.7f, 0.03f, 0.7f), teaTop);
                C("SoyDish", new Vector3(x - 1.7f, 0.05f, -8.4f), new Vector3(1.0f, 0.05f, 1.0f), white, true);
                C("Soy", new Vector3(x - 1.7f, 0.1f, -8.4f), new Vector3(0.7f, 0.012f, 0.7f), soy);
                B("ChopRest", new Vector3(x - 0.5f, 0.07f, -9.6f), new Vector3(0.22f, 0.14f, 0.5f), red, true);
                B("ChopA", new Vector3(x + 0.7f, 0.17f, -9.52f), new Vector3(2.7f, 0.05f, 0.05f), lacquer);
                B("ChopB", new Vector3(x + 0.7f, 0.17f, -9.68f), new Vector3(2.7f, 0.05f, 0.05f), lacquer);
                B("Oshibori", new Vector3(x - 3.0f, 0.1f, -9.4f), new Vector3(0.5f, 0.2f, 1.3f), white, true);
            }
            C("SoyBottle", new Vector3(-9.5f, 0.6f, -8.2f), new Vector3(0.65f, 0.6f, 0.65f), soy, true);
            C("SoyCap", new Vector3(-9.5f, 1.3f, -8.2f), new Vector3(0.38f, 0.12f, 0.38f), red, true);
            C("SoyBottle", new Vector3(9.5f, 0.6f, -8.2f), new Vector3(0.65f, 0.6f, 0.65f), soy, true);
            C("SoyCap", new Vector3(9.5f, 1.3f, -8.2f), new Vector3(0.38f, 0.12f, 0.38f), red, true);
        }
    }
}
