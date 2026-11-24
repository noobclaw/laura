// Ties the rule core, the 3D store, the interface, sound and the shop together.
// A plain class: the app drives it on a device, the cloud build drives it for screenshots.
using System;
using System.Collections.Generic;
using Souq.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Purchasing;

namespace Souq
{
    public class Product { public string id, key, desc, price, tag; public int gems; public bool once; public Func<Save, bool> owned; public string Sku => "com.noobclaw.souq." + id; }

    /// Shop catalogue and Apple in-app purchases (Unity IAP 5). The App Store product IDs are "com.noobclaw.souq." + id;
    /// each must exist in App Store Connect with the same type (once = non-consumable, otherwise consumable).
    public class Store
    {
        public static readonly int[] WarpHours = { 1, 4, 24 }; public static readonly int[] WarpGems = { 40, 120, 500 };
        public readonly List<Product> Products = new List<Product>(); readonly Game g;
        StoreController iap; bool connected, busy; Action<bool> pending; readonly Dictionary<string, string> localPrice = new Dictionary<string, string>();
        public bool Ready => connected;
        public Store(Game game)
        {
            g = game;
            Products.Add(new Product { id = "starter", key = "starter", desc = "starterd", price = "$1.99", tag = "best", once = true, owned = s => s.starter });
            Products.Add(new Product { id = "x2", key = "x2", desc = "x2d", price = "$9.99", tag = "popular", once = true, owned = s => s.profitX2 });
            Products.Add(new Product { id = "offpro", key = "offpro", desc = "offprod", price = "$5.99", once = true, owned = s => s.offlinePro });
            Products.Add(new Product { id = "gems80", key = "gems", price = "$0.99", gems = 80 });
            Products.Add(new Product { id = "gems500", key = "gems", price = "$4.99", gems = 500 });
            Products.Add(new Product { id = "gems1200", key = "gems", price = "$9.99", gems = 1200, tag = "popular" });
            Products.Add(new Product { id = "gems2800", key = "gems", price = "$19.99", gems = 2800 });
            Products.Add(new Product { id = "gems8000", key = "gems", price = "$49.99", gems = 8000 });
            Products.Add(new Product { id = "gems18000", key = "gems", price = "$99.99", gems = 18000, tag = "best" });
        }
        public Product Find(string id) { foreach (var p in Products) if (p.id == id) return p; return null; }
        Product BySku(string sku) { foreach (var p in Products) if (p.Sku == sku) return p; return null; }
        /// The App Store's own price text for the player's country once the store has answered, else the US price.
        public string PriceOf(Product p) => localPrice.TryGetValue(p.id, out var t) && !string.IsNullOrEmpty(t) ? t : p.price;

