#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$TASK_ROOT/validation/output"
python3 "$TASK_ROOT/validation/audit_reference.py"
swift test --package-path "$TASK_ROOT/validation" 2>&1 | tee "$TASK_ROOT/validation/output/swift-tests.log"
TASK_BIN_DIR="$(swift build --package-path "$TASK_ROOT/validation" --show-bin-path)"
python3 "$TASK_ROOT/validation/crash_test.py" "$TASK_BIN_DIR/JournalProbe" "$TASK_ROOT/validation/output/crash-report.json"
"$TASK_ROOT/script/run_preflight_probe.sh" --verify
