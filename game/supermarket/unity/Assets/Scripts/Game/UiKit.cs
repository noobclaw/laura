// Small helpers for building the interface in code: drawn sprites, text, buttons, layout and screen effects.
using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Souq
{
    public static class Spr
    {
        public static Sprite Round, Circle, Glow, Gem, Coin, Star, Person, Square, Ring, Arrow, Spark;
        // drawn as vector art and shipped as large pictures (game/supermarket/ui-art); null when a build has none
        public static Sprite ButtonFx, Register, Parking, Bolt, Crown, Bag, Gear, Truck, Bus, Megaphone, Clock, Gift, Cart, Up, Lock;
        static Sprite Load(string name, float ppu = 100, int border = 0)
        {
            var tex = Resources.Load<Texture2D>("Ui/" + name); if (tex == null) return null;
            return Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f), ppu, 0, SpriteMeshType.FullRect, new Vector4(border, border, border, border));
        }
        static Sprite Make(int n, Func<float, float, Color> f, int border = 0)
        {
            var t = new Texture2D(n, n, TextureFormat.RGBA32, false); t.wrapMode = TextureWrapMode.Clamp; t.filterMode = FilterMode.Bilinear;
            var px = new Color[n * n];
            for (int y = 0; y < n; y++) for (int x = 0; x < n; x++) px[y * n + x] = f((x + 0.5f) / n * 2 - 1, (y + 0.5f) / n * 2 - 1);
            t.SetPixels(px); t.Apply();
            return Sprite.Create(t, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f), 100, 0, SpriteMeshType.FullRect, new Vector4(border, border, border, border));
        }
        static float Aa(float d, float w) => Mathf.Clamp01(0.5f - d / w);          // d: signed distance, negative inside
        static float Box(float x, float y, float hx, float hy, float r)
        {
            float qx = Mathf.Abs(x) - hx + r, qy = Mathf.Abs(y) - hy + r;
            return Mathf.Min(Mathf.Max(qx, qy), 0) + new Vector2(Mathf.Max(qx, 0), Mathf.Max(qy, 0)).magnitude - r;
        }
        static Color W(float a) => new Color(1, 1, 1, a);
        public static void Init()
        {
            if (Round != null) return;
            ButtonFx = Load("button_fx", 100f * 256 / 96, 80); Register = Load("register"); Parking = Load("parking"); Bolt = Load("bolt"); Crown = Load("crown"); Bag = Load("bag"); Gear = Load("gear");
            Truck = Load("truck"); Bus = Load("bus"); Megaphone = Load("megaphone"); Clock = Load("clock"); Gift = Load("gift"); Cart = Load("cart"); Up = Load("up"); Lock = Load("lock");
            Round = Make(96, (x, y) => W(Aa(Box(x, y, 1, 1, 0.52f), 0.04f)), 30);
            Square = Make(8, (x, y) => Color.white);
            Ring = Make(128, (x, y) => { float d = Mathf.Sqrt(x * x + y * y); return W(Aa(Mathf.Abs(d - 0.84f) - 0.09f, 0.03f)); });
            // a fat arrow pointing down
            Arrow = Make(128, (x, y) => { float head = Mathf.Max(Mathf.Abs(x) * 1.25f - (y + 0.95f), y - 0.05f); float stem = Box(x, y - 0.45f, 0.28f, 0.5f, 0.12f); return W(Aa(Mathf.Min(head, stem), 0.04f)); });
            // a four-point sparkle
            Spark = Make(96, (x, y) => { float ax = Mathf.Abs(x), ay = Mathf.Abs(y); float d = Mathf.Pow(ax, 0.55f) + Mathf.Pow(ay, 0.55f) - 0.95f; return W(Aa(d, 0.08f)); });
            Circle = Make(128, (x, y) => W(Aa(Mathf.Sqrt(x * x + y * y) - 0.96f, 0.03f)));
            Glow = Make(128, (x, y) => { float d = Mathf.Sqrt(x * x + y * y); float a = Mathf.Clamp01(1 - d); return W(a * a); });
            Coin = Make(128, (x, y) =>
            {
                float d = Mathf.Sqrt(x * x + y * y); float a = Aa(d - 0.96f, 0.03f);
                var c = Color.Lerp(new Color(1f, 0.93f, 0.45f), new Color(0.98f, 0.66f, 0.10f), Mathf.Clamp01((1 - y) * 0.55f));
                if (d > 0.70f && d < 0.80f) c = Color.Lerp(c, new Color(0.80f, 0.45f, 0.05f), 0.8f);
                if (Mathf.Abs(x) < 0.09f && Mathf.Abs(y) < 0.42f) c = new Color(0.80f, 0.45f, 0.05f);
                if (d > 0.90f) c = new Color(0.72f, 0.40f, 0.05f);
                c.a = a; return c;
            });
            Gem = Make(128, (x, y) =>
            {
                float d = Mathf.Abs(x) * 0.95f + Mathf.Abs(y - 0.05f) * (y > 0.05f ? 1.9f : 1.05f) - 0.9f;
                var c = Color.Lerp(new Color(0.20f, 0.55f, 1f), new Color(0.55f, 0.95f, 1f), Mathf.Clamp01(0.5f + y * 0.6f + x * 0.35f));
                if (y > 0.05f && Mathf.Abs(x) < 0.35f) c = Color.Lerp(c, Color.white, 0.45f);
                c.a = Aa(d, 0.04f); return c;
            });
            Star = Make(128, (x, y) =>
            {
                float ang = Mathf.Atan2(x, y), r = Mathf.Sqrt(x * x + y * y);
                float k = Mathf.Abs(Mathf.Repeat(ang / (2 * Mathf.PI) * 5 + 0.5f, 1f) - 0.5f) * 2;       // 0 at a point, 1 between points
                float edge = Mathf.Lerp(0.95f, 0.42f, k);
                var c = Color.Lerp(new Color(1f, 0.95f, 0.5f), new Color(1f, 0.70f, 0.12f), Mathf.Clamp01(0.5f - y * 0.5f)); c.a = Aa(r - edge, 0.05f); return c;
            });
            Person = Make(128, (x, y) =>
            {
                float head = Mathf.Sqrt(x * x + (y - 0.42f) * (y - 0.42f)) - 0.34f; float body = Box(x, y + 0.52f, 0.62f, 0.44f, 0.4f);
                return W(Aa(Mathf.Min(head, body), 0.04f));
            });
            Coin = Load("coin") ?? Coin; Gem = Load("gem") ?? Gem; Star = Load("star") ?? Star; Person = Load("person") ?? Person;
        }
    }

    public class Tween { public float t, dur, delay; public Action<float> step; public Action done; }

    public static class U
    {
        public static Font Font;
        /// Chinese, Japanese and Korean use the phone's own typeface; the bundled one covers Latin and Arabic.
        public static void PickFont()
        {
            Font = null;
            if (Loc.Cjk) { try { Font = UnityEngine.Font.CreateDynamicFontFromOSFont(Loc.Lang == 2 ? new[] { "Hiragino Sans", "HiraginoSans-W6", "Noto Sans CJK JP", "Noto Sans JP" } : Loc.Lang == 3 ? new[] { "Apple SD Gothic Neo", "AppleSDGothicNeo-Bold", "Noto Sans CJK KR", "Noto Sans KR" } : new[] { "PingFang TC", "PingFangTC-Semibold", "Noto Sans CJK TC", "Noto Sans TC" }, 40); } catch { Font = null; } }
            if (Font == null) Font = Resources.Load<Font>("Font/Changa-Bold"); if (Font == null) Font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        }
        public static readonly Color Ink = new Color(0.13f, 0.15f, 0.25f), Panel = new Color(0.99f, 0.98f, 0.96f), Navy = new Color(0.10f, 0.13f, 0.27f, 0.94f),
            Gold = new Color(1f, 0.78f, 0.18f), Green = new Color(0.25f, 0.78f, 0.42f), Blue = new Color(0.22f, 0.56f, 0.98f), Red = new Color(0.95f, 0.30f, 0.35f),
            Purple = new Color(0.62f, 0.40f, 0.96f), Grey = new Color(0.70f, 0.72f, 0.78f), Soft = new Color(0.93f, 0.93f, 0.96f);

        public static RectTransform Rect(Transform parent, string name)
        {
            var go = new GameObject(name, typeof(RectTransform)); go.layer = 5; go.transform.SetParent(parent, false); return (RectTransform)go.transform;
        }
        /// Anchors as fractions of the parent, then pixel insets from those anchors: left, bottom, right, top.
        public static RectTransform Place(RectTransform rt, float ax0, float ay0, float ax1, float ay1, float l, float b, float r, float t)
        {
            rt.anchorMin = new Vector2(ax0, ay0); rt.anchorMax = new Vector2(ax1, ay1); rt.offsetMin = new Vector2(l, b); rt.offsetMax = new Vector2(r, t); return rt;
        }
        public static RectTransform Fill(RectTransform rt) => Place(rt, 0, 0, 1, 1, 0, 0, 0, 0);
        /// Fixed-size box whose pivot sits at anchor (ax, ay) of the parent, offset by (x, y).
        public static RectTransform Pin(RectTransform rt, float ax, float ay, float x, float y, float w, float h)
        {
            rt.anchorMin = rt.anchorMax = new Vector2(ax, ay); rt.pivot = new Vector2(ax, ay); rt.anchoredPosition = new Vector2(x, y); rt.sizeDelta = new Vector2(w, h); return rt;
        }
        public static Image Img(Transform parent, Sprite s, Color c, string name = "img", bool sliced = true, bool hit = false)
        {
            var rt = Rect(parent, name); var i = rt.gameObject.AddComponent<Image>(); i.sprite = s; i.color = c; i.raycastTarget = hit;
            if (sliced && s == Spr.Round) { i.type = Image.Type.Sliced; i.pixelsPerUnitMultiplier = 1; }
            return i;
        }
        public static Text Txt(Transform parent, string s, int size, Color c, TextAnchor a = TextAnchor.MiddleCenter, string name = "txt")
        {
            var rt = Rect(parent, name); var t = rt.gameObject.AddComponent<Text>();
            t.font = Font; t.fontSize = size; t.color = c; t.alignment = a; t.text = s; t.raycastTarget = false; t.supportRichText = false;
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Truncate;
            t.resizeTextForBestFit = true; t.resizeTextMinSize = Mathf.Max(12, size / 2); t.resizeTextMaxSize = size;
            return t;
        }
        public static Text Shade(Text t, float d = 3, float a = 0.45f) { var s = t.gameObject.AddComponent<Shadow>(); s.effectColor = new Color(0, 0, 0, a); s.effectDistance = new Vector2(0, -d); return t; }
        /// Left in English, right in Arabic.
        public static TextAnchor Lead(bool middle = true) => Loc.Ar ? (middle ? TextAnchor.MiddleRight : TextAnchor.UpperRight) : (middle ? TextAnchor.MiddleLeft : TextAnchor.UpperLeft);

        public class Btn { public RectTransform rt; public Image bg, shade; public Text label; public Button b; public Color color; public bool on = true, fireWhenOff; }
        public static Btn Button(Transform parent, string label, Color color, int size, Action onClick, string name = "btn")
        {
            var r = new Btn(); r.color = color; r.rt = Rect(parent, name);
            r.shade = Img(r.rt, Spr.Round, Color.Lerp(color, Color.black, 0.35f), "shade"); Place(r.shade.rectTransform, 0, 0, 1, 1, 0, -8, 0, -8);
            r.bg = Img(r.rt, Spr.Round, color, "bg", true, true); Fill(r.bg.rectTransform);
            if (Spr.ButtonFx != null) { var fx = Img(r.bg.transform, Spr.ButtonFx, Color.white, "fx", false); fx.type = Image.Type.Sliced; fx.pixelsPerUnitMultiplier = 1; Fill(fx.rectTransform); }
            else { var hi = Img(r.bg.transform, Spr.Round, new Color(1, 1, 1, 0.22f), "hi"); Place(hi.rectTransform, 0, 0.5f, 1, 1, 6, 0, -6, -6); }
            r.label = Shade(Txt(r.bg.transform, label, size, Color.white), 2, 0.35f); Place(r.label.rectTransform, 0, 0, 1, 1, 14, 6, -14, -6);
            r.b = r.bg.gameObject.AddComponent<Button>(); r.b.transition = Selectable.Transition.None;
            var rt = r.rt; r.b.onClick.AddListener(() => { if (!r.on) { Ui.I?.Deny(rt); if (r.fireWhenOff) onClick?.Invoke(); return; } Ui.I?.Punch(rt); onClick?.Invoke(); });
            return r;
        }
        public static void Enable(Btn b, bool on)
        {
            b.on = on; b.bg.color = on ? b.color : Grey; b.shade.color = Color.Lerp(on ? b.color : Grey, Color.black, 0.35f);
        }
    }
}
