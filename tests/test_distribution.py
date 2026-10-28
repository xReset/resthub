"""The public release must cover the canonical registry and shared dependencies."""
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "Potassium"
spec = importlib.util.spec_from_file_location("public_registry", ROOT / "tools/registry.py")
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class DistributionTests(unittest.TestCase):
    def test_every_canonical_module_is_mirrored_and_hash_pinned(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        modules = registry.modules(SOURCE)
        self.assertEqual(manifest["modules"], [
            {k: row[k] for k in ("id", "gameId", "placeId", "path")}
            for row in modules
        ])
        for row in modules:
            with self.subTest(module=row["id"]):
                expected = (SOURCE / row["source"]).read_text(encoding="utf-8").encode("utf-8")
                self.assertEqual((ROOT / row["path"]).read_bytes(), expected)
                self.assertEqual(manifest["files"][row["path"]], {
                    "sha256": hashlib.sha256(expected).hexdigest(), "localName": row["localName"]
                })

    def test_secret_scan_allows_format_placeholder_not_password_values(self):
        gate = (ROOT / "tools/gate.ps1").read_text()
        pattern = re.search(r"\$patterns = '([^']+)'", gate).group(1)
        self.assertIsNone(re.search(pattern, 'password=%s', re.I))
        for suffix in ('=test-value', ': test-value', ' = test-value'):
            self.assertIsNotNone(re.search(pattern, 'password' + suffix, re.I))

    def test_shared_runtime_and_other_dependencies_are_pinned(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        for path in ("hub.lua", "r3st_runtime.lua", "r3st_ui.lua", "anims.lua", "log.lua"):
            with self.subTest(path=path):
                self.assertEqual(manifest["files"][path]["localName"], path)
                self.assertEqual(manifest["files"][path]["sha256"],
                                 hashlib.sha256((ROOT / path).read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
