#!/usr/bin/env python3
"""Verify the manifest hashes against Git object bytes, not just checkout bytes."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def verify(root=ROOT):
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8-sig"))
    revision = manifest["revision"]
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("invalid revision")
    files = manifest["files"]
    if not isinstance(files, dict) or not files:
        raise ValueError("empty file map")
    for name, spec in files.items():
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_./-]+", name) or ".." in name or name.startswith("/"):
            raise ValueError("unsafe path")
        source = subprocess.check_output(["git", "show", f"{revision}:{name}"], cwd=root, stderr=subprocess.DEVNULL)
        if hashlib.sha256(source).hexdigest() != spec["sha256"]:
            raise ValueError("immutable hash mismatch")
    return len(files)


if __name__ == "__main__":
    try:
        count = verify()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        print("REVISION_VERIFY_FAIL [details omitted]")
        raise SystemExit(1)
    print(f"REVISION_BYTES_OK files={count}")
