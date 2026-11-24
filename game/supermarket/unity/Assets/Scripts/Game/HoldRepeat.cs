// Press-and-hold repeat for buttons.
using System;
using UnityEngine;

namespace Souq
{
    /// Fires again and again while a button is held: slow at first, then fast.
    public class HoldRepeat : MonoBehaviour, UnityEngine.EventSystems.IPointerDownHandler, UnityEngine.EventSystems.IPointerUpHandler, UnityEngine.EventSystems.IPointerExitHandler
    {
        public Func<bool> onRepeat; bool down; float held, next;
        public void OnPointerDown(UnityEngine.EventSystems.PointerEventData e) { down = true; held = 0; next = 0.38f; }
        public void OnPointerUp(UnityEngine.EventSystems.PointerEventData e) { down = false; }
        public void OnPointerExit(UnityEngine.EventSystems.PointerEventData e) { down = false; }
        void Update()
        {
            if (!down) return; held += Time.unscaledDeltaTime; if (held < next) return;
            next = held + Mathf.Lerp(0.11f, 0.045f, Mathf.Clamp01((held - 0.38f) / 2.5f));
            if (onRepeat == null || !onRepeat()) down = false;
        }
    }
}
