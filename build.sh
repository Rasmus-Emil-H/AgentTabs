#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=AgentTabs.app
mkdir -p $APP/Contents/MacOS
cp .build/release/AgentTabs $APP/Contents/MacOS/
mkdir -p $APP/Contents/Resources
cp AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentTabs</string>
<key>CFBundleIdentifier</key><string>local.agenttabs</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>AgentTabs</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "Built $(pwd)/$APP"

ditto "$APP" /Applications/AgentTabs.app
echo "Installed /Applications/AgentTabs.app"
