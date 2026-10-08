#!/usr/bin/env python3
"""Audit native droid recipes against the compiled CU retirement policy.

Read-only source/policy check, not a crafting or installed-module runtime test.
Run from any directory; the ignored evidence report contains paths and hashes,
not copies of game assets. Requires the configured Core3 checkout and g++.
"""
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "vendor/Core3/MMOCoreORB/bin/scripts"
COMPONENTS = SCRIPTS / "object/draft_schematic/droid/component"
POLICY = ROOT / "server/combat/CoreCuMedicalPolicy.h"
OBSOLETE = [f"droid_stimpack_{tier}" for tier in "abcd"] + [
    f"droid_vitapack_{tier}" for tier in "abc"
]


def lua(path):
    # These catalog entries use line comments, including commented-out fields.
    return re.sub(r"--[^\n]*", "", path.read_text())


def field(source, name):
    match = re.search(r"\b" + name + r'\s*=\s*"([^"]+)"', source)
    return match.group(1) if match else None


def main():
    rows, cases = [], []
    recipes = sorted(COMPONENTS.glob("*.lua"))
    assert recipes, "Configured native droid component catalog is missing"
    for recipe in recipes:
        if recipe.stem in ("objects", "serverobjects"):
            continue
        source = lua(recipe)
        target = field(source, "targetTemplate")
        assert target, f"Review empty component recipe: {recipe}"
        output = SCRIPTS / Path(target).with_suffix(".lua")
        assert output.is_file(), f"Missing component output: {target}"
        output_source = lua(output)
        template = recipe.relative_to(SCRIPTS).with_suffix(".iff").as_posix()
        assert f'"{template}"' in source, template
        assert f'"{target}"' in output_source, target
        module = field(output_source, "dataObjectComponent")
        if module:
            implementation = (ROOT / "vendor/Core3/MMOCoreORB/src/server/zone/objects"
                              / "tangible/components/droid" / f"{module}.cpp")
            assert implementation.is_file(), f"Missing module implementation: {module}"
        rows.append({"recipe": template, "output": target, "module": module,
                     "recipe_sha256": hashlib.sha256(recipe.read_bytes()).hexdigest(),
                     "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
        for path in (template, target):
            cases.extend([(path, False), (str(Path(path).with_name("shared_" + Path(path).name)), False)])

    # Check the already-retired empty medicine recipes alongside useful modules.
    for name in OBSOLETE:
        path = f"object/draft_schematic/droid/{name}.iff"
        assert not field(lua(SCRIPTS / Path(path).with_suffix(".lua")), "targetTemplate"), path
        for prefix in ("", "shared_"):
            cases.append((f"object/draft_schematic/droid/{prefix}{name}.iff", True))
            cases.append((f"object/tangible/medicine/pet/{prefix}{name}.iff", True))

    with tempfile.TemporaryDirectory(prefix="swgxr-droid-audit-") as tmp:
        cpp, binary = Path(tmp) / "audit.cpp", Path(tmp) / "audit"
        checks = [f'if (retiredMedicalTemplate({json.dumps(path)}) != {str(retired).lower()}) '
                  f'{{ std::cerr << {json.dumps(path)} << "\\n"; return 1; }}'
                  for path, retired in cases]
        cpp.write_text('#include "server/combat/CoreCuMedicalPolicy.h"\n#include <iostream>\n'
                       'int main(){ using corecu::medicine::retiredMedicalTemplate;\n'
                       + "\n".join(checks) + "\nreturn 0;}\n")
        subprocess.run(["g++", "-std=c++14", "-I", str(ROOT), str(cpp), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

    report = {"scope": "static native catalog and compiled retirement policy; no runtime crafting test",
              "passed": True, "component_recipes_preserved": len(rows),
              "previously_retired_empty_medicine_recipes": OBSOLETE,
              "additional_retirements": [], "policy_checks": len(cases),
              "policy_sha256": hashlib.sha256(POLICY.read_bytes()).hexdigest(), "components": rows}
    destination = ROOT / "runtime/evidence/cu-droid-components-audit.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {len(rows)} component recipes retained; {len(OBSOLETE)} obsolete medicine recipes retired; "
          f"{len(cases)} compiled policy checks. Report: {destination}")


if __name__ == "__main__":
    main()
