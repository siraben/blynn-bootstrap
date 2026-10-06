#!/usr/bin/env python3
"""Exercise the selector CLI used by the nightly/manual workflow."""

import json
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/slow-acceptance-matrix.py"
TARGETS = [
    "gcc46.m2.precisely.m2", "gccLatest.m2.precisely.m2",
    "gccGlibc.m2.precisely.m2", "gnuHello.m2.precisely.m2",
]


def select(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True,
    )


for args, targets in [
    (("schedule",), TARGETS),
    (("workflow_dispatch",), TARGETS),
    (("workflow_dispatch", "all"), TARGETS),
    (("workflow_dispatch", TARGETS[1]), [TARGETS[1]]),
]:
    result = select(*args)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"include": [{"attr": t} for t in targets]}

result = select("workflow_dispatch", "not-a-target")
assert result.returncode != 0 and result.stdout == ""
