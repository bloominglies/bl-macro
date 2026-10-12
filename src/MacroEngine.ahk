class MacroEngine {
    static FirstTapDuration := 24
    static CenterSettleDelay := 20
    static RestartReleaseGap := 50
    static RestartTapDuration := 50
    static ScanCodes := KeyBindings.ScanCodes

    __New(config) {
        this.Config := config
        this.Running := false
        this.WPhysicalHeld := false
        this.WCaptured := false
        this.WVirtualDown := false
        this.WTarget := 0
        this.WGeneration := 0
        this.WTimer := 0
        this.HoldM1 := HoldM1Controller(this)
        this.M2PhysicalHeld := false
        this.LastAttackButton := ""
        this.LastAttackTarget := 0
        this.LastAttackAt := 0
        this.RunResumeButton := ""
        this.RunResumeTimer := 0
        this.RunResumeGeneration := 0
        this.RunRestartInProgress := false
        this.NumericHeld := Map()
        this.RegisteredSources := Map()
        this.RebuildTriggerLookup(config)
        this.PendingClicks := Map()
        this.ClickSequence := 0
        this.NumericGeneration := 0
        this.WeaponReturnTimer := 0
        this.WCriterion := ObjBindMethod(this, "ShouldInterceptW")
        this.NumericCriterion := ObjBindMethod(this, "ShouldObserveNumeric")
        this.M1Criterion := ObjBindMethod(this, "ShouldInterceptM1")
    }

    Start() {
        this.Running := true
        ; If launched with a key held, require a release before arming that key.
        this.WPhysicalHeld := GetKeyState("w", "P")
        this.HoldM1.PhysicalHeld := GetKeyState("LButton", "P")
        this.M2PhysicalHeld := GetKeyState("RButton", "P")

        HotIf(this.WCriterion)
        Hotkey("$*w", ObjBindMethod(this, "WDown", true), "On T1 I0")
        Hotkey("$*w up", ObjBindMethod(this, "WUp"), "On T1 I0")
        HotIf()
        ; Passive variants track the physical cycle across focus/config changes.
        ; They pass through native input and never send macro input outside Roblox.
        Hotkey("~$*w", ObjBindMethod(this, "WDown", false), "On T1 I0")
        Hotkey("~$*w up", ObjBindMethod(this, "WUp"), "On T1 I0")
        HotIf(this.M1Criterion)
        Hotkey("*LButton", ObjBindMethod(this, "M1Down", true), "On T1 I0")
        Hotkey("*LButton up", ObjBindMethod(this, "M1Up"), "On T1 I0")
        HotIf()
        ; Passive observers preserve native mouse input and ignore level-0 sends.
        Hotkey("~*LButton", ObjBindMethod(this, "M1Down", false), "On T1 I0")
        Hotkey("~*LButton up", ObjBindMethod(this, "M1Up"), "On T1 I0")
        Hotkey("~*RButton", ObjBindMethod(this, "M2Down"), "On T1 I0")
        Hotkey("~*RButton up", ObjBindMethod(this, "M2Up"), "On T1 I0")
        this.PrepareTriggers(this.Config)
    }

    RebuildTriggerLookup(config) {
        this.TriggerSlots := Map()
        for slot, source in config.triggers
            this.TriggerSlots[source] := slot
    }

    PrepareTriggers(config) {
        ; Original numbers always remain passive observers for manual selections.
        for source in KeyBindings.Slots
            this.RegisterSource(source)
        for slot, source in config.triggers
            this.RegisterSource(source)
    }

    RegisterSource(source) {
        if this.RegisteredSources.Has(source)
            return
        token := KeyBindings.Token(source)
        this.NumericHeld[source] := GetKeyState(token, "P")
        try {
            ; Observe the configured key without replacing or suppressing it.
            HotIf(this.NumericCriterion)
            Hotkey("~$*" token, ObjBindMethod(this, "NumericDown", source, true), "On T1 I0")
            HotIf()
            Hotkey("~$*" token, ObjBindMethod(this, "NumericDown", source, false), "On T1 I0")
            Hotkey("~$*" token " up", ObjBindMethod(this, "NumericUp", source), "On T1 I0")
            this.RegisteredSources[source] := token
        } finally {
            HotIf()
        }
    }

    ShouldInterceptW(*) {
        return this.Running && this.Config.masterEnabled && this.Config.movementEnabled
            && (!this.WPhysicalHeld || this.WCaptured)
            && WinActive("ahk_exe " FocusMonitor.ProcessName)
    }

    ShouldInterceptM1(*) {
        if !this.Running || !this.Config.masterEnabled || !this.Config.holdM1Enabled
            return false
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if this.HoldM1.PhysicalHeld
            return this.HoldM1.Captured && hwnd = this.HoldM1.Target
        return hwnd && RobloxInput.PointerOverTarget(hwnd)
    }

    ShouldObserveNumeric(*) {
        return this.Running && this.Config.masterEnabled && this.Config.numericEnabled
            && WinActive("ahk_exe " FocusMonitor.ProcessName)
    }

    IsTargetActive(hwnd) {
        return hwnd && WinActive("ahk_exe " FocusMonitor.ProcessName) = hwnd
    }

    WDown(intercept, *) {
        Critical("On")
        if this.WPhysicalHeld
            return
        this.WPhysicalHeld := true
        if !intercept || !this.Running || !this.Config.masterEnabled || !this.Config.movementEnabled
            return
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if !hwnd || !GetKeyState("w", "P")
            return

        this.WCaptured := true
        this.WTarget := hwnd
        generation := ++this.WGeneration
        this.FirstTapStarted(generation)
    }

    FirstTapStarted(generation, duration := 0) {
        Critical("On")
        if generation != this.WGeneration
            return
        this.WTimer := 0
        if !this.CanContinueW(generation) {
            this.CancelMovement()
            return
        }
        this.WVirtualDown := true
        SendEvent("{Blind}{w down}")
        this.WTimer := ObjBindMethod(this, "FirstTapReleased", generation)
        SetTimer(this.WTimer, -(duration ? duration : MacroEngine.FirstTapDuration))
    }

    CanContinueW(generation) {
        return generation = this.WGeneration && this.Running && this.WCaptured
            && this.Config.masterEnabled && this.Config.movementEnabled
            && this.WPhysicalHeld && GetKeyState("w", "P") && this.IsTargetActive(this.WTarget)
    }

    FirstTapReleased(generation) {
        Critical("On")
        if generation != this.WGeneration
            return
        this.WTimer := 0
        this.ReleaseW()
        if !this.CanContinueW(generation) {
            this.CancelMovement()
            return
        }
        this.WTimer := ObjBindMethod(this, "SecondTapStarted", generation)
        SetTimer(this.WTimer, -this.Config.wInterval)
    }

    SecondTapStarted(generation) {
        Critical("On")
        if generation != this.WGeneration
            return
        this.WTimer := 0
        if !this.CanContinueW(generation) {
            this.CancelMovement()
            return
        }
        this.WVirtualDown := true
        SendEvent("{Blind}{w down}")
        if this.RunRestartInProgress {
            this.RunRestartInProgress := false
            this.RunResumeButton := ""
            this.HoldM1.Resume()
        }
    }

    CanResumeRun(hwnd, button) {
        enabled := button = "right" ? this.Config.resumeAfterM2 : this.Config.resumeAfterM1
        return enabled && hwnd = this.WTarget && this.CanContinueW(this.WGeneration)
    }

    M1Down(intercept, *) {
        Critical("On")
        if this.HoldM1.PhysicalHeld
            return
        this.HoldM1.PhysicalHeld := true
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if !hwnd || !RobloxInput.PointerOverTarget(hwnd)
            return
        if intercept
            this.HoldM1.Capture(hwnd)
        else
            this.MouseAttack(hwnd, "left")
    }

    M1Up(*) {
        Critical("On")
        captured := this.HoldM1.Captured
        hadAttack := this.HoldM1.HadAttack
        hwnd := this.HoldM1.Target
        this.HoldM1.PhysicalHeld := false
        this.HoldM1.Cancel()
        if captured && hadAttack && this.LastAttackButton = "left" && this.LastAttackTarget = hwnd
            this.ScheduleRunResume(hwnd, "left", this.LastAttackAt)
    }

    M2Down(*) {
        Critical("On")
        if this.M2PhysicalHeld
            return
        this.M2PhysicalHeld := true
        this.HoldM1.Pause()
        this.CancelRunResume()
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if hwnd && RobloxInput.PointerOverTarget(hwnd)
            this.MouseAttack(hwnd, "right")
    }

    M2Up(*) {
        Critical("On")
        this.M2PhysicalHeld := false
        this.HoldM1.Resume()
    }

    MouseAttack(hwnd, button, fromHold := false) {
        Critical("On")
        this.CancelRunResume()
        this.LastAttackButton := button
        this.LastAttackTarget := hwnd
        this.LastAttackAt := A_TickCount
        ; Continuous M1 attacks recover after the final pulse, not mid-combo.
        if !fromHold
            this.ScheduleRunResume(hwnd, button)
    }

    ScheduleRunResume(hwnd, button, attackAt := 0) {
        Critical("On")
        this.CancelRunResume()
        if !this.CanResumeRun(hwnd, button)
            return
        generation := this.RunResumeGeneration
        delay := button = "right" ? this.Config.runResumeM2Delay : this.Config.runResumeDelay
        if attackAt
            delay := Max(1, delay - (A_TickCount - attackAt))
        this.RunResumeButton := button
        this.RunResumeTimer := ObjBindMethod(this, "ResumeRun", generation, this.WGeneration, hwnd, button)
        SetTimer(this.RunResumeTimer, -delay)
    }

    ResumeRun(generation, movementGeneration, hwnd, button) {
        Critical("On")
        if generation != this.RunResumeGeneration
            return
        this.RunResumeTimer := 0
        if movementGeneration != this.WGeneration || !this.CanResumeRun(hwnd, button) {
            this.RunResumeButton := ""
            this.HoldM1.Resume()
            return
        }
        if this.WTimer {
            SetTimer(this.WTimer, 0)
            this.WTimer := 0
        }
        ; Release the old W hold before a fresh double tap. Keep the physical
        ; latch intact; a one-shot gap lets the game observe the initial key-up.
        this.ReleaseW()
        movementGeneration := ++this.WGeneration
        this.RunRestartInProgress := true
        this.WTimer := ObjBindMethod(this, "FirstTapStarted", movementGeneration, MacroEngine.RestartTapDuration)
        SetTimer(this.WTimer, -MacroEngine.RestartReleaseGap)
    }

    CancelRunResume() {
        Critical("On")
        this.RunResumeGeneration += 1
        this.RunResumeButton := ""
        if this.RunResumeTimer {
            SetTimer(this.RunResumeTimer, 0)
            this.RunResumeTimer := 0
        }
        if !this.RunRestartInProgress
            return
        this.RunRestartInProgress := false
        generation := ++this.WGeneration
        if this.WTimer {
            SetTimer(this.WTimer, 0)
            this.WTimer := 0
        }
        ; Restore a held W when an attack interrupts the restart's key-up gap.
        ; Focus loss, W-up and shutdown fail this guard and send no key-down.
        if this.CanContinueW(generation) && !this.WVirtualDown {
            this.WVirtualDown := true
            SendEvent("{Blind}{w down}")
        }
    }

    WUp(*) {
        Critical("On")
        this.WPhysicalHeld := false
        this.CancelMovement()
    }

    ReleaseW() {
        if !this.WVirtualDown
            return
        ; Cleanup can send only key-up, even after foreground loss.
        SendEvent("{Blind}{w up}")
        this.WVirtualDown := false
    }

    CancelMovement() {
        Critical("On")
        this.WGeneration += 1
        if this.WTimer {
            SetTimer(this.WTimer, 0)
            this.WTimer := 0
        }
        this.WCaptured := false
        this.WTarget := 0
        this.ReleaseW()
        this.CancelRunResume()
        this.HoldM1.Resume()
        ; Do not clear physical latch here: repeat must never start a new cycle.
    }

    NumericDown(source, eligible, *) {
        Critical("On")
        if this.NumericHeld[source]
            return
        this.NumericHeld[source] := true
        numeric := MacroEngine.ScanCodes.Has(source)
        if !numeric && !this.TriggerSlots.Has(source)
            return
        ; A newer configured key or native number supersedes older casts/returns.
        this.CancelNumeric(false)
        if !eligible || !this.ShouldObserveNumeric() {
            this.HoldM1.Resume()
            return
        }
        this.HoldM1.Pause()
        slot := this.TriggerSlots.Has(source) ? this.TriggerSlots[source] : ""
        if slot = "" {
            this.HoldM1.Resume()
            return
        }
        action := this.Config.binds[slot]
        if action = "disabled" || action = "weapon" {
            this.HoldM1.Resume()
            return
        }
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if !hwnd {
            this.HoldM1.Resume()
            return
        }
        ; The physical configured key has already reached Roblox through the tilde
        ; hotkey. Never send the entry's legacy number or another selection here.
        id := ++this.ClickSequence
        callback := ObjBindMethod(this, "PrepareClick", id, this.NumericGeneration, hwnd, action)
        this.PendingClicks[id] := callback
        delay := this.Config.skillDelays[slot]
        SetTimer(callback, -(delay ? delay : this.Config.clickDelay))
    }

    NumericUp(source, *) {
        Critical("On")
        this.NumericHeld[source] := false
    }

    CanContinueNumeric(generation, hwnd) {
        return generation = this.NumericGeneration && this.Running
            && this.Config.masterEnabled && this.Config.numericEnabled && this.IsTargetActive(hwnd)
    }

    MouseAvailable(button, hwnd) {
        owned := button = "LButton" && this.HoldM1.Captured && this.HoldM1.Target = hwnd
        return !GetKeyState(button) && (!GetKeyState(button, "P") || owned)
    }

    DropClick(id) {
        if this.PendingClicks.Has(id)
            this.PendingClicks.Delete(id)
        this.HoldM1.Resume()
    }

    PrepareClick(id, generation, hwnd, action) {
        Critical("On")
        if !this.PendingClicks.Has(id)
            return
        button := action = "left" ? "LButton" : "RButton"
        if !this.CanContinueNumeric(generation, hwnd) || !this.MouseAvailable(button, hwnd) {
            this.DropClick(id)
            return
        }
        if this.Config.shiftlockCenter {
            if !RobloxInput.CenterCursor(hwnd) {
                this.DropClick(id)
                return
            }
            ; Give the client a frame to observe the centered pointer, without Sleep.
            callback := ObjBindMethod(this, "FireClick", id, generation, hwnd, action)
            this.PendingClicks[id] := callback
            SetTimer(callback, -MacroEngine.CenterSettleDelay)
        } else {
            this.FireClick(id, generation, hwnd, action)
        }
    }

    FireClick(id, generation, hwnd, action) {
        Critical("On")
        if !this.PendingClicks.Has(id)
            return
        if !this.CanContinueNumeric(generation, hwnd) {
            this.DropClick(id)
            return
        }
        button := action = "left" ? "LButton" : "RButton"
        ; A captured Hold M1 can yield its button; native physical holds cannot.
        if !this.MouseAvailable(button, hwnd) {
            this.DropClick(id)
            return
        }
        if this.Config.shiftlockCenter && !RobloxInput.CenterCursor(hwnd) {
            this.DropClick(id)
            return
        }
        if !this.CanContinueNumeric(generation, hwnd) {
            this.DropClick(id)
            return
        }
        this.PendingClicks.Delete(id)
        ; Default mode preserves the cursor; center mode leaves it at the game center.
        SendEvent("{Blind}{" button " down}{" button " up}")
        ; Synthetic clicks skip the hooks; notify movement once for either button.
        this.MouseAttack(hwnd, action)
        this.ScheduleWeaponReturn(generation, hwnd)
        this.HoldM1.Resume()
    }

    WeaponKey() {
        for key, action in this.Config.binds
            if action = "weapon"
                return key
        return ""
    }

    ScheduleWeaponReturn(generation, hwnd) {
        key := this.WeaponKey()
        if key = "" || !this.CanContinueNumeric(generation, hwnd)
            return
        this.WeaponReturnTimer := ObjBindMethod(this, "ReturnWeapon", generation, hwnd, key)
        SetTimer(this.WeaponReturnTimer, -this.Config.weaponReturnDelay)
    }

    ReturnWeapon(generation, hwnd, key) {
        Critical("On")
        if generation != this.NumericGeneration
            return
        this.WeaponReturnTimer := 0
        try {
            if !this.CanContinueNumeric(generation, hwnd) || this.WeaponKey() != key
                return
            token := KeyBindings.Token(this.Config.triggers[key])
            if GetKeyState(token, "P") || GetKeyState(token) || !this.IsTargetActive(hwnd)
                return
            SendEvent("{Blind}{" token " down}{" token " up}")
        } finally {
            this.HoldM1.Resume()
        }
    }

    CancelNumeric(resumeHold := true) {
        Critical("On")
        this.NumericGeneration += 1
        for id, callback in this.PendingClicks
            SetTimer(callback, 0)
        this.PendingClicks.Clear()
        if this.WeaponReturnTimer {
            SetTimer(this.WeaponReturnTimer, 0)
            this.WeaponReturnTimer := 0
        }
        if resumeHold
            this.HoldM1.Resume()
    }

    FocusChanged(hwnd, previous) {
        if hwnd != previous {
            this.HoldM1.Cancel()
            this.CancelMovement()
            this.CancelNumeric()
        }
    }

    Configure(config) {
        Critical("On")
        previous := this.Config
        this.Config := config
        this.RebuildTriggerLookup(config)
        if !config.masterEnabled || !config.holdM1Enabled
            this.HoldM1.Cancel()
        else if config.holdM1Interval != previous.holdM1Interval {
            this.HoldM1.Pause()
            this.HoldM1.Resume()
        }
        if !config.masterEnabled || !config.movementEnabled || config.wInterval != previous.wInterval
            this.CancelMovement()
        if config.resumeAfterM1 != previous.resumeAfterM1 || config.runResumeDelay != previous.runResumeDelay
            || config.resumeAfterM2 != previous.resumeAfterM2 || config.runResumeM2Delay != previous.runResumeM2Delay {
            this.CancelRunResume()
            this.HoldM1.Resume()
        }
        changed := !config.masterEnabled || !config.numericEnabled || config.clickDelay != previous.clickDelay
            || config.weaponReturnDelay != previous.weaponReturnDelay || config.shiftlockCenter != previous.shiftlockCenter
        for key, action in config.binds
            if action != previous.binds[key]
                changed := true
        for slot, source in config.triggers
            if source != previous.triggers[slot]
                changed := true
        for slot, delay in config.skillDelays
            if delay != previous.skillDelays[slot]
                changed := true
        if changed
            this.CancelNumeric()
    }

    Stop() {
        Critical("On")
        this.Running := false
        this.HoldM1.Cancel()
        this.CancelMovement()
        this.CancelNumeric()
    }
}
