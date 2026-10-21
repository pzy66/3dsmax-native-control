-- Template: start-max.ps1 substitutes the two @@...@@ placeholders.
(
    global codexNativeTimer
    global codexNativeBusy = false
    global codexNativeSession = @"@@SESSION_DIRECTORY@@"
    global codexNativeToken = "@@SESSION_TOKEN@@"
    global codexNativeWriteUtf8
    global codexNativeTick

    fn codexNativeWriteUtf8 filePath message = (
        (dotNetClass "System.IO.File").WriteAllText filePath message (dotNetObject "System.Text.UTF8Encoding" true)
    )

    fn codexNativeTick sender args = (
        local pendingPath = codexNativeSession + "\\pending.ms"
        if not codexNativeBusy and doesFileExist pendingPath do (
            codexNativeBusy = true
            codexNativeTimer.Stop()
            try (fileIn pendingPath) catch (
                codexNativeWriteUtf8 (codexNativeSession + "\\bridge_error.txt") (getCurrentException() as string)
            )
            local taskConsumed = false
            try (taskConsumed = deleteFile pendingPath) catch (
                codexNativeWriteUtf8 (codexNativeSession + "\\bridge_error.txt") (getCurrentException() as string)
            )
            if taskConsumed then (
                codexNativeBusy = false
                codexNativeTimer.Start()
            ) else (
                codexNativeWriteUtf8 (codexNativeSession + "\\bridge_error.txt") "Queue paused: pending.ms could not be removed. Inspect the completed job before recovery; do not replay it."
            )
        )
    )

    try (
        autoBackup.enabled = false
        codexNativeTimer = dotNetObject "System.Windows.Forms.Timer"
        codexNativeTimer.Interval = 800
        dotNet.addEventHandler codexNativeTimer "Tick" codexNativeTick
        local taskProcess = (dotNetClass "System.Diagnostics.Process").GetCurrentProcess()
        local readyText = "PID=" + (taskProcess.Id as string) + "\nTOKEN=" + codexNativeToken + "\nPLUGCFG=" + (getDir #plugcfg) + "\nVERSION=" + (maxVersion() as string) + "\n"
        codexNativeWriteUtf8 (codexNativeSession + "\\ready.txt") readyText
        codexNativeTimer.Start()
    ) catch (
        codexNativeWriteUtf8 (codexNativeSession + "\\bridge_error.txt") (getCurrentException() as string)
    )
)
