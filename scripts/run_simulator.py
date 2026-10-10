#!/usr/bin/env python3
"""Exact SDK runtime, iPhone-only simulator smoke; every subprocess is bounded."""
import json
import os
import subprocess
import sys
from pathlib import Path


def run(*args, timeout=120, capture=False):
    print("PHASE:", " ".join(args), flush=True)
    return subprocess.run(args, check=True, timeout=timeout, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version", capture=True).strip()
    runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + sdk.replace(".", "-")
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True))
    candidates = [d for d in devices["devices"].get(runtime, [])
                  if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not candidates:
        print("Exact iOS runtime missing; download for selected Xcode", flush=True)
        run("xcodebuild", "-downloadPlatform", "iOS", "-architectureVariant", "universal", timeout=900)
        devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True))
        candidates = [d for d in devices["devices"].get(runtime, [])
                      if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not candidates:
        raise RuntimeError(f"ENVIRONMENT BLOCKER: no available iPhone for {runtime}; {devices}")
    chosen = sorted(candidates, key=lambda d: d["name"])[0]
    udid = chosen["udid"]
    if chosen["state"] != "Booted":
        run("xcrun", "simctl", "boot", udid, timeout=120)
    run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=180)
    temp = Path(os.environ["RUNNER_TEMP"])
    run("xcodebuild", "test", "-project", "SwarmGate.xcodeproj", "-scheme", "SwarmGate",
        "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={udid}",
        "-derivedDataPath", str(temp / "SwarmGateUITestBuild"),
        "-resultBundlePath", str(temp / "SwarmGateUI.xcresult"),
        "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO", timeout=1200)


if __name__ == "__main__":
    try:
        main()
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"Simulator validation failed: {exc}", file=sys.stderr)
        sys.exit(1)
