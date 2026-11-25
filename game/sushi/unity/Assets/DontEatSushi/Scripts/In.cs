// 別吃壽司 - 輸入包裝：專案裝了新版 Input System 就用新版，否則用舊版，兩邊都能編譯。
using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace DontEatSushi
{
    public enum K { W, A, S, D, Q, E, G, C, F, Z, R, Space, Shift, LeftBracket, RightBracket, Digit1, Digit2, F1, T, Minus, Equals }

    public static class In
    {
#if ENABLE_INPUT_SYSTEM
        static Key Map(K k)
        {
            switch (k)
            {
                case K.W: return Key.W; case K.A: return Key.A; case K.S: return Key.S; case K.D: return Key.D;
                case K.Q: return Key.Q; case K.E: return Key.E; case K.G: return Key.G; case K.C: return Key.C;
                case K.F: return Key.F; case K.Z: return Key.Z; case K.R: return Key.R; case K.Space: return Key.Space;
                case K.Shift: return Key.LeftShift; case K.LeftBracket: return Key.LeftBracket; case K.RightBracket: return Key.RightBracket;
                case K.Digit1: return Key.Digit1; case K.Digit2: return Key.Digit2; case K.T: return Key.T; case K.Minus: return Key.Minus; case K.Equals: return Key.Equals; default: return Key.F1;
            }
        }
        public static bool Ready { get { return Keyboard.current != null && Mouse.current != null; } }
        public static void Tick() { }
        public static bool Held(K k) { return Keyboard.current[Map(k)].isPressed; }
        public static bool Down(K k) { return Keyboard.current[Map(k)].wasPressedThisFrame; }
        public static Vector2 MousePos { get { return Mouse.current.position.ReadValue(); } }
        public static Vector2 MouseDelta { get { return Mouse.current.delta.ReadValue(); } }
        public static bool LmbHeld { get { return Mouse.current.leftButton.isPressed; } }
        public static bool LmbDown { get { return Mouse.current.leftButton.wasPressedThisFrame; } }
        public static bool RmbHeld { get { return Mouse.current.rightButton.isPressed; } }
        public static float Scroll { get { return Mouse.current.scroll.ReadValue().y; } }
#else
        static KeyCode Map(K k)
        {
            switch (k)
            {
                case K.W: return KeyCode.W; case K.A: return KeyCode.A; case K.S: return KeyCode.S; case K.D: return KeyCode.D;
                case K.Q: return KeyCode.Q; case K.E: return KeyCode.E; case K.G: return KeyCode.G; case K.C: return KeyCode.C;
                case K.F: return KeyCode.F; case K.Z: return KeyCode.Z; case K.R: return KeyCode.R; case K.Space: return KeyCode.Space;
                case K.Shift: return KeyCode.LeftShift; case K.LeftBracket: return KeyCode.LeftBracket; case K.RightBracket: return KeyCode.RightBracket;
                case K.Digit1: return KeyCode.Alpha1; case K.Digit2: return KeyCode.Alpha2; case K.T: return KeyCode.T; case K.Minus: return KeyCode.Minus; case K.Equals: return KeyCode.Equals; default: return KeyCode.F1;
            }
        }
        static Vector2 last, delta; static int lastFrame = -1;
        public static bool Ready { get { return true; } }
        public static void Tick()
        {
            if (lastFrame == Time.frameCount) return;
            Vector2 p = Input.mousePosition;
            delta = lastFrame < 0 ? Vector2.zero : p - last;
            last = p; lastFrame = Time.frameCount;
        }
        public static bool Held(K k) { return Input.GetKey(Map(k)); }
        public static bool Down(K k) { return Input.GetKeyDown(Map(k)); }
        public static Vector2 MousePos { get { return Input.mousePosition; } }
        // 滑鼠被鎖住時，游標位置不會變，要改讀滑鼠軸
        public static Vector2 MouseDelta { get { return Cursor.lockState == CursorLockMode.Locked ? new Vector2(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y")) * 10f : delta; } }
        public static bool LmbHeld { get { return Input.GetMouseButton(0); } }
        public static bool LmbDown { get { return Input.GetMouseButtonDown(0); } }
        public static bool RmbHeld { get { return Input.GetMouseButton(1); } }
        public static float Scroll { get { return Input.mouseScrollDelta.y; } }
#endif
    }
}
