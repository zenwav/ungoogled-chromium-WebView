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

LIB_SHA256=$("$APKSIGNER" verify --print-certs "$RELEASE_DIR/TrichromeLibrary.apk" 2>/dev/null \
    | grep -m1 "certificate SHA-256 digest" | awk '{print $NF}' | tr -d ':')
echo "TrichromeLibrary certificate SHA-256: $LIB_SHA256"

echo "=== Aligning TrichromeWebView certDigest with Release Certificate ==="
PYTHON=$(command -v python3 || command -v python)
"$PYTHON" -c "
import zipfile, os, shutil, sys

apk_path = sys.argv[1]
new_sha = sys.argv[2].strip().lower()

with zipfile.ZipFile(apk_path, 'r') as z_in:
    manifest = z_in.read('AndroidManifest.xml')

    # Chromium default trichrome_certdigest
    default_digest = '32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0'
    u8_old = default_digest.encode('ascii')
    u8_new = new_sha.encode('ascii')
    u16_old = default_digest.encode('utf-16le')
    u16_new = new_sha.encode('utf-16le')

    replaced = False
    if u8_old in manifest:
        manifest = manifest.replace(u8_old, u8_new)
        replaced = True
    elif u16_old in manifest:
        manifest = manifest.replace(u16_old, u16_new)
        replaced = True

    if replaced:
        temp_apk = apk_path + '.tmp'
        with zipfile.ZipFile(temp_apk, 'w') as z_out:
            for item in z_in.infolist():
                if item.filename.startswith('META-INF/'):
                    continue
                data = manifest if item.filename == 'AndroidManifest.xml' else z_in.read(item.filename)
                z_out.writestr(item, data)
        shutil.move(temp_apk, apk_path)
        print('Updated certDigest in TrichromeWebView AndroidManifest.xml to:', new_sha)
    else:
        print('Notice: default certDigest not found in manifest')
" "$RAW_WEB" "$LIB_SHA256"

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
