#Requires AutoHotkey v2.0.19+
#SingleInstance Force
#MaxThreadsPerHotkey 1
#UseHook
#InputLevel 0
;@Ahk2Exe-SetName Marco (Bloodlines)
;@Ahk2Exe-SetDescription Marco (Bloodlines) - local macro utility
;@Ahk2Exe-SetVersion 1.5.0
;@Ahk2Exe-SetMainIcon assets\marco.ico

#Include vendor\WebView2\WebView2.ahk
#Include src\Resources.ahk
#Include src\KeyBindings.ahk
#Include src\SettingsStore.ahk
#Include src\StartupManager.ahk
#Include src\FocusMonitor.ahk
#Include src\RobloxInput.ahk
#Include src\MacroEngine.ahk
#Include src\JsonWriter.ahk
#Include src\UiBridge.ahk
#Include src\WebViewHost.ahk
#Include src\Overlay.ahk
#Include src\App.ahk

SetWorkingDir(A_ScriptDir)
SendMode("Event")
SendLevel(0)
SetKeyDelay(-1, -1)
SetMouseDelay(-1)
Thread("Interrupt", 0)
A_MaxHotkeysPerInterval := 1000
InstallKeybdHook()
; Physical mouse state is used to avoid releasing a button held by the user.
InstallMouseHook()

; The hidden window and asynchronous COM callbacks do not keep AHK alive.
; Stay running until ExitApp, including while WebView2 initializes or hides to tray.
Persistent(true)
global MarcoApp := MarcoApplication()
MarcoApp.Start()
