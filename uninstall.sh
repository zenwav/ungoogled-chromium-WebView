#!/system/bin/sh

waitUntilBootCompleted() {
    resetprop -w sys.boot_completed 0 && return
    while [[ $(getprop sys.boot_completed) -eq 0 ]]; do
        sleep 10
    done
}

(
    waitUntilBootCompleted
    sleep 3
    pm uninstall com.android.webview 2>/dev/null
    pm uninstall org.chromium.trichromelibrary 2>/dev/null
) &