        /// Gives the goods for one transaction id exactly once; a repeated id or an owned one-time item is ignored.
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
                default: g.sim.AddGems(p.gems); break;
            }
            g.SaveNow(); return true;
        }

        // ---------- Apple payments ----------
        public async void StartIap()
        {
            try
            {
                try { await Unity.Services.Core.UnityServices.InitializeAsync(); } catch (Exception e) { Debug.LogWarning("IAP: services init: " + e.Message); }
                iap = UnityIAPServices.StoreController();
                iap.OnPurchasePending += OnPending;
                iap.OnPurchaseFailed += OnFailed;
                iap.OnPurchaseDeferred += o => { busy = false; Finish(false); g.ui.Toast(Loc.G("waitpay")); };
                iap.OnProductsFetched += OnFetched;
                iap.OnProductsFetchFailed += f => Debug.LogWarning("IAP: products not fetched: " + f);
                iap.OnPurchasesFetched += OnPurchasesFetched;
                iap.OnStoreDisconnected += d => { connected = false; Debug.LogWarning("IAP: store disconnected: " + d.message); };
                await iap.Connect();
                var defs = new List<ProductDefinition>();
                foreach (var p in Products) defs.Add(new ProductDefinition(p.Sku, p.once ? ProductType.NonConsumable : ProductType.Consumable));
                iap.FetchProducts(defs);
            }
            catch (Exception e) { Debug.LogWarning("IAP: start failed: " + e); }
        }
        void OnFetched(List<UnityEngine.Purchasing.Product> list)
        {
            connected = true;
            foreach (var ap in list) { var p = BySku(ap.definition.id); if (p != null && ap.metadata != null) localPrice[p.id] = ap.metadata.localizedPriceString; }
            iap.FetchPurchases();                                      // finishes any payment that was interrupted last time
        }
        void OnPurchasesFetched(Orders orders)
        {
            // one-time items already paid for (another device, a reinstall): give them back
            foreach (var o in orders.ConfirmedOrders) GrantOrder(o, false);
        }
        void OnPending(PendingOrder o)
        {
            bool ok = GrantOrder(o, true);
            iap.ConfirmPurchase(o);                                    // always confirm, or Apple keeps redelivering it
            busy = false; Finish(true);
            if (ok) g.audio.Play("win");
        }
        void OnFailed(FailedOrder o) { busy = false; Finish(false); }
        bool GrantOrder(Order o, bool consumablesToo)
        {
            bool any = false; string tx = o.Info != null ? o.Info.TransactionID : null;
            foreach (var item in o.CartOrdered.Items())
            {
                var p = item.Product != null ? BySku(item.Product.definition.id) : null; if (p == null) continue;
                if (!consumablesToo && !p.once) continue;
                if (Grant(p, string.IsNullOrEmpty(tx) ? "restore-" + p.id : tx)) any = true;
            }
            return any;
        }
        void Finish(bool ok) { var cb = pending; pending = null; cb?.Invoke(ok); }

        public void Buy(Product p, Action<bool> done)
        {
#if UNITY_EDITOR
            done?.Invoke(Grant(p, "editor-" + Guid.NewGuid().ToString("N"))); return;
#else
            if (iap == null || !connected) { g.ui.Toast(Loc.G("nostore")); done?.Invoke(false); return; }
            if (busy) return;
            var ap = iap.GetProductById(p.Sku); if (ap == null) { g.ui.Toast(Loc.G("nostore")); done?.Invoke(false); return; }
            busy = true; pending = done; iap.PurchaseProduct(ap);
#endif
        }
        public void Restore()
        {
            if (iap == null || !connected) { g.ui.Toast(Loc.G("nostore")); return; }
            iap.RestoreTransactions((ok, msg) => { if (ok) iap.FetchPurchases(); g.ui.Toast(Loc.G(ok ? "restored" : "nostore")); });
        }
    }

    public class AudioKit
    {
        readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>(); AudioSource sfx, sfxP, music; readonly Game g; float lastCoin, lastReg;
        const int R = 44100;
        public AudioKit(Game game, bool silent)
        {
            g = game; if (silent) return;
            var go = new GameObject("Audio"); sfx = go.AddComponent<AudioSource>(); sfxP = go.AddComponent<AudioSource>(); music = go.AddComponent<AudioSource>();
            Make("up", 0.13f, (t, d) => (Mathf.Sin(2 * Mathf.PI * 660 * t) + 0.5f * Mathf.Sin(2 * Mathf.PI * 1320 * t) + 0.25f * Mathf.Sin(2 * Mathf.PI * 1980 * t)) * Mathf.Exp(-t * 26) * 0.30f);
            Make("pop", 0.09f, (t, d) => Mathf.Sin(2 * Mathf.PI * (420 - 2200 * t) * t) * (1 - t / d) * 0.34f);
            Make("whoosh", 0.45f, (t, d) => { float n = Mathf.PerlinNoise(t * 900f, 0.3f) * 2 - 1; return n * Mathf.Sin(Mathf.PI * t / d) * Mathf.Sin(Mathf.PI * t / d) * 0.30f; });
            // till: a key click, then two bright bells
            Make("register", 0.42f, (t, d) => { float v = t < 0.03f ? (Mathf.PerlinNoise(t * 4000f, 0.7f) * 2 - 1) * 0.3f : 0; float b1 = t - 0.05f, b2 = t - 0.13f; if (b1 > 0) v += (Mathf.Sin(2 * Mathf.PI * 2093 * b1) + 0.5f * Mathf.Sin(2 * Mathf.PI * 4186 * b1)) * Mathf.Exp(-b1 * 14) * 0.2f; if (b2 > 0) v += (Mathf.Sin(2 * Mathf.PI * 2637 * b2) + 0.5f * Mathf.Sin(2 * Mathf.PI * 5274 * b2)) * Mathf.Exp(-b2 * 11) * 0.22f; return v; });
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
        /// A sound at a chosen pitch: rising pitch is how a run of upgrades builds up.
        public void PlayPitch(string name, float pitch)
        {
            if (sfxP == null || !g.sim.s.sfx) return; AudioClip c; if (!clips.TryGetValue(name, out c)) return; sfxP.pitch = Mathf.Clamp(pitch, 0.5f, 3f); sfxP.PlayOneShot(c);
        }
        public void Register() { if (sfx == null || Time.unscaledTime - lastReg < 0.25f) return; lastReg = Time.unscaledTime; Play("register"); }
        public void SetMusic(bool on) { if (music == null) return; if (on && !music.isPlaying) music.Play(); if (!on && music.isPlaying) music.Stop(); }
    }

    public class Game
    {
        public const float Pitch = 50f;
        public const string SaveKey = "save.v2";
        public Sim sim; public World world; public Ui ui; public Camera cam; public AudioKit audio; public Store store; public Tutorial tut;
        public bool editor, overlay; public double pendingOffline; float saveT, stuckCd, paidFx; public Vector3 focus = new Vector3(0, 0, 8); public float zoom = 22f;
        int starterShown; int combo; float comboT;
        // camera moves on its own for openings and transitions; a drag takes it back
        Vector3 glideFrom, glideTo; float glideZ0, glideZ1, glideT = -1, glideDur = 1; float punch;

        public double Now() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;

        public static string SystemLang()
        {
            switch (Application.systemLanguage)
            {
                case SystemLanguage.Arabic: return "ar"; case SystemLanguage.Japanese: return "ja"; case SystemLanguage.Korean: return "ko"; case SystemLanguage.German: return "de";
                case SystemLanguage.French: return "fr"; case SystemLanguage.Spanish: return "es"; case SystemLanguage.Chinese: case SystemLanguage.ChineseTraditional: case SystemLanguage.ChineseSimplified: return "zh";
                default: return "en";
            }
        }
        public static Save LoadSave()
        {
            Save s = null; var json = PlayerPrefs.GetString(SaveKey, "");
            if (json.Length > 0) { try { s = JsonUtility.FromJson<Save>(json); } catch { s = null; } }
            if (s == null || !s.Valid()) s = Save.Fresh();
            s.Repair();
            if (string.IsNullOrEmpty(s.lang)) s.lang = SystemLang();
            if (s.tut < Tutorial.Done && s.dOpen[1]) s.tut = Tutorial.Done;      // a store that already grew does not need the first-steps guide
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
            overlay = overlayUi; Loc.Set(save.lang);
            sim = new Sim(save, Now); store = new Store(this); audio = new AudioKit(this, editor);
            var cgo = new GameObject("Main Camera"); cgo.tag = "MainCamera"; cam = cgo.AddComponent<Camera>();
            cam.orthographic = true; cam.nearClipPlane = 0.3f; cam.farClipPlane = 400; cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.49f, 0.77f, 0.35f); cam.allowHDR = true;
            if (!editor) cgo.AddComponent<AudioListener>();
            PostFx();
            U.PickFont(); world = new World(sim); world.Build(); PlaceCamera();
            ui = new Ui(this); ui.Build(cam, overlay); tut = new Tutorial(this);
            sim.OnServed += (c, d, p) =>
            {
                if (paidFx > 0) return; paidFx = 0.1f;
                var at = World.QueuePos(d, c.staff, 0) + Vector3.up * 1.7f; ui.CoinsFromWorld(at, p, false); ui.ItemHop(World.StaffPos(d, c.staff) + Vector3.up * 1.3f, at, World.DeptColor[d]);
            };
            sim.OnPaid += (c, bill) => { var at = World.CashPos(c.cash) + Vector3.up * 1.9f; ui.CoinsFromWorld(at, bill, true); ui.Burst(ui.ToCanvas(at), U.Gold, 5, 0.7f); audio.Register(); };
            audio.SetMusic(save.music);
        }

        /// Opening shot: shutters lift on the car park and the camera travels up to the shop floor.
        public void Intro()
        {
            focus = new Vector3(0, 0, -9); zoom = 22f; PlaceCamera();
            ui.Shutter(Loc.G("title"), Loc.G("opening"), new Color(0.80f, 0.13f, 0.15f), null, true);
            ui.Run(0.1f, k => { }, () => Glide(new Vector3(0, 0, 8), 22f, 2.2f), 0.55f);
        }

        void PostFx()
        {
            try
            {
                var vol = new GameObject("PostFx").AddComponent<Volume>(); vol.isGlobal = true; var prof = ScriptableObject.CreateInstance<VolumeProfile>(); vol.sharedProfile = prof;
                var bloom = prof.Add<Bloom>(true); bloom.intensity.value = 0.45f; bloom.threshold.value = 1.0f; bloom.scatter.value = 0.6f;
                var tm = prof.Add<Tonemapping>(true); tm.mode.value = TonemappingMode.Neutral;
                var ca = prof.Add<ColorAdjustments>(true); ca.saturation.value = 14f; ca.contrast.value = 12f; ca.postExposure.value = -0.08f;
                var vg = prof.Add<Vignette>(true); vg.intensity.value = 0.16f; vg.smoothness.value = 0.5f;
                var data = cam.GetUniversalAdditionalCameraData(); data.renderPostProcessing = true; data.antialiasing = AntialiasingMode.None; cam.allowMSAA = true;   // edges are smoothed by multisampling, which does not soften the picture
            }
            catch (Exception e) { Debug.LogWarning("PostFx unavailable: " + e.Message); }
        }

        public float MinZ => -11f - Mathf.Max(0, sim.s.parkLevel - 1) * 4.6f;
        public void PlaceCamera()
        {
            // the store is as wide as the screen, so the view only travels along its length
            focus.x = 0; focus.z = Mathf.Clamp(focus.z, MinZ, World.StoreDepth - 8f); zoom = Mathf.Clamp(zoom, 13f, 24f);
            cam.transform.rotation = Quaternion.Euler(Pitch, 0, 0); cam.orthographicSize = zoom * (1 - 0.035f * Mathf.Sin(Mathf.Clamp01(punch) * Mathf.PI));
            var p = focus - cam.transform.forward * 90f; float sh = world != null ? world.shake : 0;
            if (sh > 0) p += cam.transform.right * (Mathf.Sin(Time.unscaledTime * 71f) * 0.22f * sh) + cam.transform.up * (Mathf.Sin(Time.unscaledTime * 53f) * 0.18f * sh);
            cam.transform.position = p;
        }
        public void Glide(Vector3 to, float toZoom, float dur) { glideFrom = focus; glideTo = to; glideZ0 = zoom; glideZ1 = toZoom; glideT = 0; glideDur = Mathf.Max(0.05f, dur); }
        public void LookAtDept(int d, float dur = 0.7f) { Glide(new Vector3(0, 0, World.DeptCenter(d).z - 3.5f), zoom, dur); }

        public void Tick(float dt)
        {
            if (dt > 0.25f) dt = 0.25f;
            sim.Tick(dt); world.Update(dt); ui.Update(dt); tut.Tick(dt);
            if (glideT >= 0) { glideT += dt / glideDur; float k = Mathf.Clamp01(glideT); float e = k * k * (3 - 2 * k); focus = Vector3.Lerp(glideFrom, glideTo, e); zoom = Mathf.Lerp(glideZ0, glideZ1, e); if (k >= 1) glideT = -1; }
            if (punch > 0) punch = Mathf.Max(0, punch - dt * 3f);
            if (glideT >= 0 || punch > 0 || world.shake > 0) PlaceCamera();
            comboT -= dt; if (comboT <= 0) combo = 0;
            paidFx -= dt; stuckCd -= dt; saveT += dt; if (saveT > 5) { saveT = 0; SaveNow(); }
            // a first-purchase offer once the player has seen the loop and hit the first real wait
            if (!editor && starterShown == 0 && !sim.s.starter && sim.s.played > 240 && sim.s.dOpen[1] && !ui.Busy && !tut.Active) { starterShown = 1; ui.OpenShop(); }
        }

        // ---------- rewards ----------
        public bool Warp(int i)
        {
            if (!sim.SpendGems(Store.WarpGems[i])) return false;
            double r = sim.IdleIncome(Store.WarpHours[i] * 3600); sim.Earn(r);
            var c = new Vector2(ui.root.rect.width / 2, ui.root.rect.height / 2); ui.Flash(U.Purple); ui.Float("+" + Loc.Num(r), c, U.Gold, 80); ui.Confetti(c, 40); ui.FlyIcons(Spr.Coin, c, ui.coinPill, 14); audio.Play("win"); world.shake = 0.6f; SaveNow(); return true;
        }
        /// Called when the player wants something they cannot pay for. A long wait brings up the time-skip offer.
        public void Stuck(double cost)
        {
            double perSec = sim.FlowPerMin / 60; if (perSec <= 0 || double.IsInfinity(cost) || tut.Active) return;
            double wait = (cost - sim.s.coin) / perSec; if (wait < 600 || stuckCd > 0) return;
            stuckCd = 90; int idx = wait <= 3600 ? 0 : wait <= 4 * 3600 ? 1 : 2; ui.StuckPopup(wait, idx);
        }
        Vector2 Mid => new Vector2(ui.root.rect.width / 2, ui.root.rect.height * 0.55f);
        public void OnBuilt(int d)
        {
            // grand opening: the camera goes to the new department while its fixtures drop in
            LookAtDept(d, 0.6f); world.SyncStatic(); world.PopDept(d); world.shake = 0.8f; punch = 1;
            audio.Play("whoosh"); audio.Play("win"); ui.Flash(World.DeptColor[d]); ui.Ribbon(Loc.G("opening"), Loc.G(T.DeptKey[d]), World.DeptColor[d]);
            ui.Confetti(Mid, 70); ui.Run(0.1f, k => { }, () => { ui.Confetti(Mid + new Vector2(-260, 80), 40); ui.Confetti(Mid + new Vector2(260, 80), 40); audio.Play("pop"); }, 0.35f); SaveNow();
        }
        /// One press (or one tick of a held press) of the upgrade button: `count` levels were bought.
        public void OnLevel(int d, int tierBefore, int count = 1)
        {
            int tier = T.Tier(sim.s.dLevel[d]); world.SyncStatic(); world.PopDept(d);
            combo = comboT > 0 ? combo + 1 : 1; comboT = 1.1f;
            audio.PlayPitch("up", 1f + Mathf.Min(combo, 30) * 0.035f);
            var at = ui.ToCanvas(World.DeptFx(d)); var col = World.DeptColor[d];
            ui.Burst(at, col, 7, 1f); ui.Float(Loc.Fix(Loc.Raw("level") + " " + sim.s.dLevel[d]), at + new Vector2(0, 90), Color.white, 44);
            ui.ItemPop(World.DeptFx(d), d, combo);
            if (combo >= 3) ui.Combo(combo, col);
            if (combo % 10 == 0) { world.shake = Mathf.Max(world.shake, 0.35f); ui.Confetti(at, 16); }
            if (tier > tierBefore)
            {
                audio.Play("win"); audio.Play("whoosh"); ui.Flash(col); world.shake = 1f; punch = 1;
                ui.Ribbon(Loc.Fix("x" + T.TierMul[tier - 1] + " " + Loc.Raw("bonus")), Loc.G(T.DeptKey[d]), col, true); ui.Confetti(Mid, 60); ui.FlyIcons(Spr.Star, Mid, ui.coinPill, 8);
            }
        }
        public void OnHire(int d) { world.SyncStatic(); world.PopDept(d); audio.Play("pop"); var at = ui.ToCanvas(World.StaffPos(d, sim.s.dStaff[d] - 1) + Vector3.up * 1.2f); ui.Burst(at, U.Blue, 10, 1.2f); world.shake = Mathf.Max(world.shake, 0.3f); }
        public void OnStar()
        {
            // moving to a bigger store: shutters close, the new colours go up behind them, shutters open
            audio.Play("whoosh");
            ui.Shutter(Loc.G("newstoret"), Loc.Fix(Loc.Raw("grade") + " " + sim.s.star), U.Gold, () => { world.SyncStatic(true); focus = new Vector3(0, 0, 8); PlaceCamera(); audio.Play("win"); }, false);
            ui.Run(0.1f, k => { }, () => { ui.Confetti(Mid, 90); world.shake = 0.8f; punch = 1; }, 1.5f); SaveNow();
        }
        public void SetLang(string code)
        {
            sim.s.lang = code; Loc.Set(code); U.PickFont(); world.RefreshSigns(); Kit.Kill(ui.canvas.gameObject); ui = new Ui(this); ui.Build(cam, overlay); SaveNow();
        }
        public void CheckOffline()
        {
            double now = Now(); double r = sim.OfflineReward(now); if (r <= 0) return;
            double away = now - sim.s.lastSeen; pendingOffline = r; ui.OfflinePopup(r, Math.Min(away, sim.OfflineCap), away > T.OfflineCap);
        }

        // ---------- touch ----------
        public void Tap(Vector2 screen)
        {
            var cp = new Vector2(screen.x / Mathf.Max(1, cam.pixelWidth) * ui.root.rect.width, screen.y / Mathf.Max(1, cam.pixelHeight) * ui.root.rect.height);
            ui.Ripple(cp); audio.Play("click");
            var hits = Physics.RaycastAll(cam.ScreenPointToRay(screen), 600f); if (hits.Length == 0) return;
            // small things first: a truck, the VIP car or a gift sit inside or beside the big department boxes
            foreach (var hit in hits)
            {
                var go = hit.collider.gameObject;
                if (world.truck != null && go == world.truck) { CollectTruck(); return; }
                if (world.vip != null && go == world.vip) { ui.VipPopup(); return; }
                if (go.transform.parent != null) { var c = world.CustAt(go.transform.parent.gameObject); if (c != null && c.gift) { double r = sim.CollectGift(c); ui.CoinsFromWorld(go.transform.position, r, true); ui.Burst(cp, U.Red, 12, 1.2f); audio.Play("win"); return; } }
            }
            foreach (var hit in hits) for (int d = 0; d < T.ND; d++) if (hit.collider == world.depts[d].hit) { world.PopDept(d); ui.OpenDept(d); return; }
        }
        public void CollectTruck()
        {
            double r = sim.CollectTruck(); if (r <= 0) return; var at = world.truckPos + Vector3.up * 2;
            ui.CoinsFromWorld(at, r, true); ui.Burst(ui.ToCanvas(at), U.Gold, 14, 1.3f); ui.FlyIcons(Spr.Coin, ui.ToCanvas(at), ui.coinPill, 8); audio.Play("buy"); audio.Register(); world.shake = Mathf.Max(world.shake, 0.4f);
        }
        public void Pan(Vector2 pixels)
        {
            glideT = -1; float unit = 2 * zoom / Mathf.Max(1, Screen.height); focus.z -= pixels.y * unit / Mathf.Sin(Pitch * Mathf.Deg2Rad); PlaceCamera();
        }
        public void Zoom(float factor) { glideT = -1; zoom /= factor; PlaceCamera(); }
    }
}
