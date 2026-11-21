#!/usr/bin/env python3
"""Pick an installed iPhone simulator without assuming a specific runtime exists.

Prefers the newest installed iOS runtime and, within it, a mainstream iPhone
device. xcodebuild is allowed to boot the simulator on demand; this script never
blocks on simctl boot.
"""
import json
import re
import subprocess
import sys


def runtime_version(runtime: str) -> tuple[int, ...]:
    match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    if not match:
        return (0, 0)
    return tuple(int(part) for part in match.groups(default="0"))


def device_priority(name: str) -> int:
    priorities = {
        "iPhone 17 Pro": 0,
        "iPhone 17": 1,
        "iPhone Air": 2,
        "iPhone 16 Pro": 3,
        "iPhone 16": 4,
    }
    if name in priorities:
        return priorities[name]
    if name.endswith("e"):
        return 20
    return 10


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
            name = device.get("name", "")
            if device.get("isAvailable") and name.startswith("iPhone"):
                candidates.append((runtime, runtime_version(runtime), name, device["udid"]))
    if not candidates:
        print("No installed iPhone simulator runtime/device was found", file=sys.stderr)
        return 1

    newest = max(row[1] for row in candidates)
    pool = [row for row in candidates if row[1] == newest]
    pool.sort(key=lambda row: (device_priority(row[2]), row[2]))
    runtime, _, name, udid = pool[0]
    print(udid)
    print(f"Selected {name} on {runtime}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
