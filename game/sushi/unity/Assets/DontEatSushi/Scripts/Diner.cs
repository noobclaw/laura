// 別吃壽司 - 電腦食客（人）。用「看得出差別才算看見」的方式判斷玩家是否暴露。
using System.Collections.Generic;
using UnityEngine;

namespace DontEatSushi
{
    public class Diner : MonoBehaviour
    {
        public SushiGame game;
        public float suspicion;
        public string stateLabel = "";
        public RenderTexture rt;
        public float lastDiff;

        const int W = 160, H = 120;
        const float K = 1f / 45f;

        enum St { Scan, Investigate, Grab, Eat, Return }
        St state = St.Scan;

        Camera aiCam;
        Texture2D read;
        Color32[] bufA, bufB;
        GameObject ghost;
        MeshFilter ghostF;
        MeshRenderer ghostR;
        Material ghostMat;
        readonly Dictionary<SushiKind, Texture2D> refTex = new Dictionary<SushiKind, Texture2D>();

        Transform hand;
        Vector3 handRest = new Vector3(3f, 5.5f, -10.5f);
        Vector3 handFrom, grabPoint;
        float handT;
        GameObject carry;
        Slot eatSlot;

        LineRenderer ring;
        Vector3 gazePoint = new Vector3(0f, 0.3f, -4.5f);
        Plate target;
        float dwell, perceiveT, invT, invElapsed, grace = 6f, eatT = 12f, lastSeen = -99f;

        public void Setup(SushiGame g)
        {
            game = g;
            var skin = Mats.Lit(new Color(0.93f, 0.76f, 0.62f), 0.2f);
            var cloth = Mats.Lit(new Color(0.16f, 0.2f, 0.36f), 0.1f);
            // 巨人的身體不投影子，否則整個吧台都被蓋住
            var body = game.Prim(PrimitiveType.Capsule, "DinerBody", new Vector3(0f, 0.5f, -17.5f), new Vector3(10f, 6f, 5f), cloth, false, transform);
            var head = game.Prim(PrimitiveType.Sphere, "DinerHead", new Vector3(0f, 10.8f, -16.2f), new Vector3(5f, 5.4f, 5f), skin, false, transform);
            body.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            head.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;

            var eye = new GameObject("DinerEye");
            eye.transform.SetParent(transform, false);
            eye.transform.position = new Vector3(0f, 9.6f, -12.6f);
            aiCam = eye.AddComponent<Camera>();
            aiCam.enabled = false;
            aiCam.fieldOfView = 24f;
            aiCam.nearClipPlane = 0.3f;
            aiCam.farClipPlane = 80f;
            aiCam.clearFlags = CameraClearFlags.SolidColor;
            aiCam.backgroundColor = game.bgColor;
            rt = new RenderTexture(W, H, 16, RenderTextureFormat.ARGB32);
            rt.name = "DinerView";
            aiCam.targetTexture = rt;
            read = new Texture2D(W, H, TextureFormat.RGBA32, false);
            bufA = new Color32[W * H];
            bufB = new Color32[W * H];

            ghost = new GameObject("Ghost");
            ghost.transform.SetParent(transform, false);
            ghostF = ghost.AddComponent<MeshFilter>();
            ghostR = ghost.AddComponent<MeshRenderer>();
            ghostMat = Mats.Lit(Color.white, 0.32f);
            ghostR.sharedMaterial = ghostMat;
            ghostR.enabled = false;

            var hgo = new GameObject("DinerHand");
            hgo.transform.SetParent(transform, false);
            hgo.transform.position = handRest;
            hgo.transform.rotation = Quaternion.Euler(-25f, 0f, 0f);
            hand = hgo.transform;
            var wood = Mats.Lit(new Color(0.25f, 0.13f, 0.08f), 0.5f);
            for (int i = -1; i <= 1; i += 2)
            {
                var st = game.Prim(PrimitiveType.Cylinder, "Chopstick", Vector3.zero, new Vector3(0.09f, 2.4f, 0.09f), wood, false, hand);
                st.transform.localPosition = new Vector3(i * 0.09f, 2.4f, 0f);
                st.transform.localRotation = Quaternion.Euler(0f, 0f, i * -1.5f);
            }
            var palm = game.Prim(PrimitiveType.Sphere, "Palm", Vector3.zero, new Vector3(1.5f, 1.2f, 1.1f), skin, false, hand);
            palm.transform.localPosition = new Vector3(0f, 4.6f, 0f);

            ring = game.Ring(transform, 1.8f, 0.07f, new Color(1f, 0.9f, 0.3f));
            ring.gameObject.SetActive(false);
        }

