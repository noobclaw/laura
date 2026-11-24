// Rule core: every number the player sees comes from here. No UnityEngine types.
using System;
using System.Collections.Generic;

namespace Souq.Core
{
    [Serializable]
    public class Save
    {
        public int v = 1;
        public double coin = 1000, assets = 0;
        public int gem = 0;
        public double lastSeen = 0;            // unix seconds
        public double adEnd = 0, quickBuyEnd = 0, quickCheckEnd = 0;
        public int[] dLevel, dSpeed, dStaff; public bool[] dOpen;
        public int[] cLevel;                    // 0 = closed
        public int parkLevel = 1, adLevel = 1, star = 0;
        public int[] epic; public int task = 0, trucks = 0; public int[] served;
        public int loginDay = 0;
        public int tut = 0;                     // first-steps guide: step reached, 99 when finished
        public bool noAds, profitX2, offlinePro, starter;
        public string[] txDone = new string[0];
        public string lang = ""; public bool sfx = true, music = true;
        public double played = 0; public int adsWatched = 0;

        public static Save Fresh()
        {
            var s = new Save();
            s.dLevel = new int[T.ND]; s.dSpeed = new int[T.ND]; s.dStaff = new int[T.ND]; s.dOpen = new bool[T.ND];
            for (int i = 0; i < T.ND; i++) { s.dLevel[i] = 1; s.dStaff[i] = 1; }
            s.dOpen[0] = true;
            s.cLevel = new int[T.NC]; s.cLevel[0] = 1;
            s.epic = new int[T.Epics.Length]; s.served = new int[T.ND];
            return s;
        }

        /// Repairs a save from an older or damaged file so array reads are always in range.
        public void Repair()
        {
            dOpen[0] = true; if (cLevel[0] < 1) cLevel[0] = 1;
            for (int i = 0; i < T.ND; i++) { dLevel[i] = Math.Max(1, Math.Min(T.MaxLevel, dLevel[i])); dStaff[i] = Math.Max(1, Math.Min(T.MaxStaff, dStaff[i])); dSpeed[i] = Math.Max(0, Math.Min(T.ProdMax, dSpeed[i])); if (i > 0 && !dOpen[i - 1]) dOpen[i] = false; }
            for (int i = 0; i < T.NC; i++) cLevel[i] = Math.Max(0, Math.Min(T.CashLevelMax, cLevel[i]));
            for (int i = 0; i < T.Epics.Length; i++) epic[i] = Math.Max(0, Math.Min(T.Epics[i].max, epic[i]));
            parkLevel = Math.Min(T.ParkMax, parkLevel); adLevel = Math.Min(T.AdLevelMax, adLevel); if (gem < 0) gem = 0; if (task < 0) task = 0;
        }
        public bool Valid() =>
            dLevel != null && dLevel.Length == T.ND && dSpeed != null && dSpeed.Length == T.ND && dStaff != null && dStaff.Length == T.ND &&
            dOpen != null && dOpen.Length == T.ND && cLevel != null && cLevel.Length == T.NC && epic != null && epic.Length == T.Epics.Length &&
            served != null && served.Length == T.ND && parkLevel >= 1 && adLevel >= 1 && star >= 0 && star < T.StarCost.Length &&
            !double.IsNaN(coin) && !double.IsInfinity(coin) && coin >= 0 && txDone != null;
    }

    public enum CS { CarIn, WalkIn, ToDept, Queue, Served, ToCash, CashQueue, Paying, WalkOut, CarOut, Done }

    public class Cust
    {
        public int id, slot, look; public CS st; public float t, dur;
        public List<int> plan = new List<int>(); public int dept = -1, staff = -1, cash = -1;
        public double bill; public bool gift;
    }

    public class Sim
    {
        public Save s; public Func<double> Now;
        public readonly List<Cust> custs = new List<Cust>();
        public readonly List<Cust>[][] dq = new List<Cust>[T.ND][];
        public readonly List<Cust>[] cq = new List<Cust>[T.NC];
        readonly bool[] slotUsed = new bool[T.ParkCost.Length * 6 + 6];
        readonly Random rng = new Random();
        double spawnT, giftT; int nextId = 1; public int busPending;
        public bool truckHere, vipHere; public double truckT = 20, vipT = 90, busT = 150, qbT = 110, qcT = 170;
        public bool busOffer, quickBuyOffer, quickCheckOffer; public double vipReward;

