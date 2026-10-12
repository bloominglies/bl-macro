# Marco (Bloodlines)

A Windows desktop macro utility for Bloodlines on Roblox. Built with AutoHotkey v2 and a local WebView2 interface.

Version **1.5.0** · Windows 10/11 x64

## Features

- **Double Tap W:** starts a double tap when W is pressed and holds the second press until W is released.
- **Resume after M1:** repeats the double tap after a left-click attack while W remains held.
- **Autocast:** adds a left or right click after a configured key is pressed. Ten bindings are available, initially 1–0.
- **Custom keys:** replace a binding's key without changing the key sent to the game. Binding Z means Roblox receives Z.
- **Weapon return:** select one binding as the weapon and return to it after an autocast.
- **Center aim:** optionally position the cursor at the game window's center before an autocast. Enable this manually when using shiftlock.
- **Overlay:** a draggable, always-on-top panel with engine, movement and autocast controls. It appears when the main window is unfocused.
- **Tray controls:** open the window, toggle the engine or exit. Startup and minimize behavior are configurable.

Macro input is sent only while `RobloxPlayerBeta.exe` is in the foreground. Losing focus cancels pending actions and releases held macro input.

## Run

Install the [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/#download-section), then open `MarcoBloodlines.exe` from the release folder. A local build places it in `dist/`.

The executable includes the AutoHotkey runtime and interface resources. AutoHotkey, Node.js and Python are not required to run it. Close a previous copy from its tray menu before opening an updated build.

To run from source, install [AutoHotkey v2](https://www.autohotkey.com/) **2.0.19 or later in the v2 series, x64**, keep the repository's directory structure and run:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' '.\Bloodlines.ahk'
```

## Configure

The header's **Motor** switch enables or pauses all macros. Roblox status is **focused**, **idle** (running in the background) or **off** (not detected). Feature switches show the saved preference; enabled features wait for Roblox to gain focus.

### Movement

| Setting | Default | Range |
| --- | --- | --- |
| Double tap interval | 60 ms | 20–250 ms |
| Resume after M1 | On | On / Off |
| Resume delay | 350 ms | 20–2000 ms |

The initial W tap lasts 24 ms, followed by the configured interval and a held second press. Windows key repeat does not restart the sequence.

Resume delay starts when the left mouse button is released. Each new attack restarts the delay; holding the button postpones recovery. Left clicks from autocast also schedule recovery. Releasing W, disabling movement or the engine, or losing Roblox focus cancels it. Recovery starts a fresh double tap after the delay, so allow additional time for that sequence and the game's animation. Increase the delay if the attack still prevents sprinting.

### Keybinds

Click a bracketed key, press its replacement and choose **Left Click**, **Right Click**, **Weapon** or **Disabled**. Escape cancels key capture. Each key can be assigned once; W is reserved for movement and numpad keys are excluded.

Supported keys: A–Z except W, top-row digits, F1–F12, Space, Tab, Enter, Backspace and navigation keys. Mouse buttons and key combinations such as Ctrl+Z are not assignable.

Configure the same key for the skill inside the game. For example, replacing `[7]` with `[Z]` makes Z trigger the autocast while passing Z through normally; it does not send 7 or change the game's bindings. Holding a key produces at most one autocast.

| Setting | Default | Range |
| --- | --- | --- |
| Click Delay | 80 ms | 20–1000 ms |
| Weapon Return | 150 ms | 20–2000 ms |
| Center aim | Off | On / Off |

Only one binding can be **Weapon**. It selects normally without an autocast. Weapon Return is counted after the skill's click and sends the weapon's configured key. A new bound key or a physical top-row digit cancels an older pending cast or weapon return.

**Center aim** must be switched on and off alongside shiftlock in Roblox. It moves the cursor to the client area's center and leaves it there; with the option off, cursor position is preserved. Keep the overlay away from the center, since a covered center point cancels the cast.

### Settings and overlay

Settings include starting with Windows, starting minimized, minimizing to the tray on close and restoring defaults. Use **Sair** in the tray menu to exit fully.

Drag **Marco** in the overlay to move it. The adjacent state toggles the engine; **W** and **cast** toggle movement and autocast; **open** restores the main window. Overlay position and preferences are saved locally.

- Configuration: `%LOCALAPPDATA%\BloodlinesMacro\settings.ini`
- Startup diagnostics: `%LOCALAPPDATA%\BloodlinesMacro\startup.log`

Missing or invalid settings fall back to defaults. Existing configuration files remain compatible.

## Build

Install AutoHotkey v2 x64 and the official [Ahk2Exe compiler](https://github.com/AutoHotkey/Ahk2Exe). From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

For a portable installation, supply explicit paths:

```powershell
.\build.ps1 -CompilerPath 'D:\AutoHotkey\Compiler\Ahk2Exe.exe' -BasePath 'D:\AutoHotkey\v2\AutoHotkey64.exe'
```

The build embeds the interface, icon and WebView2 loader in `dist/MarcoBloodlines.exe` and copies the README and license notices alongside it. It does not launch the application. If the runtime license is stored outside the AutoHotkey installation, supply `-RuntimeLicensePath`.

Publish the executable with `LICENSE`, `THIRD_PARTY.md` and the `licenses/` directory. Include the matching project sources and the corresponding AutoHotkey runtime source when distributing a release. The build records the runtime version and upstream source location in `licenses/AutoHotkey-SOURCE.txt`. Build output and logs are excluded from Git.

## Source layout

```text
Bloodlines.ahk       Entry point and compiler metadata
src/                Macro engine, focus handling, settings, UI bridge and overlay
ui/                 Local HTML, CSS and JavaScript
assets/             Application icon and SVG source
vendor/             Pinned WebView2 wrapper, loader and license notices
build.ps1           Windows x64 build and release files
```

## Limitations

The app observes the Roblox process, not the current experience. It cannot distinguish Bloodlines from other Roblox games, detect shiftlock, confirm weapon selection or read the character's sprint state. Input uses `SendEvent`; acceptance and timing depend on the game. No process injection, client modifications or anticheat bypasses are used.

## License

Project code and assets are licensed under [MIT](LICENSE). Dependencies retain their own licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
