#!/usr/bin/env python3
"""Validate and compare complete handler traces from two fresh backend runs."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path
import sys
import tempfile
from zipfile import ZipFile, BadZipFile

import run as tier0
from run_emulated import ROOT, digest, handler_digest, load_image, spec, validate_trace, write_json


def rows(path):
    return [[int(field, 16) for field in line.split()] for line in path.read_text().splitlines()
            if line.strip() and not line.startswith("#")]


def compare(left, right):
    with ExitStack() as stack:
        directories = []
        for path in (left, right):
            if (path / "executions.zip").is_file():
                expanded = Path(stack.enter_context(tempfile.TemporaryDirectory()))
                with ZipFile(path / "executions.zip") as archive:
                    archive.extractall(expanded)
                directories.append(expanded)
            else:
                directories.append(path)
        report = compare_directories(*directories)
        report["left"], report["right"] = str(left), str(right)
        return report


def compare_directories(left, right):
    definition = spec()
    manifest = json.loads((ROOT / "emulated_manifest.json").read_text())
    names = set(definition["tests"])
    for directory in (left, right):
        summary = json.loads((directory / "summary.json").read_text())
        if (summary["handler_sha256"] != handler_digest()
                or summary["manifest_sha256"] != digest(ROOT / "emulated_manifest.json")):
            raise ValueError(str(directory) + ": stale handler/expectation provenance")
        if {r["name"] for r in summary["results"] if r["outcome"] == "PASS"} != names:
            raise ValueError(str(directory) + ": expected every handler program to pass")
    results = []
    for name in definition["tests"]:
        image, record = load_image(name)
        for directory in (left / name, right / name):
            provenance = json.loads((directory / "provenance.json").read_text())
            if provenance["image_sha256"] != digest(image):
                raise ValueError(name + ": result provenance does not match current image")
            failures = tier0.judge(name, directory, manifest)
            if failures:
                raise ValueError(name + ": " + "; ".join(failures))
            validate_trace(image.read_bytes(), directory, record, {int(n) for n in definition["implemented"]})
        a, b = rows(left / name / "trace.txt"), rows(right / name / "trace.txt")
        if a != b:
            index = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
            raise ValueError(f"{name}: first trace difference at row {index + 1}; "
                             f"left={a[index:index + 1]}, right={b[index:index + 1]}")
        results.append({"name": name, "outcome": "MATCH", "instruction_rows": len(a)})
        print(f"MATCH {name}: {len(a)} instruction rows")
    return {"left": str(left), "right": str(right), "results": results,
            "handler_sha256": handler_digest(),
            "manifest_sha256": digest(ROOT / "emulated_manifest.json")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = compare(args.left, args.right)
        if args.output:
            write_json(args.output, report)
        print(f"MATCH: all {len(report['results'])} complete handler traces")
        return 0
    except (OSError, ValueError, BadZipFile) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
