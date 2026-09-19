#!/usr/bin/env python3
"""Read-only, pinned-source audit. Does not import or execute upstream code."""
import ast
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
repo = root / ".research/chatgpt-endless-canvas"
policy = json.loads((root / "config/generation-policy.json").read_text())
revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
if revision != policy["sourceCommit"]:
    raise SystemExit("Reference revision differs from the approved policy; review before updating")
sources = {name: (repo / name).read_text() for name in
           ["board_server.py", "generate_chatgpt_image.py", "README.md", "LICENSE"]}
for name in sources:
    committed = subprocess.check_output(["git", "-C", str(repo), "show", f"{revision}:{name}"])
    if committed != (repo / name).read_bytes():
        raise SystemExit(f"Reference file has local changes: {name}")
for name in ["board_server.py", "generate_chatgpt_image.py"]:
    ast.parse(sources[name])

specs = [
    ("workers-default-3-not-hard-service-cap", "board_server.py", 'WORKERS = max(1, int(os.environ.get("BOARD_WORKERS", "3")))'),
    ("batch-app-limit-50", "board_server.py", "if len(prompts) > 50:"),
    ("worker-delay-30-120", "board_server.py", 'os.environ.get("BATCH_INTERVAL", "30-120").split("-", 1)'),
    ("delay-occurs-inside-worker", "board_server.py", "time.sleep(delay)"),
    ("generation-timeout-420", "board_server.py", '"--timeout", "420",'),
    ("process-timeout-500", "board_server.py", "timeout=500)"),
    ("recover-then-regenerate-if-failed", "board_server.py", "if not recovered:"),
    ("history-truncated-to-500", "board_server.py", "_write_json(JOBS_PATH, JOBS[-500:])"),
    ("attachment-failure-continues", "generate_chatgpt_image.py", 'log("(reference upload not confirmed; continuing)")'),
    ("timeout-may-return-intermediate", "generate_chatgpt_image.py", "return latest  # best effort if it never clearly settled"),
    ("recovery-effective-image-wait-max-20", "generate_chatgpt_image.py", "min(timeout, 20), require_settle=False"),
    ("silent-rate-limit-described", "README.md", "silent rate limiting"),
    ("source-license-MIT", "LICENSE", "MIT License")
]
findings = []
for name, filename, needle in specs:
    lines = sources[filename].splitlines()
    matching = [i + 1 for i, line in enumerate(lines) if needle in line]
    if len(matching) != 1:
        raise SystemExit(f"Source audit mismatch: {name}: {matching}")
    findings.append({"finding": name, "file": filename, "line": matching[0],
                     "url": f"https://github.com/ManiacMike/chatgpt-endless-canvas/blob/{revision}/{filename}#L{matching[0]}"})
report = {"commit": revision, "scope": "static-source-audit; not a ChatGPT account limit test",
          "files": {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
          "findings": findings}
output = root / "validation/output/source-audit.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, indent=2) + "\n")
print(f"Pinned source audit passed: {len(findings)} findings at {revision}")
