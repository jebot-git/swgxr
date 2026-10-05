#!/usr/bin/env python3
"""Summarize the installed Godot local script profiler's bounded diagnostic window."""
import argparse
import json
from pathlib import Path
import re

NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
FRAME = re.compile(rf"^FRAME: total: ({NUMBER}) script: ({NUMBER})/")
ACCUMULATED = re.compile(rf"^ACCUMULATED: total: ({NUMBER})")
FUNCTION = re.compile(r"^\d+:(.+)$")
TIMING = re.compile(rf"^\s*total:\s*({NUMBER})/.*?self:\s*({NUMBER})/.*?tcalls:\s*(\d+)")


def parse(text):
    frames, accumulated = [], []
    current, signature = None, None
    for line in text.splitlines():
        if match := FRAME.match(line):
            current = {"frame_seconds": float(match[1]), "script_seconds": float(match[2]), "functions": []}
            frames.append(current)
            signature = None
        elif match := ACCUMULATED.match(line):
            current = {"script_seconds": float(match[1]), "functions": []}
            accumulated.append(current)
            signature = None
        elif current is not None and (match := FUNCTION.match(line)):
            signature = match[1]
        elif current is not None and signature and (match := TIMING.match(line)):
            total, own, calls = float(match[1]), float(match[2]), int(match[3])
            current["functions"].append({"signature": signature, "inclusive_seconds": total, "self_seconds": own,
                                         "calls": calls, "mean_self_ms_per_call": own * 1000 / calls if calls else None})
            signature = None
    return frames, accumulated


def summarize(text):
    frames, accumulated = parse(text)
    final = accumulated[-1] if accumulated else {"script_seconds": 0, "functions": []}
    functions = final["functions"]
    for item in functions:
        item["percent_accounted_script_time"] = 100 * item["self_seconds"] / final["script_seconds"] if final["script_seconds"] else None
    return {"test": "godot_local_script_profile_summary", "valid": bool(functions),
            "sampled_frames": [{k: v for k, v in frame.items() if k != "functions"} for frame in frames],
            "accumulated_profile_windows": len(accumulated), "accounted_script_seconds": final["script_seconds"],
            "top_self": sorted(functions, key=lambda item: item["self_seconds"], reverse=True)[:30],
            "top_inclusive": sorted(functions, key=lambda item: item["inclusive_seconds"], reverse=True)[:30],
            "limitations": ["Profile window is diagnostic and adds overhead; use separate unprofiled VR capture for performance qualification",
                            "FRAME output samples one frame approximately once per second; these are not all-frame percentile measurements",
                            "Inclusive parent and child timings overlap and must not be added",
                            "Inherited super calls may appear in both wrapper self time and base-method timing; accounted script time is profiler bookkeeping, not a proven exclusive CPU total",
                            "Script self time can include engine/native work charged to the calling script; it is not a complete native CPU call-stack profile"],
            "format_source": "https://github.com/godotengine/godot/blob/ed1daf0bf/core/debugger/local_debugger.cpp"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.log.read_text(errors="replace"))
    report["log"] = str(args.log)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"valid": report["valid"], "top_self": report["top_self"][:8], "report": str(args.output)}))
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
