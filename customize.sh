[[ $API -ge 29 ]] || abort "Android 10+ required"
[[ "$ARCH" = "arm64" ]] || abort "Only arm64 architecture is supported"

for part in product vendor system_ext; do
  src=$MODPATH/$part
  if [[ -d "$src" ]]; then
    mkdir -p $MODPATH/system/$part
    cp -a $src/* $MODPATH/system/$part
    rm -rf $src
  fi
done

. $MODPATH/common/install.sh

echo "After installation, go to:"
echo "1) Settings -> Developer options"
echo "2) WebView implementation"
echo "3) Select Ungoogled Chromium WebView"
echo
