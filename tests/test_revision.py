"""Immutable byte checks use temporary repos and synthetic Git identity only."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_revision", ROOT / "tools/verify_revision.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RevisionTests(unittest.TestCase):
    def test_git_bytes_must_match_manifest_even_if_checkout_hash_matches(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
            git("init", "--quiet")
            git("config", "core.autocrlf", "false")
            original = b"return 1\n"
            (root / "hub.lua").write_bytes(original)
            git("add", "hub.lua")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture")
            manifest = {"revision": git("rev-parse", "HEAD"), "files": {"hub.lua": {"sha256": hashlib.sha256(original).hexdigest()}}}
            (root / "manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(module.verify(root), 1)
            changed = b"return 2\n"
            (root / "hub.lua").write_bytes(changed)
            manifest["files"]["hub.lua"]["sha256"] = hashlib.sha256(changed).hexdigest()
            (root / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "immutable hash mismatch"):
                module.verify(root)

    def test_invalid_revision_fails_before_git(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "manifest.json").write_text(json.dumps({"revision": "main", "files": {}}))
            with self.assertRaises(ValueError):
                module.verify(root)


if __name__ == "__main__":
    unittest.main()
