class MarcoApplication {
    __New() {
        this.Closing := false
        this.PendingNotice := ""
        this.Engine := 0
        this.Focus := 0
        this.Host := 0
        this.Bridge := 0
        this.Overlay := 0
        this.Tray := A_TrayMenu
        this.ExitHandler := ObjBindMethod(this, "Shutdown")
        this.ErrorHandler := ObjBindMethod(this, "UnexpectedError")
        this.PowerHandler := ObjBindMethod(this, "PowerChanged")
        this.PublishTimer := ObjBindMethod(this, "PublishState")
        OnExit(this.ExitHandler)
        OnError(this.ErrorHandler)
    }

    Start() {
        try {
            if A_PtrSize != 8
                throw Error("Execute este projeto com AutoHotkey v2 de 64 bits.")
            this.DataDir := Resources.DataDirectory()
            this.LogPath := this.DataDir "\startup.log"
            log := FileOpen(this.LogPath, "w", "UTF-8")
            log.Close()
            this.Log("Starting " Resources.Version)
            this.Store := SettingsStore(this.DataDir)
            this.Config := this.Store.Load()
            this.ResourceDir := Resources.Prepare(this.DataDir)
            TraySetIcon(this.ResourceDir "\assets\marco.ico")
            this.Engine := MacroEngine(this.Config)
            this.Focus := FocusMonitor(ObjBindMethod(this, "FocusChanged"), ObjBindMethod(this, "QueuePublish"))
            this.Bridge := UiBridge(this)
            this.Host := WebViewHost(this, this.ResourceDir)
            this.Overlay := MacroOverlay(this)
            this.PrepareTray()
            OnMessage(0x218, this.PowerHandler)
            this.Host.Start(this.DataDir)
        } catch Error as err {
            this.StartupFailed(err)
        }
    }

    HostReady() {
        this.Log("WebView2 controller ready")
        this.Focus.Start()
        this.Engine.Start()
        try StartupManager.SetEnabled(this.Config.startWithWindows)
        catch Error as err {
            ; Make the displayed preference agree with the actual Run entry.
            actual := ""
            try actual := RegRead(StartupManager.RegistryPath, StartupManager.ValueName)
            this.Config.startWithWindows := actual = StartupManager.Command()
            this.PendingNotice := "A inicialização com Windows não pôde ser atualizada. " err.Message
        }
        this.UpdateTray()
    }

    PrepareTray() {
        this.Tray.Delete()
        this.Tray.Add("Abrir Marco (Bloodlines)", ObjBindMethod(this, "OpenWindow"))
        this.Tray.Add("Motor", ObjBindMethod(this, "TrayToggle"))
        this.Tray.Add()
        this.Tray.Add("Sair", (*) => ExitApp())
        this.Tray.Default := "Abrir Marco (Bloodlines)"
        this.Tray.ClickCount := 2
        this.UpdateTray()
    }

    OpenWindow(*) {
        if this.Host
            this.Host.Show()
    }

    TrayToggle(*) {
        try {
            this.ToggleMaster()
            this.Bridge.Publish()
        }
        catch Error as err {
            this.Bridge.Notice("error", "Não foi possível salvar. " err.Message)
            this.OpenWindow()
        }
    }

    UpdateTray() {
        if this.Config.masterEnabled
            this.Tray.Check("Motor")
        else
            this.Tray.Uncheck("Motor")
        A_IconTip := "Marco (Bloodlines) | motor: " (this.Config.masterEnabled ? "on" : "off")
            " | Roblox: " MarcoApplication.FocusLabel(this.Focus ? this.Focus.Status : "Not detected")
    }

    static FocusLabel(status) => status = "Connected" ? "focused" : status = "Unfocused" ? "idle" : "off"

    FocusChanged(hwnd, previous, status) {
        this.Engine.FocusChanged(hwnd, previous)
        ; GUI work runs later, keeping the foreground callback short.
        SetTimer(this.PublishTimer, -1)
    }

    PublishState(*) {
        if this.Closing
            return
        this.UpdateTray()
        this.Bridge.Publish()
        this.UpdateOverlay()
    }

    QueuePublish(*) {
        if !this.Closing
            SetTimer(this.PublishTimer, -1)
    }

    UpdateOverlay() {
        if this.Overlay && !this.Closing
            this.Overlay.Refresh()
    }

    OverlayToggle(field, *) {
        try {
            this.SettingChanged(field, this.Config.%field% ? "0" : "1")
            this.Bridge.Publish()
        } catch Error as err {
            this.Overlay.ShowError("Falha ao salvar")
            this.Log("Overlay setting failed: " err.Message)
        }
    }

    SaveOverlayPosition(x, y) {
        next := SettingsStore.Copy(this.Config)
        next.overlayX := x
        next.overlayY := y
        try this.Commit(next)
        catch Error as err {
            this.Overlay.ShowError("Posição não salva")
            this.Log("Overlay position failed: " err.Message)
        }
    }