        Texture2D RefTex(SushiShape sh, SushiKind k)
        {
            Texture2D t;
            if (refTex.TryGetValue(k, out t) && t != null) return t;
            t = new Texture2D(SushiShape.T, SushiShape.T, TextureFormat.RGBA32, false);
            t.wrapMode = TextureWrapMode.Clamp;
            t.SetPixels32(SushiShapes.BuildPixels(sh, k));
            t.Apply(false);
            refTex[k] = t;
            return t;
        }

        void Update()
        {
            if (game == null) return;
            float dt = Time.deltaTime;
            if (game.phase != Phase.Hunt)
            {
                ring.gameObject.SetActive(false);
                stateLabel = "";
                if (state == St.Return || carry != null) MoveHand(dt);
                return;
            }
            ring.gameObject.SetActive(true);
            grace -= dt;
            Vector3 pp = game.player.position;
            Vector3 gazeGoal = gazePoint;

            switch (state)
            {
                case St.Scan:
                    stateLabel = "";
                    dwell -= dt;
                    if (dwell <= 0f || target == null) PickTarget();
                    if (target != null) gazeGoal = target.tr.position;
                    eatT -= dt;
                    if (eatT <= 0f) { eatT = Random.Range(14f, 22f); TryStartEat(); }
                    if (suspicion >= 0.35f && Time.time - lastSeen < 0.6f) { state = St.Investigate; invT = 3.5f; invElapsed = 0f; game.Toast("食客好像注意到什麼了…"); }
                    break;
                case St.Investigate:
                    stateLabel = "?";
                    gazeGoal = pp;
                    invT -= dt; invElapsed += dt;
                    if (suspicion >= 1f && invElapsed > 1.2f) { state = St.Grab; handT = 0f; handFrom = hand.position; grabPoint = pp; game.Toast("筷子來了，快跑！"); }
                    else if (invT <= 0f || suspicion < 0.15f) { state = St.Scan; dwell = 0f; }
                    break;
                case St.Grab:
                    stateLabel = "!";
                    gazeGoal = pp;
                    handT += dt / 1.0f;
                    if (handT < 0.6f) grabPoint = pp;
                    hand.position = Vector3.Lerp(handFrom, grabPoint + Vector3.up * 0.25f, Mathf.SmoothStep(0f, 1f, handT));
                    if (handT >= 1f)
                    {
                        Vector3 d = pp - grabPoint; d.y = 0f;
                        if (d.magnitude < 0.75f) { game.Caught(); }
                        else { suspicion = 0.55f; game.Toast("沒夾到！"); }
                        state = St.Return; handT = 0f; handFrom = hand.position;
                    }
                    break;
                case St.Eat:
                    stateLabel = "";
                    if (eatSlot == null || eatSlot.sushi == null) { state = St.Return; handT = 0f; handFrom = hand.position; break; }
                    gazeGoal = eatSlot.tr.position;
                    handT += dt / 1.2f;
                    hand.position = Vector3.Lerp(handFrom, eatSlot.tr.position + Vector3.up * 0.3f, Mathf.SmoothStep(0f, 1f, handT));
                    if (handT >= 1f)
                    {
                        carry = eatSlot.sushi;
                        eatSlot.sushi = null;
                        carry.transform.SetParent(hand, true);
                        state = St.Return; handT = 0f; handFrom = hand.position;
                    }
                    break;
                case St.Return:
                    MoveHand(dt);
                    break;
            }

            gazePoint = Vector3.MoveTowards(gazePoint, new Vector3(gazeGoal.x, 0.3f, gazeGoal.z), 9f * dt);
            aiCam.transform.LookAt(gazePoint);
            ring.transform.position = gazePoint;
            Color rc = suspicion >= 1f ? new Color(1f, 0.15f, 0.1f) : suspicion >= 0.35f ? new Color(1f, 0.55f, 0.1f) : new Color(1f, 0.9f, 0.3f);
            Mats.SetColor(ring.sharedMaterial, rc);

            if (grace <= 0f && (state == St.Scan || state == St.Investigate))
            {
                perceiveT -= dt;
                if (perceiveT <= 0f)
                {
                    const float step = 0.4f;
                    perceiveT = step;
                    float s = Perceive();
                    float gain = 0f;
                    if (s >= 0f)
                    {
                        lastDiff = s;
                        Vector3 d = pp - gazePoint; d.y = 0f;
                        float focus = Mathf.Lerp(0.25f, 1f, Mathf.Clamp01(1f - d.magnitude / 6f));
                        gain = s * K;
                        if (!game.playerAttached) gain *= 1.6f;
                        if (game.playerMoving) gain += 0.45f;
                        gain = Mathf.Min(gain * focus, 0.45f);
                        if (gain > 0.06f) lastSeen = Time.time;
                    }
                    suspicion = Mathf.Clamp(suspicion + (gain - 0.05f) * step, 0f, 1.2f);
                    if (suspicion > game.maxSuspicion) game.maxSuspicion = suspicion;
                }
            }
        }

