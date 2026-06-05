#!/usr/bin/env python3
"""Contract tests for scheduled/default/manual downstream target selection."""

import json
from pathlib import Path
import re
import runpy
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/slow-acceptance-matrix.py"
SELECTOR = runpy.run_path(str(SCRIPT))
TARGETS = SELECTOR["TARGETS"]
select = SELECTOR["matrix"]


class SlowAcceptance(unittest.TestCase):
    def test_schedule_and_defaults(self):
        expected = {"include": [{"attr": target} for target in TARGETS]}
        for event, target in (
            ("schedule", ""),
            ("schedule", TARGETS[0]),
            ("workflow_dispatch", ""),
            ("workflow_dispatch", "all"),
        ):
            with self.subTest(event=event, target=target):
                self.assertEqual(select(event, target), expected)
        self.assertEqual(len(set(TARGETS)), len(TARGETS))
        self.assertTrue(TARGETS)

    def test_each_manual_selection_has_one_real_job(self):
        for target in TARGETS:
            with self.subTest(target=target):
                self.assertEqual(
                    select("workflow_dispatch", target),
                    {"include": [{"attr": target}]},
                )

    def test_invalid_selection_fails_closed(self):
        for event, target in (
            ("pull_request", "all"),
            ("", "all"),
            ("workflow_dispatch", "downstream-pkgs-hello"),
            ("workflow_dispatch", "tests.smoke.m1-aarch64"),
            ("workflow_dispatch", "$(echo unsafe)"),
        ):
            with self.subTest(event=event, target=target):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), event, target],
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_cli_output(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "schedule"],
            check=True, capture_output=True, text=True,
        )
        self.assertEqual(json.loads(result.stdout), select("schedule"))
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_dispatch_choices_match_allowlist(self):
        # Read just the scalar choice list; avoid a PyYAML dependency on runners.
        workflow = (ROOT / ".github/workflows/slow-acceptance.yml").read_text()
        options = re.search(r"        options:\n((?:          - [^\n]+\n)+)", workflow)
        self.assertIsNotNone(options)
        choices = re.findall(r"          - ([^\n]+)", options.group(1))
        self.assertEqual(choices, ["all", *TARGETS])
        self.assertIn("        default: all\n", workflow)


if __name__ == "__main__":
    unittest.main()
