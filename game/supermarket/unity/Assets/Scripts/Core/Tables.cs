// Number tables. The rule shapes follow game/supermarket/SPEC.md §8; every value here is our own.
using System;

namespace Souq.Core
{
    public enum EpicKind { Profit, Walk, Manager, Truck, CashierSpeed, StaffCost, CashierCost, AdTime, Research }   // AdTime is no longer offered (no ads)

    public struct EpicDef { public EpicKind kind; public int dept; public double add; public int cost; public int max; }

    public enum TaskKind { DeptLevel, DeptServed, Trucks, ParkLevel, BuildDept, Star, Assets }

    public struct TaskDef { public TaskKind kind; public int dept; public double need; public double coin; public int gem; }

    public static class T
    {
        // 2026-11-23: every number below is our own, tuned with game/supermarket/econ/model.py and checked by Editor/EconAudit.cs.
        public const int ND = 11, NC = 8, MaxStaff = 5, MaxQueue = 4, CashQueueMax = 12;
        public const int MaxLevel = 1000, ProdMax = 50, CashLevelMax = 40, AdLevelMax = 40;
        /// No price anywhere in the game is above this; level 1000 of every section costs about this much.
        public const double PriceCeiling = 1e18;

        public static readonly string[] DeptKey = { "produce", "bakery", "butcher", "seafood", "spices", "fashion", "fragrance", "electronics", "phones", "jewellery", "cars" };
        public static readonly double[] Build = { 0, 800, 8e3, 8e4, 6e6, 4e7, 3e8, 1.5e9, 6e9, 2.5e10, 1e11 };
        public static readonly double[] BasePrice = { 2, 9, 40, 180, 800, 3.5e3, 1.5e4, 6.5e4, 2.8e5, 1.2e6, 5e6 };
        /// Each level adds this share of the base price (+10% at level 2, so early levels are felt), on top of the level bonuses.
        public const double PriceStep = 0.1;
        public static readonly double[] UpBase = { 1.2, 5.4, 24, 108, 480, 2.1e3, 9e3, 3.9e4, 1.68e5, 7.2e5, 3e6 };
        /// Chosen so that level 1000 of each section costs PriceCeiling: UpRate = (PriceCeiling / UpBase)^(1/999).
        public static readonly double[] UpRate = { 1.04217, 1.04060, 1.03905, 1.03749, 1.03594, 1.03441, 1.03290, 1.03139, 1.02988, 1.02838, 1.02691 };
        public static readonly double[] SpeedBase = { 3.6, 3.0, 2.6, 2.4, 2.1, 1.9, 1.7, 1.5, 1.3, 1.1, 0.94 };   // shoppers served per minute by one staff member
        public static readonly int[] Visit = { 95, 80, 70, 65, 55, 50, 45, 40, 35, 30, 25 };                     // % chance a shopper plans a stop

        /// Bonus levels: big doublings early so a new section takes off, gentler x1.5 later so the numbers stay in range.
        public static readonly int[] TierLv = { 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000 };
        public static readonly double[] TierMul = { 2, 2, 2, 2, 2, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5 };

        public static double SpeedStep(int d) => SpeedBase[d] * 0.04;
        public static double ProdCostAt(int d, int n) => UpBase[d] * 10 * Math.Pow(1.15, n);
        /// Price to hire staff number `have + 1` (have = 1..4).
        public static double HireBase(int d, int have) => Math.Max(50, Build[d] * 0.3) * Math.Pow(3, have - 1);
        public static int Tier(int level) { int k = 0; while (k < TierLv.Length && level >= TierLv[k]) k++; return k; }
        public static double TierProduct(int level) { double m = 1; for (int k = 0; k < TierLv.Length && level >= TierLv[k]; k++) m *= TierMul[k]; return m; }

        // checkouts
        public static readonly double[] CashHire = { 0, 200, 2e3, 2e4, 3e5, 5e6, 1e8, 2e9 };                    // price to open checkout k (0-based)
        public static readonly double[] CashUpBase = { 10, 10, 25, 60, 150, 400, 1e3, 2.5e3 };
        public const double CashUpRate = 1.25;
        public static readonly double[] CashSpeedBase = { 7, 4, 4, 4.5, 4.5, 5, 5, 5.5 };                         // shoppers per minute
        public const double CashSpeedStep = 0.1;

        // car park and adverts
        public const int ParkPer = 6; public const double StayMin = 1.3;                                           // a car holds its bay about 1.3 minutes
        public static readonly double[] ParkCost = { 60, 150, 400, 1e3, 2.5e3, 8e3, 2e4, 5e4, 1.2e5, 3e5, 8e5, 2.5e6, 6e6, 1.5e7 };
        public static int ParkMax => ParkCost.Length + 1;
        public const double CarsBase = 6, CarsStep = 1.5, AdCostBase = 20, AdCostRate = 1.33;

