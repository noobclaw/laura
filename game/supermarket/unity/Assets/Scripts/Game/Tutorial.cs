// First-steps guide: five things to do, each shown with a pointer and one line of text.
using Souq.Core;
using UnityEngine;

namespace Souq
{
    public class Tutorial
    {
        public const int Done = 99;
        readonly Game g; bool entered; int mark; float stepT;
        public bool force;                                 // lets the screenshot run show the guide
        public Tutorial(Game game) { g = game; }
        public bool Active => g.sim.s.tut < Done && (!g.editor || force);

        void Next() { g.sim.s.tut++; entered = false; stepT = 0; g.ui.TutHide(); g.audio.Play("pop"); g.SaveNow(); }
        void Point(Vector2 at, string key) { g.ui.TutPoint(at, key); }

        public void Tick(float dt)
        {
            if (!Active) return; var s = g.sim.s; var ui = g.ui; stepT += dt;
            if (ui.PopupOpen || ui.ShutterOn) { ui.TutHide(); return; }
            Vector2 produce = ui.ToCanvas(World.DeptFx(0));
            switch (s.tut)
            {
                case 0:     // open the first department
                    if (ui.openDept == 0) { Next(); break; }
                    if (ui.Busy) { ui.TutHide(); break; }
                    Point(produce, "tut1"); break;
                case 1:     // upgrade it a few times
                    if (!entered) { entered = true; mark = s.dLevel[0]; }
                    if (s.dLevel[0] >= mark + 8 || s.dLevel[0] >= 12) { ui.CloseSheet(); Next(); break; }
                    if (ui.openDept == 0 && ui.upRt != null) Point(ui.CanvasPosOf(ui.upRt), "tut2"); else if (!ui.Busy) Point(produce, "tut1"); else ui.TutHide();
                    break;
                case 2:     // collect a delivery
                    if (!entered) { entered = true; mark = s.trucks; g.sim.truckHere = true; g.Glide(new Vector3(0, 0, 5), g.zoom, 0.7f); }
                    if (s.trucks > mark) { Next(); break; }
                    if (!g.sim.truckHere) g.sim.truckHere = true;
                    if (ui.Busy) { ui.TutHide(); break; }
                    Point(ui.ToCanvas(g.world.truckPos + Vector3.up * 1.6f), "tut3"); break;
                case 3:     // make room for more cars
                    if (!entered) { entered = true; mark = s.parkLevel; }
                    if (s.parkLevel > mark || s.parkLevel >= T.ParkMax || (stepT > 25 && s.coin < g.sim.ParkCost())) { ui.CloseSheet(); Next(); break; }
                    if (ui.parkRt != null) Point(ui.CanvasPosOf(ui.parkRt), "tut4"); else if (!ui.Busy) Point(ui.CanvasPosOf(ui.navRt[1]), "tut4"); else ui.TutHide();
                    break;
                case 4:     // the next goal: a second department
                    if (!entered) { entered = true; g.Glide(new Vector3(0, 0, 8), g.zoom, 0.7f); }
                    if (s.dOpen[1]) { Finish(); break; }
                    if (ui.Busy || stepT > 9) { ui.TutHide(); break; }
                    Point(ui.ToCanvas(World.DeptFx(1)), "tut5"); break;
                default: Finish(); break;
            }
        }

        void Finish()
        {
            var s = g.sim.s; s.tut = Done; g.ui.TutHide(); g.sim.AddGems(20);
            g.ui.Toast(Loc.G("tutdone")); g.ui.Confetti(new Vector2(g.ui.root.rect.width / 2, g.ui.root.rect.height * 0.6f), 50); g.ui.FlyIcons(Spr.Gem, new Vector2(g.ui.root.rect.width / 2, g.ui.root.rect.height * 0.5f), g.ui.gemPill, 8);
            g.audio.Play("win"); g.SaveNow();
        }
    }
}
