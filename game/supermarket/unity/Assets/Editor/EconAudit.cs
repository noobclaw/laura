// Plays three weeks of the real rule core (Souq.Core.Sim) at the speed of whole minutes and checks the numbers against our rules.
// Three players: one who never watches ads, one who watches them, one who always buys the cheapest thing.
// Writes econ.md next to the screenshots. Thresholds are the ones agreed for the 1000-level economy (2026-11-23).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using Souq.Core;

public static class EconAudit
{
    const int Days = 30, Session = 90;           // minutes played per day
    class Run
    {
        public string name; public Save s; public Sim sim; public double clock = 1e9;
        public List<string> events = new List<string>(); public double[] openDay = new double[T.ND]; public double[] starDay = new double[16];
        public double maxPrice, maxCoin; public int buys, useless; public List<double> best = new List<double>(), paid = new List<double>(); public double maxWait, maxHour = 1, maxJump = 1; public string hourWhere = ""; public Dictionary<string, int> hourBuys = new Dictionary<string, int>(), worstBuys = new Dictionary<string, int>();
        public List<double> sessionGrowth = new List<double>(); public int freeGems; public double[] servedAcc = new double[T.ND];
        public string end;
    }

    static double Flow(Sim m) => m.FlowPerMin;

    // ---------- what each purchase does to the store, measured by doing it and undoing it ----------
    enum K { Build, Star, Level, Hire, Speed, AdBundle, Park, CashOpen, CashUp }
    struct Opt { public K k; public int i; public double cost; }
    static List<Opt> Options(Sim m)
    {
        var s = m.s; var o = new List<Opt>();
        int nx = -1; for (int d = 0; d < T.ND; d++) if (!s.dOpen[d]) { nx = d; break; }
        if (nx >= 0) o.Add(new Opt { k = K.Build, i = nx, cost = T.Build[nx] });
        if (s.star + 1 < T.StarCost.Length) o.Add(new Opt { k = K.Star, cost = m.StarCost() });
        for (int d = 0; d < T.ND; d++)
        {
            if (!s.dOpen[d]) continue;
            if (s.dLevel[d] < T.MaxLevel) o.Add(new Opt { k = K.Level, i = d, cost = m.LevelCost(d) });
            if (s.dStaff[d] < T.MaxStaff) o.Add(new Opt { k = K.Hire, i = d, cost = m.HireCost(d) });
            if (s.dSpeed[d] < T.ProdMax) o.Add(new Opt { k = K.Speed, i = d, cost = m.ProdCost(d) });
        }
        if (s.adLevel < T.AdLevelMax) o.Add(new Opt { k = K.AdBundle, cost = 0 });
        if (s.parkLevel < T.ParkMax) o.Add(new Opt { k = K.Park, cost = m.ParkCost() });
        if (m.CashOpen < T.NC) o.Add(new Opt { k = K.CashOpen, cost = m.CashHireCost() });
        for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0 && s.cLevel[c] < T.CashLevelMax) o.Add(new Opt { k = K.CashUp, i = c, cost = m.CashUpCost(c) });
        return o;
    }
    static void Apply(Sim m, K k, int i, int sign)
    {
        var s = m.s;
        switch (k)
        {
            case K.Build: s.dOpen[i] = sign > 0; break;
            case K.Star: s.star += sign; break;
            case K.Level: s.dLevel[i] += sign; break;
            case K.Hire: s.dStaff[i] += sign; break;
            case K.Speed: s.dSpeed[i] += sign; break;
            case K.Park: s.parkLevel += sign; break;
            case K.CashUp: s.cLevel[i] += sign; break;
            case K.CashOpen:
                if (sign > 0) { for (int c = 0; c < T.NC; c++) if (s.cLevel[c] == 0) { s.cLevel[c] = 1; break; } }
                else { for (int c = T.NC - 1; c >= 0; c--) if (s.cLevel[c] > 0) { s.cLevel[c] = 0; break; } }
                break;
        }
    }
    /// One more advert level plus the parking and checkout room it needs to pay off; returns gain and total price.
    static double Bundle(Sim m, out double cost, bool keep)
    {
        var s = m.s; double f0 = Flow(m); var done = new List<(K, int)>();
        cost = m.AdLevelCost(); s.adLevel++;
        for (int g = 0; g < 40; g++)
        {
            if (m.ParkSpaces / T.StayMin < m.Arrivals && s.parkLevel < T.ParkMax) { cost += m.ParkCost(); s.parkLevel++; done.Add((K.Park, 0)); continue; }
            double cash = 0; for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0) cash += m.CashSpeed(c);
            if (cash < m.ParkedArrivals)
            {
                double bestC = m.CashOpen < T.NC ? m.CashHireCost() : double.PositiveInfinity; int which = -1;
                for (int c = 0; c < T.NC; c++) if (s.cLevel[c] > 0 && s.cLevel[c] < T.CashLevelMax && m.CashUpCost(c) < bestC) { bestC = m.CashUpCost(c); which = c; }
                if (!double.IsInfinity(bestC)) { cost += bestC; if (which < 0) { Apply(m, K.CashOpen, 0, 1); done.Add((K.CashOpen, 0)); } else { s.cLevel[which]++; done.Add((K.CashUp, which)); } continue; }
            }
            break;
        }
        double gain = Flow(m) - f0;
        if (!keep) { for (int j = done.Count - 1; j >= 0; j--) Apply(m, done[j].Item1, done[j].Item2, -1); s.adLevel--; }
        return gain;
    }
    static double Gain(Sim m, Opt o, out double cost)
    {
        cost = o.cost;
        if (o.k == K.AdBundle) return Bundle(m, out cost, false);
        double f0 = Flow(m); Apply(m, o.k, o.i, 1); double g = Flow(m) - f0; Apply(m, o.k, o.i, -1);
        if (o.k == K.Build) g = Math.Max(g, T.BasePrice[o.i] * m.ProfitMult * 0.5);
        return g;
    }
    static bool Buy(Sim m, Opt o)
    {
        switch (o.k)
        {
            case K.Build: return m.BuildDept(o.i);
            case K.Star: return m.StarUp();
            case K.Level: return m.LevelUp(o.i);
            case K.Hire: return m.Hire(o.i);
            case K.Speed: return m.ProdUp(o.i);
            case K.Park: return m.ParkUp();
            case K.CashOpen: return m.CashHire();
            case K.CashUp: return m.CashUp(o.i);
            case K.AdBundle:
                { double c; Bundle(m, out c, false); if (m.s.coin < c) return false; double c2; Bundle(m, out c2, true); m.s.coin -= c2; return true; }
        }
        return false;
    }

    // ---------- one player ----------
    static Run Play(string name, bool ads, bool cheap)
    {
        var r = new Run { name = name, s = Save.Fresh() }; r.sim = new Sim(r.s, () => r.clock); var m = r.sim; var s = r.s;
        s.tut = 99; for (int d = 0; d < T.ND; d++) r.openDay[d] = d == 0 ? 0 : -1; for (int k = 0; k < r.starDay.Length; k++) r.starDay[k] = -1;
        double minute = 0; double truckT = 0;
        for (int day = 0; day < Days; day++)
        {
            m.DailyLogin(day + 1);
            if (day > 0 && s.parkLevel > 1) { double off = m.OfflineReward(r.clock) * (ads ? 2 : 1); m.Earn(off); }
            double startFlow = Flow(m); double lastBuy = 0, hourFlow = startFlow;
            if (ads) s.adEnd = r.clock + Session * 60;                     // keeps the x2 campaign running while playing
            for (int t = 0; t < Session; t++)
            {
                double f = Flow(m); m.Earn(f); r.clock += 60; minute++; truckT += 1;
                while (truckT >= 50 / 60.0) { truckT -= 50 / 60.0; m.truckHere = true; m.CollectTruck(); }
                // shoppers served, for goals that count them
                double a = m.ParkedArrivals;
                for (int d = 0; d < T.ND; d++) if (s.dOpen[d]) { r.servedAcc[d] += Math.Min(m.DeptSpeed(d), a * T.Visit[d] / 100.0); int n = (int)r.servedAcc[d]; s.served[d] += n; r.servedAcc[d] -= n; }
                while (m.TaskDone) { r.freeGems += T.Tasks[s.task].gem; m.TaskClaim(); }
                SpendGems(m);
                int bought = Spend(r, cheap, day, t);
                if (bought > 0) lastBuy = t;
                // rules measured every minute of play
                double bestPb = double.PositiveInfinity, cheapest = double.PositiveInfinity; f = Flow(m);
                foreach (var o in Options(m)) { double c; double g = Gain(m, o, out c); if (g > 0) { bestPb = Math.Min(bestPb, c / g); cheapest = Math.Min(cheapest, c); } }
                r.best.Add(bestPb);
                if (day < 10) r.maxWait = Math.Max(r.maxWait, Math.Max(0, (cheapest - s.coin) / Math.Max(f, 1e-9)));
                if (t % 60 == 59) { double hg = f / Math.Max(hourFlow, 1e-9); if (day >= 3 && hg > r.maxHour) { r.maxHour = hg; r.hourWhere = "day " + (day + 1) + " minute " + (t + 1); r.worstBuys = new Dictionary<string, int>(r.hourBuys); } hourFlow = f; r.hourBuys.Clear(); }
                r.maxCoin = Math.Max(r.maxCoin, s.coin);
            }
            r.sessionGrowth.Add(Flow(m) / Math.Max(startFlow, 1e-9));
            s.lastSeen = r.clock; r.clock += (24 * 60 - Session) * 60;
        }
        r.freeGems += 100 * Days;
        r.end = "levels " + string.Join(",", s.dLevel) + " staff " + string.Join(",", s.dStaff) + " speed " + string.Join(",", s.dSpeed) + " ad " + s.adLevel + " park " + s.parkLevel + " checkouts " + string.Join(",", s.cLevel) + " grade " + s.star + " income/min " + Souq.Loc.Num(Flow(m)) + " coins " + Souq.Loc.Num(s.coin);
        return r;
    }
    static void SpendGems(Sim m)
    {
        for (int g = 0; g < 50; g++)
        {
            int best = -1; double bestV = 0; double f0 = Flow(m);
            for (int i = 0; i < T.Epics.Length; i++)
            {
                if (!m.EpicAvailable(i) || m.s.gem < m.EpicCost(i)) continue;
                m.s.epic[i]++; double v = (Flow(m) - f0) / m.EpicCost(i); m.s.epic[i]--;
                if (T.Epics[i].kind != EpicKind.Profit && T.Epics[i].kind != EpicKind.Manager) v = Math.Max(v, 1e-12 * f0 / m.EpicCost(i));
                if (v > bestV) { bestV = v; best = i; }
            }
            if (best < 0 || !m.EpicUp(best)) return;
        }
    }
    static int Spend(Run r, bool cheap, int day, int t)
    {
        var m = r.sim; var s = r.s; int n = 0;
        for (int guard = 0; guard < 400; guard++)
        {
            var ops = Options(m); double f = Flow(m);
            Opt pick = default; bool have = false; double pickPb = 0;
            if (cheap)
            {
                double c0 = double.PositiveInfinity;
                foreach (var o in ops) { double c = o.cost; if (o.k == K.AdBundle) Bundle(m, out c, false); if (c <= s.coin && c < c0) { c0 = c; pick = o; have = true; } }
            }
            else
            {
                double bestPb = double.PositiveInfinity, affPb = double.PositiveInfinity; Opt best = default, aff = default; double bestCost = 0;
                foreach (var o in ops)
                {
                    double c; double g = Gain(m, o, out c); if (g <= 0) continue; double pb = c / g;
                    if (pb < bestPb) { bestPb = pb; best = o; bestCost = c; }
                    if (c <= s.coin && pb < affPb) { affPb = pb; aff = o; }
                }
                if (double.IsInfinity(affPb)) break;
                if (bestCost <= s.coin) { pick = best; pickPb = bestPb; have = true; }
                else { double wait = (bestCost - s.coin) / Math.Max(f, 1e-9); if (affPb <= Math.Max(30, wait)) { pick = aff; pickPb = affPb; have = true; } }
            }
            if (!have) break;
            double before = f, cc; double gn = Gain(m, pick, out cc);
            if (gn <= 0 && (pick.k == K.Level || pick.k == K.Hire || pick.k == K.Speed)) r.useless++;
            r.maxPrice = Math.Max(r.maxPrice, cc);
            if (!Buy(m, pick)) break;
            if (!cheap && gn > 0) r.paid.Add(cc / gn);
            n++; r.buys++; string kk = pick.k.ToString(); r.hourBuys[kk] = (r.hourBuys.TryGetValue(kk, out int hv) ? hv : 0) + 1;
            double after = Flow(m); if (pick.k != K.Build && before > 0) r.maxJump = Math.Max(r.maxJump, after / before);
            double dayF = day + t / (double)Session;
            if (pick.k == K.Build) { r.openDay[pick.i] = dayF; r.events.Add("open " + pick.i + " day " + (day + 1) + " +" + t + "m"); }
            if (pick.k == K.Star) { r.starDay[s.star] = dayF; r.events.Add("grade " + s.star + " day " + (day + 1) + " +" + t + "m"); }
        }
        return n;
    }

    // ---------- report ----------
    public static string Report()
    {
        var sb = new StringBuilder(); int fails = 0;
        Action<bool, string> rule = (ok, text) => { if (!ok) fails++; sb.AppendLine((ok ? "- PASS " : "- FAIL ") + text); };
        // static: every price at level 1000 and every table entry stays under the ceiling
        double top = 0; var probe = new Sim(Save.Fresh(), () => 0);
        for (int d = 0; d < T.ND; d++) top = Math.Max(top, probe.LevelCostAt(d, T.MaxLevel - 1));
        foreach (var x in T.StarCost) top = Math.Max(top, x); foreach (var x in T.Build) top = Math.Max(top, x);
        for (int d = 0; d < T.ND; d++) top = Math.Max(top, T.HireBase(d, 4)); for (int d = 0; d < T.ND; d++) top = Math.Max(top, T.ProdCostAt(d, T.ProdMax - 1));
        double epicTotal = 0; foreach (var e in T.Epics) epicTotal += e.cost * e.max * (e.max + 1) / 2.0;

        var runs = new[] { Play("no ads", false, false), Play("watches ads", true, false), Play("buys cheapest", false, true) };
        sb.AppendLine("# Economy audit (" + Days + " days, " + Session + " min a day)\n");
        sb.AppendLine("Highest price anywhere in the tables: " + Souq.Loc.Num(top) + " (ceiling " + Souq.Loc.Num(T.PriceCeiling) + ")\n");
        foreach (var r in runs)
        {
            sb.AppendLine("## " + r.name);
            sb.AppendLine("Sections opened (day): " + string.Join("  ", Enumerable(r.openDay, 1)));
            sb.AppendLine("Grades reached (day): " + string.Join("  ", Enumerable(r.starDay, 1)));
            r.best.Sort(); double med = r.best[r.best.Count / 2], p90 = r.best[(int)(r.best.Count * 0.9)];
            r.paid.Sort(); double pmed = r.paid.Count > 0 ? r.paid[r.paid.Count / 2] : 0, p90b = r.paid.Count > 0 ? r.paid[(int)(r.paid.Count * 0.9)] : 0;
            sb.AppendLine("Payback of what this player bought: median " + pmed.ToString("0") + " min, 90% " + p90b.ToString("0") + " min");
            sb.AppendLine("Best payback still on offer after buying (info): median " + med.ToString("0") + " min, 90% " + p90.ToString("0") + " min");
            sb.AppendLine("Income growth inside each day's session: " + string.Join(" ", r.sessionGrowth.ConvertAll(x => "x" + x.ToString("0.0#"))));
            sb.AppendLine("End: " + r.end);
            sb.AppendLine("Free gems in " + Days + " days: " + r.freeGems + " of " + epicTotal + " for every boost (" + (100.0 * r.freeGems / epicTotal).ToString("0") + "%)\n");
            if (r.name == "buys cheapest") { rule(r.useless <= r.buys * 0.1, "R2 purchases that change nothing: " + r.useless + " of " + r.buys + " (limit 10%)"); continue; }
            rule(r.maxPrice <= T.PriceCeiling * 1.0001 && top <= T.PriceCeiling * 1.0001, "R1 highest price paid " + Souq.Loc.Num(r.maxPrice) + ", wallet peak " + Souq.Loc.Num(r.maxCoin) + " (limit " + Souq.Loc.Num(T.PriceCeiling) + " for prices)");
            rule(pmed <= 180, "R3 purchases pay for themselves in a median " + pmed.ToString("0") + " min of income (limit 180)");
            int flat = 0; for (int i = 0; i < Math.Min(14, r.sessionGrowth.Count); i++) if (r.sessionGrowth[i] < 1.1) flat++;
            rule(flat <= 2, "R3b sessions in the first 14 days where income grew less than 10%: " + flat + " (limit 2)");
            rule(r.maxWait <= 5, "R4 longest wait for anything useful in the first 10 days: " + r.maxWait.ToString("0.0") + " min (limit 5)");
            double last = r.openDay[T.ND - 1]; bool smooth = true; string gaps = "";
            for (int d = 4; d < T.ND; d++) { double g0 = r.openDay[d - 1] - r.openDay[d - 2], g1 = r.openDay[d] - r.openDay[d - 1]; gaps += g1.ToString("0.0") + " "; if (r.openDay[d] < 0 || (g0 > 0.3 && (g1 > 3 * g0 + 0.5 || g1 < g0 / 3 - 0.5))) smooth = false; }
            rule(last >= 0 && (r.name == "no ads" ? last >= 13 && last <= 21 : last >= 8.5 && last <= 21), "R5 all 11 sections open on day " + (last < 0 ? "never" : (last + 1).ToString("0.0")) + (r.name == "no ads" ? " (target day 14-21)" : " (target day 9.5-21)"));
            rule(smooth, "R5b gaps between openings (days): " + gaps + "(no gap more than 3x the one before)");
            rule(r.maxHour <= 10 && r.maxJump <= 3, "R6 fastest hour of play from day 4 on x" + r.maxHour.ToString("0.0") + " (limit 10) at " + r.hourWhere + ", bought then: " + string.Join(", ", new List<string>(Pairs(r.worstBuys))) + "; biggest single purchase x" + r.maxJump.ToString("0.00") + " (limit 3)");
            rule(r.freeGems >= epicTotal * 0.1 && r.freeGems <= epicTotal * 0.5, "R7 free gems cover " + (100.0 * r.freeGems / epicTotal).ToString("0") + "% of all boosts in 30 days (target 10-50%)");
            sb.AppendLine("Events: " + string.Join("; ", r.events) + "\n");
        }
        sb.Insert(0, "RESULT: " + (fails == 0 ? "all rules pass" : fails + " rule(s) fail") + "\n\n");
        return sb.ToString();
    }
    static IEnumerable<string> Pairs(Dictionary<string, int> d) { foreach (var kv in d) yield return kv.Key + " " + kv.Value; }
    static IEnumerable<string> Enumerable(double[] a, int from) { for (int i = from; i < a.Length; i++) yield return a[i] < 0 ? "-" : (a[i] + 1).ToString("0.0"); }

    public static void RunAndWrite(string dir)
    {
        var t0 = DateTime.Now; string rep;
        try { rep = Report(); } catch (Exception e) { rep = "EconAudit crashed: " + e; }
        Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir, "econ.md"), rep);
        foreach (var line in rep.Split('\n')) if (line.Trim().Length > 0) Debug.Log("ECON " + line);
        Debug.Log("ECON took " + (DateTime.Now - t0).TotalSeconds.ToString("0") + " s");
    }
}
