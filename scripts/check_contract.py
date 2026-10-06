#!/usr/bin/env python3
"""Fail closed on the committed iPhone-only, native, offline build contract."""
import json
import re
import sys
from pathlib import Path


def verify(root: Path) -> None:
    tool = json.loads((root / "toolchain.json").read_text())
    required = {
        "bundle_identifier": "com.infinityball.swarmgate",
        "targeted_device_family": "1",
        "native_ipad_support": False,
        "device_family": "iphone-only",
        "implementation": "native-swift",
        "xcode_version": "26.0.1",
        "xcode_build": "17A400",
        "iphoneos_sdk": "26.0",
        "minimum_sdk_major": 26,
        "deployment_target": "26.0",
        "swift_language_mode": "6",
        "network_allowlist": [],
    }
    for key, value in required.items():
        if tool.get(key) != value:
            raise ValueError(f"toolchain.{key} must equal {value!r}")

    project = (root / "SwarmGate.xcodeproj/project.pbxproj").read_text()
    # These IDs are the Debug and Release configurations of the APP target;
    # require the mapping itself to prevent validating unused configuration blocks.
    app_list = re.search(
        r'A10000000000000000000601 /\* Build configuration list for PBXNativeTarget "SwarmGate" \*/ = '
        r'\{isa = XCConfigurationList; buildConfigurations = \((.*?)\);', project, re.S
    )
    if not app_list:
        raise ValueError("missing app configuration list")
    ids = re.findall(r'(A100000000000000000009\d\d) /\*', app_list.group(1))
    if ids != ["A10000000000000000000903", "A10000000000000000000904"]:
        raise ValueError("app configurations must be Debug and Release")
    for config_id in ids:
        block = re.search(
            rf'{config_id} /\* (?:Debug|Release) \*/ = \{{\s*isa = XCBuildConfiguration;\s*buildSettings = \{{(.*?)\}};',
            project, re.S
        )
        if not block:
            raise ValueError(f"missing app build settings: {config_id}")
        settings = dict(re.findall(r'^\s*([A-Z_]+) = ([^;]+);', block.group(1), re.M))
        expected = {
            "TARGETED_DEVICE_FAMILY": "1",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.infinityball.swarmgate",
            "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
            "SWIFT_VERSION": "6.0",
            "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        }
        for key, value in expected.items():
            if settings.get(key) != value:
                raise ValueError(f"{config_id}: {key} must equal {value}")
    for path in [root / "SwarmGate", root / "Packages/SwarmGateKit/Sources", root / "Packages/SwarmGateStore/Sources"]:
        for source in path.rglob("*.swift"):
            text = source.read_text()
            if re.search(r'^\s*import\s+(?:Network|FoundationNetworking|WebKit)\b|\b(?:URLSession|NWConnection|WKWebView)\b', text, re.M):
                raise ValueError(f"network API in {source.relative_to(root)}")
    for source in (root / "Packages/SwarmGateKit/Sources").rglob("*.swift"):
        if re.search(r'^\s*import\s+(?:SwiftUI|UIKit|SpriteKit|GRDB)\b', source.read_text(), re.M):
            raise ValueError(f"engine must remain pure Swift: {source.relative_to(root)}")
    print("Contract PASS: iPhone-only app Debug/Release, exact bundle, iOS 26, pure engine, offline")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
    except (OSError, ValueError, KeyError) as exc:
        print(f"Contract FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
