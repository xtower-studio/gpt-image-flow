#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_REFERENCE="$TASK_ROOT/.research/chatgpt-endless-canvas"
TASK_REVISION="7783f02518d3d1878f3729e80b8499fb566d15e9"
if [[ ! -d "$TASK_REFERENCE/.git" ]]; then
  mkdir -p "$TASK_ROOT/.research"
  git clone --quiet --no-checkout https://github.com/ManiacMike/chatgpt-endless-canvas.git "$TASK_REFERENCE"
  git -C "$TASK_REFERENCE" checkout --quiet --detach "$TASK_REVISION"
fi
if [[ "$(git -C "$TASK_REFERENCE" rev-parse HEAD)" != "$TASK_REVISION" ]]; then
  echo "Reference checkout is not the pinned revision; preserve it and review manually." >&2
  exit 1
fi
python3 "$TASK_ROOT/validation/audit_reference.py"
