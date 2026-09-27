#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="macOS Toolkit"
BUNDLE_ID="local.toolkit.mac"
BUILD_DIR=".build/release"
APP_DIR="dist"
ENTITLEMENTS="Resources/Toolkit.entitlements"
ICON_SOURCE="Resources/AppIcon.icns"

if [ ! -f "$ICON_SOURCE" ]; then
    echo "==> 生成应用图标..."
    swift scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o "$ICON_SOURCE"
fi

if [ "${1:-}" = "--install" ]; then
    echo "==> 编译并安装到 /Applications..."
    "$0"
    pkill -f "/Applications/macOS Toolkit.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/macOS Toolkit.app"
    cp -R "$APP_DIR/$APP_NAME.app" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/macOS Toolkit.app"
    open -a "/Applications/macOS Toolkit.app"
    echo "==> 已安装并启动: /Applications/macOS Toolkit.app"
    exit 0
fi

echo "==> 构建 release..."
swift build -c release

if [ ! -f "$BUILD_DIR/Toolkit" ]; then
    ACTUAL_BIN=$(find .build -name Toolkit -type f -perm +111 2>/dev/null | head -1)
    BUILD_DIR=$(dirname "$ACTUAL_BIN")
fi

echo "==> 编译 SMC helper..."
cc SMCHelper/main.c SMCCore/SMCCore.c -I SMCCore/include -o .build/smchelper -framework IOKit -Wall -Werror

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_DIR/$APP_NAME.app/Contents/Resources"

echo "==> 打包 .app..."
cp "$BUILD_DIR/Toolkit" "$APP_DIR/$APP_NAME.app/Contents/MacOS/Toolkit"
if [ -f ".build/smchelper" ]; then
    mkdir -p "$APP_DIR/$APP_NAME.app/Contents/Library/LaunchServices"
    cp .build/smchelper "$APP_DIR/$APP_NAME.app/Contents/Library/LaunchServices/local.toolkit.smchelper"
    codesign --force --sign - "$APP_DIR/$APP_NAME.app/Contents/Library/LaunchServices/local.toolkit.smchelper"
    cp SMCHelper/Info.plist "$APP_DIR/$APP_NAME.app/Contents/Library/LaunchServices/Info.plist"
fi
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/$APP_NAME.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Toolkit</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.toolkit.mac</string>
    <key>CFBundleName</key>
    <string>macOS Toolkit</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationsUsageDescription</key>
    <string>用于发送系统指标告警通知</string>
</dict>
</plist>
PLIST

if [ -f "$ENTITLEMENTS" ]; then
    echo "==> ad-hoc 签名..."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" --options runtime "$APP_DIR/$APP_NAME.app"
else
    codesign --force --sign - "$APP_DIR/$APP_NAME.app"
fi

echo "==> 刷新 Launch Services 注册..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP_DIR/$APP_NAME.app" || true

echo "==> 完成: $APP_DIR/$APP_NAME.app"
echo "    双击运行，或执行: open \"$APP_DIR/$APP_NAME.app\""
