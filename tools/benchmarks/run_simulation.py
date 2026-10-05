#!/usr/bin/env python3
"""Run deterministic, synthetic action-authority workloads (not a real MMO load test)."""
from __future__ import annotations
import argparse
import json
import os
import platform
import datetime
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from client.launch_environment import client_environment
TARGETS = json.loads((ROOT / "client/benchmarks/simulation_targets.json").read_text())
PROFILES = [(p["players"], p["npcs"], p["instances"]) for p in TARGETS["profiles"]]

def concurrent_workloads() -> list[dict]:
    rows = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            comm = (entry / "comm").read_text().strip()
            if comm.startswith("godot"):
                rows.append({"pid": int(entry.name), "executable": comm})
        except (OSError, PermissionError):
            continue
    return rows

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--players", type=int, default=16)
    parser.add_argument("--npcs", type=int, default=16)
    parser.add_argument("--duration", type=float, default=15)
    parser.add_argument("--warmup", type=float, default=3)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--instances", type=int, default=1)
    parser.add_argument("--latency-ms", type=float, default=50)
    parser.add_argument("--jitter-ms", type=float, default=25)
    parser.add_argument("--loss", type=float, default=.01)
    parser.add_argument("--output", type=Path, default=ROOT / "runtime/evidence/action-simulation.json")
    parser.add_argument("--suite", action="store_true")
    args = parser.parse_args()
    if not (1 <= args.players <= 512 and 0 <= args.npcs <= 512 and args.players + args.npcs <= 1024):
        parser.error("Actor pool supports 1–512 players, 0–512 NPCs, at most 1024 total")
    if not (1 <= args.duration <= 600 and 0 <= args.warmup <= 60 and 1 <= args.instances <= 64 and 0 <= args.loss <= .9):
        parser.error("Invalid duration, warmup, instances or loss")
    if not (0 <= args.latency_ms <= 2000 and 0 <= args.jitter_ms <= 1000):
        parser.error("Latency must be 0–2000 ms and jitter 0–1000 ms")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    profiles = PROFILES if args.suite else [(args.players, args.npcs, args.instances)]
    results = []
    for players, npcs, instances in profiles:
        destination = output.with_name(f"{output.stem}-{players}p-{npcs}n-{instances}i.json") if args.suite else output
        values = {"players": players, "npcs": npcs, "instances": instances, "duration": args.duration, "warmup": args.warmup, "seed": args.seed, "latency-ms": args.latency_ms, "jitter-ms": args.jitter_ms, "loss": args.loss, "output": str(destination)}
        command = [os.environ.get("GODOT", "godot"), "--headless", "--xr-mode", "off", "--audio-driver", "Dummy", "--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "--path", str(ROOT / "client"), "--script", "res://benchmarks/action_simulation.gd", "--"] + [f"--{key}={value}" for key, value in values.items()]
        workloads = concurrent_workloads()
        measured_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        completed = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600, env=client_environment())
        destination.with_suffix(".log").write_text(completed.stdout)
        print(completed.stdout, end="")
        if completed.returncode or not destination.exists():
            return completed.returncode or 2
        result = json.loads(destination.read_text())
        result["measurement_context"] = {"utc": measured_at, "platform": platform.platform(), "logical_cpus": os.cpu_count(), "concurrent_godot_processes_at_start": workloads, "timing_is_isolated": False, "no_other_godot_at_start": not workloads, "process_sampling_limit": "Only Godot processes at start sampled; CPU isolation is not enforced and other system load may affect results."}
        destination.write_text(json.dumps(result, indent=2) + "\n")
        results.append(result)
    if args.suite:
        output.write_text(json.dumps({"kind": "synthetic_action_simulation_suite", "passed": all(r["passed"] for r in results), "all_timing_targets_pass": all(r["timing_target_pass"] for r in results), "results": results}, indent=2) + "\n")
    return 0 if all(r["passed"] for r in results) else 1

if __name__ == "__main__":
    sys.exit(main())
