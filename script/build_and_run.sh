#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:-run}"
TASK_BUNDLE="$TASK_ROOT/dist/ImageFlow.app"
case "$TASK_MODE" in run|--verify|--connect|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--verify|--connect|--debug|--logs|--telemetry]" >&2; exit 2;; esac
pkill -x ImageFlow >/dev/null 2>&1 || true
cp "$TASK_ROOT/config/generation-policy.json" "$TASK_ROOT/Sources/ImageFlow/Resources/generation-policy.json"
# SwiftPM's swiftbuild backend can stamp the deployment target as the SDK.
# AppKit uses the linked SDK to select its appearance. Record the real SDK while
# retaining macOS 14 as the minimum supported runtime.
TASK_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build --package-path "$TASK_ROOT" --product ImageFlow \
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$TASK_SDK_VERSION"
TASK_BIN_DIR="$(swift build --package-path "$TASK_ROOT" --show-bin-path)"
TASK_LINKED_SDK="$(xcrun vtool -show-build "$TASK_BIN_DIR/ImageFlow" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$TASK_LINKED_SDK" != "$TASK_SDK_VERSION" ]]; then
  echo "Linked SDK $TASK_LINKED_SDK does not match installed SDK $TASK_SDK_VERSION" >&2
  exit 1
fi
mkdir -p "$TASK_BUNDLE/Contents/MacOS" "$TASK_BUNDLE/Contents/Resources" "$TASK_ROOT/.runtime"
# Replace the executable inode to avoid reusing a cached code signature.
install -m 755 "$TASK_BIN_DIR/ImageFlow" "$TASK_BUNDLE/Contents/MacOS/ImageFlow.next"
mv -f "$TASK_BUNDLE/Contents/MacOS/ImageFlow.next" "$TASK_BUNDLE/Contents/MacOS/ImageFlow"
cp -R "$TASK_BIN_DIR/ImageFlow_ImageFlow.bundle" "$TASK_BUNDLE/Contents/Resources/"
cp "$TASK_ROOT/Sources/ImageFlow/Resources/ImageFlowIcon.icns" "$TASK_BUNDLE/Contents/Resources/"
cat > "$TASK_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ImageFlow</string>
<key>CFBundleIdentifier</key><string>app.imageflow.mac</string>
<key>CFBundleIconFile</key><string>ImageFlowIcon</string>
<key>CFBundleName</key><string>Image Flow</string>
<key>CFBundleDisplayName</key><string>Image Flow</string>
<key>CFBundleShortVersionString</key><string>0.10.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# The linker's ad hoc signature covers a standalone executable, not this bundle.
# Seal the assembled local development app after writing its plist and resources.
codesign --force --sign - "$TASK_BUNDLE"
codesign --verify --strict "$TASK_BUNDLE"
if [[ "$TASK_MODE" == "--debug" ]]; then
  exec lldb -- "$TASK_BUNDLE/Contents/MacOS/ImageFlow" --dev-directory "$TASK_ROOT/.runtime"
fi
TASK_ARGS=(--dev-directory "$TASK_ROOT/.runtime")
if [[ "$TASK_MODE" == "--connect" ]]; then TASK_ARGS+=(--connect); fi
/usr/bin/open -n "$TASK_BUNDLE" --args "${TASK_ARGS[@]}"
case "$TASK_MODE" in
  --verify) sleep 1; pgrep -x ImageFlow >/dev/null ;;
  --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "ImageFlow"' ;;
esac
