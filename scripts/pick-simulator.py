#!/usr/bin/env python3
"""Pick an installed iPhone simulator without assuming a specific runtime exists."""
import json
import subprocess
import sys


def main() -> int:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
    )
    data = json.loads(raw)
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        if "SimRuntime.iOS" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                candidates.append((runtime, device["name"], device["udid"]))
    if not candidates:
        print("No installed iPhone simulator runtime/device was found", file=sys.stderr)
        return 1
    candidates.sort(key=lambda row: row[0])
    runtime, name, udid = candidates[-1]
    print(udid)
    print(f"Selected {name} on {runtime}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
