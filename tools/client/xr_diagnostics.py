#!/usr/bin/env python3
"""Read-only Linux OpenXR prerequisites; never load a runtime or create a session.

Only allowlisted WiVRn status properties are read. Pairing keys, configuration,
device serial numbers, network addresses and tracking poses are not collected.
An existing runtime session is not proof that this project's XR rendering works.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return ""


def elf_info(path: Path) -> dict:
    try:
        with path.open("rb") as stream:
            header = stream.read(20)
    except OSError:
        return {"readable": False}
    if len(header) < 20 or header[:4] != b"\x7fELF":
        return {"readable": True, "elf": False}
    machine = struct.unpack(("<" if header[5] == 1 else ">") + "H", header[18:20])[0]
    architecture = {3: "x86", 62: "x86_64", 183: "aarch64"}.get(machine, str(machine))
    return {"readable": True, "elf": True, "bits": {1: 32, 2: 64}.get(header[4]),
            "architecture": architecture, "host_architecture_matches": architecture == platform.machine()}


def runtime_info() -> dict:
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    override = os.environ.get("XR_RUNTIME_JSON")
    candidates = ([Path(override)] if override else
                  [config / "openxr/1/active_runtime.json", Path("/etc/xdg/openxr/1/active_runtime.json"),
                   Path("/etc/openxr/1/active_runtime.json"), Path("/usr/share/openxr/1/active_runtime.json")])
    result = {"environment_override": bool(override),
              "inspected_manifest_candidates": [{"path": str(p), "exists": p.exists()} for p in candidates],
              "selection_note": "Inspected explicit override or common Linux manifest locations; loader was not executed."}
    selected = next((p for p in candidates if p.exists()), None)
    if selected is None:
        result["status"] = "manifest_not_found"
        return result
    resolved = selected.resolve()
    result.update({"manifest_path": str(selected), "resolved_manifest_path": str(resolved)})
    try:
        manifest = json.loads(resolved.read_text())
        runtime = manifest["runtime"]
        library = Path(runtime["library_path"])
        # WiVRn installs a symlink in ~/.config; relative paths belong to its target.
        library = library if library.is_absolute() else resolved.parent / library
        library = library.resolve()
        result.update({"name": runtime.get("name"), "file_format_version": manifest.get("file_format_version"),
                       "library_path": str(library), "library_exists": library.is_file(),
                       "library": elf_info(library), "status": "manifest_read"})
    except (OSError, ValueError, KeyError, TypeError) as error:
        result.update({"status": "invalid_manifest", "error_type": type(error).__name__})
    return result


def existing_sockets() -> list[dict]:
    sockets: dict[str, dict] = {}
    for line in read_text(Path("/proc/net/unix")).splitlines()[1:]:
        fields = line.split(maxsplit=7)
        if len(fields) != 8 or not any(s in fields[7].lower() for s in ("wivrn", "monado", "openxr")):
            continue
        path = fields[7]
        item = sockets.setdefault(path, {"path": path, "listening": False,
                                         "filesystem_entry_exists": Path(path).exists()})
        item["listening"] |= bool(int(fields[3], 16) & 0x10000)
    return sorted(sockets.values(), key=lambda item: item["path"])


def runtime_processes() -> list[dict]:
    names: dict[str, int] = {}
    for path in Path("/proc").glob("[0-9]*/comm"):
        name = read_text(path)
        if any(s in name.lower() for s in ("wivrn", "monado", "vrserver", "vrcompositor")):
            names[name] = names.get(name, 0) + 1
    return [{"name": name, "count": count} for name, count in sorted(names.items())]


def wivrn_status() -> dict:
    busctl = shutil.which("busctl")
    result: dict = {"service": "io.github.wivrn.Server", "running": False, "headset_connected": None}
    if not busctl:
        result["query_status"] = "busctl_unavailable"
        return result
    prefix = [busctl, "--user", "--auto-start=no", "--timeout=2"]
    try:
        listing = subprocess.run(prefix + ["list", "--no-pager", "--no-legend"],
                                 capture_output=True, text=True, timeout=3)
        names = {line.split()[0] for line in listing.stdout.splitlines() if line.split()}
        if result["service"] not in names:
            result["query_status"] = "service_not_owned" if listing.returncode == 0 else "user_bus_unavailable"
            return result
        result["running"] = True
        properties = {"HeadsetConnected": "headset_connected", "SessionRunning": "existing_session_running",
                      "SystemName": "system_name", "PreferredRefreshRate": "preferred_refresh_rate_hz",
                      "AvailableRefreshRates": "available_refresh_rates_hz", "HandTracking": "hand_tracking_supported",
                      "EyeGaze": "eye_gaze_supported", "FaceTracking": "face_tracking_supported"}
        for source, target in properties.items():
            reply = subprocess.run(prefix + ["--json=short", "get-property", result["service"],
                                   "/io/github/wivrn/Server", result["service"], source],
                                   capture_output=True, text=True, timeout=3)
            if reply.returncode == 0:
                result[target] = json.loads(reply.stdout).get("data")
        result["query_status"] = "existing_service_properties_read"
    except (OSError, subprocess.TimeoutExpired, ValueError):
        result["query_status"] = "status_query_unavailable"
    return result


def relevant_usb_devices() -> list[dict]:
    devices = []
    # Oculus/Meta, Valve, HTC and Pico; WiVRn network headsets need not appear here.
    for device in Path("/sys/bus/usb/devices").glob("*"):
        vendor = read_text(device / "idVendor")
        if vendor in {"2833", "28de", "0bb4", "2d40", "3318"}:
            devices.append({"vendor_id": vendor, "product_id": read_text(device / "idProduct"),
                            "manufacturer": read_text(device / "manufacturer"), "product": read_text(device / "product")})
    return devices


def collect() -> dict:
    runtime = runtime_info()
    status = wivrn_status()
    prerequisites = (runtime.get("library_exists") and runtime.get("library", {}).get("host_architecture_matches"))
    return {"schema_version": 1, "observed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "read_only": True, "runtime_loaded_by_diagnostic": False, "session_created_by_diagnostic": False,
            "project_xr_rendering_tested": False, "platform": platform.system(), "architecture": platform.machine(),
            "runtime": runtime, "runtime_processes": runtime_processes(), "runtime_sockets": existing_sockets(),
            "wivrn": status, "relevant_usb_devices": relevant_usb_devices(),
            "usb_note": "Network-connected Quest headsets need not appear as USB devices.",
            "assessment": ("runtime_library_present_and_wivrn_reports_connected_headset" if prerequisites and status.get("headset_connected")
                           else "runtime_library_present_headset_unconfirmed" if prerequisites else "runtime_prerequisites_incomplete"),
            "limitations": ["No OpenXR loader, graphics device, headset or controller session was initialized.",
                            "Library dependencies and application rendering are not verified by this read-only check.",
                            "WiVRn status describes its existing service, not this Godot application's session."]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Additionally write the JSON report at this explicit path.")
    args = parser.parse_args()
    output = json.dumps(collect(), indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
