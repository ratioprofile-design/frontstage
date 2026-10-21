"""Expose test failures in Actions annotations without changing the runner's exit status."""
import os
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def annotate(message):
    escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error::{escaped}")


if "--build" in sys.argv:
    log = Path("build/build.log")
    if log.exists():
        for line in log.read_text().splitlines()[-24:]:
            annotate(line)
    raise SystemExit(0)

result = Path("build/test-results.xml")
if result.exists():
    cases = list(ET.parse(result).getroot().iter("testcase"))
    failures = []
    skipped = 0
    for case in cases:
        skipped += case.find("skipped") is not None
        for failure in list(case.findall("failure")) + list(case.findall("error")):
            message = f"{case.get('classname', '')}.{case.get('name', '')}: {failure.get('message', '')} {failure.text or ''}"
            failures.append(message)
            annotate(message)
    summary = f"Swift tests: {len(cases)} executed, {len(failures)} failures, {skipped} skipped.\n"
    print(summary)
    if failures:
        # Swift's xUnit output can contain only "failed". Preserve the actual assertion location.
        log = Path("build/test.log")
        if log.exists():
            errors = [line for line in log.read_text().splitlines() if "error:" in line]
            for line in errors[:30]:
                annotate(line)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(summary)
else:
    log = Path("build/test.log")
    if log.exists():
        errors = [line for line in log.read_text().splitlines() if "error:" in line]
        for line in errors[:30]:
            annotate(line)
