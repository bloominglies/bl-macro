; A small native companion: no second browser, no focus stealing, no game hooks.
class MacroOverlay {
    __New(app) {
        this.App := app
        this.Visible := false
        this.LastX := "unset"
        this.LastY := "unset"
        this.Window := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +E0x08000000", "Marco (Bloodlines) / overlay")
        this.Window.BackColor := "0D0D0D"
        this.Window.MarginX := 0
        this.Window.MarginY := 0
        this.Window.SetFont("s9 cE5E5E5", "Consolas")
        this.Header := this.Window.AddText("x9 y6 w84 h18 +0x100", "Marco")
        this.Header.OnEvent("Click", ObjBindMethod(this, "Drag"))
        this.Master := this.Row(93, 6, 41, "masterEnabled", "Motor")
        open := this.Window.AddText("x146 y6 w38 h18 Center +0x100", "open")
        open.OnEvent("Click", ObjBindMethod(app, "OpenWindow"))
        this.Movement := this.Row(9, 30, 67, "movementEnabled", "W")
        this.Numeric := this.Row(99, 30, 78, "numericEnabled", "cast")
        this.Hold := this.Row(9, 54, 177, "holdM1Enabled", "hold M1")
        this.Window.SetFont("s8 c858585", "Consolas")
        this.Status := this.Window.AddText("x9 y81 w177 h17", "Roblox: …")
        this.Window.AddText("x0 y0 w194 h1 Background292929")
        this.Window.AddText("x0 y105 w194 h1 Background292929")
        this.Window.AddText("x0 y0 w1 h106 Background292929")
        this.Window.AddText("x193 y0 w1 h106 Background292929")
        this.NoticeUntil := 0
        this.ActivateHandler := ObjBindMethod(this, "MouseActivate")
        this.MoveHandler := ObjBindMethod(this, "MoveFinished")
        this.DisplayHandler := ObjBindMethod(this, "DisplayChanged")
        this.SaveTimer := ObjBindMethod(this, "SavePosition")
        this.LayoutTimer := ObjBindMethod(this, "RestorePosition")
        OnMessage(0x21, this.ActivateHandler)
        OnMessage(0x232, this.MoveHandler)
        OnMessage(0x7E, this.DisplayHandler)
        this.Window.Show("Hide w194 h106")
        this.RestorePosition()
    }

    Row(x, y, width, field, label) {
        ; Each compact label/state is one click target.
        control := this.Window.AddText("x" x " y" y " w" width " h22 +0x100", label)
        control.OnEvent("Click", ObjBindMethod(this.App, "OverlayToggle", field))
        if field = "masterEnabled" {
            control.Move(x, y, width, 18)
            return control
        }
        return control
    }

    Bounds() {
        ; GetWindowRect uses desktop pixels, matching monitor work areas and INI.
        rect := Buffer(16, 0)
        if !DllCall("user32\GetWindowRect", "ptr", this.Window.Hwnd, "ptr", rect)
            throw OSError(A_LastError, "GetWindowRect")
        return {x: NumGet(rect, 0, "int"), y: NumGet(rect, 4, "int"),
            width: NumGet(rect, 8, "int") - NumGet(rect, 0, "int"),
            height: NumGet(rect, 12, "int") - NumGet(rect, 4, "int")}
    }

    MouseActivate(wParam, lParam, msg, hwnd) {
        if hwnd = this.Window.Hwnd || DllCall("user32\GetAncestor", "ptr", hwnd, "uint", 2, "ptr") = this.Window.Hwnd
            return 3 ; MA_NOACTIVATE: deliver click, preserve foreground Roblox.
    }

    Drag(*) {
        DllCall("user32\ReleaseCapture")
        PostMessage(0xA1, 2, 0, , this.Window.Hwnd) ; WM_NCLBUTTONDOWN / HTCAPTION
    }

    MoveFinished(wParam, lParam, msg, hwnd) {
        if hwnd = this.Window.Hwnd
            SetTimer(this.SaveTimer, -1)
    }

    DisplayChanged(*) => SetTimer(this.LayoutTimer, -1)

    static Clamp(x, y, width, height) {
        ; Coordinates are physical desktop pixels; negative positions are valid.
        primary := MonitorGetPrimary()
        MonitorGetWorkArea(primary, &left, &top, &right, &bottom)
        if x = "" || y = ""
            return {x: Max(left, right - width - 24), y: top + 24}
        best := 0x7FFFFFFFFFFFFFFF
        selected := {left: left, top: top, right: right, bottom: bottom}
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            cx := x + width / 2
            cy := y + height / 2
            dx := Max(left - cx, 0, cx - right)
            dy := Max(top - cy, 0, cy - bottom)
            distance := dx * dx + dy * dy
            if distance < best {
                best := distance
                selected := {left: left, top: top, right: right, bottom: bottom}
            }
        }
        return {x: Max(selected.left, Min(x, selected.right - width)),
            y: Max(selected.top, Min(y, selected.bottom - height))}
    }

    RestorePosition(*) {
        if this.App.Closing
            return
        bounds := this.Bounds()
        config := this.App.Config
        position := MacroOverlay.Clamp(config.overlayX, config.overlayY, bounds.width, bounds.height)
        this.Window.Move(position.x, position.y)
        this.LastX := config.overlayX
        this.LastY := config.overlayY
    }

    SavePosition(*) {
        if this.App.Closing
            return
        bounds := this.Bounds()
        position := MacroOverlay.Clamp(bounds.x, bounds.y, bounds.width, bounds.height)
        this.Window.Move(position.x, position.y)
        this.App.SaveOverlayPosition(position.x, position.y)
    }

    Refresh() {
        config := this.App.Config
        if config.overlayX != this.LastX || config.overlayY != this.LastY
            this.RestorePosition()
        ; Each on/off describes the actual stored control, never temporary focus.
        this.SetState(this.Master, "", config.masterEnabled)
        this.SetState(this.Movement, "W", config.movementEnabled)
        this.SetState(this.Numeric, "cast", config.numericEnabled)
        this.SetState(this.Hold, "hold M1", config.holdM1Enabled)
        if A_TickCount >= this.NoticeUntil
            this.SetText(this.Status, "Roblox: " MarcoApplication.FocusLabel(this.App.Focus.Status))
        show := this.App.Bridge.Ready && !WinActive(this.App.Host.Window.Hwnd)
        if show && !this.Visible {
            this.Window.Show("NA")
            this.Visible := true
            this.App.Log("Overlay shown without activation")
        } else if !show && this.Visible {
            this.Window.Hide()
            this.Visible := false
            this.App.Log("Overlay hidden: main panel focused")
        }
    }

    SetText(control, text) {
        if control.Text != text
            control.Text := text
    }

    SetState(control, label, enabled) {
        text := (label ? label "  " : "") (enabled ? "on" : "off")
        if control.Text != text {
            control.Text := text
            control.SetFont("c" (enabled ? "B8C7A0" : "858585"))
        }
    }

    ShowError(text) {
        this.NoticeUntil := A_TickCount + 5000
        this.Status.Text := text
    }

    Dispose() {
        OnMessage(0x21, this.ActivateHandler, 0)
        OnMessage(0x232, this.MoveHandler, 0)
        OnMessage(0x7E, this.DisplayHandler, 0)
        SetTimer(this.SaveTimer, 0)
        SetTimer(this.LayoutTimer, 0)
        this.Window.Destroy()
    }
}
