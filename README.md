# Ungoogled Chromium WebView Installer

This module replaces your system WebView with Ungoogled Chromium Trichrome WebView.

## Features
- Installs Ungoogled Chromium Trichrome Library
- Installs Ungoogled Chromium Trichrome WebView
- Works with Magisk and KernelSU (systemless)
- Automatic overlay configuration for Android 10+

## What is this project?
A Magisk/KernelSU module that replaces your system WebView implementation with Ungoogled Chromium Trichrome WebView, providing privacy-focused, degoogled web rendering for Android apps.

## Prerequisites
- Android 10+ (API level 29 or higher)
- arm64 architecture
- Magisk or KernelSU
- Magic Mount or OverlayFS
- Internet connection during installation (Wi-Fi recommended)

## Known Issues
- Curl may fail to download over mobile data. Use Wi-Fi if possible.
- On some devices, you may need to go into Developer options and manually select the WebView implementation.

## Installation Guide
1. Download the latest release of this module.
2. Flash it in Magisk or KernelSU.
3. Reboot your device.
4. Go to Settings.
5. Go to Developer options.
6. Go to WebView implementation.
7. Select Ungoogled Chromium WebView.

## Credits
- Ungoogled Chromium project
- Original module: WebView Changer by Lordify (https://gitlab.com/Lordify/webview-changer)
- Vanadium project (GrapheneOS)
- topjohnwu – for Magisk
- Tiann – for KernelSU
- Zackptg5 – for MMT-Extended
- F3FFO – for Open WebView module

## License
This project is licensed under the GNU General Public License v2.0 (GPL-3.0) or later.
You are free to modify and redistribute it under the same terms.

See the full [LICENSE](LICENSE) file for details.
