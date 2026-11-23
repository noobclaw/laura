// Ties the rule core, the 3D store, the interface, sound and the shop together.
// A plain class: the app drives it on a device, the cloud build drives it for screenshots.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Souq
{
    public class Product { public string id, key, desc, price, tag; public int gems; public Func<Save, bool> owned; }

    /// Shop catalogue. This build has no payment connection: Buy() grants at once and the shop says so on screen.
    public class Store
    {
        public static readonly int[] WarpHours = { 1, 4, 24 }; public static readonly int[] WarpGems = { 40, 120, 500 };
        public readonly List<Product> Products = new List<Product>(); readonly Game g;
        public Store(Game game)
        {
            g = game;
            Products.Add(new Product { id = "starter", key = "starter", desc = "starterd", price = "$1.99", tag = "best", owned = s => s.starter });
            Products.Add(new Product { id = "x2", key = "x2", desc = "x2d", price = "$9.99", tag = "popular", owned = s => s.profitX2 });
            Products.Add(new Product { id = "offpro", key = "offpro", desc = "offprod", price = "$5.99", owned = s => s.offlinePro });
            Products.Add(new Product { id = "noads", key = "noads", desc = "noadsd", price = "$7.99", owned = s => s.noAds });
            Products.Add(new Product { id = "gems1", key = "gems", price = "$0.99", gems = 80 });
            Products.Add(new Product { id = "gems2", key = "gems", price = "$4.99", gems = 500 });
            Products.Add(new Product { id = "gems3", key = "gems", price = "$9.99", gems = 1200, tag = "popular" });
            Products.Add(new Product { id = "gems4", key = "gems", price = "$19.99", gems = 2800 });
            Products.Add(new Product { id = "gems5", key = "gems", price = "$49.99", gems = 8000 });
            Products.Add(new Product { id = "gems6", key = "gems", price = "$99.99", gems = 18000, tag = "best" });
        }
        public Product Find(string id) { foreach (var p in Products) if (p.id == id) return p; return null; }

        /// Gives the goods for one transaction id exactly once; a repeated id is ignored.
        public bool Grant(Product p, string tx)
        {
            var s = g.sim.s; if (p == null || string.IsNullOrEmpty(tx)) return false;
            foreach (var t in s.txDone) if (t == tx) return false;
            if (p.owned != null && p.owned(s)) return false;
            var list = new List<string>(s.txDone); list.Add(tx); if (list.Count > 200) list.RemoveAt(0); s.txDone = list.ToArray();
            switch (p.id)
            {
                case "starter": s.starter = true; g.sim.AddGems(300); g.sim.Earn(g.sim.IdleIncome(4 * 3600)); break;
                case "x2": s.profitX2 = true; break;
                case "offpro": s.offlinePro = true; break;
                case "noads": s.noAds = true; break;
                default: g.sim.AddGems(p.gems); break;
            }
            g.SaveNow(); return true;
        }
        public void Buy(Product p, Action<bool> done) { bool ok = Grant(p, "test-" + Guid.NewGuid().ToString("N")); done?.Invoke(ok); }
    }

    public class AudioKit
    {
        readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>(); AudioSource sfx, music; readonly Game g; float lastCoin;
        const int R = 44100;
        public AudioKit(Game game, bool silent)
        {
            g = game; if (silent) return;
            var go = new GameObject("Audio"); sfx = go.AddComponent<AudioSource>(); music = go.AddComponent<AudioSource>();
            Make("click", 0.06f, (t, d) => Mathf.Sin(2 * Mathf.PI * 880 * t) * (1 - t / d) * 0.35f);
            Make("coin", 0.16f, (t, d) => (Mathf.Sin(2 * Mathf.PI * (t < 0.05f ? 1318 : 1760) * t) + 0.4f * Mathf.Sin(2 * Mathf.PI * 2637 * t)) * Mathf.Exp(-t * 22) * 0.32f);
            Make("buy", 0.2f, (t, d) => Mathf.Sin(2 * Mathf.PI * (520 + 1400 * t) * t) * (1 - t / d) * 0.38f);
            Make("deny", 0.18f, (t, d) => Mathf.Sign(Mathf.Sin(2 * Mathf.PI * 150 * t)) * (1 - t / d) * 0.16f);
            Make("open", 0.14f, (t, d) => Mathf.Sin(2 * Mathf.PI * (300 + 900 * t / d) * t) * Mathf.Sin(Mathf.PI * t / d) * 0.22f);
            Make("power", 0.5f, (t, d) => Mathf.Sin(2 * Mathf.PI * (300 + 1500 * t / d * t / d) * t) * Mathf.Sin(Mathf.PI * t / d) * 0.32f);
            Make("win", 0.7f, (t, d) => { float[] f = { 523, 659, 784, 1047 }; int i = Mathf.Min(3, (int)(t / 0.12f)); float lt = t - i * 0.12f; return (Mathf.Sin(2 * Mathf.PI * f[i] * t) + 0.3f * Mathf.Sin(2 * Mathf.PI * f[i] * 2 * t)) * Mathf.Exp(-lt * 6) * 0.33f; });
            // a slow four-chord loop: soft pad plus a plucked top line
            float bar = 2.4f; float[][] chords = { new[] { 220f, 277.18f, 329.63f }, new[] { 185f, 233.08f, 277.18f }, new[] { 146.83f, 185f, 220f }, new[] { 164.81f, 207.65f, 246.94f } };
            int[] tune = { 2, 1, 2, 0, 1, 2, 1, 0 };
            Make("music", bar * 4, (t, d) =>
            {
                int b = Mathf.Min(3, (int)(t / bar)); float bt = t - b * bar; float v = 0; var ch = chords[b];
                float env = Mathf.Min(1, bt / 0.5f) * Mathf.Min(1, (bar - bt) / 0.5f);
                for (int i = 0; i < 3; i++) v += Mathf.Sin(2 * Mathf.PI * ch[i] * t) * 0.07f * env;
                int n = (int)(bt / 0.3f); float nt = bt - n * 0.3f; float nf = ch[tune[n % 8]] * 2;
                v += Mathf.Sin(2 * Mathf.PI * nf * t) * Mathf.Exp(-nt * 9) * 0.09f;
                return v;
            });
            music.clip = clips["music"]; music.loop = true; music.volume = 0.5f;
        }
        void Make(string name, float secs, Func<float, float, float> f)
        {
            int n = (int)(secs * R); var data = new float[n]; for (int i = 0; i < n; i++) data[i] = f(i / (float)R, secs);
            var c = AudioClip.Create(name, n, 1, R, false); c.SetData(data, 0); clips[name] = c;
        }
        public void Play(string name)
        {
            if (sfx == null || !g.sim.s.sfx) return;
            if (name == "coin") { if (Time.unscaledTime - lastCoin < 0.07f) return; lastCoin = Time.unscaledTime; }
            AudioClip c; if (clips.TryGetValue(name, out c)) sfx.PlayOneShot(c);
        }
        public void SetMusic(bool on) { if (music == null) return; if (on && !music.isPlaying) music.Play(); if (!on && music.isPlaying) music.Stop(); }
    }

    public class Game
    {
        public const string SaveKey = "save.v2";
        public Sim sim; public World world; public Ui ui; public Camera cam; public AudioKit audio; public Store store;
        public bool editor, overlay; public double pendingOffline; float saveT, stuckCd, paidFx; public Vector3 focus = new Vector3(0, 0, 9); public float zoom = 19f;
        int starterShown;

        public double Now() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;

        public static Save LoadSave()
        {
            Save s = null; var json = PlayerPrefs.GetString(SaveKey, "");
            if (json.Length > 0) { try { s = JsonUtility.FromJson<Save>(json); } catch { s = null; } }
            if (s == null || !s.Valid()) s = Save.Fresh();
            if (string.IsNullOrEmpty(s.lang)) s.lang = Application.systemLanguage == SystemLanguage.Arabic ? "ar" : "en";
            return s;
        }
        public void SaveNow()
        {
            if (editor) return;
            if (pendingOffline <= 0) sim.s.lastSeen = Now();       // an uncollected welcome-back reward keeps its start time
            PlayerPrefs.SetString(SaveKey, JsonUtility.ToJson(sim.s)); PlayerPrefs.Save();
        }

        public void Start(Save save, bool overlayUi)
        {
            overlay = overlayUi; Loc.Ar = save.lang == "ar";
            sim = new Sim(save, Now); store = new Store(this); audio = new AudioKit(this, editor);
            var cgo = new GameObject("Main Camera"); cgo.tag = "MainCamera"; cam = cgo.AddComponent<Camera>();
            cam.orthographic = true; cam.nearClipPlane = 0.3f; cam.farClipPlane = 400; cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.13f, 0.12f, 0.24f); cam.allowHDR = true;
            if (!editor) cgo.AddComponent<AudioListener>();
            PostFx();
            world = new World(sim); world.Build(); PlaceCamera();
            ui = new Ui(this); ui.Build(cam, overlay);
            sim.OnServed += (c, d, p) => { if (paidFx <= 0) { ui.CoinsFromWorld(World.QueuePos(d, c.staff, 0) + Vector3.up * 1.6f, p, false); paidFx = 0.12f; } };
            sim.OnPaid += (c, bill) => { ui.CoinsFromWorld(World.CashPos(c.cash) + Vector3.up * 1.8f, bill, true); audio.Play("coin"); };
            audio.SetMusic(save.music);
        }

        void PostFx()
        {
            try
            {
                var vol = new GameObject("PostFx").AddComponent<Volume>(); vol.isGlobal = true; var prof = ScriptableObject.CreateInstance<VolumeProfile>(); vol.sharedProfile = prof;
                var bloom = prof.Add<Bloom>(true); bloom.intensity.value = 0.85f; bloom.threshold.value = 1.05f; bloom.scatter.value = 0.62f;
                var tm = prof.Add<Tonemapping>(true); tm.mode.value = TonemappingMode.Neutral;
                var ca = prof.Add<ColorAdjustments>(true); ca.saturation.value = 16f; ca.contrast.value = 10f; ca.postExposure.value = 0.15f;
                var vg = prof.Add<Vignette>(true); vg.intensity.value = 0.2f; vg.smoothness.value = 0.5f;
                var data = cam.GetUniversalAdditionalCameraData(); data.renderPostProcessing = true; data.antialiasing = AntialiasingMode.FastApproximateAntialiasing;
            }
            catch (Exception e) { Debug.LogWarning("PostFx unavailable: " + e.Message); }
        }

        public void PlaceCamera()
        {
            focus.x = Mathf.Clamp(focus.x, -5f, 5f); focus.z = Mathf.Clamp(focus.z, -10f - sim.s.parkLevel * 2.2f, World.StoreDepth - 6f); zoom = Mathf.Clamp(zoom, 8f, 26f);
            cam.transform.rotation = Quaternion.Euler(52, 0, 0); cam.transform.position = focus - cam.transform.forward * 90f; cam.orthographicSize = zoom;
        }

        public void Tick(float dt)
        {
            if (dt > 0.25f) dt = 0.25f;
            sim.Tick(dt); world.Update(dt); ui.Update(dt);
            paidFx -= dt; stuckCd -= dt; saveT += dt; if (saveT > 5) { saveT = 0; SaveNow(); }
            // a first-purchase offer once the player has seen the loop and hit the first real wait
            if (!editor && starterShown == 0 && !sim.s.starter && sim.s.played > 240 && sim.s.dOpen[1] && !ui.Busy) { starterShown = 1; ui.OpenShop(); }
        }

        // ---------- rewards ----------
        /// Rewarded-ad slot. No ad network is connected in this build, so the reward follows a short pause.
        public void Ad(Action reward)
        {
            if (sim.s.noAds) { reward(); return; }
            sim.s.adsWatched++; ui.Toast("AD (test)"); ui.Run(0.6f, k => { }, () => reward());
        }
        public bool Warp(int i)
        {
            if (!sim.SpendGems(Store.WarpGems[i])) return false;
            double r = sim.IdleIncome(Store.WarpHours[i] * 3600); sim.Earn(r);
            var c = new Vector2(ui.root.rect.width / 2, ui.root.rect.height / 2); ui.Flash(U.Purple); ui.Float("+" + Loc.Num(r), c, U.Gold, 80); ui.Confetti(c, 40); audio.Play("win"); SaveNow(); return true;
        }
        /// Called when the player wants something they cannot pay for. A long wait brings up the time-skip offer.
        public void Stuck(double cost)
        {
            double perSec = sim.EarnPerMin / 60; if (perSec <= 0 || double.IsInfinity(cost)) return;
            double wait = (cost - sim.s.coin) / perSec; if (wait < 600 || stuckCd > 0) return;
            stuckCd = 90; int idx = wait <= 3600 ? 0 : wait <= 4 * 3600 ? 1 : 2; ui.StuckPopup(wait, idx);
        }
        public void OnBuilt(int d)
        {
            world.SyncStatic(); world.PopDept(d); audio.Play("win"); ui.Flash(World.DeptColor[d]); ui.Banner(Loc.G(T.DeptKey[d]), World.DeptColor[d]);
            ui.Confetti(new Vector2(ui.root.rect.width / 2, ui.root.rect.height * 0.55f), 60); SaveNow();
        }
        public void OnLevel(int d, int tierBefore)
        {
            int tier = T.Tier(sim.s.dLevel[d]); world.SyncStatic(); world.PopDept(d);
            if (tier > tierBefore) { audio.Play("win"); ui.Flash(World.DeptColor[d]); ui.Banner("x" + T.TierMul[tier - 1], World.DeptColor[d]); ui.Confetti(new Vector2(ui.root.rect.width / 2, ui.root.rect.height * 0.55f), 50); }
        }
        public void OnStar()
        {
            audio.Play("win"); ui.Flash(U.Gold); ui.Banner(Loc.Fix(Loc.Raw("grade") + " " + sim.s.star), U.Gold); ui.Confetti(new Vector2(ui.root.rect.width / 2, ui.root.rect.height * 0.55f), 90); SaveNow();
        }
        public void SetLang(bool ar)
        {
            sim.s.lang = ar ? "ar" : "en"; Loc.Ar = ar; Kit.Kill(ui.canvas.gameObject); ui = new Ui(this); ui.Build(cam, overlay); SaveNow();
        }
        public void CheckOffline()
        {
            double now = Now(); double r = sim.OfflineReward(now); if (r <= 0) return;
            double away = now - sim.s.lastSeen; pendingOffline = r; ui.OfflinePopup(r, Math.Min(away, sim.OfflineCap), away > T.OfflineCap);
        }

        // ---------- touch ----------
        public void Tap(Vector2 screen)
        {
            var hits = Physics.RaycastAll(cam.ScreenPointToRay(screen), 600f); if (hits.Length == 0) return;
            // small things first: a truck, the VIP car or a gift sit inside or beside the big department boxes
            foreach (var hit in hits)
            {
                var go = hit.collider.gameObject;
                if (world.truck != null && go == world.truck) { double r = sim.CollectTruck(); ui.CoinsFromWorld(world.truckPos + Vector3.up * 2, r, true); audio.Play("buy"); return; }
                if (world.vip != null && go == world.vip) { ui.VipPopup(); return; }
                if (go.transform.parent != null) { var c = world.CustAt(go.transform.parent.gameObject); if (c != null && c.gift) { double r = sim.CollectGift(c); ui.CoinsFromWorld(go.transform.position, r, true); audio.Play("win"); return; } }
            }
            foreach (var hit in hits) for (int d = 0; d < T.ND; d++) if (hit.collider == world.depts[d].hit) { ui.OpenDept(d); return; }
        }
        public void Pan(Vector2 pixels)
        {
            float unit = 2 * zoom / Screen.height; focus.x -= pixels.x * unit; focus.z -= pixels.y * unit / Mathf.Sin(52 * Mathf.Deg2Rad); PlaceCamera();
        }
        public void Zoom(float factor) { zoom /= factor; PlaceCamera(); }
    }
}
