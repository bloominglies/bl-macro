class KeyBindings {
    static Slots := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static ScanCodes := Map("1", "sc002", "2", "sc003", "3", "sc004", "4", "sc005",
        "5", "sc006", "6", "sc007", "7", "sc008", "8", "sc009", "9", "sc00A", "0", "sc00B")
    static NamedKeys := Map("Space", "sc039", "Tab", "sc00F", "Enter", "sc01C", "Backspace", "sc00E",
        "Insert", "sc152", "Delete", "sc153", "Home", "sc147", "End", "sc14F",
        "PgUp", "sc149", "PgDn", "sc151", "Up", "sc148", "Down", "sc150", "Left", "sc14B", "Right", "sc14D")

    static SupportedKeys() {
        keys := this.Slots.Clone()
        Loop 26 {
            key := Chr(64 + A_Index)
            if key != "W"
                keys.Push(key)
        }
        Loop 12
            keys.Push("F" A_Index)
        for key in this.NamedKeys
            keys.Push(key)
        return keys
    }

    static Canonical(value) {
        value := StrUpper(Trim(value))
        if RegExMatch(value, "^[0-9A-VXYZ]$") || RegExMatch(value, "^F([1-9]|1[0-2])$")
            return value
        for key in this.NamedKeys
            if StrUpper(key) = value
                return key
        return ""
    }

    static Token(key) {
        if this.ScanCodes.Has(key)
            return this.ScanCodes[key]
        if RegExMatch(key, "^[A-VXYZ]$")
            return Format("vk{:02X}", Ord(key))
        if this.NamedKeys.Has(key)
            return this.NamedKeys[key]
        if RegExMatch(key, "^F([1-9]|1[0-2])$") {
            number := Integer(SubStr(key, 2))
            return Format("sc{:03X}", number <= 10 ? 0x3A + number : number = 11 ? 0x57 : 0x58)
        }
        throw ValueError("Tecla de ativação inválida.")
    }

    static NormalizeTriggers(raw) {
        result := Map()
        used := Map()
        for slot in this.Slots {
            key := raw.Has(slot) ? this.Canonical(raw[slot]) : slot
            if key != "" && !used.Has(key) {
                result[slot] := key
                used[key] := true
            }
        }
        ; Repair only invalid/duplicate assignments; preserve every valid first choice.
        for slot in this.Slots {
            if result.Has(slot)
                continue
            key := slot
            if used.Has(key) {
                for fallback in this.Slots {
                    if !used.Has(fallback) {
                        key := fallback
                        break
                    }
                }
            }
            result[slot] := key
            used[key] := true
        }
        return result
    }
}
