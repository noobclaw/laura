// Solid builder: many small coloured parts merged into one mesh. Colours live on the vertices, so there are no textures to blur.
using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Souq
{
    public class Geo
    {
        readonly List<Vector3> p = new List<Vector3>(), n = new List<Vector3>(); readonly List<Color> c = new List<Color>(); readonly List<int> ix = new List<int>();
        Matrix4x4 m = Matrix4x4.identity; Color col = Color.white; public float Shade = 0.16f;
        public int Triangles => ix.Count / 3;

        public static Color Hex(string h)
        {
            if (h[0] == '#') h = h.Substring(1);
            float r = Convert.ToInt32(h.Substring(0, 2), 16) / 255f, g = Convert.ToInt32(h.Substring(2, 2), 16) / 255f, b = Convert.ToInt32(h.Substring(4, 2), 16) / 255f;
            return new Color(r, g, b, 1);
        }
        public Geo C(string hex) { col = Hex(hex).linear; return this; }
        public Geo C(Color srgb) { col = srgb.linear; return this; }
        /// Where the next parts go: position, then turn about Y, X, Z (degrees).
        public Geo At(float x = 0, float y = 0, float z = 0, float ry = 0, float rx = 0, float rz = 0) { m = Matrix4x4.TRS(new Vector3(x, y, z), Quaternion.Euler(rx, ry, rz), Vector3.one); return this; }
        public Geo At(Matrix4x4 matrix) { m = matrix; return this; }
        public Matrix4x4 M => m;
        int V(float x, float y, float z, float nx, float ny, float nz, float k)
        {
            p.Add(m.MultiplyPoint3x4(new Vector3(x, y, z))); n.Add(m.MultiplyVector(new Vector3(nx, ny, nz)).normalized); c.Add(new Color(col.r * k, col.g * k, col.b * k, 1)); return p.Count - 1;
        }
        void Quad(int a) { ix.Add(a); ix.Add(a + 1); ix.Add(a + 2); ix.Add(a); ix.Add(a + 2); ix.Add(a + 3); }
        /// Box centred on x,z with its base at y. The lower edge is a little darker so parts look seated.
        public Geo Box(float w, float h, float d, float x = 0, float y = 0, float z = 0)
        {
            float X = w / 2, Z = d / 2, lo = 1 - Shade, hi = 1.04f; int s;
            s = p.Count; V(x - X, y, z + Z, 0, 0, 1, lo); V(x + X, y, z + Z, 0, 0, 1, lo); V(x + X, y + h, z + Z, 0, 0, 1, 1); V(x - X, y + h, z + Z, 0, 0, 1, 1); Quad(s);
            s = p.Count; V(x + X, y, z - Z, 0, 0, -1, lo); V(x - X, y, z - Z, 0, 0, -1, lo); V(x - X, y + h, z - Z, 0, 0, -1, 1); V(x + X, y + h, z - Z, 0, 0, -1, 1); Quad(s);
            s = p.Count; V(x + X, y, z + Z, 1, 0, 0, lo); V(x + X, y, z - Z, 1, 0, 0, lo); V(x + X, y + h, z - Z, 1, 0, 0, 1); V(x + X, y + h, z + Z, 1, 0, 0, 1); Quad(s);
            s = p.Count; V(x - X, y, z - Z, -1, 0, 0, lo); V(x - X, y, z + Z, -1, 0, 0, lo); V(x - X, y + h, z + Z, -1, 0, 0, 1); V(x - X, y + h, z - Z, -1, 0, 0, 1); Quad(s);
            s = p.Count; V(x - X, y + h, z + Z, 0, 1, 0, hi); V(x + X, y + h, z + Z, 0, 1, 0, hi); V(x + X, y + h, z - Z, 0, 1, 0, hi); V(x - X, y + h, z - Z, 0, 1, 0, hi); Quad(s);
            s = p.Count; V(x - X, y, z - Z, 0, -1, 0, lo); V(x + X, y, z - Z, 0, -1, 0, lo); V(x + X, y, z + Z, 0, -1, 0, lo); V(x - X, y, z + Z, 0, -1, 0, lo); Quad(s);
            return this;
        }
        /// Upright cylinder or cone with its base at y.
        public Geo Cyl(float r0, float r1, float h, float x = 0, float y = 0, float z = 0, int seg = 14)
        {
            int s = p.Count; float lo = 1 - Shade, sl = (r0 - r1) / Mathf.Max(1e-4f, h);
            for (int k = 0; k <= seg; k++) { float a = k / (float)seg * Mathf.PI * 2, cx = Mathf.Cos(a), sz = Mathf.Sin(a); V(x + cx * r0, y, z + sz * r0, cx, sl, sz, lo); V(x + cx * r1, y + h, z + sz * r1, cx, sl, sz, 1); }
            for (int k = 0; k < seg; k++) { int a = s + k * 2; ix.Add(a); ix.Add(a + 1); ix.Add(a + 3); ix.Add(a); ix.Add(a + 3); ix.Add(a + 2); }
            if (r1 > 0)
            {
                int ctr = V(x, y + h, z, 0, 1, 0, 1.04f), t = p.Count;
                for (int k = 0; k <= seg; k++) { float a = k / (float)seg * Mathf.PI * 2; V(x + Mathf.Cos(a) * r1, y + h, z + Mathf.Sin(a) * r1, 0, 1, 0, 1.04f); }
                for (int k = 0; k < seg; k++) { ix.Add(ctr); ix.Add(t + k + 1); ix.Add(t + k); }
            }
            return this;
        }
        /// Ellipsoid centred at x,y,z.
        public Geo Ball(float rx, float ry, float rz, float x = 0, float y = 0, float z = 0, int seg = 14, int rings = 9)
        {
            int s = p.Count; float lo = 1 - Shade;
            for (int j = 0; j <= rings; j++)
            {
                float v = j / (float)rings * Mathf.PI, sy = Mathf.Cos(v), sr = Mathf.Sin(v);
                for (int k = 0; k <= seg; k++) { float a = k / (float)seg * Mathf.PI * 2, nx = Mathf.Cos(a) * sr, nz = Mathf.Sin(a) * sr; V(x + nx * rx, y + sy * ry, z + nz * rz, nx / rx, sy / ry, nz / rz, lo + (1.04f - lo) * (sy * 0.5f + 0.5f)); }
            }
            for (int j = 0; j < rings; j++) for (int k = 0; k < seg; k++) { int a = s + j * (seg + 1) + k, b = a + seg + 1; ix.Add(a); ix.Add(a + 1); ix.Add(b + 1); ix.Add(a); ix.Add(b + 1); ix.Add(b); }
            return this;
        }
        /// Flat rounded rectangle lying on the ground at height y (a floor mat, a painted bay).
        public Geo Slab(float w, float d, float r, float x, float y, float z, float thick = 0.012f)
        {
            int s = p.Count; r = Mathf.Min(r, Mathf.Min(w, d) / 2); V(x, y + thick, z, 0, 1, 0, 1); int n0 = p.Count, per = 6;
            for (int corner = 0; corner < 4; corner++)
            {
                float cx = x + (corner == 0 || corner == 3 ? 1 : -1) * (w / 2 - r), cz = z + (corner < 2 ? 1 : -1) * (d / 2 - r);
                for (int k = 0; k <= per; k++) { float a = (corner * 90 + k * 90f / per) * Mathf.Deg2Rad; V(cx + Mathf.Cos(a) * r, y + thick, cz + Mathf.Sin(a) * r, 0, 1, 0, 1); }
            }
            int cnt = p.Count - n0; for (int k = 0; k < cnt; k++) { ix.Add(s); ix.Add(n0 + (k + 1) % cnt); ix.Add(n0 + k); }
            return this;
        }
        public Mesh ToMesh(string name = "geo")
        {
            var mesh = new Mesh { name = name }; if (p.Count > 65000) mesh.indexFormat = IndexFormat.UInt32;
            mesh.SetVertices(p); mesh.SetNormals(n); mesh.SetColors(c); mesh.SetTriangles(ix, 0); mesh.RecalculateBounds(); return mesh;
        }
        public GameObject Make(string name, Transform parent, Material mat, bool shadows = true)
        {
            var g = new GameObject(name); g.transform.SetParent(parent, false); g.AddComponent<MeshFilter>().sharedMesh = ToMesh(name);
            var r = g.AddComponent<MeshRenderer>(); r.sharedMaterial = mat; r.shadowCastingMode = shadows ? ShadowCastingMode.On : ShadowCastingMode.Off; r.receiveShadows = true; return g;
        }
    }
}