        public event Action<Cust, int, double> OnServed;   // shopper, department, price added
        public event Action<Cust, double> OnPaid;          // shopper, bill
        public event Action OnChange;                      // something a panel shows has changed

        public Sim(Save save, Func<double> now)
        {
            s = save; Now = now;
            for (int d = 0; d < T.ND; d++) { dq[d] = new List<Cust>[T.MaxStaff]; for (int k = 0; k < T.MaxStaff; k++) dq[d][k] = new List<Cust>(); }
            for (int c = 0; c < T.NC; c++) cq[c] = new List<Cust>();
        }

        // ---------- derived numbers ----------
        public int Epic(EpicKind k, int dept = -1)
        {
            for (int i = 0; i < T.Epics.Length; i++) if (T.Epics[i].kind == k && T.Epics[i].dept == dept) return s.epic[i];
            return 0;
        }
        double EpicAdd(EpicKind k, int dept = -1)
        {
            for (int i = 0; i < T.Epics.Length; i++) if (T.Epics[i].kind == k && T.Epics[i].dept == dept) return T.Epics[i].add * s.epic[i];
            return 0;
        }
        public bool AdActive => s.adEnd > Now();
        public bool QuickBuy => s.quickBuyEnd > Now();
        public bool QuickCheck => s.quickCheckEnd > Now();
        public double ProfitMult => T.StarProfit[s.star] * Math.Pow(2, Epic(EpicKind.Profit)) * (AdActive ? 2 : 1) * (s.profitX2 ? 2 : 1);
        public double Price(int d) => (T.BasePrice[d] + (s.dLevel[d] - 1) * T.PriceStep(d)) * T.TierProduct(s.dLevel[d]) * ProfitMult;
        public double StaffSpeed(int d) => (T.SpeedBase[d] + s.dSpeed[d] * T.SpeedStep(d)) * (1 + EpicAdd(EpicKind.Manager, d));
        public double DeptSpeed(int d) => StaffSpeed(d) * s.dStaff[d];
        public double ServiceSecs(int d) => 60.0 / StaffSpeed(d) * (QuickBuy ? 0.5 : 1);
        public double LevelCost(int d) => Math.Floor(Math.Pow(T.UpRate[d], s.dLevel[d] - 1) * T.UpBase[d] * 100) / 100 * (1 - EpicAdd(EpicKind.Research, d));
        public double ProdCost(int d) => Math.Pow(T.ProdRate(d), s.dSpeed[d]) * T.ProdBase(d);
        public double HireCost(int d) => Math.Floor(T.HireBase(d, s.dStaff[d]) * (1 - EpicAdd(EpicKind.StaffCost)));
        public int CashOpen { get { int n = 0; foreach (var l in s.cLevel) if (l > 0) n++; return n; } }
        public double CashSpeed(int c) => (T.CashSpeedBase[c] + (s.cLevel[c] - 1) * T.CashSpeedStep[c]) * (1 + EpicAdd(EpicKind.CashierSpeed));
        public double CashSecs(int c) => 60.0 / CashSpeed(c) * (QuickCheck ? 0.5 : 1);
        public double CashUpCost(int c) => Math.Floor(10 * Math.Pow(T.CashUpRate[c], s.cLevel[c] - 1) * T.CashUpBase[c]) / 10;
        public double CashHireCost() { int n = CashOpen; return n >= T.NC ? double.PositiveInfinity : T.CashHire[n] * (1 - EpicAdd(EpicKind.CashierCost)); }
        public int ParkSpaces => 6 * s.parkLevel;
        public double ParkCost() => s.parkLevel >= T.ParkMax ? double.PositiveInfinity : T.ParkCost[s.parkLevel - 1];
        public double Arrivals => Math.Floor(100 * (8 + 0.8 * (s.adLevel - 1))) / 100;      // cars per minute
        public double AdLevelCost() => s.adLevel >= T.AdLevelMax ? double.PositiveInfinity : Math.Pow(2, s.adLevel + 1);
        public double StarCost() => s.star + 1 >= T.StarCost.Length ? double.PositiveInfinity : T.StarCost[s.star + 1];
        public double WalkMult => 1 + EpicAdd(EpicKind.Walk);
        public int OpenDepts { get { int n = 0; foreach (var o in s.dOpen) if (o) n++; return n; } }
        /// Income per minute if every department worked without pause.
        public double EarnPerMin { get { double e = 0; for (int d = 0; d < T.ND; d++) if (s.dOpen[d]) e += Price(d) * DeptSpeed(d); return e; } }
        /// Income per minute the store can really take: limited by how many cars arrive and how fast the checkouts clear.
        public double FlowPerMin
        {
            get
            {
                double a = Arrivals, cash = 0; for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0) cash += CashSpeed(c);
                double scale = a > 0 ? Math.Min(1, cash / a) : 0, e = 0;
                for (int d = 0; d < T.ND; d++) if (s.dOpen[d]) e += Price(d) * Math.Min(DeptSpeed(d), a * T.Visit[d] / 100.0) * scale;
                return e;
            }
        }
        public double AdBoostCap => T.AdBoostMax + EpicAdd(EpicKind.AdTime);
        public double OfflineCap => s.offlinePro ? T.OfflineCapPro : T.OfflineCap;

