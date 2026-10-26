#!/usr/bin/env python3
"""Ensure changelog metadata for an immutable Beta Tag build workspace.

This modifies only the checked-out build workspace, never the pushed Git tag.
Existing correct release notes are preserved verbatim.
"""

import argparse
import re
from pathlib import Path


def ensure_changelog(root, version, fallback_note):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+", version):
        raise ValueError("Invalid beta version")
    path = Path(root) / "CHANGELOG.md"
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines()
    correct = f"## {version}"
    legacy = f"## v{version}"

    def matches_heading(line, head):
        return line == head or line.startswith(head + " - ") or line.startswith(head + " — ")

    candidates = [i for i, line in enumerate(lines)
                  if matches_heading(line, correct) or matches_heading(line, legacy)]
    if len(candidates) > 1:
        raise ValueError("Duplicate release changelog sections")
    if candidates:
        start = candidates[0]
        end = next((j for j in range(start + 1, len(lines))
                    if lines[j].startswith("## ") or lines[j].strip().lower() == "# changelog"), len(lines))
        entry = lines[start:end]
        entry[0] = entry[0].replace(legacy, correct, 1) if matches_heading(entry[0], legacy) else entry[0]
        if not any(line.strip().startswith("- ") and line.strip()[2:].strip() for line in entry[1:]):
            raise ValueError("Release section must contain at least one bullet")
        # The version section belongs below the top-level # Changelog heading.
        top = next((i for i, line in enumerate(lines) if line.strip().lower() == "# changelog"), None)
        if top is not None and top > start:
            remainder = lines[:start] + lines[end:]
            h = next(i for i, line in enumerate(remainder) if line.strip().lower() == "# changelog")
            out = remainder[:h + 1] + [""] + entry + [""] + remainder[h + 1:]
        else:
            out = lines[:start] + entry + lines[end:]
    else:
        fallback_note = (fallback_note or "").strip()
        if not fallback_note or fallback_note.startswith("#"):
            raise ValueError("Missing release notes and unusable commit title")
        title = [correct + " - Beta Update", "", "- " + fallback_note, ""]
        top = next((i for i, line in enumerate(lines) if line.strip().lower() == "# changelog"), None)
        if top is None:
            out = ["# Changelog", ""] + title + lines
        else:
            out = lines[:top + 1] + [""] + title + lines[top + 1:]
    result = "\n".join(out).rstrip() + "\n"
    if result != original:
        path.write_text(result, encoding="utf-8")
        return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    updated = ensure_changelog(args.root, args.version, args.notes)
    print("Beta changelog:", "normalized" if updated else "already valid")


if __name__ == "__main__":
    main()
