// Number tables. The rule shapes follow game/supermarket/SPEC.md §8; every value here is our own.
using System;

namespace Souq.Core
{
    public enum EpicKind { Profit, Walk, Manager, Truck, CashierSpeed, StaffCost, CashierCost, AdTime, Research }

    public struct EpicDef { public EpicKind kind; public int dept; public double add; public int cost; public int max; }

    public enum TaskKind { DeptLevel, DeptServed, Trucks, ParkLevel, BuildDept, Star, Assets }

    public struct TaskDef { public TaskKind kind; public int dept; public double need; public double coin; public int gem; }

    public static class T
    {
        public const int ND = 11, NC = 8, MaxStaff = 5, MaxQueue = 4, CashQueueMax = 12;
        public const int MaxLevel = 300, ProdMax = 40, CashLevelMax = 50, AdLevelMax = 100;

        public static readonly string[] DeptKey = { "produce", "bakery", "butcher", "seafood", "spices", "fashion", "fragrance", "electronics", "phones", "jewellery", "cars" };
        // Sized so nothing in the game needs a number past the trillions (2026-11-23 rebalance; model in game/supermarket/econ/model.py).
        public static readonly double[] Build = { 0, 2e3, 4e4, 4e5, 2.5e6, 1.5e7, 8e7, 5e8, 2e9, 1e10, 5e10 };
        public static readonly double[] BasePrice = { 2, 8, 50, 150, 800, 5e3, 2.5e4, 8e4, 2e5, 8e5, 2e6 };
        public static readonly double[] UpBase = { 2, 15, 60, 200, 600, 2e3, 5e3, 1.5e4, 4e4, 1.2e5, 3e5 };
        public static readonly double[] UpRate = { 1.045, 1.045, 1.045, 1.045, 1.045, 1.045, 1.045, 1.045, 1.045, 1.045, 1.045 };
        public static readonly double[] SpeedBase = { 28, 19, 8, 6, 3, 1.2, 0.6, 0.5, 0.4, 0.32, 0.25 };   // customers per minute, per staff
        public static readonly int[] Visit = { 90, 90, 85, 70, 60, 50, 40, 30, 20, 12, 6 };                 // % chance a shopper plans a stop

        public static readonly int[] TierLv = { 25, 50, 100, 150, 200, 300 };
        public static readonly double[] TierMul = { 1.5, 1.5, 1.5, 1.5, 1.5, 1.5 };

        public static double PriceStep(int d) => BasePrice[d] * 0.08;
        public static double SpeedStep(int d) => SpeedBase[d] * 0.05;
        public static double ProdBase(int d) => UpBase[d] * 20;
        public static double ProdRate(int d) => 1.12;
        /// Price to hire staff number `have + 1` (have = 1..4).
        public static double HireBase(int d, int have)
        {
            double first = d == 0 ? 200 : Build[d] * 0.5;
            return first * Math.Pow(5, have - 1);
        }
        public static int Tier(int level) { int k = 0; while (k < TierLv.Length && level >= TierLv[k]) k++; return k; }
        public static double TierProduct(int level) { double m = 1; for (int k = 0; k < TierLv.Length && level >= TierLv[k]; k++) m *= TierMul[k]; return m; }

        // checkouts
        public static readonly double[] CashHire = { 0, 150, 2e3, 5e4, 2e6, 5e7, 1e9, 2e10 };      // price to open checkout k (0-based)
        public static readonly double[] CashUpBase = { 6, 6, 18, 300, 1500, 3000, 12000, 12000 };
        public static readonly double[] CashUpRate = { 1.2, 1.2, 1.22, 1.24, 1.25, 1.26, 1.27, 1.28 };
        public static readonly double[] CashSpeedBase = { 5, 5, 7, 8, 10, 12, 14, 14 };                 // customers per minute
        public static readonly double[] CashSpeedStep = { .1, .1, .1, .1, .2, .2, .24, .28 };

        // parking: index = current level - 1, value = price of the next level
        public static readonly double[] ParkCost = { 60, 250, 1e3, 4e3, 1.5e4, 6e4, 2.5e5, 1e6, 4e6, 1.5e7, 5e7, 1.5e8, 5e8, 1.5e9, 5e9, 1.5e10, 4e10, 1e11, 2.5e11, 6e11, 1.5e12, 4e12 };
        public static int ParkMax => ParkCost.Length + 1;

        // store grades: profit multiplier is the value itself, not a running product
        public static readonly double[] StarCost = { 0, 2e6, 1.2e7, 6e7, 2.5e8, 1e9, 4e9, 1.2e10, 3e10, 8e10, 2e11, 4e11, 8e11, 1.5e12, 3e12, 5e12 };
        public static readonly double[] StarProfit = { 1, 1.5, 2, 2.5, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20 };