        // ---------- spending ----------
        void Changed() { OnChange?.Invoke(); }
        bool Pay(double c) { if (double.IsNaN(c) || double.IsInfinity(c) || c < 0 || s.coin < c) return false; s.coin -= c; Changed(); return true; }
        public void Earn(double c) { if (double.IsNaN(c) || double.IsInfinity(c) || c <= 0) return; s.coin += c; s.assets += c; }
        public bool BuildDept(int d) { if (s.dOpen[d] || (d > 0 && !s.dOpen[d - 1])) return false; if (!Pay(T.Build[d])) return false; s.dOpen[d] = true; Changed(); return true; }
        public bool LevelUp(int d) { if (!s.dOpen[d] || s.dLevel[d] >= T.MaxLevel) return false; if (!Pay(LevelCost(d))) return false; s.dLevel[d]++; Changed(); return true; }
        public bool ProdUp(int d) { if (!s.dOpen[d] || s.dSpeed[d] >= T.ProdMax) return false; if (!Pay(ProdCost(d))) return false; s.dSpeed[d]++; Changed(); return true; }
        public bool Hire(int d) { if (!s.dOpen[d] || s.dStaff[d] >= T.MaxStaff) return false; if (!Pay(HireCost(d))) return false; s.dStaff[d]++; Changed(); return true; }
        public bool CashHire() { int n = CashOpen; if (n >= T.NC) return false; if (!Pay(CashHireCost())) return false; s.cLevel[n] = 1; Changed(); return true; }
        public bool CashUp(int c) { if (s.cLevel[c] <= 0 || s.cLevel[c] >= T.CashLevelMax) return false; if (!Pay(CashUpCost(c))) return false; s.cLevel[c]++; Changed(); return true; }
        public bool ParkUp() { if (s.parkLevel >= T.ParkMax) return false; if (!Pay(ParkCost())) return false; s.parkLevel++; Changed(); return true; }
        public bool AdLevelUp() { if (s.adLevel >= T.AdLevelMax) return false; if (!Pay(AdLevelCost())) return false; s.adLevel++; Changed(); return true; }
        public bool StarUp() { if (s.star + 1 >= T.StarCost.Length) return false; if (!Pay(StarCost())) return false; s.star++; Changed(); return true; }
        public int EpicCost(int i) => T.Epics[i].cost * (s.epic[i] + 1);
        public bool EpicAvailable(int i) { var e = T.Epics[i]; return s.epic[i] < e.max && (e.dept < 0 || s.dOpen[e.dept]); }
        public bool EpicUp(int i) { if (!EpicAvailable(i)) return false; int c = EpicCost(i); if (s.gem < c) return false; s.gem -= c; s.epic[i]++; Changed(); return true; }
        public bool SpendGems(int n) { if (n < 0 || s.gem < n) return false; s.gem -= n; Changed(); return true; }
        public void AddGems(int n) { if (n > 0) { s.gem += n; Changed(); } }

        // ---------- tasks ----------
        public double TaskValue(TaskDef t)
        {
            switch (t.kind)
            {
                case TaskKind.DeptLevel: return s.dOpen[t.dept] ? s.dLevel[t.dept] : 0;
                case TaskKind.DeptServed: return s.served[t.dept];
                case TaskKind.Trucks: return s.trucks;
                case TaskKind.ParkLevel: return s.parkLevel;
                case TaskKind.BuildDept: return s.dOpen[t.dept] ? 1 : 0;
                case TaskKind.Star: return s.star;
                default: return s.assets;
            }
        }
        public bool TaskDone => s.task < T.Tasks.Length && TaskValue(T.Tasks[s.task]) >= T.Tasks[s.task].need;
        public bool TaskClaim()
        {
            if (!TaskDone) return false;
            var t = T.Tasks[s.task]; s.task++; Earn(t.coin); s.gem += t.gem; Changed(); return true;
        }

