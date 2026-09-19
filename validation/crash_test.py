#!/usr/bin/env python3
"""Kills our local CLI probe at persistent boundaries. Never launches a browser."""
import json
import pathlib
import subprocess
import sys
import tempfile
import uuid

binary, output = sys.argv[1:]
expected = {"queued": "prepare", "uploading": "prepare", "submitting": "needsReview",
            "submitted": "collectExisting", "generating": "collectExisting",
            "collecting": "useSaved", "saved": "useSaved"}
results = []
with tempfile.TemporaryDirectory(prefix="imageflow-crash-") as directory:
    for state, action in expected.items():
        identifier = str(uuid.uuid4())
        writer = subprocess.run([binary, "write", directory, identifier, state], capture_output=True)
        reader = subprocess.run([binary, "read", directory, identifier, state], capture_output=True, text=True)
        actual = reader.stdout.strip()
        results.append({"boundary": state, "writerExit": writer.returncode,
                        "expected": action, "actual": actual,
                        "passed": writer.returncode == -9 and reader.returncode == 0 and actual == action})
pathlib.Path(output).write_text(json.dumps(results, indent=2) + "\n")
print(json.dumps(results, indent=2))
sys.exit(0 if all(row["passed"] for row in results) else 1)
