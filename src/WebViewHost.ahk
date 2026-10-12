class WebViewHost {
    static DocumentUrl := "https://bloodlines.invalid/index.html"

    __New(app, resourceDir) {
        this.App := app
        this.ResourceDir := resourceDir
        this.Controller := 0
        this.Core := 0
        this.Events := []
        this.AutoFit := true
        this.SizingHandler := ObjBindMethod(this, "UserSizing")
        this.StartupTimer := ObjBindMethod(this, "StartupTimedOut")
        this.Window := Gui("+Resize +MinSize640x200", "Marco (Bloodlines)")
        this.Window.BackColor := "0D0D0D"
        this.Window.SetFont("s9 c858585", "Consolas")
        this.Loading := this.Window.AddText("x16 y16 w580 h40", "Marco (Bloodlines)`nCarregando…")
        this.Window.OnEvent("Close", ObjBindMethod(this, "CloseRequested"))
        this.Window.OnEvent("Escape", ObjBindMethod(this, "CloseRequested"))
        this.Window.OnEvent("Size", ObjBindMethod(this, "Resized"))
        OnMessage(0x214, this.SizingHandler)
        this.DarkTitleBar()
        ; Initialize a hidden client area so WebView2 can size itself before showing.
        scale := A_ScreenDPI / 96
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        width := Min(720, Max(640, Floor((right - left) / scale) - 64))
        height := Min(340, Max(200, Floor((bottom - top) / scale) - 96))
        this.Window.Show("Hide w" width " h" height)
    }

    DarkTitleBar() {
        try {
            dark := Buffer(4, 0)
            NumPut("int", 1, dark)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", this.Window.Hwnd, "uint", 20, "ptr", dark, "uint", 4)
            caption := Buffer(4, 0)
            NumPut("uint", 0x000D0D0D, caption)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", this.Window.Hwnd, "uint", 35, "ptr", caption, "uint", 4)
        }
    }

    Start(dataDir) {
        this.App.Log("Requesting WebView2 controller")
        if !this.App.Config.startMinimized
            this.Show()
        SetTimer(this.StartupTimer, -30000)
        loader := this.ResourceDir "\vendor\WebView2\64bit\WebView2Loader.dll"
        if !FileExist(loader)
            throw Error("WebView2Loader.dll não encontrado. Preserve a estrutura da pasta do projeto.")
        DirCreate(dataDir "\WebView2")
        options := {AdditionalBrowserArguments: "--disable-background-networking --no-first-run"}
        this.Creation := WebView2.CreateControllerAsync(this.Window.Hwnd, options,
            dataDir "\WebView2", "", loader).then(ObjBindMethod(this, "Created"))
            .catch(ObjBindMethod(this.App, "StartupFailed"))
        this.App.Log("WebView2 request submitted")
    }

    Created(controller) {
        this.App.Log("WebView2 controller callback")
        if this.App.Closing {
            controller.Close()
            return
        }
        ; Explicitly query the interfaces used by extended COM methods.
        this.Controller := controller.as(WebView2.Controller, WebView2.Controller.IID_2)
        ; COREWEBVIEW2_COLOR stores bytes as A, R, G, B (little-endian uint).
        ; Alpha must be 0 or 255; an ARGB integer would pass alpha 0x13.
        this.Controller.DefaultBackgroundColor := 0x0D0D0DFF
        this.Core := this.Controller.CoreWebView2.as(WebView2.Core, WebView2.Core.IID_3)
        settings := this.Core.Settings
        settings.IsStatusBarEnabled := false
        settings.AreDevToolsEnabled := false
        settings.AreDefaultContextMenusEnabled := false
        settings.AreDefaultScriptDialogsEnabled := false
        settings.AreHostObjectsAllowed := false
        settings.IsZoomControlEnabled := false
        this.Core.SetVirtualHostNameToFolderMapping("bloodlines.invalid", this.ResourceDir "\ui", 0)
        this.Events.Push(this.Core.WebMessageReceived(ObjBindMethod(this.App.Bridge, "Receive")))
        this.Events.Push(this.Core.NavigationStarting(ObjBindMethod(this, "NavigationStarting")))
        this.Events.Push(this.Core.NavigationCompleted(ObjBindMethod(this, "NavigationCompleted")))
        this.Events.Push(this.Core.FrameNavigationStarting(ObjBindMethod(this, "NavigationStarting")))
        this.Events.Push(this.Core.NewWindowRequested(ObjBindMethod(this, "NewWindowRequested")))
        this.Events.Push(this.Core.PermissionRequested(ObjBindMethod(this, "PermissionRequested")))
        this.Events.Push(this.Core.ProcessFailed(ObjBindMethod(this, "ProcessFailed")))
        this.Core.AddWebResourceRequestedFilter("*", 0)
        this.Events.Push(this.Core.WebResourceRequested(ObjBindMethod(this, "ResourceRequested")))
        this.App.HostReady()
        this.Core.Navigate(WebViewHost.DocumentUrl)
        this.Loading.Visible := false
        this.Controller.Fill()
        if !this.App.Config.startMinimized
            this.Show()
        else
            this.Controller.IsVisible := false
    }

    NavigationStarting(sender, args) {
        if args.Uri != WebViewHost.DocumentUrl
            args.Cancel := true
    }

    NavigationCompleted(sender, args) {
        if !args.IsSuccess
            this.App.StartupFailed(Error("Falha ao carregar a interface local. Código WebView2: " args.WebErrorStatus))
    }

    InterfaceReady() {
        SetTimer(this.StartupTimer, 0)
        this.App.Log("Interface connected to macro engine")
        this.App.QueuePublish()
    }

    StartupTimedOut(*) {
        this.App.StartupFailed(Error("A interface não concluiu a inicialização em 30 segundos."))
    }

    ResourceRequested(sender, args) {
        if InStr(args.Request.Uri, "https://bloodlines.invalid/") != 1
            args.Response := this.Core.Environment.CreateWebResourceResponse(
                WebView2.CreateMemStream(), 403, "Forbidden", "Content-Type: text/plain")
    }

    NewWindowRequested(sender, args) => args.Handled := true
    PermissionRequested(sender, args) => args.State := 2

    ProcessFailed(sender, args) {
        SetTimer(ObjBindMethod(this.App, "StartupFailed",
            Error("O processo da interface WebView2 parou de responder ou foi encerrado.")), -1)
    }

    Show(*) {
        this.Window.Show()
        if WinGetMinMax(this.Window.Hwnd) = -1
            WinRestore(this.Window.Hwnd)
        if this.Controller {
            this.Controller.IsVisible := true
            this.Controller.Fill()
            this.Controller.MoveFocus(0)
        }
        this.App.QueuePublish()
    }

    Hide() {
        this.Window.Hide()
        if this.Controller
            this.Controller.IsVisible := false
        this.App.QueuePublish()
    }

    CloseRequested(*) {
        if this.App.Config.minimizeOnClose
            this.Hide()
        else
            ExitApp()
    }

    Resized(gui, minMax, width, height) {
        if this.Controller && minMax != -1
            this.Controller.Fill()
    }

    UserSizing(wParam, lParam, msg, hwnd) {
        if hwnd = this.Window.Hwnd
            this.AutoFit := false
    }

    FitContent(cssHeight) {
        ; Fit only until the user resizes. This changes presentation, never settings.
        if !this.AutoFit || this.App.Closing
            || DllCall("user32\IsIconic", "ptr", this.Window.Hwnd)
            || DllCall("user32\IsZoomed", "ptr", this.Window.Hwnd)
            return
        this.Window.GetPos(, &y, , &outerHeight)
        this.Window.GetClientPos(, , , &clientHeight)
        systemScale := A_ScreenDPI / 96
        windowDpi := DllCall("user32\GetDpiForWindow", "ptr", this.Window.Hwnd, "uint")
        target := Ceil(cssHeight * (windowDpi ? windowDpi : A_ScreenDPI) / A_ScreenDPI)
            + outerHeight - clientHeight
        monitor := DllCall("user32\MonitorFromWindow", "ptr", this.Window.Hwnd, "uint", 2, "ptr")
        info := Buffer(40, 0)
        NumPut("uint", 40, info)
        if DllCall("user32\GetMonitorInfoW", "ptr", monitor, "ptr", info) {
            top := NumGet(info, 24, "int")
            bottom := NumGet(info, 32, "int")
            target := Min(target, Floor((bottom - top) / systemScale))
            y := Max(top, Min(y, bottom - Ceil(target * systemScale)))
        }
        this.Window.Move(, y, , target)
    }

    Dispose() {
        OnMessage(0x214, this.SizingHandler, 0)
        SetTimer(this.StartupTimer, 0)
        try this.Events.Clear()
        if this.Controller
            try this.Controller.Close()
        this.Core := 0
        this.Controller := 0
        try this.Window.Destroy()
    }
}