        // store grades: profit multiplier is the value itself, not a running product
        public static readonly double[] StarCost = { 0, 2e7, 5e8, 5e9, 2e10, 8e10, 3e11, 1e12, 4e12, 1.5e13, 6e13, 2.5e14, 1e15, 5e15, 2.5e16, 1.5e17 };
        public static readonly double[] StarProfit = { 1, 1.5, 2, 2.6, 3.3, 4.1, 5, 6, 7.2, 8.5, 10, 12, 14, 16.5, 19, 22 };

        public static readonly EpicDef[] Epics = MakeEpics();
        static EpicDef[] MakeEpics()
        {
            var l = new System.Collections.Generic.List<EpicDef>();
            l.Add(new EpicDef { kind = EpicKind.Profit, dept = -1, add = 0.2, cost = 120, max = 15 });
            l.Add(new EpicDef { kind = EpicKind.Walk, dept = -1, add = 0.04, cost = 30, max = 10 });
            for (int d = 0; d < ND; d++) l.Add(new EpicDef { kind = EpicKind.Manager, dept = d, add = 0.5, cost = 60 * (d + 1), max = 1 });
            l.Add(new EpicDef { kind = EpicKind.Truck, dept = -1, add = 0.4, cost = 25, max = 10 });
            l.Add(new EpicDef { kind = EpicKind.CashierSpeed, dept = -1, add = 0.06, cost = 30, max = 10 });
            l.Add(new EpicDef { kind = EpicKind.StaffCost, dept = -1, add = 0.03, cost = 20, max = 10 });
            l.Add(new EpicDef { kind = EpicKind.CashierCost, dept = -1, add = 0.03, cost = 20, max = 10 });
            for (int d = 0; d < ND; d++) l.Add(new EpicDef { kind = EpicKind.Research, dept = d, add = 0.03, cost = 6 + 2 * d, max = 10 });
            return l.ToArray();
        }

        public static readonly TaskDef[] Tasks = MakeTasks();
        static TaskDef Tk(TaskKind k, int d, double need, double coin, int gem) => new TaskDef { kind = k, dept = d, need = need, coin = coin, gem = gem };
        /// Goals in order: each new section gets built, then pushed through its bonus levels; grades and side goals in between.
        static TaskDef[] MakeTasks()
        {
            var l = new System.Collections.Generic.List<TaskDef>
            {
                Tk(TaskKind.DeptLevel, 0, 10, 100, 0), Tk(TaskKind.DeptServed, 0, 15, 0, 5), Tk(TaskKind.ParkLevel, -1, 2, 0, 5),
                Tk(TaskKind.BuildDept, 1, 1, 0, 10), Tk(TaskKind.Trucks, -1, 5, 300, 0), Tk(TaskKind.DeptLevel, 0, 50, 0, 10),
                Tk(TaskKind.BuildDept, 2, 1, 0, 10), Tk(TaskKind.DeptLevel, 1, 50, 0, 10), Tk(TaskKind.Star, -1, 1, 0, 20),
                Tk(TaskKind.BuildDept, 3, 1, 0, 15), Tk(TaskKind.ParkLevel, -1, 5, 0, 10), Tk(TaskKind.DeptLevel, 0, 100, 0, 15),
                Tk(TaskKind.Trucks, -1, 30, 0, 15), Tk(TaskKind.Star, -1, 2, 0, 30), Tk(TaskKind.DeptLevel, 2, 100, 0, 15),
            };
            int[] grades = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
            int g = 0;
            for (int d = 4; d < ND; d++)
            {
                l.Add(Tk(TaskKind.BuildDept, d, 1, 0, 20 + 5 * d));
                l.Add(Tk(TaskKind.DeptLevel, d - 1, 150, 0, 15 + 2 * d));
                l.Add(Tk(TaskKind.DeptServed, d, 100, 0, 10 + d));
                l.Add(Tk(TaskKind.DeptLevel, d - 3, 250 + 25 * d, 0, 20 + 2 * d));
                l.Add(Tk(TaskKind.Star, -1, grades[g], 0, 30 + 10 * g)); g++;
                if (d % 2 == 0) l.Add(Tk(TaskKind.Trucks, -1, 30 * d, 0, 20 + 3 * d));
            }
            for (; g < grades.Length; g++)
            {
                l.Add(Tk(TaskKind.DeptLevel, ND - 1, 150 + 75 * g, 0, 40 + 5 * g));
                l.Add(Tk(TaskKind.DeptLevel, (g * 3) % ND, 500 + 40 * g, 0, 40 + 5 * g));
                l.Add(Tk(TaskKind.Star, -1, grades[g], 0, 60 + 15 * g));
            }
            for (int d = 0; d < ND; d++) l.Add(Tk(TaskKind.DeptLevel, d, 1000, 0, 150));
            return l.ToArray();
        }

        // paid extras (rule values; store prices live in Store.cs)
        public const int LoginGems = 100, AdGems = 30;
        public const double OfflineMinAway = 180, OfflineCap = 14400, OfflineCapPro = 28800, OfflineRate = 0.5;   // away pay: half speed, up to 4 h (8 h with Night Manager)
        public const double QuickBuySecs = 180, QuickCheckSecs = 120;
    }
}
