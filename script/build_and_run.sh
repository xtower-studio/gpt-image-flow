#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:-run}"
TASK_BUNDLE="$TASK_ROOT/dist/ImageFlow.app"
case "$TASK_MODE" in run|--verify|--connect|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--verify|--connect|--debug|--logs|--telemetry]" >&2; exit 2;; esac
pkill -x ImageFlow >/dev/null 2>&1 || true
cp "$TASK_ROOT/config/generation-policy.json" "$TASK_ROOT/Sources/ImageFlow/Resources/generation-policy.json"
swift build --package-path "$TASK_ROOT" --product ImageFlow
TASK_BIN_DIR="$(swift build --package-path "$TASK_ROOT" --show-bin-path)"
mkdir -p "$TASK_BUNDLE/Contents/MacOS" "$TASK_BUNDLE/Contents/Resources" "$TASK_ROOT/.runtime"
cp "$TASK_BIN_DIR/ImageFlow" "$TASK_BUNDLE/Contents/MacOS/ImageFlow"
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
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
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
