#!/bin/zsh
# Export the Xcode project, build it signed, and install it on a connected iPhone.
# Usage: tools/ios_deploy.sh [device-udid]   (defaults to the first paired physical iPhone)
set -euo pipefail
cd "${0:A:h}/.."

mkdir -p build/ios
godot --headless --export-debug "iOS" build/ios/Boxing.xcodeproj > build/export.log 2>&1 \
	|| { tail -20 build/export.log; exit 1; }

xcodebuild -project build/ios/Boxing.xcodeproj -scheme Boxing -configuration Debug \
	-destination 'generic/platform=iOS' -derivedDataPath build/ios-derived \
	-allowProvisioningUpdates build > build/xcodebuild.log 2>&1 \
	|| { grep -E "error:" build/xcodebuild.log | head -20; exit 1; }

device="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
if [[ -z "$device" ]]; then
	echo "Built build/ios-derived/Build/Products/Debug-iphoneos/Boxing.app, but no unlocked, paired iPhone found."
	exit 1
fi
xcrun devicectl device install app --device "$device" build/ios-derived/Build/Products/Debug-iphoneos/Boxing.app > /dev/null
xcrun devicectl device process launch --device "$device" com.nathantau.boxing > /dev/null \
	|| echo "Installed. Unlock the phone and tap Boxing to launch."
echo "Done."
