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

    /// 用程式產生的簡單提示音，之後換成正式音效。
    public static class Sfx
    {
        static AudioSource src;
        static readonly Dictionary<int, AudioClip> clips = new Dictionary<int, AudioClip>();
        public static void Init(GameObject host) { src = host.AddComponent<AudioSource>(); src.playOnAwake = false; }
        public static void Beep(float freq, float dur, float vol)
        {
            if (src == null || !Application.isPlaying) return;
            int key = Mathf.RoundToInt(freq) * 1000 + Mathf.RoundToInt(dur * 100f);
            AudioClip clip;
            if (!clips.TryGetValue(key, out clip) || clip == null)
            {
                const int rate = 44100;
                int n = Mathf.Max(1, (int)(rate * dur));
                var data = new float[n];
                for (int i = 0; i < n; i++)
                {
                    float x = i / (float)rate, env = Mathf.Exp(-x / (dur * 0.35f)) * Mathf.Min(1f, i / 200f);
                    data[i] = (Mathf.Sin(x * freq * 6.2832f) + 0.35f * Mathf.Sin(x * freq * 12.566f)) * env * 0.6f;
                }
                clip = AudioClip.Create("beep" + key, n, 1, rate, false);
                clip.SetData(data, 0);
                clips[key] = clip;
            }
            src.PlayOneShot(clip, vol);
        }
    }

    public class Paintable : MonoBehaviour
    {
        public SushiShape shape;
        public Texture2D tex;
        public Color32[] px;
        public MeshRenderer rend;
        public MeshCollider meshCol;
        MeshFilter mf;

        /// 換姿勢：換網格和對照表，貼圖保留。
        public void SetShape(SushiShape sh)
        {
            shape = sh; mf.sharedMesh = sh.mesh;
            if (meshCol != null) meshCol.sharedMesh = sh.mesh;
        }

        bool dirty;
        readonly List<Color32[]> undo = new List<Color32[]>();

        public void Init(SushiShape sh, SushiKind kind, bool withMeshCollider)
        {
            shape = sh;
            mf = gameObject.AddComponent<MeshFilter>();
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

        /// 用帶一點雜色的單一顏色塗滿（電腦壽司偽裝成桌面時用）。
        public void FillNoisy(Color c, float noise)
        {
            var pos = shape.texPos;
            for (int i = 0; i < px.Length; i++)
            {
                float g = Mathf.PerlinNoise(pos[i].x * 9f + 3f, pos[i].z * 30f + pos[i].y * 11f) - 0.5f;
                Color k = c * (1f + g * 2f * noise); k.a = 1f;
                px[i] = k;
            }
            dirty = true; Flush();
        }

        /// 把貼圖弄得「不夠像」：flat 讓花紋變糊，tint 讓顏色偏掉，miss 留一塊沒塗的白。
        public void Degrade(float flat, float tint, float miss)
        {
            var pos = shape.texPos; var part = shape.texPart;
            var sum = new Vector3[4]; var cnt = new int[4];
            for (int i = 0; i < px.Length; i++)
            {
                int q = part[i]; if (q > 3) continue;
                sum[q] += new Vector3(px[i].r, px[i].g, px[i].b); cnt[q]++;
            }
            Vector3 t = new Vector3(1f + Random.Range(-tint, tint), 1f + Random.Range(-tint, tint), 1f + Random.Range(-tint, tint));
            Vector3 hole = Vector3.zero; bool hasHole = miss > 0f;
            if (hasHole)
            {
                for (int tries = 0; tries < 200; tries++)
                {
                    int k = Random.Range(0, px.Length);
                    if (part[k] != 255 && shape.texNrm[k].y > 0.3f) { hole = pos[k]; break; }
                }
            }
            for (int i = 0; i < px.Length; i++)
            {
                int q = part[i]; if (q > 3) continue;
                Vector3 c = new Vector3(px[i].r, px[i].g, px[i].b);
                if (cnt[q] > 0) c = Vector3.Lerp(c, sum[q] / cnt[q], flat);
                c = Vector3.Scale(c, t);
                if (hasHole && (pos[i] - hole).sqrMagnitude < miss * miss) c = new Vector3(244f, 242f, 234f);
                px[i] = new Color32((byte)Mathf.Clamp(c.x, 0f, 255f), (byte)Mathf.Clamp(c.y, 0f, 255f), (byte)Mathf.Clamp(c.z, 0f, 255f), 255);
            }
            dirty = true; Flush();
        }

        /// 在世界座標 wp 處畫一個半徑 wr 的點。wn 是命中處的法線，背對它的表面不上色。
        public void Dab(Vector3 wp, Vector3 wn, float wr, Color32 c)
        {
            Vector3 lp = transform.InverseTransformPoint(wp);
            Vector3 ln = transform.InverseTransformDirection(wn);
            float lr = wr / Mathf.Max(0.0001f, transform.lossyScale.x);
            float rr = lr * lr;
            var pos = shape.texPos; var nrm = shape.texNrm; var part = shape.texPart;
            const int T = SushiShape.T;
            for (int ch = 0; ch < shape.cRad.Length; ch++)
            {
                float reach = shape.cRad[ch] + lr;
                if ((shape.cCenter[ch] - lp).sqrMagnitude > reach * reach) continue;
                int x0 = shape.cRect[ch * 4], y0 = shape.cRect[ch * 4 + 1], x1 = shape.cRect[ch * 4 + 2], y1 = shape.cRect[ch * 4 + 3];
                for (int y = y0; y <= y1; y++)
                {
                    int row = y * T;
                    for (int x = x0; x <= x1; x++)
                    {
                        int i = row + x;
                        if (part[i] == 255) continue;
                        float dx = pos[i].x - lp.x, dy = pos[i].y - lp.y, dz = pos[i].z - lp.z;
                        if (dx * dx + dy * dy + dz * dz > rr) continue;
                        if (nrm[i].x * ln.x + nrm[i].y * ln.y + nrm[i].z * ln.z <= 0f) continue;
                        px[i] = c;
                        dirty = true;
                    }
                }
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
