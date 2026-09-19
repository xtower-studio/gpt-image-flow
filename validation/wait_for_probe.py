import json
import pathlib
import sys
import time

output = pathlib.Path(sys.argv[1])
deadline = time.monotonic() + 45
while time.monotonic() < deadline:
    if output.exists():
        report = json.loads(output.read_text())
        print(json.dumps(report, ensure_ascii=False, indent=2))
        sys.exit(0 if report["passed"] else 1)
    time.sleep(0.25)
raise SystemExit("Probe did not produce its report within 45 seconds")
