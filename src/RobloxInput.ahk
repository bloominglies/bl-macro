class RobloxInput {
    static PointerOverTarget(hwnd) {
        if !hwnd
            return false
        point := Buffer(8, 0)
        if !DllCall("user32\GetCursorPos", "ptr", point, "int")
            return false
        hit := DllCall("user32\WindowFromPoint", "int64", NumGet(point, 0, "int64"), "ptr")
        return hit && DllCall("user32\GetAncestor", "ptr", hit, "uint", 2, "ptr") = hwnd
    }

    static CenterCursor(hwnd) {
        if !hwnd || WinActive("ahk_exe " FocusMonitor.ProcessName) != hwnd
            return false

        ; Use physical coordinates on every monitor, independent of GUI scaling.
        previousDpiContext := DllCall("user32\SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        if !previousDpiContext
            return false
        try {
            rect := Buffer(16, 0)
            if !DllCall("user32\GetClientRect", "ptr", hwnd, "ptr", rect, "int")
                return false
            width := NumGet(rect, 8, "int")
            height := NumGet(rect, 12, "int")
            if width <= 0 || height <= 0
                return false

            point := Buffer(8, 0)
            NumPut("int", width // 2, "int", height // 2, point)
            if !DllCall("user32\ClientToScreen", "ptr", hwnd, "ptr", point, "int")
                return false
            x := NumGet(point, 0, "int")
            y := NumGet(point, 4, "int")
            ; Do not click an overlay or another window covering the game center.
            hit := DllCall("user32\WindowFromPoint", "int64", NumGet(point, 0, "int64"), "ptr")
            if !hit || DllCall("user32\GetAncestor", "ptr", hit, "uint", 2, "ptr") != hwnd
                return false
            if WinActive("ahk_exe " FocusMonitor.ProcessName) != hwnd
                return false

            cursor := Buffer(8, 0)
            if !DllCall("user32\GetCursorPos", "ptr", cursor, "int")
                return false
            if NumGet(cursor, 0, "int") != x || NumGet(cursor, 4, "int") != y {
                if !DllCall("user32\SetCursorPos", "int", x, "int", y, "int")
                    return false
            }
            ; ClipCursor or a desktop change can prevent the requested position.
            return DllCall("user32\GetCursorPos", "ptr", cursor, "int")
                && NumGet(cursor, 0, "int") = x && NumGet(cursor, 4, "int") = y
                && WinActive("ahk_exe " FocusMonitor.ProcessName) = hwnd
        } finally {
            if previousDpiContext
                DllCall("user32\SetThreadDpiAwarenessContext", "ptr", previousDpiContext, "ptr")
        }
    }
}
