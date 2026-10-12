class FocusMonitor {
    static ProcessName := "RobloxPlayerBeta.exe"

    __New(onChanged, onForeground := 0) {
        this.OnChanged := onChanged
        this.OnForeground := onForeground
        this.ActiveHwnd := 0
        this.Status := "Not detected"
        this.Hook := 0
        this.Callback := 0
        this.CheckTimer := ObjBindMethod(this, "Refresh")
    }

    Start() {
        this.Callback := CallbackCreate(ObjBindMethod(this, "ForegroundChanged"), "", 7)
        ; OUTOFCONTEXT: Windows notifications only, never inject into Roblox.
        ; Own-process events are intentionally included: opening this GUI loses focus.
        this.Hook := DllCall("user32\SetWinEventHook", "uint", 3, "uint", 3,
            "ptr", 0, "ptr", this.Callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
        if !this.Hook
            throw OSError(A_LastError, "SetWinEventHook")
        this.Refresh()
        ; One cheap check per second discovers launch/exit and is a safety fallback.
        ; Keyboard and send paths independently verify the foreground every time.
        SetTimer(this.CheckTimer, 1000)
    }

    ForegroundChanged(hook, event, hwnd, objectId, childId, threadId, eventTime) {
        Critical("On")
        ; Honor the actual event even if focus has already returned by delivery.
        ; A quick away/back transition must still invalidate older macro timers.
        if this.ActiveHwnd && hwnd != this.ActiveHwnd {
            previous := this.ActiveHwnd
            this.ActiveHwnd := 0
            this.Status := "Unfocused"
            (this.OnChanged)(0, previous, this.Status)
        }
        this.Refresh()
    }

    Refresh(*) {
        Critical("On")
        ; Observe all foreground transitions, even when Roblox status is unchanged.
        if this.OnForeground
            (this.OnForeground)()
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        status := hwnd ? "Connected" : ProcessExist(FocusMonitor.ProcessName) ? "Unfocused" : "Not detected"
        if hwnd = this.ActiveHwnd && status = this.Status
            return
        previous := this.ActiveHwnd
        this.ActiveHwnd := hwnd
        this.Status := status
        (this.OnChanged)(hwnd, previous, status)
    }

    Stop() {
        SetTimer(this.CheckTimer, 0)
        if this.Hook {
            DllCall("user32\UnhookWinEvent", "ptr", this.Hook)
            this.Hook := 0
        }
        if this.Callback {
            CallbackFree(this.Callback)
            this.Callback := 0
        }
    }
}
