// Everything drawn over the 3D store: top bar, task strip, offers, bottom menu, panels, pop-ups and effects.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;
using UnityEngine.UI;

namespace Souq
{
    public class Ui
    {
        public static Ui I;
        public Canvas canvas; public RectTransform root, hud, labels, fx, sheetLayer; Game g; Sim sim => g.sim; Save s => g.sim.s;
        Text coinTxt, rateTxt, gemTxt, taskTxt, taskProg, gradeTxt; Image taskBar; U.Btn taskBtn; public RectTransform coinPill, gemPill; RectTransform taskStrip, tutLayer;
        public RectTransform[] navRt = new RectTransform[5]; public RectTransform upRt, parkRt;
        readonly List<Tween> tweens = new List<Tween>(); double shownCoin = -1; float tick;
        class DeptLabel { public RectTransform rt; public Text name, sub; public Image bg, dot; }
        DeptLabel[] dl = new DeptLabel[T.ND];
        class Offer { public RectTransform rt; public Text timer; public Func<bool> show; public Func<string> text; }
        readonly List<Offer> offers = new List<Offer>();
        Image[] navDot = new Image[5]; RectTransform sheet; Action sheetRefresh; public int openDept = -1; public bool Busy => sheet != null || popup != null;
        RectTransform popup; Text toast; float toastT; Text fullWarn; int buyMode;

        public Ui(Game game) { g = game; I = this; }

        // ---------- build ----------
        public void Build(Camera cam, bool overlay)
        {
            Spr.Init(); U.PickFont();
            var go = new GameObject("Canvas", typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster)); go.layer = 5;
            canvas = go.GetComponent<Canvas>(); canvas.renderMode = overlay ? RenderMode.ScreenSpaceOverlay : RenderMode.ScreenSpaceCamera;
            if (!overlay) { canvas.worldCamera = cam; canvas.planeDistance = 1f; }
            var sc = go.GetComponent<CanvasScaler>(); sc.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize; sc.referenceResolution = new Vector2(1080, 2340); sc.matchWidthOrHeight = 0;
            root = (RectTransform)go.transform;
            if (overlay && Screen.height > 0) { var sa = Screen.safeArea; float k = 1080f / Mathf.Max(1, Screen.width); topInset = (Screen.height - sa.yMax) * k; botInset = sa.yMin * k; }
            labels = U.Fill(U.Rect(root, "labels")); hud = U.Fill(U.Rect(root, "hud")); sheetLayer = U.Fill(U.Rect(root, "sheets")); tutLayer = U.Fill(U.Rect(root, "tut")); fx = U.Fill(U.Rect(root, "fx"));
            BuildTop(); BuildOffers(); BuildNav(); BuildLabels();
            toast = U.Shade(U.Txt(fx, "", 54, Color.white)); U.Pin(toast.rectTransform, 0.5f, 0.5f, 0, 420, 960, 150); toast.gameObject.SetActive(false);
            fullWarn = U.Shade(U.Txt(hud, "", 36, new Color(1f, 0.85f, 0.4f))); U.Pin(fullWarn.rectTransform, 0.5f, 0, 0, 300, 900, 70); fullWarn.gameObject.SetActive(false);
            Refresh(true);
        }

        float topInset, botInset;
        void BuildTop()
        {
            float top = -(Mathf.Max(96, topInset + 14));
            var coin = U.Img(hud, Spr.Round, U.Navy, "coinPill"); coinPill = U.Pin(coin.rectTransform, 0, 1, 28, top, 500, 118);
            var ci = U.Img(coin.transform, Spr.Coin, Color.white, "icon", false); U.Pin(ci.rectTransform, 0, 0.5f, 12, 0, 96, 96);
            coinTxt = U.Txt(coin.transform, "0", 54, Color.white, TextAnchor.MiddleLeft); U.Place(coinTxt.rectTransform, 0, 0.36f, 1, 1, 122, 0, -16, -4);
            rateTxt = U.Txt(coin.transform, "", 28, new Color(0.62f, 0.95f, 0.70f), TextAnchor.MiddleLeft); U.Place(rateTxt.rectTransform, 0, 0, 1, 0.42f, 124, 6, -16, 0);
            var gem = U.Img(hud, Spr.Round, U.Navy, "gemPill", true, true); gemPill = U.Pin(gem.rectTransform, 0, 1, 548, top, 330, 118);
            var gi = U.Img(gem.transform, Spr.Gem, Color.white, "icon", false); U.Pin(gi.rectTransform, 0, 0.5f, 14, 0, 84, 84);
            gemTxt = U.Txt(gem.transform, "0", 48, Color.white, TextAnchor.MiddleLeft); U.Place(gemTxt.rectTransform, 0, 0, 1, 1, 110, 0, -78, 0);
            var plus = U.Button(gem.transform, "+", U.Green, 50, () => OpenShop(), "plus"); U.Pin(plus.rt, 1, 0.5f, -12, 4, 70, 70);
            var gear = U.Button(hud, "", new Color(0.30f, 0.34f, 0.50f), 40, () => OpenSettings(), "gear"); U.Pin(gear.rt, 1, 1, -28, top - 6, 150, 106);
            for (int i = 0; i < 3; i++) { var ln = U.Img(gear.bg.transform, Spr.Round, Color.white, "line"); U.Pin(ln.rectTransform, 0.5f, 0.5f, 0, (i - 1) * 24, 76, 12); ln.rectTransform.pivot = new Vector2(0.5f, 0.5f); }
            gradeTxt = U.Txt(gear.bg.transform, "", 10, Color.clear); U.Pin(gradeTxt.rectTransform, 0, 0, 0, 0, 2, 2);
            // task strip
            var ts = U.Img(hud, Spr.Round, new Color(1, 1, 1, 0.95f), "task", true, true); taskStrip = U.Pin(ts.rectTransform, 0.5f, 1, 0, top - 136, 1024, 110);
            taskBar = U.Img(ts.transform, Spr.Round, new Color(0.80f, 0.93f, 0.82f), "bar"); U.Place(taskBar.rectTransform, 0, 0, 0, 1, 6, 6, 6, -6);
            taskTxt = U.Txt(ts.transform, "", 34, U.Ink, U.Lead()); U.Place(taskTxt.rectTransform, 0, 0, 1, 1, 28, 4, -300, -4);
            taskProg = U.Txt(ts.transform, "", 30, new Color(0.35f, 0.40f, 0.55f), TextAnchor.MiddleRight); U.Place(taskProg.rectTransform, 1, 0, 1, 1, -290, 0, -24, 0);
            taskBtn = U.Button(ts.transform, Loc.G("claim"), U.Green, 34, () => ClaimTask(), "claim"); U.Pin(taskBtn.rt, 1, 0.5f, -12, 4, 250, 84);
        }

        void AddOffer(string key, Color c, Sprite icon, Func<bool> show, Func<string> text, Action tap)
        {
            var b = U.Button(hud, "", c, 30, tap, "offer_" + key); var o = new Offer { rt = b.rt, show = show, text = text };
            var glow = U.Img(b.rt, Spr.Glow, new Color(c.r, c.g, c.b, 0.55f), "glow", false); U.Pin(glow.rectTransform, 0.5f, 0.5f, 0, 0, 300, 300); glow.rectTransform.pivot = new Vector2(0.5f, 0.5f); glow.transform.SetAsFirstSibling();
            var ic = U.Img(b.bg.transform, icon, Color.white, "icon", false); U.Pin(ic.rectTransform, 0.5f, 1, 0, -14, 70, 70);
            var lb = U.Txt(b.bg.transform, Loc.G(key), 24, Color.white); U.Place(lb.rectTransform, 0, 0, 1, 0, 6, 34, -6, 76);
            o.timer = U.Txt(b.bg.transform, "", 24, new Color(1f, 0.95f, 0.6f)); U.Place(o.timer.rectTransform, 0, 0, 1, 0, 6, 6, -6, 40);
            offers.Add(o);
        }
        void BuildOffers()
        {
            AddOffer("adboost", new Color(0.98f, 0.55f, 0.15f), Spr.Megaphone ?? Spr.Coin, () => true, () => sim.AdActive ? "x2 " + Loc.Time(s.adEnd - g.Now()) : "x2", () => OfferPopup("adboost", "adboostd", () => { if (!sim.AdBoost()) Toast(Loc.G("max")); else { Flash(new Color(1f, 0.8f, 0.3f)); g.audio.Play("power"); } }));
            AddOffer("vip", U.Purple, Spr.Star, () => sim.vipHere, () => Loc.Num(sim.vipReward), () => VipPopup());
            AddOffer("bus", U.Blue, Spr.Bus ?? Spr.Person, () => sim.busOffer, () => "+10-49", () => OfferPopup("bus", "busd", () => { int n = sim.AcceptBus(); Toast("+" + n + " " + Loc.G("bus")); g.audio.Play("power"); }, () => sim.busOffer = false));
            AddOffer("qbuy", U.Green, Spr.Bolt ?? Spr.Person, () => sim.quickBuyOffer || sim.QuickBuy, () => sim.QuickBuy ? Loc.Time(s.quickBuyEnd - g.Now()) : "x2", () => { if (!sim.QuickBuy) OfferPopup("qbuy", "qbuyd", () => { sim.StartQuickBuy(); g.audio.Play("power"); }, () => sim.quickBuyOffer = false); });
            AddOffer("qcheck", U.Red, Spr.Register ?? Spr.Coin, () => sim.quickCheckOffer || sim.QuickCheck, () => sim.QuickCheck ? Loc.Time(s.quickCheckEnd - g.Now()) : "x2", () => { if (!sim.QuickCheck) OfferPopup("qcheck", "qcheckd", () => { sim.StartQuickCheck(); g.audio.Play("power"); }, () => sim.quickCheckOffer = false); });
        }

