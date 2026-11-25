// 別吃壽司 - 壽司的形狀、貼圖展開和參考貼圖。全部用程式生成，不依賴外部素材。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public enum ShapeKind { Nigiri, Maki, Stand, Sit, Prone, Side, Star }
    public enum SushiKind { Blank, Salmon, Tuna, Tamago, Shrimp, CucumberRoll, TunaRoll }

    /// 一種身形：網格，加上「貼圖上每個像素對應物體表面哪一點」的對照表。
    public class SushiShape
    {
        public const int T = 512;
        public ShapeKind kind;
        public Mesh mesh;
        public Vector3[] texPos;   // 每個像素在物體空間的位置
        public Vector3[] texNrm;   // 每個像素的法線
        public byte[] texPart;     // 部位編號，255 表示沒用到
        public Bounds bounds;
        public SushiKind[] references;
        // 每塊展開區的像素範圍和包圍球，塗色時用來跳過離筆刷很遠的區塊
        public int[] cRect;
        public Vector3[] cCenter;
        public float[] cRad;
    }

    public static class SushiShapes
    {
        const int T = SushiShape.T;
        delegate void Surf(float s, float t, out Vector3 p, out Vector3 n);

        class Chart
        {
            public Rect cell;
            public Surf f;
            public byte part;
            public int ns, nt;
        }

        static readonly Dictionary<ShapeKind, SushiShape> cache = new Dictionary<ShapeKind, SushiShape>();

        public static ShapeKind ShapeOf(SushiKind k)
        {
            return (k == SushiKind.CucumberRoll || k == SushiKind.TunaRoll) ? ShapeKind.Maki : ShapeKind.Nigiri;
        }

        public static SushiShape Get(ShapeKind kind)
        {
            SushiShape s;
            if (cache.TryGetValue(kind, out s) && s.mesh != null) return s;
            s = Build(kind);
            cache[kind] = s;
            return s;
        }

        static SushiShape Build(ShapeKind kind)
        {
            var charts = new List<Chart>();
            var shape = new SushiShape();
            shape.kind = kind;
            if (kind == ShapeKind.Nigiri)
            {
                AddBox(charts, new Vector3(0f, 0.2f, 0f), new Vector3(0.5f, 0.2f, 0.28f), 0.17f, 0, 0, 4, 3);
                AddBox(charts, new Vector3(0f, 0.43f, 0f), new Vector3(0.58f, 0.075f, 0.31f), 0.06f, 1, 6, 4, 3);
                shape.references = new[] { SushiKind.Salmon, SushiKind.Tuna, SushiKind.Tamago, SushiKind.Shrimp };
            }
            else if (kind >= ShapeKind.Stand)
            {
                // 小人：身體、頭、雙手、雙腳六個圓角方塊。姿勢只是把各部位繞關節轉一下，貼圖位置不變，所以換姿勢顏色還在。
                Quaternion root = Quaternion.identity, armL = Quaternion.identity, armR = Quaternion.identity, legL = Quaternion.identity, legR = Quaternion.identity;
                if (kind == ShapeKind.Sit) { legL = legR = Quaternion.Euler(-90f, 0f, 0f); armL = armR = Quaternion.Euler(-35f, 0f, 0f); }
                else if (kind == ShapeKind.Prone) { root = Quaternion.Euler(90f, 0f, 0f); armL = armR = Quaternion.Euler(180f, 0f, 0f); }
                else if (kind == ShapeKind.Side) { root = Quaternion.Euler(0f, 0f, 90f); armL = Quaternion.Euler(-40f, 0f, 0f); legR = Quaternion.Euler(-30f, 0f, 0f); }
                else if (kind == ShapeKind.Star) { armL = Quaternion.Euler(0f, 0f, -115f); armR = Quaternion.Euler(0f, 0f, 115f); legL = Quaternion.Euler(0f, 0f, -28f); legR = Quaternion.Euler(0f, 0f, 28f); }
                AddBox(charts, new Vector3(0f, 1.02f, 0f), new Vector3(0.30f, 0.36f, 0.22f), 0.2f, 0, 0, 6, 6, root, Vector3.zero);
                AddBox(charts, new Vector3(0f, 1.62f, 0f), new Vector3(0.25f, 0.25f, 0.25f), 0.23f, 1, 6, 6, 6, root, Vector3.zero);
                AddLimb(charts, root, armL, new Vector3(-0.40f, 1.30f, 0f), new Vector3(0.09f, 0.30f, 0.09f), 0.085f, 2, 12);
                AddLimb(charts, root, armR, new Vector3(0.40f, 1.30f, 0f), new Vector3(0.09f, 0.30f, 0.09f), 0.085f, 3, 18);
                AddLimb(charts, root, legL, new Vector3(-0.16f, 0.68f, 0f), new Vector3(0.115f, 0.34f, 0.115f), 0.1f, 4, 24);
                AddLimb(charts, root, legR, new Vector3(0.16f, 0.68f, 0f), new Vector3(0.115f, 0.34f, 0.115f), 0.1f, 5, 30);
                shape.references = new SushiKind[0];
            }
            else
            {
                const float R = 0.36f, H = 0.3f;
                charts.Add(new Chart
                {
                    cell = new Rect(0f, 0.5f, 1f, 0.5f), part = 0, ns = 32, nt = 4,
                    f = (float s, float t, out Vector3 p, out Vector3 n) =>
                    {
                        float a = s * Mathf.PI * 2f;
                        n = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a));
                        p = new Vector3(n.x * R, t * 2f * H, n.z * R);
                    }
                });
                charts.Add(new Chart
                {
                    cell = new Rect(0f, 0f, 0.5f, 0.5f), part = 1, ns = 10, nt = 10,
                    f = (float s, float t, out Vector3 p, out Vector3 n) =>
                    {
                        float a = 2f * s - 1f, b = 2f * t - 1f;
                        float x = a * Mathf.Sqrt(1f - b * b * 0.5f), z = b * Mathf.Sqrt(1f - a * a * 0.5f);
                        n = Vector3.up;
                        p = new Vector3(x * R, 2f * H, z * R);
                    }
                });
                charts.Add(new Chart
                {
                    cell = new Rect(0.5f, 0f, 0.5f, 0.5f), part = 2, ns = 10, nt = 10,
                    f = (float s, float t, out Vector3 p, out Vector3 n) =>
                    {
                        float a = 2f * s - 1f, b = 2f * t - 1f;
                        float x = a * Mathf.Sqrt(1f - b * b * 0.5f), z = b * Mathf.Sqrt(1f - a * a * 0.5f);
                        n = Vector3.down;
                        p = new Vector3(x * R, 0f, z * R);
                    }
                });
                shape.references = new[] { SushiKind.CucumberRoll, SushiKind.TunaRoll };
            }

            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            shape.texPos = new Vector3[T * T];
            shape.texNrm = new Vector3[T * T];
            shape.texPart = new byte[T * T];
            for (int i = 0; i < shape.texPart.Length; i++) shape.texPart[i] = 255;

            const float pad = 3f / T;
            shape.cRect = new int[charts.Count * 4];
            shape.cCenter = new Vector3[charts.Count];
            shape.cRad = new float[charts.Count];
            int ci = -1;
            foreach (var c in charts)
            {
                ci++;
                var uvRect = new Rect(c.cell.x + pad, c.cell.y + pad, c.cell.width - 2f * pad, c.cell.height - 2f * pad);
                int baseIdx = verts.Count;
                for (int j = 0; j <= c.nt; j++)
                {
                    for (int i = 0; i <= c.ns; i++)
                    {
                        float s = i / (float)c.ns, t = j / (float)c.nt;
                        Vector3 p, n;
                        c.f(s, t, out p, out n);
                        verts.Add(p); norms.Add(n);
                        uvs.Add(new Vector2(uvRect.x + uvRect.width * s, uvRect.y + uvRect.height * t));
                    }
                }
                // 判斷三角形的繞向，保證正面朝外
                Vector3 p0, n0, ps, ns_, pt, nt_;
                c.f(0.5f, 0.5f, out p0, out n0);
                c.f(0.55f, 0.5f, out ps, out ns_);
                c.f(0.5f, 0.55f, out pt, out nt_);
                bool front = Vector3.Dot(Vector3.Cross(ps - p0, pt - p0), n0) > 0f;
                int row = c.ns + 1;
                for (int j = 0; j < c.nt; j++)
                {
                    for (int i = 0; i < c.ns; i++)
                    {
                        int a = baseIdx + j * row + i, b = a + 1, d = a + row, e = d + 1;
                        if (front) { tris.Add(a); tris.Add(b); tris.Add(d); tris.Add(b); tris.Add(e); tris.Add(d); }
                        else { tris.Add(a); tris.Add(d); tris.Add(b); tris.Add(b); tris.Add(d); tris.Add(e); }
                    }
                }
                // 像素對照表（含邊緣外擴，避免接縫漏色）
                int x0 = Mathf.Clamp(Mathf.FloorToInt(c.cell.xMin * T), 0, T - 1);
                int x1 = Mathf.Clamp(Mathf.CeilToInt(c.cell.xMax * T) - 1, 0, T - 1);
                int y0 = Mathf.Clamp(Mathf.FloorToInt(c.cell.yMin * T), 0, T - 1);
                int y1 = Mathf.Clamp(Mathf.CeilToInt(c.cell.yMax * T) - 1, 0, T - 1);
                for (int y = y0; y <= y1; y++)
                {
                    for (int x = x0; x <= x1; x++)
                    {
                        float u = (x + 0.5f) / T, v = (y + 0.5f) / T;
                        float s = Mathf.Clamp01((u - uvRect.x) / uvRect.width);
                        float t = Mathf.Clamp01((v - uvRect.y) / uvRect.height);
                        Vector3 p, n;
                        c.f(s, t, out p, out n);
                        int k = y * T + x;
                        shape.texPos[k] = p; shape.texNrm[k] = n; shape.texPart[k] = c.part;
                    }
                }
                shape.cRect[ci * 4] = x0; shape.cRect[ci * 4 + 1] = y0; shape.cRect[ci * 4 + 2] = x1; shape.cRect[ci * 4 + 3] = y1;
                Vector3 pc, nc; c.f(0.5f, 0.5f, out pc, out nc);
                float rad = 0f;
                for (int q = 0; q < 4; q++) { Vector3 pe, ne; c.f(q % 2, q / 2, out pe, out ne); rad = Mathf.Max(rad, (pe - pc).magnitude); }
                shape.cCenter[ci] = pc; shape.cRad[ci] = rad * 1.05f + 0.01f;
            }
            if (kind >= ShapeKind.Stand)
            {
                // 讓最低點剛好踩在地面上
                float minY = float.MaxValue;
                foreach (var v in verts) minY = Mathf.Min(minY, v.y);
                Vector3 lift = new Vector3(0f, -minY, 0f);
                for (int i = 0; i < verts.Count; i++) verts[i] += lift;
                for (int i = 0; i < shape.texPos.Length; i++) if (shape.texPart[i] != 255) shape.texPos[i] += lift;
                for (int i = 0; i < shape.cCenter.Length; i++) shape.cCenter[i] += lift;
            }

            var mesh = new Mesh();
            mesh.name = "Sushi_" + kind;
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            shape.mesh = mesh;
            shape.bounds = mesh.bounds;
            return shape;
        }

        // 手或腳：方塊掛在關節下方，繞關節轉
        static void AddLimb(List<Chart> charts, Quaternion root, Quaternion joint, Vector3 pivot, Vector3 half, float r, byte part, int startCell)
        {
            AddBox(charts, new Vector3(0f, -half.y, 0f), half, r, part, startCell, 6, 6, root * joint, root * pivot);
        }

        static void AddBox(List<Chart> charts, Vector3 center, Vector3 half, float r, byte part, int startCell, int cols, int rows)
        {
            AddBox(charts, center, half, r, part, startCell, cols, rows, Quaternion.identity, Vector3.zero);
        }

        static void AddBox(List<Chart> charts, Vector3 center, Vector3 half, float r, byte part, int startCell, int cols, int rows, Quaternion rot, Vector3 pivot)
        {
            for (int face = 0; face < 6; face++)
            {
                int axis = face / 2;
                float sign = (face % 2 == 0) ? 1f : -1f;
                int idx = startCell + face;
                var cell = new Rect((idx % cols) / (float)cols, (idx / cols) / (float)rows, 1f / cols, 1f / rows);
                Vector3 lim = new Vector3(half.x - r, half.y - r, half.z - r);
                charts.Add(new Chart
                {
                    cell = cell, part = part, ns = 8, nt = 8,
                    f = (float s, float t, out Vector3 p, out Vector3 n) =>
                    {
                        Vector3 c = Vector3.zero;
                        c[axis] = sign;
                        c[(axis + 1) % 3] = 2f * s - 1f;
                        c[(axis + 2) % 3] = 2f * t - 1f;
                        Vector3 q = Vector3.Scale(c, half);
                        Vector3 inner = new Vector3(Mathf.Clamp(q.x, -lim.x, lim.x), Mathf.Clamp(q.y, -lim.y, lim.y), Mathf.Clamp(q.z, -lim.z, lim.z));
                        Vector3 d = q - inner;
                        if (d.sqrMagnitude < 1e-10f) { d = Vector3.zero; d[axis] = sign; }
                        n = d.normalized;
                        p = pivot + rot * (center + inner + n * r);
                        n = rot * n;
                    }
                });
            }
        }

        // ---------- 參考貼圖 ----------

        // 和著色器裡的 smoothstep 相同：x 在 a 以下回傳 0，b 以上回傳 1
        static float SS(float a, float b, float x)
        {
            float t = Mathf.Clamp01((x - a) / (b - a));
            return t * t * (3f - 2f * t);
        }

        static Color Rice(Vector3 p)
        {
            float g = Mathf.PerlinNoise(p.x * 38f + p.y * 21f + 7f, p.z * 38f + p.y * 9f + 3f);
            return Color.Lerp(new Color(0.80f, 0.78f, 0.72f), new Color(0.97f, 0.96f, 0.92f), SS(0.2f, 0.6f, g));
        }

        static Color Nori(Vector3 p)
        {
            float g = Mathf.PerlinNoise(p.x * 30f + 11f, (p.y + p.z) * 30f + 5f);
            return new Color(0.05f + g * 0.05f, 0.09f + g * 0.05f, 0.07f + g * 0.04f);
        }

        static Color Shade(ShapeKind shape, SushiKind kind, byte part, Vector3 p)
        {
            if (kind == SushiKind.Blank || shape >= ShapeKind.Stand) return Rice(p);
            if (shape == ShapeKind.Nigiri)
            {
                if (kind == SushiKind.Tamago && Mathf.Abs(p.x) < 0.11f) return Nori(p);
                if (part == 0) return Rice(p);
                switch (kind)
                {
                    case SushiKind.Salmon:
                    {
                        float w = Mathf.Abs(Mathf.Sin(p.x * 9f + p.z * 4f));
                        return Color.Lerp(new Color(0.98f, 0.50f, 0.26f), new Color(1f, 0.82f, 0.68f), SS(0.88f, 0.97f, w));
                    }
                    case SushiKind.Tuna:
                    {
                        float w = 0.5f + 0.5f * Mathf.Sin(p.x * 14f + p.z * 3f);
                        return Color.Lerp(new Color(0.66f, 0.08f, 0.12f), new Color(0.80f, 0.14f, 0.18f), w);
                    }
                    case SushiKind.Tamago:
                    {
                        float g = Mathf.PerlinNoise(p.x * 12f + 2f, p.z * 12f + 9f);
                        return Color.Lerp(new Color(0.93f, 0.72f, 0.22f), new Color(0.99f, 0.86f, 0.36f), g);
                    }
                    default: // Shrimp
                    {
                        if (Mathf.Abs(p.z) < 0.03f) return new Color(0.99f, 0.95f, 0.92f);
                        float w = Mathf.Sin(p.x * 16f);
                        return Color.Lerp(new Color(0.99f, 0.90f, 0.84f), new Color(0.96f, 0.45f, 0.25f), SS(0.2f, 0.7f, w));
                    }
                }
            }
            // 卷
            if (part == 0) return Nori(p);
            float r = Mathf.Sqrt(p.x * p.x + p.z * p.z) / 0.36f;
            if (r > 0.88f) return Nori(p);
            if (r > 0.40f) return Rice(p);
            if (kind == SushiKind.CucumberRoll)
                return Color.Lerp(new Color(0.78f, 0.90f, 0.60f), new Color(0.36f, 0.66f, 0.26f), SS(0.15f, 0.38f, r));
            return Color.Lerp(new Color(0.80f, 0.14f, 0.18f), new Color(0.66f, 0.08f, 0.12f), r / 0.4f);
        }

        public static Color32[] BuildPixels(SushiShape sh, SushiKind kind)
        {
            var px = new Color32[T * T];
            Color32 fallback = new Color(0.95f, 0.94f, 0.9f);
            for (int i = 0; i < px.Length; i++)
            {
                if (sh.texPart[i] == 255) { px[i] = fallback; continue; }
                Color c = Shade(sh.kind, kind, sh.texPart[i], sh.texPos[i]);
                c.a = 1f;
                px[i] = c;
            }
            return px;
        }
    }
}