        // ---------- timed rewards ----------
        public double TruckReward() => EarnPerMin * (0.1 + 0.3 * rng.NextDouble()) * (1 + EpicAdd(EpicKind.Truck));
        public double CollectTruck() { if (!truckHere) return 0; truckHere = false; truckT = 35 + 30 * rng.NextDouble(); double r = TruckReward(); Earn(r); s.trucks++; Changed(); return r; }
        public double RollVip()
        {
            int[] w = { 60, 40, 10, 5 }; double[] k = { 1, 10, 50, 300 };
            int roll = rng.Next(115), i = 0; while (i < 3 && roll >= w[i]) { roll -= w[i]; i++; }
            return EarnPerMin * (0.8 + (k[i] - 0.8) * rng.NextDouble());
        }
        public void DismissVip() { vipHere = false; vipT = 150 + 60 * rng.NextDouble(); }
        public double CollectVip() { if (!vipHere) return 0; double r = vipReward; DismissVip(); Earn(r); Changed(); return r; }
        public int AcceptBus() { busOffer = false; int n = 10 + rng.Next(40); busPending += n; return n; }
        public void StartQuickBuy() { quickBuyOffer = false; s.quickBuyEnd = Now() + T.QuickBuySecs; Changed(); }
        public void StartQuickCheck() { quickCheckOffer = false; s.quickCheckEnd = Now() + T.QuickCheckSecs; Changed(); }
        public bool CanAdBoost => s.adEnd - Now() <= AdBoostCap - T.AdBoostStep;
        public bool AdBoost()
        {
            if (!CanAdBoost) return false;
            s.adEnd = Math.Max(s.adEnd, Now()) + T.AdBoostStep; Changed(); return true;
        }
        public double GiftReward() => EarnPerMin * OpenDepts;
        public double CollectGift(Cust c) { if (!c.gift) return 0; c.gift = false; double r = GiftReward(); Earn(r); return r; }
        /// Income for `secs` of an idle store; used for offline pay and time-skip items.
        public double IdleIncome(double secs) => FlowPerMin / 60 * Math.Max(0, secs);
        public double OfflineReward(double now)
        {
            double away = now - s.lastSeen;
            if (s.lastSeen <= 0 || s.parkLevel <= 1 || away < T.OfflineMinAway) return 0;   // a clock set backwards gives a negative gap and pays nothing
            return IdleIncome(Math.Min(OfflineCap, away));
        }
        public bool DailyLogin(int day) { if (day <= s.loginDay) return false; s.loginDay = day; s.gem += T.LoginGems; Changed(); return true; }

