class UiBridge {
    __New(app) {
        this.App := app
        this.Ready := false
        this.Revision := 0
    }

    Receive(sender, args) {
        if args.Source != WebViewHost.DocumentUrl
            return
        requestId := 0
        try {
            message := args.TryGetWebMessageAsString()
            if StrLen(message) > 256
                throw ValueError("Comando muito longo.")
            parts := StrSplit(message, "|")
            if parts.Length < 2 || !RegExMatch(parts[1], "^\d{1,9}$")
                throw ValueError("Identificador de comando inválido.")
            requestId := Integer(parts.RemoveAt(1))
            if parts.Length = 1 {
                switch parts[1] {
                    case "ready":
                        this.Ready := true
                        this.App.Host.InterfaceReady()
                        this.App.DeliverPendingNotice()
                    case "toggle": this.App.ToggleMaster()
                    case "defaults": this.App.RestoreDefaults()
                    default: throw ValueError("Comando desconhecido.")
                }
            } else if parts.Length = 3 && parts[1] = "set" {
                this.App.SettingChanged(parts[2], parts[3])
            } else if parts.Length = 3 && parts[1] = "bind" {
                this.App.BindingChanged(parts[2], parts[3])
            } else if parts.Length = 3 && parts[1] = "trigger" {
                this.App.TriggerChanged(parts[2], parts[3])
            } else if parts.Length = 3 && parts[1] = "delay" {
                this.App.SkillDelayChanged(parts[2], parts[3])
            } else if parts.Length = 2 && parts[1] = "layout" {
                if !RegExMatch(parts[2], "^\d{3}$") || Integer(parts[2]) < 200 || Integer(parts[2]) > 600
                    throw ValueError("Dimensão de interface inválida.")
                this.App.Host.FitContent(Integer(parts[2]))
            } else {
                throw ValueError("Comando inválido.")
            }
            this.Publish(requestId)
        } catch Error as err {
            this.Publish(requestId)
            this.Notice("error", "Não foi possível salvar a alteração. " err.Message)
        }
    }

    Publish(requestId := 0, *) {
        if !this.Ready || !this.App.Host.Core || this.App.Closing
            return
        config := this.App.Config
        settings := Map()
        for field in ["masterEnabled", "movementEnabled", "numericEnabled", "wInterval", "clickDelay", "weaponReturnDelay", "shiftlockCenter", "resumeAfterM1", "runResumeDelay",
            "resumeAfterM2", "runResumeM2Delay", "holdM1Enabled", "holdM1Interval",
            "startWithWindows", "startMinimized", "minimizeOnClose"]
            settings[field] := config.%field%
        settings["binds"] := config.binds
        settings["triggers"] := config.triggers
        settings["skillDelays"] := config.skillDelays
        payload := Map("type", "state", "revision", ++this.Revision, "ack", requestId, "version", Resources.Version,
            "robloxStatus", this.App.Focus.Status, "settings", settings)
        payload["triggerKeys"] := KeyBindings.SupportedKeys()
        this.App.Host.Core.PostWebMessageAsJson(JsonWriter.Encode(payload))
    }

    Notice(level, message) {
        if !this.Ready {
            this.App.PendingNotice := message
            return
        }
        if this.App.Host.Core
            this.App.Host.Core.PostWebMessageAsJson(JsonWriter.Encode(Map("type", "notice", "level", level, "message", message)))
    }
}
