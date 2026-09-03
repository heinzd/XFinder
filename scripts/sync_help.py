#!/usr/bin/env python3
"""Embed docs/Bedienung.md into the existing Swift target; no Xcode changes needed."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = "// BEGIN GENERATED USER GUIDE"
END = "// END GENERATED USER GUIDE"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the embedded guide is stale")
    args = parser.parse_args()
    manual = (ROOT / "docs/Bedienung.md").read_text(encoding="utf-8").rstrip()
    # Increase the raw-string delimiter if future prose happens to contain it.
    hashes = "#"
    while ('"""' + hashes) in manual or ("\\" + hashes + "(") in manual:
        hashes += "#"
    generated = START + "\nprivate enum XFinderUserGuide {\n    static let markdown = " + hashes + '"""\n' + manual + '\n"""' + hashes + "\n}\n" + END
    path = ROOT / "XFinder/XFinderApp.swift"
    source = path.read_text(encoding="utf-8")
    assert source.count(START) == source.count(END) == 1, "Missing or duplicate guide markers"
    start, end = source.index(START), source.index(END) + len(END)
    updated = source[:start] + generated + source[end:]
    if args.check:
        if updated != source:
            raise SystemExit("Embedded help is stale: run python3 scripts/sync_help.py")
        print("Embedded help matches docs/Bedienung.md")
    else:
        path.write_text(updated, encoding="utf-8")
        print("Updated embedded help")

if __name__ == "__main__":
    main()
