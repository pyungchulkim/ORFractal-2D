#Requires AutoHotkey v2.0

; Apply shortcut only if L-studio, lpfg, or cpfg windows are active
#HotIf WinActive("ahk_exe lpfg.exe") or WinActive("ahk_exe cpfg.exe")

Space::
{
    Send "^w"       ; Sends Ctrl+W (Rewind)
    Sleep 50        ; Waits 50 milliseconds
    Send "^r"       ; Sends Ctrl+R (Rerun)
    return
}

#HotIf