    DeliverPendingNotice() {
        if this.PendingNotice {
            message := this.PendingNotice
            this.PendingNotice := ""
            this.Bridge.Notice("error", message)
        }
    }

    SettingChanged(name, value) {
        next := SettingsStore.Copy(this.Config)
        switch name {
            case "masterEnabled", "movementEnabled", "numericEnabled", "shiftlockCenter", "resumeAfterM1", "startWithWindows", "startMinimized", "minimizeOnClose":
                if value != "0" && value != "1"
                    throw ValueError("Valor booleano inválido.")
                next.%name% := value = "1"
            case "wInterval", "clickDelay", "weaponReturnDelay", "runResumeDelay":
                if !RegExMatch(value, "^\d{1,4}$")
                    throw ValueError("Informe um intervalo inteiro em milissegundos.")
                maximum := name = "wInterval" ? 250 : name = "clickDelay" ? 1000 : 2000
                number := Integer(value)
                if number < 20 || number > maximum
                    throw ValueError("O intervalo deve estar entre 20 e " maximum " ms.")
                next.%name% := number
            default: throw ValueError("Configuração desconhecida.")
        }
        this.Commit(next)
    }

    BindingChanged(key, action) {
        action := StrLower(action)
        if !this.Config.binds.Has(key) || !SettingsStore.ValidAction(action)
            throw ValueError("Tecla ou ação inválida.")
        next := SettingsStore.Copy(this.Config)
        if action = "weapon" {
            for otherKey, otherAction in next.binds
                if otherKey != key && otherAction = "weapon"
                    next.binds[otherKey] := "disabled"
        }
        next.binds[key] := action
        this.Commit(next)
    }

    TriggerChanged(slot, value) {
        key := KeyBindings.Canonical(value)
        if !this.Config.binds.Has(slot) || key = ""
            throw ValueError("Use uma tecla suportada. W é reservada ao Double Tap; numpad e combinações não são aceitos.")
        for otherSlot, otherKey in this.Config.triggers
            if otherSlot != slot && otherKey = key
                throw ValueError("A tecla " key " já está configurada em outro macro. Altere essa tecla primeiro.")
        next := SettingsStore.Copy(this.Config)
        next.triggers[slot] := key
        this.Commit(next)
    }

    ToggleMaster() {
        next := SettingsStore.Copy(this.Config)
        next.masterEnabled := !next.masterEnabled
        this.Commit(next)
    }

    RestoreDefaults() {
        this.Commit(SettingsStore.Defaults())
        this.Bridge.Notice("success", "Configurações padrão restauradas.")
    }

    Commit(next) {
        previous := this.Config
        ; Register inactive hook variants before saving, so a failure cannot confirm
        ; settings which the engine was unable to prepare.
        this.Engine.PrepareTriggers(next)
        startupChanged := next.startWithWindows != previous.startWithWindows
        if startupChanged
            StartupManager.SetEnabled(next.startWithWindows)
        try this.Store.Save(next)
        catch Error as err {
            if startupChanged
                try StartupManager.SetEnabled(previous.startWithWindows)
            throw err
        }
        this.Config := next
        this.Engine.Configure(next)
        this.UpdateTray()
        this.UpdateOverlay()
    }

    PowerChanged(event, *) {
        ; Suspend/resume must discard pending work even if the foreground is stale.
        if (event = 4 || event = 7 || event = 0x12) && this.Engine {
            this.Engine.CancelMovement()
            this.Engine.CancelNumeric()
        }
        return true
    }

    StartupFailed(err) {
        if this.Closing
            return
        this.Log("Startup failed: " err.Message " | " err.File ":" err.Line)
        this.Shutdown()
        MsgBox("Não foi possível abrir Marco (Bloodlines).`n`n" err.Message
            "`n`nVerifique o Microsoft Edge WebView2 Runtime (Evergreen) e os arquivos do projeto.`nConsulte o README para os requisitos.",
            "Marco (Bloodlines)", "Iconx")
        ExitApp(1)
    }

    UnexpectedError(err, mode) {
        this.Log("Unhandled error: " err.Message " | " err.File ":" err.Line)
        this.Shutdown()
        MsgBox("O aplicativo foi encerrado e as ações pendentes foram canceladas.`n`n"
            err.Message "`nArquivo: " err.File "`nLinha: " err.Line, "Marco (Bloodlines)", "Iconx")
        ExitApp(1)
        return 1
    }

    Shutdown(*) {
        if this.Closing
            return
        this.Closing := true
        this.Log("Shutdown")
        SetTimer(this.PublishTimer, 0)
        ; Release keyboard input before disposing any UI/COM resources.
        if this.Engine
            this.Engine.Stop()
        if this.Focus
            this.Focus.Stop()
        if this.Overlay
            this.Overlay.Dispose()
        if this.Host
            this.Host.Dispose()
    }

    Log(message) {
        if this.HasOwnProp("LogPath")
            try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", this.LogPath, "UTF-8")
    }
}
