class StartupManager {
    static RegistryPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    static ValueName := "Marco (Bloodlines)"
    static LegacyValueName := "BloodlinesMacro"

    static Command() {
        quote := Chr(34)
        return A_IsCompiled ? quote A_ScriptFullPath quote
            : quote A_AhkPath quote " " quote A_ScriptFullPath quote
    }

    static SetEnabled(enabled) {
        if enabled {
            RegWrite(this.Command(), "REG_SZ", this.RegistryPath, this.ValueName)
        } else {
            this.DeleteIfPresent(this.ValueName)
        }
        ; Migrate only the former entry owned by this application.
        this.DeleteIfPresent(this.LegacyValueName)
    }

    static DeleteIfPresent(name) {
        try RegRead(this.RegistryPath, name)
        catch OSError as err {
            if err.Number = 2
                return
            throw err
        }
        RegDelete(this.RegistryPath, name)
    }
}