        public static readonly EpicDef[] Epics = MakeEpics();
        static EpicDef[] MakeEpics()
        {
            var l = new System.Collections.Generic.List<EpicDef>();
            l.Add(new EpicDef { kind = EpicKind.Profit, dept = -1, add = 0.25, cost = 150, max = 20 });
            l.Add(new EpicDef { kind = EpicKind.Walk, dept = -1, add = 0.05, cost = 20, max = 10 });
            for (int d = 0; d < ND; d++) l.Add(new EpicDef { kind = EpicKind.Manager, dept = d, add = 0.5, cost = 100 * (d + 1), max = 1 });
            l.Add(new EpicDef { kind = EpicKind.Truck, dept = -1, add = 0.5, cost = 30, max = 20 });
            l.Add(new EpicDef { kind = EpicKind.CashierSpeed, dept = -1, add = 0.05, cost = 25, max = 10 });
            l.Add(new EpicDef { kind = EpicKind.StaffCost, dept = -1, add = 0.02, cost = 15, max = 20 });
            l.Add(new EpicDef { kind = EpicKind.CashierCost, dept = -1, add = 0.02, cost = 15, max = 20 });
            l.Add(new EpicDef { kind = EpicKind.AdTime, dept = -1, add = 1800, cost = 25, max = 6 });
            for (int d = 0; d < ND; d++) l.Add(new EpicDef { kind = EpicKind.Research, dept = d, add = 0.019, cost = 5 + 3 * d, max = 50 });
            return l.ToArray();
        }

        public static readonly TaskDef[] Tasks = MakeTasks();
        static TaskDef Tk(TaskKind k, int d, double need, double coin, int gem) => new TaskDef { kind = k, dept = d, need = need, coin = coin, gem = gem };
        static TaskDef[] MakeTasks()
        {
            return new[]
            {
                Tk(TaskKind.DeptLevel, 0, 25, 150, 0), Tk(TaskKind.DeptServed, 0, 20, 0, 5), Tk(TaskKind.Trucks, -1, 5, 600, 0),
                Tk(TaskKind.ParkLevel, -1, 3, 0, 6), Tk(TaskKind.BuildDept, 1, 1, 0, 10), Tk(TaskKind.DeptLevel, 0, 50, 6e3, 0),
                Tk(TaskKind.DeptLevel, 1, 25, 0, 8), Tk(TaskKind.ParkLevel, -1, 4, 3e4, 0), Tk(TaskKind.DeptServed, 1, 50, 4e4, 0),
                Tk(TaskKind.DeptLevel, 0, 100, 0, 10), Tk(TaskKind.DeptServed, 0, 250, 0, 5), Tk(TaskKind.BuildDept, 2, 1, 0, 25),
                Tk(TaskKind.Trucks, -1, 20, 0, 20), Tk(TaskKind.DeptLevel, 2, 50, 0, 5), Tk(TaskKind.Assets, -1, 2e7, 0, 15),
                Tk(TaskKind.DeptLevel, 2, 100, 0, 10), Tk(TaskKind.DeptLevel, 1, 200, 0, 10), Tk(TaskKind.DeptLevel, 0, 200, 0, 10),
                Tk(TaskKind.BuildDept, 3, 1, 0, 25), Tk(TaskKind.Star, -1, 1, 0, 50), Tk(TaskKind.DeptLevel, 3, 200, 0, 8),
                Tk(TaskKind.DeptServed, 3, 250, 0, 5), Tk(TaskKind.BuildDept, 4, 1, 0, 25), Tk(TaskKind.DeptServed, 0, 1000, 0, 10),
                Tk(TaskKind.DeptServed, 4, 100, 0, 10), Tk(TaskKind.Trucks, -1, 50, 0, 50), Tk(TaskKind.BuildDept, 5, 1, 0, 50),
                Tk(TaskKind.Star, -1, 2, 0, 100), Tk(TaskKind.DeptLevel, 4, 300, 0, 15), Tk(TaskKind.DeptLevel, 5, 250, 0, 20),
                Tk(TaskKind.DeptLevel, 0, 300, 0, 30), Tk(TaskKind.Star, -1, 3, 0, 150), Tk(TaskKind.BuildDept, 6, 1, 0, 40),
                Tk(TaskKind.DeptLevel, 6, 200, 0, 15), Tk(TaskKind.BuildDept, 7, 1, 0, 45), Tk(TaskKind.DeptLevel, 7, 200, 0, 15),
                Tk(TaskKind.Star, -1, 4, 0, 200), Tk(TaskKind.BuildDept, 8, 1, 0, 60), Tk(TaskKind.DeptLevel, 8, 300, 0, 25),
                Tk(TaskKind.Trucks, -1, 150, 0, 80), Tk(TaskKind.BuildDept, 9, 1, 0, 80), Tk(TaskKind.Star, -1, 5, 0, 250),
                Tk(TaskKind.DeptLevel, 9, 300, 0, 30), Tk(TaskKind.BuildDept, 10, 1, 0, 100), Tk(TaskKind.Star, -1, 6, 0, 300),
            };
        }

        // paid extras (rule values; store prices live in Store.cs)
        public const int LoginGems = 100, AdGems = 30;
        public const double OfflineMinAway = 180, OfflineCap = 21600, OfflineCapPro = 43200;
        public const double AdBoostStep = 1800, AdBoostMax = 21600, QuickBuySecs = 120, QuickCheckSecs = 30;
    }
}
