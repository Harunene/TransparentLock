#!/bin/zsh
# TransparentLock.app 빌드
#   ./build.sh            빌드만
#   ./build.sh --install  /Applications에 설치하고 Dock에 등록
set -e
cd "$(dirname "$0")"
APP=TransparentLock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/TransparentLock"
swift make_icon.swift
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.transparentlock</string>
  <key>CFBundleName</key><string>TransparentLock</string>
  <key>CFBundleExecutable</key><string>TransparentLock</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "빌드 완료: $(pwd)/$APP"

if [[ "$1" == "--install" ]]; then
  DEST=/Applications/$APP
  pkill -f "$DEST/Contents/MacOS/TransparentLock" || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  touch "$DEST"  # Finder/Dock 아이콘 캐시 갱신
  if ! defaults read com.apple.dock persistent-apps | grep -q "$DEST"; then
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://$DEST/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
    killall Dock
    echo "Dock에 등록함"
  fi
  echo "설치 완료: $DEST"
fi