        void MoveHand(float dt)
        {
            handT += dt / 1.1f;
            hand.position = Vector3.Lerp(handFrom, handRest, Mathf.SmoothStep(0f, 1f, handT));
            if (handT >= 1f)
            {
                if (carry != null) { Destroy(carry); carry = null; }
                if (state == St.Return) { state = suspicion >= 0.35f ? St.Investigate : St.Scan; invT = 2.5f; invElapsed = 0f; dwell = 0f; }
            }
        }

        void PickTarget()
        {
            var near = new List<Plate>();
            foreach (var p in game.plates) if (p.tr.position.z < 0f) near.Add(p);
            var pool = (near.Count > 0 && Random.value < 0.8f) ? near : game.plates;
            if (pool.Count == 0) { target = null; return; }
            target = pool[Random.Range(0, pool.Count)];
            dwell = Random.Range(2.2f, 3.4f);
        }

        void TryStartEat()
        {
            var cands = new List<Slot>();
            foreach (var p in game.plates)
            {
                if (p.tr.position.z > -2f || Mathf.Abs(p.tr.position.x) > 8f) continue;
                foreach (var s in p.slots) if (s.sushi != null) cands.Add(s);
            }
            if (cands.Count == 0) return;
            eatSlot = cands[Random.Range(0, cands.Count)];
            state = St.Eat; handT = 0f; handFrom = hand.position;
        }

        /// 回傳「玩家看起來和真壽司（或背景）差多少」。負數表示玩家不在視野內。
        float Perceive()
        {
            if (game.playerRenderer == null || !game.player.gameObject.activeSelf) return -1f;
            Bounds b = game.playerRenderer.bounds;
            float xmin = 9f, xmax = -9f, ymin = 9f, ymax = -9f;
            for (int i = 0; i < 8; i++)
            {
                Vector3 c = b.center + Vector3.Scale(b.extents, new Vector3((i & 1) == 0 ? -1f : 1f, (i & 2) == 0 ? -1f : 1f, (i & 4) == 0 ? -1f : 1f));
                Vector3 v = aiCam.WorldToViewportPoint(c);
                if (v.z <= 0f) return -1f;
                xmin = Mathf.Min(xmin, v.x); xmax = Mathf.Max(xmax, v.x);
                ymin = Mathf.Min(ymin, v.y); ymax = Mathf.Max(ymax, v.y);
            }
            if (xmax < 0f || xmin > 1f || ymax < 0f || ymin > 1f) return -1f;
            int x0 = Mathf.Clamp(Mathf.FloorToInt(xmin * W) - 2, 0, W - 1), x1 = Mathf.Clamp(Mathf.CeilToInt(xmax * W) + 2, 0, W - 1);
            int y0 = Mathf.Clamp(Mathf.FloorToInt(ymin * H) - 2, 0, H - 1), y1 = Mathf.Clamp(Mathf.CeilToInt(ymax * H) + 2, 0, H - 1);
            if (x1 - x0 < 3 || y1 - y0 < 3) return -1f;

            var sh = game.playerPaint.shape;
            ghostF.sharedMesh = sh.mesh;
            ghost.transform.SetPositionAndRotation(game.player.position, game.player.rotation);
            ghost.transform.localScale = game.player.lossyScale;

            Shot(true, false, bufA);
            Shot(false, false, bufB);
            float best = Diff(x0, y0, x1, y1);
            foreach (var k in sh.references)
            {
                var t = RefTex(sh, k);
                if (ghostMat.HasProperty("_BaseMap")) ghostMat.SetTexture("_BaseMap", t); else ghostMat.mainTexture = t;
                Shot(false, true, bufB);
                best = Mathf.Min(best, Diff(x0, y0, x1, y1));
            }
            game.playerRenderer.enabled = true;
            ghostR.enabled = false;
            return best;
        }

        void Shot(bool showPlayer, bool showGhost, Color32[] buf)
        {
            game.playerRenderer.enabled = showPlayer;
            ghostR.enabled = showGhost;
            aiCam.Render();
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            read.ReadPixels(new Rect(0, 0, W, H), 0, 0, false);
            RenderTexture.active = prev;
            read.GetPixelData<Color32>(0).CopyTo(buf);
        }

        float Diff(int x0, int y0, int x1, int y1)
        {
            float s = 0f;
            for (int y = y0; y <= y1; y++)
            {
                int row = y * W;
                for (int x = x0; x <= x1; x++)
                {
                    Color32 a = bufA[row + x], c = bufB[row + x];
                    float dr = (a.r - c.r) / 255f, dg = (a.g - c.g) / 255f, db = (a.b - c.b) / 255f;
                    float d = Mathf.Sqrt(dr * dr * 0.3f + dg * dg * 0.59f + db * db * 0.11f);
                    if (d > 0.05f) s += d - 0.05f;
                }
            }
            return s;
        }

        void OnDestroy()
        {
            if (rt != null) rt.Release();
        }
    }
}
