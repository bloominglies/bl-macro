# Third-party notices

Project code and assets use the MIT license in `LICENSE`. The components below retain their upstream licenses. Vendored files and their notices are preserved without modification.

## Included components

| Component | Version / source | License notice |
| --- | --- | --- |
| WebView2.ahk | thqby, 2.0.5 | `vendor/licenses/thqby-MIT.txt` (MIT) |
| Promise.ahk | thqby, 1.0.10 | `vendor/licenses/thqby-MIT.txt` (MIT) |
| ComVar.ahk | thqby, pinned revision below | `vendor/licenses/thqby-MIT.txt` (MIT) |
| WebView2Loader.dll, x64 | Microsoft.Web.WebView2 1.0.2903.40 | `vendor/licenses/Microsoft-WebView2.txt` and `Microsoft-NOTICE.txt` |

The AHK libraries are pinned to [ahk2_lib commit 06aed7a1c42f754dfcb67962d055311a480d0848](https://github.com/thqby/ahk2_lib/tree/06aed7a1c42f754dfcb67962d055311a480d0848).

The loader comes from `runtimes/win-x64/native/WebView2Loader.dll` in the official [Microsoft.Web.WebView2 1.0.2903.40 NuGet package](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2903.40). The Microsoft notice files accompany the loader; they are separate from the installed Evergreen Runtime's terms.

## AutoHotkey runtime and build tool

AutoHotkey is not included in this source tree. Compiled releases embed the unmodified x64 interpreter selected by `build.ps1`. [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) is distributed under the GNU General Public License, version 2; its license is copied from the selected installation to `dist/licenses/AutoHotkey-license.txt`.

`dist/licenses/AutoHotkey-SOURCE.txt` records that runtime's version, SHA-256 and upstream source location. Release distributors should provide the corresponding runtime source together with the release. This project's MIT license does not replace the runtime's license.

[Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe) is a build-time tool and is not bundled with the application. Microsoft Edge WebView2 Evergreen Runtime is installed separately and is not included in the release.

## File integrity

SHA-256 values for the vendored components:

```text
WebView2.ahk
3192AB02C276E06EA4FC16524128B2ECB02BDDBBADE79F118F5A76D61E4604FC

Promise.ahk
9369562490FB509943B93FD603FA553C42347F5FBD108DACC6079EA7759A4C30

ComVar.ahk
4102D3BFC358B17565547AEE155214367F7EA8110DB1D81CCDE6398054AB3215

WebView2Loader.dll (x64)
462B36FD1BE6CA9F7563466A89E57C41EF4A4DEF3E0A84FA885D203AEA4A3AAF
```

Builds copy all files from `vendor/licenses/` into `dist/licenses/`. Keep these notices with redistributed binaries and sources.
