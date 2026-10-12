class Resources {
    static Version := "1.5.0"

    static DataDirectory() {
        root := EnvGet("LOCALAPPDATA")
        if !root
            root := A_AppData "\..\Local"
        ; Keep the existing data location so saved bindings and preferences survive.
        path := root "\BloodlinesMacro"
        DirCreate(path)
        return path
    }

    static Prepare(dataDir) {
        if !A_IsCompiled
            return A_ScriptDir

        root := dataDir "\resources\" this.Version
        DirCreate(root "\ui")
        DirCreate(root "\assets")
        DirCreate(root "\vendor\WebView2\64bit")
        ; Literal source paths let Ahk2Exe embed all runtime resources.
        FileInstall("ui\index.html", root "\ui\index.html", 1)
        FileInstall("ui\styles.css", root "\ui\styles.css", 1)
        FileInstall("ui\app.js", root "\ui\app.js", 1)
        FileInstall("assets\marco.ico", root "\assets\marco.ico", 1)
        FileInstall("vendor\WebView2\64bit\WebView2Loader.dll", root "\vendor\WebView2\64bit\WebView2Loader.dll", 1)
        return root
    }
}
