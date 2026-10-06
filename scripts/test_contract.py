import json
import shutil
import tempfile
import unittest
from pathlib import Path

from check_contract import verify

ROOT = Path(__file__).resolve().parents[1]


class ContractTests(unittest.TestCase):
    def test_actual_tree_passes(self):
        verify(ROOT)

    def test_each_contract_mutation_is_rejected(self):
        mutations = {
            "bundle_identifier": "com.invalid.app",
            "targeted_device_family": "1,2",
            "native_ipad_support": True,
            "network_allowlist": ["example.org"],
            "implementation": "other",
            "xcode_version": "25.0",
            "xcode_build": "wrong",
            "iphoneos_sdk": "25.0",
        }
        for key, bad in mutations.items():
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temp:
                path = Path(temp)
                self.copy_minimal_tree(path)
                config = json.loads((path / "toolchain.json").read_text())
                config[key] = bad
                (path / "toolchain.json").write_text(json.dumps(config))
                with self.assertRaises(ValueError):
                    verify(path)

    def test_both_app_configurations_are_guarded(self):
        for original, replacement in (
            ("TARGETED_DEVICE_FAMILY = 1;", "TARGETED_DEVICE_FAMILY = 1,2;"),
            ("PRODUCT_BUNDLE_IDENTIFIER = com.infinityball.swarmgate;", "PRODUCT_BUNDLE_IDENTIFIER = com.invalid.app;"),
            ("IPHONEOS_DEPLOYMENT_TARGET = 26.0;", "IPHONEOS_DEPLOYMENT_TARGET = 25.0;"),
        ):
            for occurrence in (0, 1):
                with self.subTest(original=original, occurrence=occurrence), tempfile.TemporaryDirectory() as temp:
                    path = Path(temp)
                    self.copy_minimal_tree(path)
                    project = path / "SwarmGate.xcodeproj/project.pbxproj"
                    text = project.read_text()
                    # Replace the app Debug/Release setting, not the project or UI-test setting.
                    start = text.index("A10000000000000000000903 /* Debug */ = {")
                    if occurrence:
                        start = text.index("A10000000000000000000904 /* Release */ = {")
                    target = text.index(original, start)
                    project.write_text(text[:target] + replacement + text[target + len(original):])
                    with self.assertRaises(ValueError):
                        verify(path)

    def test_network_and_engine_imports_are_rejected(self):
        for relative, content in (
            ("Packages/SwarmGateKit/Sources/SwarmGateKit/RunSeed.swift", "import UIKit\n"),
            ("SwarmGate/App/DefenseHomeView.swift", "import Network\n"),
        ):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as temp:
                path = Path(temp)
                self.copy_minimal_tree(path)
                source = path / relative
                source.write_text(content + source.read_text())
                with self.assertRaises(ValueError):
                    verify(path)

    @staticmethod
    def copy_minimal_tree(path):
        shutil.copy(ROOT / "toolchain.json", path / "toolchain.json")
        for folder in ("SwarmGate.xcodeproj", "SwarmGate", "Packages/SwarmGateKit/Sources", "Packages/SwarmGateStore/Sources"):
            shutil.copytree(ROOT / folder, path / folder)


if __name__ == "__main__":
    unittest.main()