        void BuildNav()
        {
            var bar = U.Img(hud, Spr.Round, U.Navy, "nav", true, true); float nb = Mathf.Max(30, botInset * 0.6f + 14); U.Place(bar.rectTransform, 0, 0, 1, 0, 20, nb, -20, nb + 206);
            string[] keys = { "checkouts", "parking", "boostsNav", "gradeNav", "shop" }; Color[] cols = { U.Green, U.Blue, U.Purple, U.Gold, U.Red };
            Sprite[] ic = { Spr.Register ?? Spr.Coin, Spr.Parking, Spr.Bolt ?? Spr.Person, Spr.Crown ?? Spr.Star, Spr.Bag ?? Spr.Gem }; Action[] act = { () => OpenCheckouts(), () => OpenParking(), () => OpenBoosts(), () => OpenGrade(), () => OpenShop() };
            for (int i = 0; i < 5; i++)
            {
                var b = U.Button(bar.transform, "", cols[i], 30, act[i], "nav" + i); U.Place(b.rt, i / 5f, 0, (i + 1) / 5f, 1, 12, 20, -12, -14); navRt[i] = b.rt;
                if (ic[i] != null) { var im = U.Img(b.bg.transform, ic[i], Color.white, "icon", false); U.Pin(im.rectTransform, 0.5f, 1, 0, -14, 86, 86); }
                else { var p = U.Shade(U.Txt(b.bg.transform, "P", 76, Color.white)); U.Pin(p.rectTransform, 0.5f, 1, 0, -10, 100, 96); }
                var lb = U.Txt(b.bg.transform, Loc.G(keys[i]), 28, Color.white); U.Place(lb.rectTransform, 0, 0, 1, 0, 4, 8, -4, 60);
                navDot[i] = U.Img(b.rt, Spr.Circle, new Color(1f, 0.25f, 0.3f), "dot", false); U.Pin(navDot[i].rectTransform, 1, 1, 4, 8, 38, 38); navDot[i].gameObject.SetActive(false);
            }
        }

        void BuildLabels()
        {
            for (int d = 0; d < T.ND; d++)
            {
                var l = new DeptLabel(); l.bg = U.Img(labels, Spr.Round, U.Navy, "dl" + d); l.rt = l.bg.rectTransform; l.rt.anchorMin = l.rt.anchorMax = Vector2.zero; l.rt.pivot = new Vector2(0.5f, 0.5f); l.rt.sizeDelta = new Vector2(330, 96);
                l.name = U.Txt(l.rt, "", 30, Color.white); U.Place(l.name.rectTransform, 0, 0.45f, 1, 1, 12, 0, -12, -4);
                l.sub = U.Txt(l.rt, "", 28, new Color(1f, 0.88f, 0.45f)); U.Place(l.sub.rectTransform, 0, 0, 1, 0.5f, 12, 4, -12, 0);
                l.dot = U.Img(l.rt, Spr.Circle, U.Green, "dot", false); U.Pin(l.dot.rectTransform, 1, 1, 10, 10, 40, 40);
                dl[d] = l;
            }
        }

        // ---------- per frame ----------
        public Vector2 ToCanvas(Vector3 world)
        {
            var sp = g.cam.WorldToScreenPoint(world); var size = root.rect.size;      // bottom-left based, in canvas units
            return new Vector2(sp.x / Mathf.Max(1, g.cam.pixelWidth) * size.x, sp.y / Mathf.Max(1, g.cam.pixelHeight) * size.y);
        }
        public Vector2 CanvasPosOf(RectTransform rt) { Vector3 w = rt.TransformPoint(rt.rect.center); Vector2 lp = root.InverseTransformPoint(w); return lp + root.rect.size * 0.5f; }

        public void Update(float dt)
        {
            for (int i = tweens.Count - 1; i >= 0; i--)
            {
                var t = tweens[i]; if (t.delay > 0) { t.delay -= dt; continue; }
                t.t += dt; float k = t.dur <= 0 ? 1 : Mathf.Clamp01(t.t / t.dur); t.step?.Invoke(k);
                if (k >= 1) { tweens.RemoveAt(i); t.done?.Invoke(); }
            }
            if (comboT > 0) { comboT -= dt; if (comboTxt != null) { comboTxt.color = new Color(comboTxt.color.r, comboTxt.color.g, comboTxt.color.b, Mathf.Clamp01(comboT * 4)); if (comboT <= 0) comboTxt.gameObject.SetActive(false); } }
            if (toastT > 0) { toastT -= dt; if (toastT <= 0) toast.gameObject.SetActive(false); else toast.color = new Color(1, 1, 1, Mathf.Clamp01(toastT * 3)); }
            double coin = s.coin; if (shownCoin < 0) shownCoin = coin;
            shownCoin += (coin - shownCoin) * Math.Min(1.0, dt * 12); if (Math.Abs(coin - shownCoin) < Math.Max(0.5, coin * 1e-4)) shownCoin = coin;
            coinTxt.text = Loc.Num(shownCoin);
            tick -= dt; if (tick <= 0) { tick = 0.15f; Refresh(false); }
            // department chips follow their departments
            for (int d = 0; d < T.ND; d++) dl[d].rt.anchoredPosition = ToCanvas(World.DeptCenter(d) + new Vector3(0, 0.05f, -3.05f));
            float tm = Time.unscaledTime;
            foreach (var o in offers) if (o.rt.gameObject.activeSelf) o.rt.localScale = Vector3.one * (1 + 0.05f * Mathf.Sin(tm * 5f + o.rt.anchoredPosition.y));
        }

