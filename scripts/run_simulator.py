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


def ensure_booted(run, udid, already_booted):
    """Boot `udid` and wait for bootstatus, each wait bounded.

    First boot of a runtime fetched via `xcodebuild -downloadPlatform`
    installs its device image lazily and can exceed one 180s bootstatus
    window (macos-26 run 38068161640 attempts 2 and 3 timed out at exactly
    this phase on two different devices). Allow one bounded shutdown and
    reboot without hiding a second timeout.
    """
    for attempt in (1, 2):
        try:
            if not already_booted or attempt == 2:
                run("xcrun", "simctl", "boot", udid, timeout=120)
            run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=180)
            return
        except subprocess.TimeoutExpired:
            print(f"simctl bootstatus timed out (attempt {attempt})",
                  file=sys.stderr, flush=True)
            if attempt == 2:
                raise
            run("xcrun", "simctl", "shutdown", udid, timeout=60, capture=True)


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
    ensure_booted(run, udid, chosen["state"] == "Booted")
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
