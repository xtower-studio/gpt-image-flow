#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:-run}"
TASK_APP_NAME="ImageFlowProbe"
TASK_BUNDLE="$TASK_ROOT/dist/$TASK_APP_NAME.app"
TASK_OUTPUT="$TASK_ROOT/validation/output/webkit-report.json"
case "$TASK_MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
pkill -x "$TASK_APP_NAME" >/dev/null 2>&1 || true
swift build --package-path "$TASK_ROOT/validation" --product "$TASK_APP_NAME"
TASK_BIN_DIR="$(swift build --package-path "$TASK_ROOT/validation" --show-bin-path)"
mkdir -p "$TASK_BUNDLE/Contents/MacOS" "$TASK_ROOT/validation/output"
cp "$TASK_BIN_DIR/$TASK_APP_NAME" "$TASK_BUNDLE/Contents/MacOS/$TASK_APP_NAME"
mkdir -p "$TASK_BUNDLE/Contents/Resources"
cp -R "$TASK_BIN_DIR/ImageFlowPreflight_ImageFlowProbe.bundle" "$TASK_BUNDLE/Contents/Resources/"
cat > "$TASK_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ImageFlowProbe</string>
<key>CFBundleIdentifier</key><string>local.imageflow.preflight</string>
<key>CFBundleName</key><string>Image Flow Preflight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
rm -f "$TASK_OUTPUT"
if [[ "$TASK_MODE" == "--debug" ]]; then
  exec lldb -- "$TASK_BUNDLE/Contents/MacOS/$TASK_APP_NAME" --output "$TASK_OUTPUT"
fi
/usr/bin/open -n "$TASK_BUNDLE" --args --output "$TASK_OUTPUT"
case "$TASK_MODE" in
  --verify)
    python3 "$TASK_ROOT/validation/wait_for_probe.py" "$TASK_OUTPUT"
    ;;
  --logs|--telemetry)
    /usr/bin/log stream --info --style compact --predicate 'process == "ImageFlowProbe"'
    ;;
esac
