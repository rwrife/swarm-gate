"""Bounded boot retry and failure propagation without requiring macOS."""
import importlib.util
import subprocess
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("run_simulator", Path(__file__).with_name("run_simulator.py"))
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)


class BootTests(unittest.TestCase):
    def test_retry_then_succeed(self):
        calls = []
        failures = 1

        def fake_run(*args, **kwargs):
            nonlocal failures
            calls.append((args[2], kwargs["timeout"]))
            if args[2] == "bootstatus" and failures:
                failures -= 1
                raise subprocess.TimeoutExpired(args, kwargs["timeout"])

        sim.ensure_booted(fake_run, "test-udid", False)
        self.assertEqual(calls, [("boot", 120), ("bootstatus", 180),
                                 ("shutdown", 60), ("boot", 120), ("bootstatus", 180)])

    def test_second_timeout_propagates(self):
        calls = []

        def fake_run(*args, **kwargs):
            calls.append(args[2])
            if args[2] == "bootstatus":
                raise subprocess.TimeoutExpired(args, kwargs["timeout"])

        with self.assertRaises(subprocess.TimeoutExpired):
            sim.ensure_booted(fake_run, "test-udid", True)
        self.assertEqual(calls, ["bootstatus", "shutdown", "boot", "bootstatus"])


if __name__ == "__main__":
    unittest.main()
