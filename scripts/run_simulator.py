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

    macos-26 hosted runners time out the 180s bootstatus window here on
    every job so far (run 38068161640 attempts 2-3, run 38280518348
    attempt 1; 4 distinct UDIDs, all after a fresh
    `xcodebuild -downloadPlatform iOS`, whose first boot prepares the
    device image lazily). First wait gets 300s; one bounded
    shutdown/reboot retry then gets 180s and a second timeout still
    fails. shutdown itself has been observed to hang
    (run 38280518348), so its bounded timeout must not abort the retry.
    """
    for attempt, wait in ((1, 300), (2, 180)):
        try:
            if not already_booted or attempt == 2:
                run("xcrun", "simctl", "boot", udid, timeout=120)
            run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=wait)
            return
        except subprocess.TimeoutExpired:
            print(f"simctl bootstatus timed out after {wait}s (attempt {attempt})",
                  file=sys.stderr, flush=True)
            if attempt == 2:
                raise
            try:
                run("xcrun", "simctl", "shutdown", udid, timeout=90, capture=True)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as exc:
                print(f"simctl shutdown incomplete ({exc}); boot retry proceeds",
                      file=sys.stderr, flush=True)


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
