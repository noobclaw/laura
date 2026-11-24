// Device entry point: creates the game, forwards touch, saves on pause.
using Souq.Core;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Souq
{
    public class App : MonoBehaviour
    {
        Game g; Vector2 downPos, lastPos; float downTime, pinch; bool down, overUi, dragged;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot() { new GameObject("App").AddComponent<App>(); }

        void Awake()
        {
            Application.targetFrameRate = 60; Screen.sleepTimeout = SleepTimeout.NeverSleep; Input.multiTouchEnabled = true;
            new GameObject("EventSystem", typeof(EventSystem), typeof(StandaloneInputModule));
            g = new Game(); g.Start(Game.LoadSave(), true);
            g.sim.DailyLogin((int)(g.Now() / 86400));
            g.Intro();
            g.store.StartIap();
            g.CheckOffline();
        }

        void OnApplicationPause(bool paused)
        {
            if (g == null) return;
            if (paused) g.SaveNow(); else if (g.pendingOffline <= 0) { g.sim.DailyLogin((int)(g.Now() / 86400)); g.CheckOffline(); }
        }
        void OnApplicationQuit() { if (g != null) g.SaveNow(); }

        void Update()
        {
            Pointer(); g.Tick(Time.unscaledDeltaTime);
        }

        void Pointer()
        {
            if (Input.touchCount >= 2)
            {
                var a = Input.GetTouch(0); var b = Input.GetTouch(1); float dist = Vector2.Distance(a.position, b.position);
                if (pinch > 0 && dist > 1 && !g.ui.Busy) g.Zoom(dist / pinch);
                pinch = dist; down = false; return;
            }
            pinch = 0;
            bool isDown, began, ended; Vector2 pos; int finger = -1;
            if (Input.touchCount == 1) { var t = Input.GetTouch(0); pos = t.position; finger = t.fingerId; began = t.phase == TouchPhase.Began; ended = t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled; isDown = !ended; }
            else { pos = Input.mousePosition; began = Input.GetMouseButtonDown(0); ended = Input.GetMouseButtonUp(0); isDown = Input.GetMouseButton(0); if (!began && !ended && !isDown) { down = false; return; } }
            if (began)
            {
                down = true; dragged = false; downPos = lastPos = pos; downTime = Time.unscaledTime;
                var es = EventSystem.current; overUi = es != null && (finger >= 0 ? es.IsPointerOverGameObject(finger) : es.IsPointerOverGameObject());
                return;
            }
            if (!down) return;
            if (isDown && !ended)
            {
                if (!overUi && !g.ui.Busy)
                {
                    if (!dragged && Vector2.Distance(pos, downPos) > Screen.height * 0.012f) dragged = true;
                    if (dragged) g.Pan(pos - lastPos);
                }
                lastPos = pos; return;
            }
            if (ended)
            {
                down = false;
                if (!overUi && !dragged && !g.ui.Busy && Time.unscaledTime - downTime < 0.5f) g.Tap(pos);
            }
        }
    }
}
