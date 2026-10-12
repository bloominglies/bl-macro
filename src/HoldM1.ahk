class HoldM1Controller {
    static PressDuration := 20

    __New(engine) {
        this.Engine := engine
        this.PhysicalHeld := false
        this.Captured := false
        this.VirtualDown := false
        this.Target := 0
        this.Generation := 0
        this.Timer := 0
        this.PressStartedAt := 0
        this.HadAttack := false
    }

    CanContinue() {
        return this.Engine.Running && this.Engine.Config.masterEnabled && this.Engine.Config.holdM1Enabled
            && this.Captured && this.PhysicalHeld && GetKeyState("LButton", "P")
            && this.Engine.IsTargetActive(this.Target)
    }

    Blocked() {
        ; Skills own the mouse until their cast and weapon return finish.
        return this.Engine.PendingClicks.Count || this.Engine.WeaponReturnTimer
            || this.Engine.M2PhysicalHeld || GetKeyState("RButton", "P")
            || (this.Engine.RunResumeButton = "right"
                && (this.Engine.RunResumeTimer || this.Engine.RunRestartInProgress))
    }

    Capture(hwnd) {
        Critical("On")
        this.Cancel()
        this.Target := hwnd
        this.Captured := true
        this.Press(this.Generation)
    }

    Press(generation) {
        Critical("On")
        if generation != this.Generation
            return
        this.Timer := 0
        if !this.CanContinue() || !RobloxInput.PointerOverTarget(this.Target) {
            this.Cancel()
            return
        }
        if this.Blocked()
            return
        this.PressStartedAt := A_TickCount
        this.HadAttack := true
        this.VirtualDown := true
        SendEvent("{Blind}{LButton down}")
        this.Engine.MouseAttack(this.Target, "left", true)
        this.Timer := ObjBindMethod(this, "ReleasePulse", generation)
        SetTimer(this.Timer, -HoldM1Controller.PressDuration)
    }

    ReleasePulse(generation) {
        Critical("On")
        if generation != this.Generation
            return
        this.Timer := 0
        this.Release()
        if !this.CanContinue() {
            this.Cancel()
            return
        }
        if this.Blocked()
            return
        delay := Max(1, this.Engine.Config.holdM1Interval - (A_TickCount - this.PressStartedAt))
        this.Timer := ObjBindMethod(this, "Press", generation)
        SetTimer(this.Timer, -delay)
    }

    Resume() {
        Critical("On")
        if !this.CanContinue() || this.Blocked() || this.Timer || this.VirtualDown
            return
        this.Timer := ObjBindMethod(this, "Press", this.Generation)
        SetTimer(this.Timer, -this.Engine.Config.holdM1Interval)
    }

    Pause() {
        Critical("On")
        this.Generation += 1
        if this.Timer {
            SetTimer(this.Timer, 0)
            this.Timer := 0
        }
        this.Release()
    }

    Release() {
        if !this.VirtualDown
            return
        ; Only an intercepted physical press gives us ownership of its key-up.
        SendEvent("{Blind}{LButton up}")
        this.VirtualDown := false
    }

    Cancel() {
        Critical("On")
        this.Pause()
        this.Captured := false
        this.Target := 0
        this.HadAttack := false
        ; A fresh physical press is required after cancellation.
    }
}
