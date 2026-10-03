#!/usr/bin/env bash
set -euo pipefail

UGC_WORK="${UGC_WORK:-/mnt/ugc}"
OUT="${UGC_WORK}/src/out/Default"
RELEASE_DIR="${GITHUB_WORKSPACE}/release_assets"
mkdir -p "$RELEASE_DIR"

# Ensure JDK from Chromium checkout is available
_TREE_JDK="${UGC_WORK}/src/third_party/jdk/current/bin"
if [ -x "$_TREE_JDK/java" ]; then
    JAVA_HOME="$(cd "$_TREE_JDK/.." && pwd)"
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
fi

APKSIGNER="${UGC_WORK}/src/third_party/android_sdk/public/build-tools/37.0.0/apksigner"
if [ ! -x "$APKSIGNER" ]; then
    APKSIGNER=$(find "${UGC_WORK}/src/third_party/android_sdk" -name apksigner -type f -perm /111 2>/dev/null | head -1)
fi
if [ ! -x "$APKSIGNER" ]; then
    APKSIGNER=$(command -v apksigner || true)
fi
if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
    echo "FATAL: apksigner binary not found or not executable"
    exit 1
fi

echo "=== Staging Keystore ==="
KS_PATH="/tmp/release.keystore"
KS_ALIAS="${KEYSTORE_ALIAS:-ungoogled-chromium-signing-key}"
export KS_PASS="${KEYSTORE_PASS:-}"
trap 'rm -f "$KS_PATH"' EXIT

if [ -n "${KEYSTORE_B64:-}" ]; then
    printf '%s' "${KEYSTORE_B64}" | base64 -d > "$KS_PATH"
else
    echo "FATAL: KEYSTORE_B64 is not provided"
    exit 1
fi

echo "=== Locating and Signing Trichrome APKs ==="
RAW_LIB=$(find "$OUT/apks" -name "TrichromeLibrary*64*.apk" 2>/dev/null | head -1)
[ -n "$RAW_LIB" ] || RAW_LIB=$(find "$OUT/apks" -name "TrichromeLibrary*.apk" 2>/dev/null | head -1)

RAW_WEB=$(find "$OUT/apks" -name "TrichromeWebView*64*.apk" 2>/dev/null | head -1)
[ -n "$RAW_WEB" ] || RAW_WEB=$(find "$OUT/apks" -name "TrichromeWebView*.apk" 2>/dev/null | head -1)

[ -n "$RAW_LIB" ] || { echo "FATAL: TrichromeLibrary APK not found in $OUT/apks"; exit 1; }
[ -n "$RAW_WEB" ] || { echo "FATAL: TrichromeWebView APK not found in $OUT/apks"; exit 1; }
echo "Found TrichromeLibrary APK: $RAW_LIB"
echo "Found TrichromeWebView APK: $RAW_WEB"

"$APKSIGNER" sign --ks "$KS_PATH" --ks-key-alias "$KS_ALIAS" \
    --ks-pass "env:KS_PASS" --key-pass "env:KS_PASS" \
    --in "$RAW_LIB" --out "$RELEASE_DIR/TrichromeLibrary.apk"

"$APKSIGNER" sign --ks "$KS_PATH" --ks-key-alias "$KS_ALIAS" \
    --ks-pass "env:KS_PASS" --key-pass "env:KS_PASS" \
    --in "$RAW_WEB" --out "$RELEASE_DIR/TrichromeWebView.apk"

echo "=== Verifying Signatures ==="
"$APKSIGNER" verify --print-certs "$RELEASE_DIR/TrichromeLibrary.apk"
"$APKSIGNER" verify --print-certs "$RELEASE_DIR/TrichromeWebView.apk"

echo "=== Aligning Overlay APK with Release Certificate ==="
PYTHON=$(command -v python3 || command -v python)
"$PYTHON" .github/scripts/align-overlay.py Overlay/WebViewOverlay29.apk "$RELEASE_DIR/TrichromeWebView.apk"
"$APKSIGNER" sign --ks "$KS_PATH" --ks-key-alias "$KS_ALIAS" \
    --ks-pass "env:KS_PASS" --key-pass "env:KS_PASS" \
    --min-sdk-version 29 \
    Overlay/WebViewOverlay29.apk
"$APKSIGNER" verify --min-sdk-version 29 --print-certs Overlay/WebViewOverlay29.apk

echo "=== Packaging Magisk / KernelSU Module ==="
sed -i "s/^version=.*/version=${UPSTREAM_TAG}/" module.prop
VCODE=$(echo "$UPSTREAM_TAG" | tr -cd '0-9' | cut -c1-8)
sed -i "s/^versionCode=.*/versionCode=${VCODE}/" module.prop
MODULE_ZIP="$RELEASE_DIR/Ungoogled-Chromium-WebView-Magisk-v${UPSTREAM_TAG}.zip"
zip -r9 "$MODULE_ZIP" \
    META-INF \
    bin \
    common \
    customize.sh \
    module.prop \
    Overlay \
    service.sh \
    system \
    uninstall.sh -x "*/.placeholder"

echo "=== Generating Checksums ==="
cd "$RELEASE_DIR"
sha256sum TrichromeLibrary.apk TrichromeWebView.apk "$(basename "$MODULE_ZIP")" > sha256sums.txt
cat sha256sums.txt

echo "=== Publishing Release ${UPSTREAM_TAG} ==="
if gh release view "$UPSTREAM_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo "Release ${UPSTREAM_TAG} already exists. Uploading/updating assets..."
    gh release upload "$UPSTREAM_TAG" \
        TrichromeLibrary.apk \
        TrichromeWebView.apk \
        "$(basename "$MODULE_ZIP")" \
        sha256sums.txt \
        --repo "$GITHUB_REPOSITORY" --clobber
else
    gh release create "$UPSTREAM_TAG" \
        TrichromeLibrary.apk \
        TrichromeWebView.apk \
        "$(basename "$MODULE_ZIP")" \
        sha256sums.txt \
        --repo "$GITHUB_REPOSITORY" \
        --title "Ungoogled Chromium WebView ${UPSTREAM_TAG}" \
        --notes "Automated release of Ungoogled Chromium Trichrome WebView ${UPSTREAM_TAG} for arm64 (Android 10+ / API 29+)."
fi
