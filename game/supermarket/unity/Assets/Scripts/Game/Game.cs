// First playable shell: runs the rule core, saves locally, pays offline earnings.
// Screen layout here is a stand-in; the art pass replaces it.
using System;
using Souq.Core;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Souq
{
    public class Game : MonoBehaviour
    {
        const string SaveKey = "save.v1";
        Tables t; GameState s;
        Text cashText, rateText; Text[] rowText; Text starText;
        float saveTimer;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot() => new GameObject("Game").AddComponent<Game>();

        static long Now() => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        void Awake()
        {
            Application.targetFrameRate = 60;
            t = JsonUtility.FromJson<Tables>(Resources.Load<TextAsset>("tables").text);
            s = Load();
            BuildWorld();
            BuildHud();
        }

        GameState Load()
        {
            var json = PlayerPrefs.GetString(SaveKey, "");
            GameState g = null;
            if (json.Length > 0) { try { g = JsonUtility.FromJson<GameState>(json); } catch { g = null; } }
            if (g == null || g.level == null || g.level.Length != t.departments.Length) return GameState.Fresh(t);
            g.cash += Economy.Offline(t, g, Now());
            return g;
        }

        void Save()
        {
            s.lastSeenUnix = Now();
            PlayerPrefs.SetString(SaveKey, JsonUtility.ToJson(s));
            PlayerPrefs.Save();
        }

        void OnApplicationPause(bool paused)
        {
            if (paused) Save();
            else if (s != null) { s.cash += Economy.Offline(t, s, Now()); s.lastSeenUnix = Now(); }
        }

        void Update()
        {
            Economy.Tick(t, s, Time.unscaledDeltaTime);
            saveTimer += Time.unscaledDeltaTime;
            if (saveTimer > 5) { saveTimer = 0; Save(); }
            Refresh();
        }

        // ---------- world (placeholder blocks, one per department) ----------
        void BuildWorld()
        {
            var cam = new GameObject("Camera").AddComponent<Camera>();
            cam.transform.position = new Vector3(0, 14, -13);
            cam.transform.rotation = Quaternion.Euler(48, 0, 0);
            cam.fieldOfView = 40;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.05f, 0.07f, 0.13f);

            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional; sun.intensity = 1.2f; sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(50, -30, 0);

            var baseMat = Resources.Load<Material>("BaseLit");
            Block(baseMat, new Vector3(0, -0.25f, 0), new Vector3(12, 0.5f, 16), new Color(0.82f, 0.80f, 0.76f));
            for (int i = 0; i < t.departments.Length; i++)
            {
                var pos = new Vector3(-3.6f + (i % 3) * 3.6f, 0.6f, 5.4f - (i / 3) * 3.6f);
                Block(baseMat, pos, new Vector3(2.6f, 1.2f, 2.2f), Color.HSVToRGB(i / 12f, 0.55f, 0.9f));
            }
        }

        static void Block(Material baseMat, Vector3 pos, Vector3 size, Color c)
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
            g.transform.position = pos; g.transform.localScale = size;
            var m = new Material(baseMat);
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c); else m.color = c;
            g.GetComponent<Renderer>().sharedMaterial = m;
        }

        // ---------- HUD ----------
        void BuildHud()
        {
            new GameObject("EventSystem", typeof(EventSystem), typeof(StandaloneInputModule));
            var canvasGo = new GameObject("Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasGo.GetComponent<Canvas>(); canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1080, 2340); scaler.matchWidthOrHeight = 0;
            var font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var root = canvasGo.transform;

            cashText = Label(root, font, 84, TextAnchor.UpperCenter, new Vector2(0, 1), new Vector2(1, 1), new Vector2(0, -170), new Vector2(0, 110));
            rateText = Label(root, font, 40, TextAnchor.UpperCenter, new Vector2(0, 1), new Vector2(1, 1), new Vector2(0, -280), new Vector2(0, 60));

            int n = t.departments.Length;
            rowText = new Text[n];
            const float rowH = 84, gap = 8, bottom = 150;
            for (int i = 0; i < n; i++)
            {
                int idx = i;
                float y = bottom + (n - 1 - i) * (rowH + gap);
                rowText[i] = Button(root, font, new Vector2(40, y), new Vector2(-40, rowH), () => Tap(idx));
            }
            starText = Button(root, font, new Vector2(40, 50), new Vector2(-40, rowH), () => Economy.StarUp(t, s));
        }

        void Tap(int i)
        {
            if (s.level[i] == 0) Economy.Unlock(t, s, i); else Economy.LevelUp(t, s, i);
        }

        static Text Label(Transform parent, Font font, int size, TextAnchor anchor, Vector2 aMin, Vector2 aMax, Vector2 pos, Vector2 sizeDelta)
        {
            var go = new GameObject("Label", typeof(RectTransform), typeof(Text));
            go.transform.SetParent(parent, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = aMin; rt.anchorMax = aMax; rt.pivot = new Vector2(0.5f, 1);
            rt.anchoredPosition = pos; rt.sizeDelta = sizeDelta;
            var tx = go.GetComponent<Text>();
            tx.font = font; tx.fontSize = size; tx.alignment = anchor; tx.color = Color.white; tx.raycastTarget = false;
            return tx;
        }

        static Text Button(Transform parent, Font font, Vector2 offsetMin, Vector2 size, Action onTap)
        {
            var go = new GameObject("Button", typeof(RectTransform), typeof(Image), typeof(Button));
            go.transform.SetParent(parent, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = new Vector2(0, 0); rt.anchorMax = new Vector2(1, 0); rt.pivot = new Vector2(0.5f, 0);
            rt.offsetMin = new Vector2(offsetMin.x, offsetMin.y); rt.offsetMax = new Vector2(size.x, offsetMin.y + size.y);
            go.GetComponent<Image>().color = new Color(0.12f, 0.16f, 0.26f, 0.92f);
            go.GetComponent<Button>().onClick.AddListener(() => onTap());
            var tx = Label(go.transform, font, 34, TextAnchor.MiddleCenter, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            ((RectTransform)tx.transform).pivot = new Vector2(0.5f, 0.5f);
            return tx;
        }

        void Refresh()
        {
            cashText.text = Num(s.cash);
            rateText.text = Num(Economy.Rate(t, s)) + " / s";
            for (int i = 0; i < rowText.Length; i++)
            {
                var d = t.departments[i];
                bool locked = s.level[i] == 0;
                bool reachable = i == 0 || s.level[i - 1] > 0;
                double cost = locked ? d.unlockCost : Economy.LevelCost(t, i, s.level[i]);
                rowText[i].text = locked
                    ? (reachable ? d.id + "  -  open " + Num(cost) : d.id + "  -  locked")
                    : d.id + "  Lv " + s.level[i] + "  -  " + Num(cost);
                rowText[i].color = (reachable && s.cash >= cost) ? Color.white : new Color(1, 1, 1, 0.45f);
            }
            bool maxed = s.star >= t.@params.starMax;
            double sc = Economy.StarCost(t, s.star);
            starText.text = "store star " + s.star + (maxed ? "  (max)" : "  -  " + Num(sc));
            starText.color = (!maxed && s.cash >= sc) ? new Color(1f, 0.85f, 0.4f) : new Color(1f, 0.85f, 0.4f, 0.45f);
        }

        static readonly string[] Units = { "", "K", "M", "B", "T" };
        public static string Num(double v)
        {
            if (v < 1000) return v.ToString("0.#");
            int e = (int)Math.Floor(Math.Log10(v) / 3);
            if (e < Units.Length) return (v / Math.Pow(1000, e)).ToString("0.##") + Units[e];
            return v.ToString("0.00e0");
        }
    }
}