        void Refresh(bool first)
        {
            rateTxt.text = "+" + Loc.Num(sim.FlowPerMin) + Loc.Fix(Loc.Raw("permin")); gemTxt.text = Loc.Num(s.gem); gradeTxt.text = s.star.ToString();
            if (s.task < T.Tasks.Length)
            {
                var t = T.Tasks[s.task]; double v = Math.Min(sim.TaskValue(t), t.need); bool done = sim.TaskDone;
                taskTxt.text = TaskText(t); taskProg.text = done ? "" : Loc.Num(v) + "/" + Loc.Num(t.need);
                taskBar.rectTransform.anchorMax = new Vector2((float)(t.need > 0 ? v / t.need : 1), 1); taskBar.rectTransform.offsetMax = new Vector2(-6 * (float)(t.need > 0 ? v / t.need : 1), -6);
                taskBtn.rt.gameObject.SetActive(done); taskStrip.gameObject.SetActive(true);
            }
            else taskStrip.gameObject.SetActive(false);
            for (int d = 0; d < T.ND; d++)
            {
                var l = dl[d]; bool open = s.dOpen[d], can = d == 0 || s.dOpen[d - 1];
                l.rt.gameObject.SetActive(open || can);
                // an open section carries its name on its own board, so the chip only shows the level
                l.name.text = Loc.G(T.DeptKey[d]); l.name.gameObject.SetActive(!open); l.rt.sizeDelta = open ? new Vector2(210, 62) : new Vector2(330, 96);
                U.Place(l.sub.rectTransform, 0, 0, 1, open ? 1f : 0.5f, 12, 4, -12, open ? -4 : 0);
                l.sub.text = open ? Loc.Fix(Loc.Raw("level") + " " + s.dLevel[d]) : Loc.Fix(Loc.Raw("build") + " " + Loc.Num(T.Build[d]));
                bool afford = open ? (s.coin >= sim.LevelCost(d) && s.dLevel[d] < T.MaxLevel) : s.coin >= T.Build[d];
                l.dot.gameObject.SetActive(afford); l.bg.color = open ? U.Navy : (afford ? new Color(0.16f, 0.55f, 0.30f, 0.96f) : new Color(0.35f, 0.36f, 0.44f, 0.94f));
            }
            int row = 0;
            foreach (var o in offers)
            {
                bool on = o.show(); o.rt.gameObject.SetActive(on); if (!on) continue;
                U.Pin(o.rt, 1, 1, -24, -(Mathf.Max(96, topInset + 14) + 300) - row * 196, 170, 176); o.timer.text = o.text(); row++;
            }
            navDot[0].gameObject.SetActive(s.coin >= sim.CashHireCost() || AnyCashUp()); navDot[1].gameObject.SetActive(s.coin >= sim.ParkCost());
            navDot[2].gameObject.SetActive(AnyEpic()); navDot[3].gameObject.SetActive(s.coin >= sim.StarCost()); navDot[4].gameObject.SetActive(false);
            bool full = sim.MarketFull(); fullWarn.gameObject.SetActive(full && sheet == null); if (full) fullWarn.text = Loc.G("full");
            sheetRefresh?.Invoke();
        }
        bool AnyCashUp() { for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0 && s.cLevel[c] < T.CashLevelMax && s.coin >= sim.CashUpCost(c)) return true; return false; }
        bool AnyEpic() { for (int i = 0; i < T.Epics.Length; i++) if (sim.EpicAvailable(i) && s.gem >= sim.EpicCost(i)) return true; return false; }
        string TaskText(TaskDef t)
        {
            string dn = t.dept >= 0 ? Loc.Raw(T.DeptKey[t.dept]) : ""; string n = Loc.Num(t.need);
            switch (t.kind)
            {
                case TaskKind.DeptLevel: return Loc.F("t_lvl", dn, n);
                case TaskKind.DeptServed: return Loc.F("t_srv", dn, n);
                case TaskKind.Trucks: return Loc.F("t_truck", dn, n);
                case TaskKind.ParkLevel: return Loc.F("t_park", dn, n);
                case TaskKind.BuildDept: return Loc.F("t_build", dn, n);
                case TaskKind.Star: return Loc.F("t_star", dn, n);
                default: return Loc.F("t_assets", dn, n);
            }
        }
        void ClaimTask()
        {
            if (s.task >= T.Tasks.Length) return; var t = T.Tasks[s.task]; var from = CanvasPosOf(taskStrip);
            if (!sim.TaskClaim()) return;
            g.audio.Play("win"); Confetti(from, 26);
            if (t.gem > 0) FlyIcons(Spr.Gem, from, gemPill, Mathf.Min(10, 3 + t.gem / 10)); if (t.coin > 0) FlyIcons(Spr.Coin, from, coinPill, 8);
        }

        // ---------- effects ----------
        public Tween Run(float dur, Action<float> step, Action done = null, float delay = 0) { var t = new Tween { dur = dur, step = step, done = done, delay = delay }; tweens.Add(t); return t; }
        static float OutBack(float k) { float c = 1.9f; k -= 1; return 1 + k * k * ((c + 1) * k + c); }
        public void Punch(RectTransform rt) { if (rt == null) return; g.audio.Play("click"); Run(0.22f, k => { if (rt != null) rt.localScale = Vector3.one * (1 + 0.14f * Mathf.Sin(k * Mathf.PI)); }, () => { if (rt != null) rt.localScale = Vector3.one; }); }
        public void Deny(RectTransform rt) { if (rt == null) return; g.audio.Play("deny"); var p = rt.anchoredPosition; Run(0.25f, k => { if (rt != null) rt.anchoredPosition = p + new Vector2(Mathf.Sin(k * Mathf.PI * 5) * 10 * (1 - k), 0); }, () => { if (rt != null) rt.anchoredPosition = p; }); }
        public void Toast(string text) { toast.text = text; toast.gameObject.SetActive(true); toastT = 1.8f; var rt = toast.rectTransform; Run(0.3f, k => rt.localScale = Vector3.one * OutBack(k)); }
        public void Flash(Color c)
        {
            var im = U.Img(fx, Spr.Square, c, "flash", false); U.Fill(im.rectTransform);
            Run(0.5f, k => im.color = new Color(c.r, c.g, c.b, 0.55f * (1 - k)), () => Kit.Kill(im.gameObject));
        }
        public void Float(string text, Vector2 at, Color c, int size = 40)
        {
            var t = U.Shade(U.Txt(fx, text, size, c)); t.rectTransform.anchorMin = t.rectTransform.anchorMax = Vector2.zero; t.rectTransform.sizeDelta = new Vector2(420, 80); t.rectTransform.anchoredPosition = at;
            Run(0.9f, k => { t.rectTransform.anchoredPosition = at + new Vector2(0, 130 * (1 - (1 - k) * (1 - k))); t.color = new Color(c.r, c.g, c.b, k < 0.7f ? 1 : 1 - (k - 0.7f) / 0.3f); t.rectTransform.localScale = Vector3.one * (k < 0.15f ? OutBack(k / 0.15f) : 1); }, () => Kit.Kill(t.gameObject));
        }
        public void FlyIcons(Sprite sp, Vector2 from, RectTransform to, int n)
        {
            var dest = CanvasPosOf(to);
            for (int i = 0; i < n; i++)
            {
                var im = U.Img(fx, sp, Color.white, "fly", false); var rt = im.rectTransform; rt.anchorMin = rt.anchorMax = Vector2.zero; rt.sizeDelta = new Vector2(64, 64); rt.anchoredPosition = from; im.gameObject.SetActive(false);
                var mid = from + new Vector2(UnityEngine.Random.Range(-170f, 170f), UnityEngine.Random.Range(40f, 240f)); bool last = i == n - 1;
                Run(0.62f, k =>
                {
                    im.gameObject.SetActive(true); float e = k * k * (3 - 2 * k);
                    rt.anchoredPosition = (1 - e) * (1 - e) * from + 2 * (1 - e) * e * mid + e * e * dest; rt.localScale = Vector3.one * (0.6f + 0.6f * Mathf.Sin(k * Mathf.PI)); rt.localRotation = Quaternion.Euler(0, 0, k * 300);
                }, () => { Kit.Kill(im.gameObject); g.audio.Play("coin"); if (last && to != null) { to.localScale = Vector3.one; Run(0.2f, k => to.localScale = Vector3.one * (1 + 0.12f * Mathf.Sin(k * Mathf.PI))); } }, i * 0.045f);
            }
        }
        public void Confetti(Vector2 at, int n)
        {
            Color[] cs = { U.Gold, U.Red, U.Blue, U.Green, U.Purple, Color.white };
            for (int i = 0; i < n; i++)
            {
                var im = U.Img(fx, Spr.Square, cs[i % cs.Length], "conf", false); var rt = im.rectTransform; rt.anchorMin = rt.anchorMax = Vector2.zero; rt.sizeDelta = new Vector2(UnityEngine.Random.Range(14f, 26f), UnityEngine.Random.Range(22f, 38f));
                float ang = UnityEngine.Random.Range(20f, 160f) * Mathf.Deg2Rad, sp = UnityEngine.Random.Range(500f, 1200f), spin = UnityEngine.Random.Range(-700f, 700f); var v = new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * sp;
                Run(UnityEngine.Random.Range(0.9f, 1.4f), k => { float tt = k * 1.2f; rt.anchoredPosition = at + v * tt + new Vector2(0, -1500f * tt * tt); rt.localRotation = Quaternion.Euler(0, 0, spin * tt); im.color = new Color(im.color.r, im.color.g, im.color.b, k < 0.75f ? 1 : (1 - k) * 4); }, () => Kit.Kill(im.gameObject));
            }
        }
        public void Banner(string text, Color c)
        {
            var glow = U.Img(fx, Spr.Glow, new Color(c.r, c.g, c.b, 0.9f), "glow", false); U.Pin(glow.rectTransform, 0.5f, 0.5f, 0, 260, 1500, 620); glow.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            var t = U.Shade(U.Txt(fx, text, 110, Color.white), 6, 0.5f); U.Pin(t.rectTransform, 0.5f, 0.5f, 0, 260, 1000, 260); t.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            Run(1.5f, k =>
            {
                float sc = k < 0.25f ? OutBack(k / 0.25f) : 1 + 0.03f * Mathf.Sin(k * 20); float a = k < 0.8f ? 1 : 1 - (k - 0.8f) / 0.2f;
                t.rectTransform.localScale = Vector3.one * sc; t.color = new Color(1, 1, 1, a); glow.color = new Color(c.r, c.g, c.b, 0.9f * a); glow.rectTransform.localScale = Vector3.one * (0.6f + 0.6f * k);
            }, () => { Kit.Kill(t.gameObject); Kit.Kill(glow.gameObject); });
        }
        /// Coins burst from a point in the store and fly to the coin counter.
        public void CoinsFromWorld(Vector3 world, double amount, bool big)
        {
            if (!big && Busy) return;
            var at = ToCanvas(world); if (at.x < -100 || at.x > root.rect.width + 100 || at.y < -100 || at.y > root.rect.height + 100) return;
            Float("+" + Loc.Num(amount), at + new Vector2(0, 30), big ? U.Gold : new Color(1f, 0.95f, 0.75f), big ? 52 : 34);
            if (big) FlyIcons(Spr.Coin, at, coinPill, 5);
        }


        // ---------- feedback: every tap, sale and upgrade answers back ----------
        Image FxImg(Sprite sp, Color c, Vector2 at, float size, Transform layer = null)
        {
            var im = U.Img(layer ?? fx, sp, c, "fx", false); var rt = im.rectTransform; rt.anchorMin = rt.anchorMax = Vector2.zero; rt.pivot = new Vector2(0.5f, 0.5f); rt.sizeDelta = new Vector2(size, size); rt.anchoredPosition = at; return im;
        }
        bool OnScreen(Vector2 at) => at.x > -80 && at.x < root.rect.width + 80 && at.y > -80 && at.y < root.rect.height + 80;
        public void Ripple(Vector2 at)
        {
            var im = FxImg(Spr.Ring, Color.white, at, 60);
            Run(0.32f, k => { im.rectTransform.sizeDelta = Vector2.one * (60 + 190 * (1 - (1 - k) * (1 - k))); im.color = new Color(1, 1, 1, 0.75f * (1 - k)); }, () => Kit.Kill(im.gameObject));
        }
        public void Burst(Vector2 at, Color c, int n, float scale = 1f)
        {
            if (!OnScreen(at)) return;
            for (int i = 0; i < n; i++)
            {
                float ang = (i + UnityEngine.Random.value * 0.7f) / n * Mathf.PI * 2, dist = UnityEngine.Random.Range(90f, 190f) * scale, sz = UnityEngine.Random.Range(34f, 62f) * scale, spin = UnityEngine.Random.Range(-240f, 240f);
                var col = i % 3 == 0 ? Color.white : Color.Lerp(c, Color.white, 0.25f); var dir = new Vector2(Mathf.Cos(ang), Mathf.Sin(ang));
                var im = FxImg(Spr.Spark, col, at, sz);
                Run(UnityEngine.Random.Range(0.38f, 0.6f), k => { float e = 1 - (1 - k) * (1 - k); im.rectTransform.anchoredPosition = at + dir * dist * e + new Vector2(0, -70f * k * k); im.rectTransform.localScale = Vector3.one * (k < 0.2f ? k / 0.2f : 1 - (k - 0.2f) / 0.8f); im.rectTransform.localRotation = Quaternion.Euler(0, 0, spin * k); }, () => Kit.Kill(im.gameObject));
            }
        }
        /// A sold item hops from the staff to the shopper.
        public void ItemHop(Vector3 worldFrom, Vector3 worldTo, Color c)
        {
            if (Busy) return; Vector2 a = ToCanvas(worldFrom), b = ToCanvas(worldTo); if (!OnScreen(a)) return;
            var im = FxImg(Spr.Round, Color.Lerp(c, Color.white, 0.2f), a, 40); im.type = Image.Type.Simple;
            Run(0.3f, k => { im.rectTransform.anchoredPosition = Vector2.Lerp(a, b, k) + new Vector2(0, 90 * Mathf.Sin(k * Mathf.PI)); im.rectTransform.localRotation = Quaternion.Euler(0, 0, 200 * k); }, () => Kit.Kill(im.gameObject));
        }
        /// New stock jumps up over a department that was just upgraded.
        public void ItemPop(Vector3 world, int d, int combo)
        {
            var at = ToCanvas(world); if (!OnScreen(at)) return; int n = Mathf.Min(2 + combo / 4, 6); var col = World.DeptColor[d];
            for (int i = 0; i < n; i++)
            {
                float vx = UnityEngine.Random.Range(-260f, 260f), vy = UnityEngine.Random.Range(520f, 820f), spin = UnityEngine.Random.Range(-360f, 360f);
                var im = FxImg(Spr.Round, i % 2 == 0 ? Color.Lerp(col, Color.white, 0.15f) : new Color(1f, 0.97f, 0.9f), at, UnityEngine.Random.Range(34f, 52f)); im.type = Image.Type.Simple;
                Run(0.55f, k => { im.rectTransform.anchoredPosition = at + new Vector2(vx * k, vy * k - 1500f * k * k); im.rectTransform.localRotation = Quaternion.Euler(0, 0, spin * k); im.color = new Color(im.color.r, im.color.g, im.color.b, k < 0.8f ? 1 : (1 - k) * 5); }, () => Kit.Kill(im.gameObject));
            }
        }
        Text comboTxt; float comboT;
        public void Combo(int n, Color c)
        {
            if (comboTxt == null) { comboTxt = U.Shade(U.Txt(fx, "", 120, Color.white), 6, 0.5f); U.Pin(comboTxt.rectTransform, 0.5f, 1, 0, -520, 800, 170); comboTxt.rectTransform.pivot = new Vector2(0.5f, 0.5f); }
            comboTxt.gameObject.SetActive(true); comboTxt.text = "x" + n; comboTxt.color = Color.Lerp(Color.white, Color.Lerp(U.Gold, U.Red, Mathf.Clamp01(n / 40f)), Mathf.Clamp01(n / 8f)); comboT = 1.0f;
            var rt = comboTxt.rectTransform; float big = 1.25f + Mathf.Min(n, 40) * 0.012f; Run(0.16f, k => { if (rt != null) rt.localScale = Vector3.one * Mathf.Lerp(big, 1f, k); });
        }
        /// A coloured band sweeps across the screen for an opening or a bonus level.
        public void Ribbon(string title, string sub, Color c, bool small = false)
        {
            float h = small ? 250 : 330, w = root.rect.width; var holder = U.Rect(fx, "ribbon"); U.Place(holder, 0, 0.5f, 1, 0.5f, 0, 190, 0, 190 + h);
            var back = U.Img(holder, Spr.Square, Color.Lerp(c, Color.black, 0.35f), "back", false); U.Place(back.rectTransform, 0, 0, 1, 1, 0, -14, 0, 14);
            var band = U.Img(holder, Spr.Square, c, "band", false); U.Fill(band.rectTransform);
            var shine = U.Img(holder, Spr.Square, new Color(1, 1, 1, 0.22f), "shine", false); U.Place(shine.rectTransform, 0, 0.55f, 1, 1, 0, 0, 0, 0);
            var t1 = U.Shade(U.Txt(holder, title, small ? 110 : 96, Color.white), 6, 0.45f); U.Place(t1.rectTransform, 0, 0.36f, 1, 1, 40, 0, -40, -8);
            var t2 = U.Shade(U.Txt(holder, sub, 54, new Color(1f, 0.96f, 0.75f)), 4, 0.45f); U.Place(t2.rectTransform, 0, 0, 1, 0.42f, 40, 10, -40, 0);
            Run(1.7f, k =>
            {
                if (holder == null) return; float x = k < 0.14f ? -w * (1 - OutBack(k / 0.14f)) : k > 0.86f ? w * ((k - 0.86f) / 0.14f) * ((k - 0.86f) / 0.14f) : 0;
                holder.anchoredPosition = new Vector2(x, holder.anchoredPosition.y); float sc = k < 0.3f && k > 0.14f ? 1 + 0.12f * Mathf.Sin((k - 0.14f) / 0.16f * Mathf.PI) : 1; t1.rectTransform.localScale = Vector3.one * sc;
            }, () => Kit.Kill(holder.gameObject));
        }
        public bool ShutterOn;
        /// Roller shutters: closed at launch and opened, or closed and reopened around a change of store.
        public void Shutter(string title, string sub, Color c, Action mid, bool startClosed)
        {
            ShutterOn = true; var holder = U.Fill(U.Rect(fx, "shutter")); var hit = U.Img(holder, Spr.Square, new Color(0, 0, 0, 0), "hit", false, true); U.Fill(hit.rectTransform);
            float H = root.rect.height; var dark = Color.Lerp(c, Color.black, 0.3f);
            var top = U.Img(holder, Spr.Square, c, "top", false); U.Place(top.rectTransform, 0, 0.5f, 1, 1, 0, 0, 0, 0);
            var bot = U.Img(holder, Spr.Square, dark, "bot", false); U.Place(bot.rectTransform, 0, 0, 1, 0.5f, 0, 0, 0, 0);
            for (int i = 0; i < 9; i++) { var l1 = U.Img(top.transform, Spr.Square, new Color(0, 0, 0, 0.10f), "slat", false); U.Place(l1.rectTransform, 0, i / 9f, 1, i / 9f, 0, 0, 0, 10); var l2 = U.Img(bot.transform, Spr.Square, new Color(0, 0, 0, 0.14f), "slat", false); U.Place(l2.rectTransform, 0, i / 9f, 1, i / 9f, 0, 0, 0, 10); }
            var edge = U.Img(top.transform, Spr.Square, U.Gold, "edge", false); U.Place(edge.rectTransform, 0, 0, 1, 0, 0, 0, 0, 16);
            var t1 = U.Shade(U.Txt(top.transform, title, 130, Color.white), 7, 0.45f); U.Place(t1.rectTransform, 0, 0, 1, 0, 50, 110, -50, 330);
            var t2 = U.Shade(U.Txt(top.transform, sub, 62, new Color(1f, 0.93f, 0.6f)), 4, 0.45f); U.Place(t2.rectTransform, 0, 0, 1, 0, 50, 30, -50, 120);
            Action<float> set = open => { if (holder == null) return; top.rectTransform.anchoredPosition = new Vector2(0, H * 0.52f * open); bot.rectTransform.anchoredPosition = new Vector2(0, -H * 0.52f * open); };
            Action finish = () => { ShutterOn = false; if (holder != null) Kit.Kill(holder.gameObject); };
            if (startClosed) { set(0); Run(0.75f, k => set(k * k * (3 - 2 * k)), finish, 0.6f); }
            else
            {
                set(1); Run(0.32f, k => set(1 - k * k), () => { mid?.Invoke(); g.audio.Play("pop"); Run(0.6f, k => set(k * k * (3 - 2 * k)), finish, 0.8f); });
            }
        }

        // ---------- first-steps pointer ----------
        RectTransform tutRing, tutArrow, tutBubble; Text tutTxt; Vector2 tutAt; string tutKey;
        public bool PopupOpen => popup != null;
        public void TutPoint(Vector2 at, string key)
        {
            if (tutRing == null)
            {
                tutRing = FxImg(Spr.Ring, U.Gold, at, 200, tutLayer).rectTransform; tutArrow = FxImg(Spr.Arrow, U.Gold, at, 130, tutLayer).rectTransform;
                var bub = U.Img(tutLayer, Spr.Round, U.Navy, "bubble"); tutBubble = bub.rectTransform; tutBubble.anchorMin = tutBubble.anchorMax = Vector2.zero; tutBubble.pivot = new Vector2(0.5f, 0.5f); tutBubble.sizeDelta = new Vector2(880, 170);
                var line = U.Img(bub.transform, Spr.Round, U.Gold, "line"); U.Place(line.rectTransform, 0, 0, 1, 0, 30, 10, -30, 20);
                tutTxt = U.Txt(bub.transform, "", 44, Color.white); U.Place(tutTxt.rectTransform, 0, 0, 1, 1, 34, 22, -34, -12);
            }
            tutRing.gameObject.SetActive(true); tutArrow.gameObject.SetActive(true); tutBubble.gameObject.SetActive(true);
            if (tutKey != key) { tutKey = key; tutTxt.text = Loc.G(key); var b = tutBubble; Run(0.25f, k => { if (b != null) b.localScale = Vector3.one * OutBack(k); }); }
            tutAt = at; float tm = Time.unscaledTime; float W = root.rect.width, H = root.rect.height;
            tutRing.anchoredPosition = at; tutRing.sizeDelta = Vector2.one * (170 + 50 * Mathf.Abs(Mathf.Sin(tm * 4f)));
            tutArrow.anchoredPosition = at + new Vector2(0, 150 + 34 * Mathf.Abs(Mathf.Sin(tm * 5f)));
            float by = at.y > H * 0.5f ? at.y - 250 : at.y + 400; tutBubble.anchoredPosition = new Vector2(W / 2, Mathf.Clamp(by, 420, H - 420));
        }
        public void TutHide() { if (tutRing == null) return; tutRing.gameObject.SetActive(false); tutArrow.gameObject.SetActive(false); tutBubble.gameObject.SetActive(false); tutKey = null; }

        // ---------- sheets (bottom panels) ----------
        public void CloseSheet() { if (sheet != null) { Kit.Kill(sheet.gameObject); sheet = null; sheetRefresh = null; openDept = -1; upRt = null; parkRt = null; } }
        RectTransform OpenSheet(string title, Color band, float height)
        {
            CloseSheet(); g.audio.Play("open");
            var holder = U.Fill(U.Rect(sheetLayer, "sheet")); sheet = holder;
            var dim = U.Img(holder, Spr.Square, new Color(0, 0, 0, 0.35f), "dim", false, true); U.Fill(dim.rectTransform); dim.gameObject.AddComponent<Button>().onClick.AddListener(() => CloseSheet());
            var card = U.Img(holder, Spr.Round, U.Panel, "card", true, true); var crt = U.Place(card.rectTransform, 0, 0, 1, 0, 16, 30, -16, 30 + height);
            var head = U.Img(card.transform, Spr.Round, band, "head"); U.Place(head.rectTransform, 0, 1, 1, 1, 10, -128, -10, -10);
            var tt = U.Shade(U.Txt(head.transform, title, 52, Color.white)); U.Place(tt.rectTransform, 0, 0, 1, 1, 120, 0, -120, 0);
            var x = U.Button(head.transform, "X", U.Red, 44, () => CloseSheet(), "x"); U.Pin(x.rt, 1, 0.5f, -16, 4, 88, 84);
            var body = U.Place(U.Rect(card.transform, "body"), 0, 0, 1, 1, 26, 26, -26, -146);
            float y0 = -(height + 60); var basePos = crt.anchoredPosition; Run(0.28f, k => { if (crt != null) crt.anchoredPosition = basePos + new Vector2(0, y0 * (1 - OutBack(k))); });
            return body;
        }
        class Row { public RectTransform rt; public Text title, sub; public U.Btn btn; public Text cost; }
        Row AddRow(RectTransform parent, float y, float h, string title, Color btnColor, Action onClick, Sprite costIcon = null)
        {
            var r = new Row(); var bg = U.Img(parent, Spr.Round, U.Soft, "row"); r.rt = U.Place(bg.rectTransform, 0, 1, 1, 1, 0, y - h, 0, y);
            r.title = U.Txt(bg.transform, title, 36, U.Ink, U.Lead()); U.Place(r.title.rectTransform, 0, 0.5f, 1, 1, 24, 0, -330, -6);
            r.sub = U.Txt(bg.transform, "", 28, new Color(0.38f, 0.42f, 0.56f), U.Lead()); U.Place(r.sub.rectTransform, 0, 0, 1, 0.5f, 24, 8, -330, 0);
            r.btn = U.Button(bg.transform, "", btnColor, 30, onClick); U.Pin(r.btn.rt, 1, 0.5f, -14, 4, 300, h - 26);
            U.Place(r.btn.label.rectTransform, 0, 0.5f, 1, 1, 10, 0, -10, -4);
            var ic = U.Img(r.btn.bg.transform, costIcon ?? Spr.Coin, Color.white, "ci", false); U.Pin(ic.rectTransform, 0, 0, 22, 8, 44, 44);
            r.cost = U.Txt(r.btn.bg.transform, "", 32, Color.white, TextAnchor.MiddleLeft); U.Place(r.cost.rectTransform, 0, 0, 1, 0.5f, 74, 4, -10, 4);
            return r;
        }
        void SetRow(Row r, string sub, string label, double cost, bool can, bool maxed = false)
        {
            r.sub.text = sub; r.btn.label.text = maxed ? Loc.G("max") : label; r.cost.text = maxed ? "" : Loc.Num(cost); U.Enable(r.btn, can && !maxed); r.btn.fireWhenOff = !maxed;
        }
        void Bought(RectTransform at, bool big = false) { g.audio.Play(big ? "win" : "buy"); if (at != null) Confetti(CanvasPosOf(at), big ? 34 : 10); }

        public void OpenDept(int d)
        {
            if (!s.dOpen[d])
            {
                if (d > 0 && !s.dOpen[d - 1]) return;
                var b0 = OpenSheet(Loc.G(T.DeptKey[d]), World.DeptColor[d], 420); openDept = d;
                var r0 = AddRow(b0, -10, 170, Loc.G(T.DeptKey[d]), U.Green, () => { if (sim.BuildDept(d)) { g.OnBuilt(d); CloseSheet(); } else g.Stuck(T.Build[d]); });
                sheetRefresh = () => SetRow(r0, Loc.Fix(Loc.Raw("price") + " " + Loc.Num(T.BasePrice[d] * sim.ProfitMult)), Loc.G("build"), T.Build[d], s.coin >= T.Build[d]);
                sheetRefresh(); return;
            }
            var body = OpenSheet(Loc.G(T.DeptKey[d]), World.DeptColor[d], 1090); openDept = d;
            var info = U.Txt(body, "", 34, U.Ink); U.Place(info.rectTransform, 0, 1, 1, 1, 0, -150, 0, -4);
            var barBg = U.Img(body, Spr.Round, U.Soft, "tierBg"); U.Place(barBg.rectTransform, 0, 1, 1, 1, 0, -216, 0, -160);
            var bar = U.Img(barBg.transform, Spr.Round, World.DeptColor[d], "tier"); U.Place(bar.rectTransform, 0, 0, 0.5f, 1, 4, 4, -4, -4);
            var barTxt = U.Txt(barBg.transform, "", 28, U.Ink); U.Fill(barTxt.rectTransform);
            // buy amount: 1, 10 or as many as the coins allow
            string[] mk = { "x1", "x10", "xmax" }; var modeBtns = new U.Btn[3];
            for (int i = 0; i < 3; i++) { int m = i; modeBtns[i] = U.Button(body, Loc.G(mk[i]), U.Blue, 30, () => { buyMode = m; }, "mode" + i); U.Pin(modeBtns[i].rt, 1, 1, -(2 - i) * 150, -232, 140, 70); }
            Row up = null, hire = null, train = null;
            Func<bool, bool> doUp = held =>
            {
                int n = buyMode == 0 ? 1 : buyMode == 1 ? 10 : 100000, done = 0; int tier0 = T.Tier(s.dLevel[d]);
                while (done < n && sim.LevelUp(d)) done++;
                if (done == 0) { if (!held) g.Stuck(sim.LevelCost(d)); return false; }
                g.OnLevel(d, tier0, done); Burst(CanvasPosOf(up.btn.rt), U.Green, 5, 0.8f);
                if (held) { var rt = up.btn.rt; Run(0.1f, k => { if (rt != null) rt.localScale = Vector3.one * (1 + 0.08f * Mathf.Sin(k * Mathf.PI)); }); }
                return true;
            };
            up = AddRow(body, -322, 170, Loc.G("upgrade"), U.Green, () => doUp(false));
            upRt = up.btn.rt; var hold = up.btn.bg.gameObject.AddComponent<HoldRepeat>(); hold.onRepeat = () => doUp(true);
            hire = AddRow(body, -506, 170, Loc.G("staff"), U.Blue, () => { if (sim.Hire(d)) { Bought(hire.btn.rt, true); g.OnHire(d); } else g.Stuck(sim.HireCost(d)); });
            train = AddRow(body, -690, 170, Loc.G("speed"), U.Purple, () => { if (sim.ProdUp(d)) Bought(train.btn.rt); else g.Stuck(sim.ProdCost(d)); });
            sheetRefresh = () =>
            {
                int lv = s.dLevel[d]; int tier = T.Tier(lv); int lo = tier == 0 ? 1 : T.TierLv[tier - 1]; bool top = tier >= T.TierLv.Length; int hi = top ? T.MaxLevel : T.TierLv[tier];
                info.text = Loc.Fix(Loc.Raw("level") + " " + lv) + "\n" + Loc.Fix(Loc.Raw("price") + " " + Loc.Num(sim.Price(d))) + "   " + Loc.Fix(Loc.Num(sim.DeptSpeed(d)) + Loc.Raw("permin"));
                bar.rectTransform.anchorMax = new Vector2(Mathf.Clamp01((lv - lo) / (float)Mathf.Max(1, hi - lo)), 1);
                barTxt.text = top ? Loc.G("max") : Loc.Fix(Loc.Raw("next") + " " + hi + "  x" + T.TierMul[tier]);
                for (int i = 0; i < 3; i++) U.Enable(modeBtns[i], true); modeBtns[buyMode].bg.color = U.Gold;
                double cost = sim.LevelCost(d); if (buyMode == 1) { double c = 0; for (int i = 0; i < 10; i++) c += Math.Floor(Math.Pow(T.UpRate[d], lv - 1 + i) * T.UpBase[d] * 100) / 100; cost = c * (sim.LevelCost(d) / Math.Max(1e-9, Math.Floor(Math.Pow(T.UpRate[d], lv - 1) * T.UpBase[d] * 100) / 100)); }
                SetRow(up, Loc.Fix(Loc.Raw("price") + " " + Loc.Num(sim.Price(d))), Loc.G("upgrade"), buyMode == 2 ? sim.LevelCost(d) : cost, s.coin >= sim.LevelCost(d), lv >= T.MaxLevel);
                SetRow(hire, s.dStaff[d] + " / " + T.MaxStaff, Loc.G("hire"), sim.HireCost(d), s.coin >= sim.HireCost(d), s.dStaff[d] >= T.MaxStaff);
                SetRow(train, Loc.Fix(Loc.Num(sim.StaffSpeed(d)) + Loc.Raw("permin")), Loc.G("train"), sim.ProdCost(d), s.coin >= sim.ProdCost(d), s.dSpeed[d] >= T.ProdMax);
            };
            sheetRefresh();
        }

        public void OpenCheckouts()
        {
            var body = OpenSheet(Loc.G("checkouts"), U.Green, 1240); var rows = new Row[T.NC];
            for (int c = 0; c < T.NC; c++)
            {
                int k = c; rows[c] = AddRow(body, -6 - c * 132, 122, Loc.Fix(Loc.Raw("checkout") + " " + (c + 1)), U.Green, () =>
                {
                    bool ok = s.cLevel[k] > 0 ? sim.CashUp(k) : (k == sim.CashOpen && sim.CashHire());
                    if (ok) Bought(rows[k].btn.rt, s.cLevel[k] == 1); else g.Stuck(s.cLevel[k] > 0 ? sim.CashUpCost(k) : sim.CashHireCost());
                });
            }
            sheetRefresh = () =>
            {
                int open = sim.CashOpen;
                for (int c = 0; c < T.NC; c++)
                {
                    if (s.cLevel[c] > 0) SetRow(rows[c], Loc.Fix(Loc.Raw("level") + " " + s.cLevel[c] + "   " + Loc.Num(sim.CashSpeed(c)) + Loc.Raw("permin")), Loc.G("upgrade"), sim.CashUpCost(c), s.coin >= sim.CashUpCost(c), s.cLevel[c] >= T.CashLevelMax);
                    else { SetRow(rows[c], "", Loc.G("open"), c == open ? sim.CashHireCost() : T.CashHire[c], c == open && s.coin >= sim.CashHireCost()); rows[c].rt.gameObject.SetActive(c <= open); }
                }
            };
            sheetRefresh();
        }

        public void OpenParking()
        {
            var body = OpenSheet(Loc.G("parking"), U.Blue, 560); Row a = null, b = null;
            a = AddRow(body, -10, 170, Loc.G("spaces"), U.Blue, () => { if (sim.ParkUp()) { Bought(a.btn.rt, true); g.world.shake = 0.4f; g.Glide(new Vector3(0, 0, g.MinZ + 6), g.zoom, 0.6f); } else g.Stuck(sim.ParkCost()); });
            parkRt = a.btn.rt;
            b = AddRow(body, -194, 170, Loc.G("marketing"), U.Gold, () => { if (sim.AdLevelUp()) Bought(b.btn.rt); else g.Stuck(sim.AdLevelCost()); });
            sheetRefresh = () =>
            {
                SetRow(a, Loc.Fix(sim.ParkSpaces + "   " + Loc.Raw("level") + " " + s.parkLevel), Loc.G("expand"), sim.ParkCost(), s.coin >= sim.ParkCost(), s.parkLevel >= T.ParkMax);
                SetRow(b, Loc.Fix(Loc.Raw("carsmin") + " " + sim.Arrivals.ToString("0.#")), Loc.G("promote"), sim.AdLevelCost(), s.coin >= sim.AdLevelCost(), s.adLevel >= T.AdLevelMax);
            };
            sheetRefresh();
        }

        RectTransform Scroll(RectTransform body, float contentH)
        {
            var view = U.Fill(U.Rect(body, "view")); view.gameObject.AddComponent<RectMask2D>(); var hit = view.gameObject.AddComponent<Image>(); hit.color = new Color(0, 0, 0, 0); hit.raycastTarget = true;
            var content = U.Rect(view, "content"); content.anchorMin = new Vector2(0, 1); content.anchorMax = new Vector2(1, 1); content.pivot = new Vector2(0.5f, 1); content.sizeDelta = new Vector2(0, contentH); content.anchoredPosition = Vector2.zero;
            var sr = body.gameObject.AddComponent<ScrollRect>(); sr.viewport = view; sr.content = content; sr.horizontal = false; sr.vertical = true; sr.movementType = ScrollRect.MovementType.Clamped; sr.scrollSensitivity = 40;
            return content;
        }
        string EpicName(EpicDef e)
        {
            switch (e.kind)
            {
                case EpicKind.Profit: return Loc.G("e_profit"); case EpicKind.Walk: return Loc.G("e_walk"); case EpicKind.Truck: return Loc.G("e_truck");
                case EpicKind.CashierSpeed: return Loc.G("e_cash"); case EpicKind.StaffCost: return Loc.G("e_staff"); case EpicKind.CashierCost: return Loc.G("e_ccost"); case EpicKind.AdTime: return Loc.G("e_ad");
                case EpicKind.Manager: return Loc.Fix(Loc.Raw(T.DeptKey[e.dept]) + " - " + Loc.Raw("manager"));
                default: return Loc.Fix(Loc.Raw(T.DeptKey[e.dept]) + " - " + Loc.Raw("research"));
            }
        }
        string EpicDesc(EpicDef e)
        {
            switch (e.kind)
            {
                case EpicKind.Profit: return Loc.G("e_profitd"); case EpicKind.Walk: return Loc.G("e_walkd"); case EpicKind.Truck: return Loc.G("e_truckd");
                case EpicKind.CashierSpeed: return Loc.G("e_cashd"); case EpicKind.StaffCost: return Loc.G("e_staffd"); case EpicKind.CashierCost: return Loc.G("e_ccostd"); case EpicKind.AdTime: return Loc.G("e_add");
                case EpicKind.Manager: return Loc.G("e_mgrd"); default: return Loc.G("e_resd");
            }
        }
        public void OpenBoosts()
        {
            var body = OpenSheet(Loc.G("boosts"), U.Purple, 1500); int n = T.Epics.Length; var content = Scroll(body, n * 132 + 10); var rows = new Row[n];
            for (int i = 0; i < n; i++)
            {
                int k = i; rows[i] = AddRow(content, -6 - i * 132, 122, EpicName(T.Epics[i]), U.Purple, () => { if (sim.EpicUp(k)) { Bought(rows[k].btn.rt, true); g.world.SyncStatic(); } else if (sim.EpicAvailable(k)) NeedGems(); }, Spr.Gem);
            }
            sheetRefresh = () =>
            {
                for (int i = 0; i < n; i++) { var e = T.Epics[i]; bool lockd = e.dept >= 0 && !s.dOpen[e.dept]; SetRow(rows[i], EpicDesc(e) + "  " + s.epic[i] + "/" + e.max, Loc.G("buy"), sim.EpicCost(i), !lockd && s.gem >= sim.EpicCost(i), s.epic[i] >= e.max); if (lockd) U.Enable(rows[i].btn, false); }
            };
            sheetRefresh();
        }

        public void OpenGrade()
        {
            var body = OpenSheet(Loc.G("grade"), new Color(0.95f, 0.65f, 0.10f), 620);
            var info = U.Txt(body, "", 40, U.Ink); U.Place(info.rectTransform, 0, 1, 1, 1, 0, -220, 0, -6);
            Row r = null; r = AddRow(body, -240, 170, Loc.G("newstore"), U.Gold, () =>
            {
                if (sim.StarUp()) { CloseSheet(); g.OnStar(); } else g.Stuck(sim.StarCost());
            });
            sheetRefresh = () =>
            {
                bool top = s.star + 1 >= T.StarCost.Length;
                info.text = Loc.Fix(Loc.Raw("grade") + " " + s.star) + "\n" + Loc.Fix(Loc.Raw("profit") + " x" + Loc.Num(T.StarProfit[s.star])) + (top ? "" : "\n" + Loc.Fix(Loc.Raw("grade") + " " + (s.star + 1) + "  " + Loc.Raw("profit") + " x" + Loc.Num(T.StarProfit[s.star + 1])));
                SetRow(r, top ? "" : Loc.Fix(Loc.Raw("profit") + " x" + Loc.Num(T.StarProfit[s.star + 1])), Loc.G("move"), sim.StarCost(), s.coin >= sim.StarCost(), top);
            };
            sheetRefresh();
        }

        public void OpenShop()
        {
            var body = OpenSheet(Loc.G("shop"), U.Red, 1700); var list = g.store.Products; int warps = Store.WarpHours.Length;
            var content = Scroll(body, list.Count * 180 + warps * 162 + 140);
            var note = U.Txt(content, Loc.G("test"), 28, U.Red); U.Place(note.rectTransform, 0, 1, 1, 1, 0, -90, 0, -4);
            var rows = new List<Row>(); float y = -120;
            foreach (var p in list)
            {
                var pp = p; Row r = null; r = AddRow(content, y, 150, Loc.G(pp.key), pp.gems > 0 ? U.Green : U.Red, () => g.store.Buy(pp, ok => { if (ok) { Bought(r.btn.rt, true); Flash(U.Gold); if (pp.gems > 0) FlyIcons(Spr.Gem, CanvasPosOf(r.btn.rt), gemPill, 10); } }), Spr.Gem);
                r.btn.bg.transform.Find("ci").gameObject.SetActive(false); U.Place(r.cost.rectTransform, 0, 0, 1, 0.5f, 10, 4, -10, 4); r.cost.alignment = TextAnchor.MiddleCenter;
                if (pp.gems > 0) { var gi = U.Img(r.rt, Spr.Gem, Color.white, "gem", false); U.Pin(gi.rectTransform, Loc.Ar ? 1 : 0, 0.5f, Loc.Ar ? -340 : 20, 0, 84, 84); U.Place(r.title.rectTransform, 0, 0.5f, 1, 1, Loc.Ar ? 24 : 120, 0, Loc.Ar ? -440 : -330, -6); U.Place(r.sub.rectTransform, 0, 0, 1, 0.5f, Loc.Ar ? 24 : 120, 8, Loc.Ar ? -440 : -330, 0); r.title.text = Loc.Num(pp.gems) + " " + Loc.G("gems"); }
                if (pp.tag != null) { var tg = U.Img(r.rt, Spr.Round, U.Gold, "tag"); U.Pin(tg.rectTransform, 0, 1, 12, 26, 250, 44); var tt = U.Txt(tg.transform, Loc.G(pp.tag), 24, U.Ink); U.Fill(tt.rectTransform); }
                rows.Add(r); y -= 180;
            }
            var warpRows = new Row[warps];
            for (int i = 0; i < warps; i++)
            {
                int k = i; warpRows[i] = AddRow(content, y, 150, Loc.Fix(Loc.Raw("warp") + " " + Store.WarpHours[i] + Loc.Raw("hours")), U.Purple, () => { if (!g.Warp(k)) NeedGems(); else Bought(warpRows[k].btn.rt, true); }, Spr.Gem); y -= 162;
            }
            sheetRefresh = () =>
            {
                for (int i = 0; i < list.Count; i++) { var p = list[i]; bool own = p.owned != null && p.owned(s); rows[i].sub.text = p.desc != null ? Loc.G(p.desc) : ""; rows[i].btn.label.text = own ? Loc.G("owned") : Loc.G("buy"); rows[i].cost.text = own ? "" : p.price; U.Enable(rows[i].btn, !own); }
                for (int i = 0; i < warps; i++) SetRow(warpRows[i], "+" + Loc.Num(sim.IdleIncome(Store.WarpHours[i] * 3600)), Loc.G("buy"), Store.WarpGems[i], s.gem >= Store.WarpGems[i]);
            };
            sheetRefresh();
        }
        void NeedGems() { Toast(Loc.G("needgems")); g.audio.Play("deny"); OpenShop(); }

        public void OpenSettings()
        {
            var body = OpenSheet(Loc.G("settings"), new Color(0.30f, 0.34f, 0.50f), 980); Row a = null, b = null, c = null;
            a = AddRow(body, -10, 140, Loc.G("sound"), U.Blue, () => { s.sfx = !s.sfx; }); b = AddRow(body, -160, 140, Loc.G("music"), U.Blue, () => { s.music = !s.music; g.audio.SetMusic(s.music); });
            c = AddRow(body, -310, 140, Loc.G("lang"), U.Purple, () => LangPopup());
            foreach (var r in new[] { a, b, c }) { r.btn.bg.transform.Find("ci").gameObject.SetActive(false); U.Place(r.btn.label.rectTransform, 0, 0, 1, 1, 10, 4, -10, -4); }
            var stats = U.Txt(body, "", 32, U.Ink, U.Lead(false)); U.Place(stats.rectTransform, 0, 0, 1, 1, 10, 10, -10, -480);
            sheetRefresh = () =>
            {
                a.btn.label.text = Loc.G(s.sfx ? "on" : "off"); b.btn.label.text = Loc.G(s.music ? "on" : "off"); c.btn.label.text = Loc.Lang == 1 ? Loc.Shape(Loc.Names[1]) : Loc.Names[Loc.Lang];
                int served = 0; foreach (int v in s.served) served += v;
                stats.text = Loc.Fix(Loc.Raw("total") + ": " + Loc.Num(s.assets)) + "\n" + Loc.Fix(Loc.Raw("income") + ": " + Loc.Num(sim.FlowPerMin) + Loc.Raw("permin")) + "\n" + Loc.Fix(Loc.Raw("served") + ": " + Loc.Num(served)) + "\n" + Loc.Fix(Loc.Raw("shoppers") + ": " + sim.custs.Count) + "\n\n" + Loc.G("test");
            };
            sheetRefresh();
        }

        // ---------- pop-ups ----------
        public void ClosePopup() { if (popup != null) { Kit.Kill(popup.gameObject); popup = null; } }
        RectTransform OpenPopup(string title, Color band, float h, out RectTransform cardRt)
        {
            ClosePopup(); g.audio.Play("open");
            popup = U.Fill(U.Rect(fx, "popup")); popup.SetAsFirstSibling();
            var dim = U.Img(popup, Spr.Square, new Color(0.03f, 0.04f, 0.12f, 0.62f), "dim", false, true); U.Fill(dim.rectTransform);
            var glow = U.Img(popup, Spr.Glow, new Color(band.r, band.g, band.b, 0.7f), "glow", false); U.Pin(glow.rectTransform, 0.5f, 0.5f, 0, 60, 1500, 1500); glow.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            var card = U.Img(popup, Spr.Round, U.Panel, "card", true, true); cardRt = U.Pin(card.rectTransform, 0.5f, 0.5f, 0, 60, 900, h); cardRt.pivot = new Vector2(0.5f, 0.5f);
            var head = U.Img(card.transform, Spr.Round, band, "head"); U.Place(head.rectTransform, 0, 1, 1, 1, 10, -150, -10, -10);
            var tt = U.Shade(U.Txt(head.transform, title, 58, Color.white)); U.Fill(tt.rectTransform);
            var crt = cardRt; Run(0.3f, k => { if (crt != null) crt.localScale = Vector3.one * OutBack(k); });
            return U.Place(U.Rect(card.transform, "body"), 0, 0, 1, 1, 40, 40, -40, -170);
        }
        string AdLabel(string key) => s.noAds ? Loc.G("go") : Loc.G(key);

        public void OfferPopup(string title, string desc, Action onYes, Action onNo = null)
        {
            RectTransform card; var body = OpenPopup(Loc.G(title), U.Blue, 620, out card);
            var d = U.Txt(body, Loc.G(desc), 40, U.Ink); U.Place(d.rectTransform, 0, 0.5f, 1, 1, 0, 0, 0, 0);
            var yes = U.Button(body, AdLabel("watch"), U.Green, 44, () => g.Ad(() => { ClosePopup(); onYes(); })); U.Place(yes.rt, 0.08f, 0, 0.92f, 0, 0, 100, 0, 220);
            var no = U.Txt(body, Loc.G("nothanks"), 32, new Color(0.45f, 0.48f, 0.60f)); U.Place(no.rectTransform, 0, 0, 1, 0, 0, 0, 0, 80); no.raycastTarget = true; no.gameObject.AddComponent<Button>().onClick.AddListener(() => { ClosePopup(); onNo?.Invoke(); });
        }
        /// All eight languages at once, each written in its own script.
        public void LangPopup()
        {
            RectTransform card; var body = OpenPopup(Loc.G("lang"), U.Purple, 1000, out card); Font cjk = null;
            try { cjk = Font.CreateDynamicFontFromOSFont(new[] { "PingFang TC", "Hiragino Sans", "Apple SD Gothic Neo", "Noto Sans CJK TC", "Noto Sans CJK JP", "Noto Sans CJK KR" }, 40); } catch { cjk = null; }
            for (int i = 0; i < Loc.Codes.Length; i++)
            {
                int k = i; bool now = i == Loc.Lang; string name = i == 1 ? Loc.Shape(Loc.Names[1]) : Loc.Names[i];
                var b = U.Button(body, name, now ? U.Gold : U.Blue, 46, () => { ClosePopup(); CloseSheet(); if (k != Loc.Lang) g.SetLang(Loc.Codes[k]); }, "lang" + i);
                U.Place(b.rt, (i % 2) * 0.5f, 1, (i % 2) * 0.5f + 0.5f, 1, 12, -(i / 2 + 1) * 178 + 12, -12, -(i / 2) * 178 - 8);
                if ((i == 2 || i == 3 || i == 7) && cjk != null) b.label.font = cjk;
            }
            var no = U.Txt(body, Loc.G("close"), 34, new Color(0.45f, 0.48f, 0.60f)); U.Place(no.rectTransform, 0, 0, 1, 0, 0, 0, 0, 80); no.raycastTarget = true; no.gameObject.AddComponent<Button>().onClick.AddListener(() => ClosePopup());
        }

        public void VipPopup()
        {
            RectTransform card; var body = OpenPopup(Loc.G("vip"), U.Purple, 700, out card);
            var d = U.Txt(body, Loc.G("vipd"), 38, U.Ink); U.Place(d.rectTransform, 0, 0.72f, 1, 1, 0, 0, 0, 0);
            var ic = U.Img(body, Spr.Coin, Color.white, "coin", false); U.Pin(ic.rectTransform, 0.5f, 0.5f, -230, 30, 110, 110); ic.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            var amt = U.Txt(body, Loc.Num(sim.vipReward), 84, new Color(0.95f, 0.62f, 0.05f), TextAnchor.MiddleLeft); U.Pin(amt.rectTransform, 0.5f, 0.5f, -150, 30, 520, 130); amt.rectTransform.pivot = new Vector2(0, 0.5f);
            var yes = U.Button(body, AdLabel("watch"), U.Green, 44, () => g.Ad(() => { var at = CanvasPosOf(card); ClosePopup(); double r = sim.CollectVip(); FlyIcons(Spr.Coin, at, coinPill, 14); Float("+" + Loc.Num(r), at, U.Gold, 70); Flash(U.Gold); g.audio.Play("win"); })); U.Place(yes.rt, 0.08f, 0, 0.92f, 0, 0, 100, 0, 220);
            var no = U.Txt(body, Loc.G("nothanks"), 32, new Color(0.45f, 0.48f, 0.60f)); U.Place(no.rectTransform, 0, 0, 1, 0, 0, 0, 0, 80); no.raycastTarget = true; no.gameObject.AddComponent<Button>().onClick.AddListener(() => { ClosePopup(); sim.DismissVip(); });
        }
        public void OfflinePopup(double reward, double away, bool capped)
        {
            RectTransform card; var body = OpenPopup(Loc.G("welcome"), new Color(0.95f, 0.65f, 0.10f), capped && !s.offlinePro ? 1120 : 800, out card);
            var d = U.Txt(body, Loc.G("away") + "\n" + Loc.Time(away), 36, U.Ink); U.Place(d.rectTransform, 0, 1, 1, 1, 0, -150, 0, 0);
            var ic = U.Img(body, Spr.Coin, Color.white, "coin", false); U.Pin(ic.rectTransform, 0.5f, 1, -250, -170, 110, 110);
            var amt = U.Txt(body, Loc.Num(reward), 88, new Color(0.95f, 0.62f, 0.05f), TextAnchor.MiddleLeft); U.Pin(amt.rectTransform, 0.5f, 1, -120, -160, 540, 130); amt.rectTransform.pivot = new Vector2(0, 1);
            Action<double> pay = m => { var at = CanvasPosOf(card); ClosePopup(); g.pendingOffline = 0; sim.Earn(reward * m); FlyIcons(Spr.Coin, at, coinPill, 16); Float("+" + Loc.Num(reward * m), at, U.Gold, 70); g.audio.Play("win"); if (m > 1) Flash(U.Gold); };
            var x3 = U.Button(body, s.noAds ? Loc.G("free3") : Loc.G("collect3"), U.Green, 44, () => g.Ad(() => pay(3))); U.Pin(x3.rt, 0.5f, 1, 0, -330, 760, 130); x3.rt.pivot = new Vector2(0.5f, 1);
            var x1 = U.Button(body, Loc.G("collect"), U.Blue, 40, () => pay(1)); U.Pin(x1.rt, 0.5f, 1, 0, -486, 520, 104); x1.rt.pivot = new Vector2(0.5f, 1);
            if (capped && !s.offlinePro)
            {
                // the shopper lost income past the cap: the moment the longer cap is worth most to them
                var note = U.Txt(body, Loc.Fix(Loc.Raw("capped") + " " + (int)(T.OfflineCap / 3600) + Loc.Raw("hours")) + "\n" + Loc.G("offprod"), 30, U.Red); U.Pin(note.rectTransform, 0.5f, 0, 0, 140, 800, 100); note.rectTransform.pivot = new Vector2(0.5f, 0);
                var p = g.store.Find("offpro"); var bb = U.Button(body, Loc.G("offpro") + "  " + p.price, U.Red, 36, () => g.store.Buy(p, ok => { if (ok) Toast(Loc.G("owned")); })); U.Pin(bb.rt, 0.5f, 0, 0, 16, 700, 110); bb.rt.pivot = new Vector2(0.5f, 0);
            }
        }
        /// Shown when the player taps something they cannot afford and the wait is long.
        public void StuckPopup(double waitSecs, int warpIndex)
        {
            RectTransform card; var body = OpenPopup(Loc.G("stuck"), U.Purple, 720, out card);
            var d = U.Txt(body, Loc.Time(waitSecs) + "\n" + Loc.G("warpd"), 38, U.Ink); U.Place(d.rectTransform, 0, 0.62f, 1, 1, 0, 0, 0, 0);
            var amt = U.Txt(body, "+" + Loc.Num(sim.IdleIncome(Store.WarpHours[warpIndex] * 3600)), 76, new Color(0.95f, 0.62f, 0.05f)); U.Place(amt.rectTransform, 0, 0.40f, 1, 0.62f, 0, 0, 0, 0);
            var yes = U.Button(body, Loc.Fix(Loc.Raw("warp") + " " + Store.WarpHours[warpIndex] + Loc.Raw("hours")) + "   " + Store.WarpGems[warpIndex], U.Purple, 40, () => { ClosePopup(); if (!g.Warp(warpIndex)) NeedGems(); }); U.Place(yes.rt, 0.08f, 0, 0.92f, 0, 0, 100, 0, 220);
            var gi = U.Img(yes.bg.transform, Spr.Gem, Color.white, "gem", false); U.Pin(gi.rectTransform, 1, 0.5f, -24, 0, 64, 64);
            var no = U.Txt(body, Loc.G("nothanks"), 32, new Color(0.45f, 0.48f, 0.60f)); U.Place(no.rectTransform, 0, 0, 1, 0, 0, 0, 0, 80); no.raycastTarget = true; no.gameObject.AddComponent<Button>().onClick.AddListener(() => ClosePopup());
        }
    }
}
