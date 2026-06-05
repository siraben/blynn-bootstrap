#!/usr/bin/env python3
"""Select additive downstream acceptance builds, never placeholder matrix jobs."""

import json
import sys


TARGETS = (
    "gcc46.m2.precisely.m2",
    "gccLatest.m2.precisely.m2",
    "gccGlibc.m2.precisely.m2",
    "gnuHello.m2.precisely.m2",
)


def matrix(event, target=""):
    if event == "schedule":
        selected = TARGETS
    elif event == "workflow_dispatch":
        if target in ("", "all"):
            selected = TARGETS
        elif target in TARGETS:
            selected = (target,)
        else:
            raise ValueError(f"unknown slow acceptance target: {target!r}")
    else:
        raise ValueError(f"unsupported slow acceptance event: {event!r}")
    return {"include": [{"attr": attr} for attr in selected]}


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: slow-acceptance-matrix.py EVENT [TARGET]")
    try:
        print(json.dumps(matrix(*sys.argv[1:]), separators=(",", ":")))
    except ValueError as error:
        sys.exit(str(error))
