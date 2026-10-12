class SettingsStore {
    __New(dataDir) {
        this.Path := dataDir "\settings.ini"
    }

    static Defaults() {
        binds := Map()
        triggers := Map()
        for key in KeyBindings.Slots {
            binds[key] := "disabled"
            triggers[key] := key
        }
        return {
            masterEnabled: false,
            movementEnabled: true,
            numericEnabled: true,
            wInterval: 60,
            resumeAfterM1: true,
            runResumeDelay: 350,
            clickDelay: 80,
            weaponReturnDelay: 150,
            shiftlockCenter: false,
            startWithWindows: false,
            startMinimized: false,
            minimizeOnClose: true,
            overlayX: "",
            overlayY: "",
            binds: binds,
            triggers: triggers
        }
    }

    static Copy(config) {
        copy := config.Clone()
        copy.binds := config.binds.Clone()
        copy.triggers := config.triggers.Clone()
        return copy
    }

    Read(section, key, fallback) {
        try return IniRead(this.Path, section, key, fallback)
        catch
            return fallback
    }

    ReadBool(section, key, fallback) {
        value := this.Read(section, key, fallback ? "1" : "0")
        return value = "1" ? true : value = "0" ? false : fallback
    }

    ReadInterval(section, key, fallback, minimum, maximum) {
        value := this.Read(section, key, fallback)
        if !RegExMatch(value, "^\d{1,4}$")
            return fallback
        value := Integer(value)
        return value >= minimum && value <= maximum ? value : fallback
    }

    Load() {
        config := SettingsStore.Defaults()
        for field in ["masterEnabled", "movementEnabled", "numericEnabled", "shiftlockCenter", "resumeAfterM1"]
            config.%field% := this.ReadBool("Macros", field, config.%field%)
        for field in ["startWithWindows", "startMinimized", "minimizeOnClose"]
            config.%field% := this.ReadBool("Application", field, config.%field%)
        config.wInterval := this.ReadInterval("Macros", "wInterval", 60, 20, 250)
        config.runResumeDelay := this.ReadInterval("Macros", "runResumeDelay", 350, 20, 2000)
        config.clickDelay := this.ReadInterval("Macros", "clickDelay", 80, 20, 1000)
        config.weaponReturnDelay := this.ReadInterval("Macros", "weaponReturnDelay", 150, 20, 2000)
        config.overlayX := this.ReadPosition("x")
        config.overlayY := this.ReadPosition("y")
        weaponAssigned := false
        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            defaultAction := config.binds[key]
            action := StrLower(Trim(this.Read("Keybinds", key, defaultAction)))
            ; A hand-edited INI must never assign more than one weapon.
            if action = "weapon" {
                if weaponAssigned
                    action := "disabled"
                else
                    weaponAssigned := true
            }
            config.binds[key] := SettingsStore.ValidAction(action) ? action : defaultAction
        }
        rawTriggers := Map()
        for slot in KeyBindings.Slots
            rawTriggers[slot] := this.Read("Triggers", slot, slot)
        config.triggers := KeyBindings.NormalizeTriggers(rawTriggers)
        return config
    }

    static ValidAction(action) => action = "left" || action = "right" || action = "weapon" || action = "disabled"

    ReadPosition(key) {
        value := this.Read("Overlay", key, "")
        return RegExMatch(value, "^-?\d{1,6}$") && Abs(Integer(value)) <= 100000 ? Integer(value) : ""
    }

    Save(config) {
        text := "[Application]`r`nschema=4`r`n"
        for field in ["startWithWindows", "startMinimized", "minimizeOnClose"]
            text .= field "=" (config.%field% ? "1" : "0") "`r`n"
        text .= "`r`n[Macros]`r`n"
        for field in ["masterEnabled", "movementEnabled", "numericEnabled", "shiftlockCenter", "resumeAfterM1"]
            text .= field "=" (config.%field% ? "1" : "0") "`r`n"
        text .= "wInterval=" config.wInterval "`r`nclickDelay=" config.clickDelay
        text .= "`r`nrunResumeDelay=" config.runResumeDelay
        text .= "`r`nweaponReturnDelay=" config.weaponReturnDelay "`r`n`r`n[Keybinds]`r`n"
        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            text .= key "=" config.binds[key] "`r`n"
        text .= "`r`n[Triggers]`r`n"
        for slot in KeyBindings.Slots
            text .= slot "=" config.triggers[slot] "`r`n"
        text .= "`r`n[Overlay]`r`nx=" config.overlayX "`r`ny=" config.overlayY "`r`n"

        temporary := this.Path "." ProcessExist() ".tmp"
        try {
            file := FileOpen(temporary, "w", "UTF-16")
            try file.Write(text)
            finally file.Close()
            ; Replace in the same directory, preserving the old file on failure.
            if !DllCall("kernel32\MoveFileExW", "str", temporary, "str", this.Path, "uint", 0x9, "int")
                throw OSError(A_LastError, "MoveFileExW")
        } finally {
            if FileExist(temporary)
                try FileDelete(temporary)
        }
    }
}
