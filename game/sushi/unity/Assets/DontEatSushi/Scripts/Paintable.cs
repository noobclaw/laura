// 別吃壽司 - 可以被塗色的壽司。筆刷是空間中的一個球，碰到的表面像素都上色。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public static class Mats
    {
        public static Material Lit(Color c, float smooth = 0.3f, Texture tex = null)
        {
            // 打包後 Shader.Find 找不到沒被引用的著色器，所以優先複製 Resources 裡的材質
            var baseMat = Resources.Load<Material>("SushiLit");
            Material m;
            if (baseMat != null) m = new Material(baseMat);
            else
            {
                var sh = Shader.Find("Universal Render Pipeline/Lit");
                if (sh == null) sh = Shader.Find("Standard");
                m = new Material(sh);
            }
            SetColor(m, c);
            if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smooth);
            else if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smooth);
            if (tex != null)
            {
                if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", tex);
                else m.mainTexture = tex;
            }
            return m;
        }

        public static Material Unlit(Color c)
        {
            var baseMat = Resources.Load<Material>("SushiUnlit");
            Material m;
            if (baseMat != null) m = new Material(baseMat);
            else
            {
                var sh = Shader.Find("Universal Render Pipeline/Unlit");
                if (sh == null) sh = Shader.Find("Unlit/Color");
                m = new Material(sh);
            }
            SetColor(m, c);
            return m;
        }

        public static void SetColor(Material m, Color c)
        {
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
            else if (m.HasProperty("_Color")) m.SetColor("_Color", c);
        }

        public static Color GetColor(Material m)
        {
            if (m == null) return Color.gray;
            if (m.HasProperty("_BaseColor")) return m.GetColor("_BaseColor");
            if (m.HasProperty("_Color")) return m.GetColor("_Color");
            return Color.gray;
        }
    }

    public class Paintable : MonoBehaviour
    {
        public SushiShape shape;
        public Texture2D tex;
        public Color32[] px;
        public MeshRenderer rend;
        public MeshCollider meshCol;

        bool dirty;
        readonly List<Color32[]> undo = new List<Color32[]>();

        public void Init(SushiShape sh, SushiKind kind, bool withMeshCollider)
        {
            shape = sh;
            var mf = gameObject.AddComponent<MeshFilter>();
            mf.sharedMesh = sh.mesh;
            rend = gameObject.AddComponent<MeshRenderer>();
            tex = new Texture2D(SushiShape.T, SushiShape.T, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;
            tex.filterMode = FilterMode.Bilinear;
            px = SushiShapes.BuildPixels(sh, kind);
            tex.SetPixels32(px);
            tex.Apply(false);
            rend.sharedMaterial = Mats.Lit(Color.white, 0.32f, tex);
            if (withMeshCollider)
            {
                meshCol = gameObject.AddComponent<MeshCollider>();
                meshCol.sharedMesh = sh.mesh;
            }
            else
            {
                var bc = gameObject.AddComponent<BoxCollider>();
                bc.center = sh.bounds.center;
                bc.size = sh.bounds.size;
            }
        }

        public void PushUndo()
        {
            undo.Add((Color32[])px.Clone());
            if (undo.Count > 12) undo.RemoveAt(0);
        }

        public bool Undo()
        {
            if (undo.Count == 0) return false;
            px = undo[undo.Count - 1];
            undo.RemoveAt(undo.Count - 1);
            dirty = true;
            Flush();
            return true;
        }

        public void Fill(Color32 c)
        {
            for (int i = 0; i < px.Length; i++) px[i] = c;
            dirty = true;
        }

        /// 在世界座標 wp 處畫一個半徑 wr 的點。wn 是命中處的法線，背對它的表面不上色。
        public void Dab(Vector3 wp, Vector3 wn, float wr, Color32 c)
        {
            Vector3 lp = transform.InverseTransformPoint(wp);
            Vector3 ln = transform.InverseTransformDirection(wn);
            float lr = wr / Mathf.Max(0.0001f, transform.lossyScale.x);
            float rr = lr * lr;
            var pos = shape.texPos; var nrm = shape.texNrm; var part = shape.texPart;
            for (int i = 0; i < px.Length; i++)
            {
                if (part[i] == 255) continue;
                float dx = pos[i].x - lp.x, dy = pos[i].y - lp.y, dz = pos[i].z - lp.z;
                if (dx * dx + dy * dy + dz * dz > rr) continue;
                if (nrm[i].x * ln.x + nrm[i].y * ln.y + nrm[i].z * ln.z <= 0f) continue;
                px[i] = c;
                dirty = true;
            }
        }

        /// 讀取離世界座標 wp 最近的表面顏色（取色器用）。
        public Color32 Sample(Vector3 wp)
        {
            Vector3 lp = transform.InverseTransformPoint(wp);
            var pos = shape.texPos; var part = shape.texPart;
            float best = float.MaxValue; int bi = 0;
            for (int i = 0; i < px.Length; i++)
            {
                if (part[i] == 255) continue;
                float d = (pos[i] - lp).sqrMagnitude;
                if (d < best) { best = d; bi = i; }
            }
            return px[bi];
        }

        public void Flush()
        {
            if (!dirty) return;
            tex.SetPixels32(px);
            tex.Apply(false);
            dirty = false;
        }
    }
}
