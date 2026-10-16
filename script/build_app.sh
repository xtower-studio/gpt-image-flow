#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_CONFIG="${1:-debug}"
TASK_BUNDLE="${2:-$TASK_ROOT/dist/ImageFlow.app}"
TASK_ARCH="${IMAGEFLOW_ARCH:-native}"
TASK_IDENTITY="${IMAGEFLOW_SIGN_IDENTITY:--}"
TASK_VERSION="$(cat "$TASK_ROOT/config/version.txt")"
case "$TASK_CONFIG" in debug|release) ;; *) echo 'Expected debug or release' >&2; exit 2;; esac
TASK_ARCH_ARGS=(--arch "$(uname -m)")
if [[ "$TASK_ARCH" == universal ]]; then TASK_ARCH_ARGS=(--arch arm64 --arch x86_64); fi
cp "$TASK_ROOT/config/generation-policy.json" "$TASK_ROOT/Sources/ImageFlow/Resources/generation-policy.json"
TASK_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build --package-path "$TASK_ROOT" -c "$TASK_CONFIG" "${TASK_ARCH_ARGS[@]}" --product ImageFlow \
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$TASK_SDK_VERSION"
TASK_BIN_DIR="$(swift build --package-path "$TASK_ROOT" -c "$TASK_CONFIG" "${TASK_ARCH_ARGS[@]}" --show-bin-path)"
TASK_LINKED_SDK="$(xcrun vtool -show-build "$TASK_BIN_DIR/ImageFlow" | awk '$1 == "sdk" { print $2; exit }')"
[[ "$TASK_LINKED_SDK" == "$TASK_SDK_VERSION" ]] || { echo 'Linked SDK mismatch' >&2; exit 1; }
mkdir -p "$TASK_BUNDLE/Contents/MacOS" "$TASK_BUNDLE/Contents/Resources"
install -m 755 "$TASK_BIN_DIR/ImageFlow" "$TASK_BUNDLE/Contents/MacOS/ImageFlow.next"
mv -f "$TASK_BUNDLE/Contents/MacOS/ImageFlow.next" "$TASK_BUNDLE/Contents/MacOS/ImageFlow"
# Replace the resource bundle so removed assets cannot survive an update.
rm -rf "$TASK_BUNDLE/Contents/Resources/ImageFlow_ImageFlow.bundle"
ditto "$TASK_BIN_DIR/ImageFlow_ImageFlow.bundle" "$TASK_BUNDLE/Contents/Resources/ImageFlow_ImageFlow.bundle"
cp "$TASK_ROOT/Sources/ImageFlow/Resources/ImageFlowIcon.icns" "$TASK_BUNDLE/Contents/Resources/"
cp "$TASK_ROOT/THIRD_PARTY_NOTICES.md" "$TASK_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cat > "$TASK_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ImageFlow</string>
<key>CFBundleIdentifier</key><string>studio.xtower.imageflow</string>
<key>CFBundleIconFile</key><string>ImageFlowIcon</string>
<key>CFBundleName</key><string>Image Flow</string>
<key>CFBundleDisplayName</key><string>Image Flow</string>
<key>CFBundleShortVersionString</key><string>$TASK_VERSION</string>
<key>CFBundleVersion</key><string>13</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Distributed by DEAUM (Daeummoyang) · 다음모양. Designed and developed by xtower.</string>
</dict></plist>
PLIST
if [[ "$TASK_IDENTITY" == - ]]; then
  codesign --force --sign - "$TASK_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$TASK_IDENTITY" "$TASK_BUNDLE"
fi
codesign --verify --deep --strict "$TASK_BUNDLE"
echo "Built: $TASK_BUNDLE"
