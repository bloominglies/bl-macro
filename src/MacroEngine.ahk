class MacroEngine {
    static FirstTapDuration := 24
    static CenterSettleDelay := 20
    static RestartReleaseGap := 20
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
        this.M1PhysicalHeld := false
        this.M1Target := 0
        this.M1WGeneration := 0
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
    }

    Start() {
        this.Running := true
        ; If launched with a key held, require a release before arming that key.
        this.WPhysicalHeld := GetKeyState("w", "P")
        this.M1PhysicalHeld := GetKeyState("LButton", "P")

        HotIf(this.WCriterion)
        Hotkey("$*w", ObjBindMethod(this, "WDown", true), "On T1 I0")
        Hotkey("$*w up", ObjBindMethod(this, "WUp"), "On T1 I0")
        HotIf()
        ; Passive variants track the physical cycle across focus/config changes.
        ; They pass through native input and never send macro input outside Roblox.
        Hotkey("~$*w", ObjBindMethod(this, "WDown", false), "On T1 I0")
        Hotkey("~$*w up", ObjBindMethod(this, "WUp"), "On T1 I0")
        ; Mouse observers preserve native M1 and ignore our level-0 clicks.
        Hotkey("~*LButton", ObjBindMethod(this, "M1Down"), "On T1 I0")
        Hotkey("~*LButton up", ObjBindMethod(this, "M1Up"), "On T1 I0")
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

    FirstTapStarted(generation) {
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
        SetTimer(this.WTimer, -MacroEngine.FirstTapDuration)
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
        this.RunRestartInProgress := false
    }

    CanResumeRun(hwnd) {
        return this.Config.resumeAfterM1 && hwnd = this.WTarget && this.CanContinueW(this.WGeneration)
    }

    M1Down(*) {
        Critical("On")
        if this.M1PhysicalHeld
            return
        this.M1PhysicalHeld := true
        ; Each attack cancels the older delay and any partially restarted tap.
        this.CancelRunResume()
        hwnd := this.WTarget
        if !this.CanResumeRun(hwnd) || !RobloxInput.PointerOverTarget(hwnd)
            return
        this.M1Target := hwnd
        this.M1WGeneration := this.WGeneration
    }

    M1Up(*) {
        Critical("On")
        this.M1PhysicalHeld := false
        hwnd := this.M1Target
        movementGeneration := this.M1WGeneration
        this.M1Target := 0
        this.M1WGeneration := 0
        if hwnd && movementGeneration = this.WGeneration && this.CanResumeRun(hwnd)
            this.ScheduleRunResume(hwnd)
    }

    ScheduleRunResume(hwnd) {
        Critical("On")
        this.CancelRunResume()
        if !this.CanResumeRun(hwnd) || this.M1PhysicalHeld || GetKeyState("LButton", "P")
            return
        generation := this.RunResumeGeneration
        this.RunResumeTimer := ObjBindMethod(this, "ResumeRun", generation, this.WGeneration, hwnd)
        SetTimer(this.RunResumeTimer, -this.Config.runResumeDelay)
    }

    ResumeRun(generation, movementGeneration, hwnd) {
        Critical("On")
        if generation != this.RunResumeGeneration
            return
        this.RunResumeTimer := 0
        if movementGeneration != this.WGeneration || !this.CanResumeRun(hwnd)
            || this.M1PhysicalHeld || GetKeyState("LButton", "P") || GetKeyState("LButton")
            return
        if this.WTimer {
            SetTimer(this.WTimer, 0)
            this.WTimer := 0
        }
        ; Release the old W hold before a fresh double tap. Keep the physical
        ; latch intact; a one-shot gap lets the game observe the initial key-up.
        this.ReleaseW()
        movementGeneration := ++this.WGeneration
        this.RunRestartInProgress := true
        this.WTimer := ObjBindMethod(this, "FirstTapStarted", movementGeneration)
        SetTimer(this.WTimer, -MacroEngine.RestartReleaseGap)
    }

    CancelRunResume() {
        Critical("On")
        this.RunResumeGeneration += 1
        if this.RunResumeTimer {
            SetTimer(this.RunResumeTimer, 0)
            this.RunResumeTimer := 0
        }
        this.M1Target := 0
        this.M1WGeneration := 0
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
        this.CancelNumeric()
        if !eligible || !this.ShouldObserveNumeric()
            return
        slot := this.TriggerSlots.Has(source) ? this.TriggerSlots[source] : ""
        if slot = ""
            return
        action := this.Config.binds[slot]
        if action = "disabled" || action = "weapon"
            return
        hwnd := WinActive("ahk_exe " FocusMonitor.ProcessName)
        if !hwnd
            return
        ; The physical configured key has already reached Roblox through the tilde
        ; hotkey. Never send the entry's legacy number or another selection here.
        id := ++this.ClickSequence
        callback := ObjBindMethod(this, "PrepareClick", id, this.NumericGeneration, hwnd, action)
        this.PendingClicks[id] := callback
        SetTimer(callback, -this.Config.clickDelay)
    }

    NumericUp(source, *) {
        Critical("On")
        this.NumericHeld[source] := false
    }

    CanContinueNumeric(generation, hwnd) {
        return generation = this.NumericGeneration && this.Running
            && this.Config.masterEnabled && this.Config.numericEnabled && this.IsTargetActive(hwnd)
    }

    PrepareClick(id, generation, hwnd, action) {
        Critical("On")
        if !this.PendingClicks.Has(id)
            return
        button := action = "left" ? "LButton" : "RButton"
        if !this.CanContinueNumeric(generation, hwnd) || GetKeyState(button, "P") || GetKeyState(button) {
            this.PendingClicks.Delete(id)
            return
        }
        if this.Config.shiftlockCenter {
            if !RobloxInput.CenterCursor(hwnd) {
                this.PendingClicks.Delete(id)
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
        this.PendingClicks.Delete(id)
        if !this.CanContinueNumeric(generation, hwnd)
            return
        button := action = "left" ? "LButton" : "RButton"
        ; Never release a real mouse button held by the user or another application.
        if GetKeyState(button, "P") || GetKeyState(button)
            return
        if this.Config.shiftlockCenter && !RobloxInput.CenterCursor(hwnd)
            return
        if !this.CanContinueNumeric(generation, hwnd)
            return
        ; Default mode preserves the cursor; center mode leaves it at the game center.
        SendEvent("{Blind}{" button " down}{" button " up}")
        ; Synthetic left clicks skip the hook, so notify the movement motor once.
        if action = "left"
            this.ScheduleRunResume(hwnd)
        this.ScheduleWeaponReturn(generation, hwnd)
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
        if !this.CanContinueNumeric(generation, hwnd) || this.WeaponKey() != key
            return
        token := KeyBindings.Token(this.Config.triggers[key])
        ; Never synthesize key-up over a physical weapon press.
        if GetKeyState(token, "P") || GetKeyState(token)
            return
        if !this.IsTargetActive(hwnd)
            return
        ; Hook hotkeys ignore these synthetic events; this cannot trigger a new cast.
        ; Blind also preserves the virtual W hold and the user's modifier keys.
        SendEvent("{Blind}{" token " down}{" token " up}")
    }

    CancelNumeric() {
        Critical("On")
        this.NumericGeneration += 1
        for id, callback in this.PendingClicks
            SetTimer(callback, 0)
        this.PendingClicks.Clear()
        if this.WeaponReturnTimer {
            SetTimer(this.WeaponReturnTimer, 0)
            this.WeaponReturnTimer := 0
        }
    }

    FocusChanged(hwnd, previous) {
        if hwnd != previous {
            this.CancelMovement()
            this.CancelNumeric()
        }
    }

    Configure(config) {
        Critical("On")
        previous := this.Config
        this.Config := config
        this.RebuildTriggerLookup(config)
        if !config.masterEnabled || !config.movementEnabled || config.wInterval != previous.wInterval
            this.CancelMovement()
        if config.resumeAfterM1 != previous.resumeAfterM1 || config.runResumeDelay != previous.runResumeDelay
            this.CancelRunResume()
        changed := !config.masterEnabled || !config.numericEnabled || config.clickDelay != previous.clickDelay
            || config.weaponReturnDelay != previous.weaponReturnDelay || config.shiftlockCenter != previous.shiftlockCenter
        for key, action in config.binds
            if action != previous.binds[key]
                changed := true
        for slot, source in config.triggers
            if source != previous.triggers[slot]
                changed := true
        if changed
            this.CancelNumeric()
    }

    Stop() {
        Critical("On")
        this.Running := false
        this.CancelMovement()
        this.CancelNumeric()
    }
}
