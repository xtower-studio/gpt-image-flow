#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:-run}"
TASK_BUNDLE="$TASK_ROOT/dist/ImageFlow.app"
case "$TASK_MODE" in run|--verify|--connect|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--verify|--connect|--debug|--logs|--telemetry]" >&2; exit 2;; esac
pkill -x ImageFlow >/dev/null 2>&1 || true
bash "$TASK_ROOT/script/build_app.sh" debug "$TASK_BUNDLE"
mkdir -p "$TASK_ROOT/.runtime"
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
