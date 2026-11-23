// Rule core: no UnityEngine types, so the server can run the same file.
// Formulas are ours (see balance/BALANCE.md). Numbers come from tables.json.
using System;

namespace Souq.Core
{
    [Serializable] public class DeptRow { public string id; public double unlockCost; public double baseIncomePerSec; public double levelCost0; }

    [Serializable] public class Params
    {
        public double levelGrowth, levelCostFrac, payback0, paybackGrowth;
        public int[] milestones;
        public double offlineRate, offlineCapSec, starCost0, starCostGrowth, starMult;
        public int starMax;
    }

    [Serializable] public class Tables { public string version; public Params @params; public DeptRow[] departments; }

    [Serializable] public class GameState
    {
        public double cash;
        public int star;
        public int[] level;          // 0 = locked
        public long lastSeenUnix;    // seconds
        public double boost = 1;     // paid / event multiplier

        public static GameState Fresh(Tables t)
        {
            var s = new GameState { level = new int[t.departments.Length] };
            s.level[0] = 1;
            return s;
        }
    }

    public static class Economy
    {
        public static double Milestone(Params p, int level)
        {
            double m = 1;
            foreach (var th in p.milestones) if (level >= th) m *= 2;
            return m;
        }

        public static double DeptIncome(Tables t, int i, int level) =>
            level <= 0 ? 0 : t.departments[i].baseIncomePerSec * level * Milestone(t.@params, level);

        /// Cost to raise department i from `level` to `level + 1`.
        public static double LevelCost(Tables t, int i, int level) =>
            t.departments[i].levelCost0 * Math.Pow(t.@params.levelGrowth, level - 1);

        public static double StarCost(Tables t, int star) =>
            t.@params.starCost0 * Math.Pow(t.@params.starCostGrowth, star);

        public static double Rate(Tables t, GameState s)
        {
            double sum = 0;
            for (int i = 0; i < s.level.Length; i++) sum += DeptIncome(t, i, s.level[i]);
            return sum * Math.Pow(t.@params.starMult, s.star) * s.boost;
        }

        public static void Tick(Tables t, GameState s, double seconds) => s.cash += Rate(t, s) * seconds;

        public static bool CanUnlock(Tables t, GameState s, int i) =>
            s.level[i] == 0 && (i == 0 || s.level[i - 1] > 0) && s.cash >= t.departments[i].unlockCost;

        public static bool Unlock(Tables t, GameState s, int i)
        {
            if (!CanUnlock(t, s, i)) return false;
            s.cash -= t.departments[i].unlockCost; s.level[i] = 1; return true;
        }

        public static bool LevelUp(Tables t, GameState s, int i)
        {
            if (s.level[i] <= 0) return false;
            double c = LevelCost(t, i, s.level[i]);
            if (s.cash < c) return false;
            s.cash -= c; s.level[i]++; return true;
        }

        public static bool StarUp(Tables t, GameState s)
        {
            if (s.star >= t.@params.starMax) return false;
            double c = StarCost(t, s.star);
            if (s.cash < c) return false;
            s.cash -= c; s.star++; return true;
        }

        /// Earnings for time away. A clock that went backwards pays nothing.
        public static double Offline(Tables t, GameState s, long nowUnix)
        {
            double away = Math.Max(0, nowUnix - s.lastSeenUnix);
            return Rate(t, s) * t.@params.offlineRate * Math.Min(away, t.@params.offlineCapSec);
        }
    }
}