        // ---------- shoppers ----------
        int FreeSlot() { int n = ParkSpaces; for (int i = 0; i < n; i++) if (!slotUsed[i]) return i; return -1; }
        public bool MarketFull() { for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0 && cq[c].Count < T.CashQueueMax) return false; return true; }

        List<int> MakePlan()
        {
            var open = new List<int>(); for (int d = 0; d < T.ND; d++) if (s.dOpen[d]) open.Add(d);
            for (int i = open.Count - 1; i > 0; i--) { int j = rng.Next(i + 1); int tmp = open[i]; open[i] = open[j]; open[j] = tmp; }
            var plan = new List<int>(); foreach (int d in open) if (rng.Next(100) < T.Visit[d]) plan.Add(d);
            if (plan.Count == 0) plan.Add(open[0]);
            return plan;
        }

        void Spawn(bool byBus)
        {
            int slot = -1;
            if (!byBus) { slot = FreeSlot(); if (slot < 0) return; slotUsed[slot] = true; }
            var c = new Cust { id = nextId++, slot = slot, look = rng.Next(1000), plan = MakePlan() };
            c.st = byBus ? CS.WalkIn : CS.CarIn; c.dur = byBus ? 3f : 2.6f;
            custs.Add(c);
        }

        void NextStop(Cust c)
        {
            c.dept = -1; c.staff = -1;
            while (c.plan.Count > 0)
            {
                int d = c.plan[0]; c.plan.RemoveAt(0);
                int best = -1;
                for (int k = 0; k < s.dStaff[d]; k++) if (dq[d][k].Count < T.MaxQueue && (best < 0 || dq[d][k].Count < dq[d][best].Count)) best = k;
                if (best < 0) continue;                       // every line is full: skip this department
                c.dept = d; c.staff = best; dq[d][best].Add(c);
                c.st = CS.ToDept; c.t = 0; c.dur = (float)(2.2 / WalkMult); return;
            }
            int bc = -1;
            for (int k = 0; k < T.NC; k++) if (s.cLevel[k] > 0 && (bc < 0 || cq[k].Count < cq[bc].Count)) bc = k;
            c.cash = bc; cq[bc].Add(c);
            c.st = CS.ToCash; c.t = 0; c.dur = (float)(2.4 / WalkMult);
        }

        public void Tick(double dt)
        {
            if (dt <= 0) return; if (dt > 0.25) dt = 0.25;
            s.played += dt;
            // arrivals
            spawnT += dt; double gap = 60.0 / Arrivals;
            if (spawnT >= gap) { spawnT = 0; if (!MarketFull()) Spawn(false); }
            if (busPending > 0 && rng.NextDouble() < dt / 0.3) { busPending--; Spawn(true); }
            // side events
            if (!truckHere) { truckT -= dt; if (truckT <= 0) truckHere = true; }
            if (!vipHere) { vipT -= dt; if (vipT <= 0) { vipHere = true; vipReward = RollVip(); } }
            if (!busOffer) { busT -= dt; if (busT <= 0) { busOffer = true; busT = 200 + 80 * rng.NextDouble(); } }
            if (!quickBuyOffer && !QuickBuy) { qbT -= dt; if (qbT <= 0) { quickBuyOffer = true; qbT = 180 + 60 * rng.NextDouble(); } }
            if (!quickCheckOffer && !QuickCheck) { qcT -= dt; if (qcT <= 0) { quickCheckOffer = true; qcT = 220 + 60 * rng.NextDouble(); } }
            giftT += dt;
            if (giftT >= 60 && custs.Count > 0) { giftT = 0; var g = custs[rng.Next(custs.Count)]; if (g.st != CS.CarIn && g.st != CS.CarOut) g.gift = true; }

            for (int i = custs.Count - 1; i >= 0; i--)
            {
                var c = custs[i]; c.t += (float)dt;
                switch (c.st)
                {
                    case CS.CarIn: if (c.t >= c.dur) { c.st = CS.WalkIn; c.t = 0; c.dur = (float)(3.0 / WalkMult); } break;
                    case CS.WalkIn: if (c.t >= c.dur) NextStop(c); break;
                    case CS.ToDept: if (c.t >= c.dur) { c.st = CS.Queue; c.t = 0; } break;
                    case CS.Queue:
                        if (dq[c.dept][c.staff][0] == c) { c.st = CS.Served; c.t = 0; c.dur = (float)ServiceSecs(c.dept); }
                        break;
                    case CS.Served:
                        if (c.t >= c.dur)
                        {
                            int d = c.dept; double p = Price(d);
                            dq[d][c.staff].Remove(c); c.bill += p; s.served[d]++;
                            OnServed?.Invoke(c, d, p); NextStop(c);
                        }
                        break;
                    case CS.ToCash: if (c.t >= c.dur) { c.st = CS.CashQueue; c.t = 0; } break;
                    case CS.CashQueue:
                        if (cq[c.cash][0] == c) { c.st = CS.Paying; c.t = 0; c.dur = (float)CashSecs(c.cash); }
                        break;
                    case CS.Paying:
                        if (c.t >= c.dur)
                        {
                            cq[c.cash].Remove(c); Earn(c.bill); OnPaid?.Invoke(c, c.bill);
                            c.st = CS.WalkOut; c.t = 0; c.dur = (float)(3.0 / WalkMult);
                        }
                        break;
                    case CS.WalkOut:
                        if (c.t >= c.dur) { if (c.slot < 0) { c.st = CS.Done; } else { c.st = CS.CarOut; c.t = 0; c.dur = 2.6f; } }
                        break;
                    case CS.CarOut: if (c.t >= c.dur) c.st = CS.Done; break;
                }
                if (c.st == CS.Done) { if (c.slot >= 0) slotUsed[c.slot] = false; custs.RemoveAt(i); }
            }
        }
    }
}
