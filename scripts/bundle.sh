#!/bin/zsh
# リリースビルドして build/Disk Ledger.app を作る。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product DiskLedger
BIN="$(swift build -c release --show-bin-path)/DiskLedger"
APP="build/Disk Ledger.app"

/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskLedger"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>ja</string>
	<key>CFBundleExecutable</key><string>DiskLedger</string>
	<key>CFBundleIdentifier</key><string>io.github.kuridanho.DiskLedger</string>
	<key>CFBundleName</key><string>Disk Ledger</string>
	<key>CFBundleDisplayName</key><string>Disk Ledger</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# ローカル署名。署名が変わるとフルディスクアクセスの許可が外れるので、作り直したら許可し直す。
codesign --force --options runtime --sign - "$APP"
echo "$APP"
