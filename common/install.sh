#!/system/bin/sh

unzip -j "$MODPATH/bin/curl64.zip" -d "$MODPATH/bin"
chmod 0755 "$MODPATH/bin/curl"
CURL_BIN="$MODPATH/bin/curl"

dl() {
	url="$1"; out="$2"; n=1
	while [[ $n -le 5 ]]; do
		echo "Attempt $n of 5..."
		if [[ $n -le 3 ]]; then
			"$CURL_BIN" --fail --location --connect-timeout 15 --retry 2 --retry-delay 3 \
				--dns-servers 1.1.1.1,1.0.0.1 -o "$out" "$url"
		else
			"$CURL_BIN" --fail --location --connect-timeout 15 --retry 2 --retry-delay 3 \
				-o "$out" "$url"
		fi
		[[ -s "$out" ]] && return 0
		rm -f "$out"
		sleep 5
		n=$((n + 1))
	done
	return 1
}

LOS=$(getprop | grep -o -c "lineage")

if [[ $LOS -gt 0 ]]; then
	TLP=/system/product/app/TrichromeLibrary
	WVP=/system/product/app/TrichromeWebView
else
	TLP=/system/app/TrichromeLibrary
	WVP=/system/app/TrichromeWebView
fi
mkdir -p "$MODPATH/$TLP" "$MODPATH/$WVP"

MODULE_VERSION=$(grep '^version=' "$MODPATH/module.prop" | cut -d= -f2)

BASE_URL="https://github.com/zenwav/ungoogled-chromium-WebView/releases/download/${MODULE_VERSION}"
TRI_URL="${BASE_URL}/TrichromeLibrary.apk"
WEB_URL="${BASE_URL}/TrichromeWebView.apk"

ui_print "Installing TrichromeLibrary..."
dl "$TRI_URL" "$MODPATH/$TLP/TrichromeLibrary.apk" || abort "Download failed: TrichromeLibrary"
cp "$MODPATH/$TLP/TrichromeLibrary.apk" /data/local/tmp/
pm install -r --install-location 1 /data/local/tmp/TrichromeLibrary.apk
rm -f /data/local/tmp/TrichromeLibrary.apk

ui_print "Installing Ungoogled Chromium WebView..."
dl "$WEB_URL" "$MODPATH/$WVP/TrichromeWebView.apk" || abort "Download failed: WebView"
cp "$MODPATH/$WVP/TrichromeWebView.apk" /data/local/tmp/
pm install -r --install-location 1 /data/local/tmp/TrichromeWebView.apk
rm -f /data/local/tmp/TrichromeWebView.apk

if [[ $LOS -gt 0 ]]; then
	OVERLAY_PATH=system/product/overlay/
elif [[ -d /system/product/overlay ]]; then
	OVERLAY_PATH=system/product/overlay/
elif [[ -d /system_ext/overlay ]]; then
	OVERLAY_PATH=system/system_ext/overlay/
elif [[ -d /system/overlay ]]; then
	OVERLAY_PATH=system/overlay/
elif [[ -d /system/vendor/overlay ]]; then
	OVERLAY_PATH=system/vendor/overlay/
else
	abort "No overlay partition found"
fi
mkdir -p "$MODPATH/$OVERLAY_PATH"
cp "$MODPATH/Overlay/WebViewOverlay29.apk" "$MODPATH/$OVERLAY_PATH/WebViewOverlay.apk"

rm -rf "$MODPATH/bin/"*.zip "$MODPATH/system/.placeholder" "$MODPATH/Overlay" "$MODPATH/common"
