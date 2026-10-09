#!/usr/bin/env python3
"""Read-only Combat Medic recipe audit using original tables and compiled CU policy.

Requires the supplied local game media, configured Core3 checkout, and c++.
Only the ignored evidence report is written. No item, recipe, service or DB mutation.
"""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "vendor/Core3/MMOCoreORB/bin/scripts"
DRAFT = "object/draft_schematic/chemistry/"
COMPONENTS = ("dispersal_mechanism", "infection_amplifier", "resilience_compound")
DISEASE_ATTRIBUTES = ("action", "constitution", "focus", "health", "mind", "quickness", "stamina", "strength", "willpower")


def expected_recipes():
    """Independent exhaustive inventory of the original CM families and variants."""
    expected = {}
    for family, attributes, retained in (("poison", ("health", "action", "mind"), "health"),
                                          ("disease", DISEASE_ATTRIBUTES, "action")):
        for area in ("", "area_"):
            for attribute in attributes:
                for tier in "abc":
                    expected[DRAFT + f"medpack_{family}_{area}{attribute}_{tier}.iff"] = {
                        "family": family, "attribute": attribute, "area": bool(area),
                        "tier": tier.upper(), "retired": attribute != retained}
    for family, prefix, tiers in (("ranged_stim", "med_stimpack_range_", "abcde"),
                                  ("area_stim", "med_stimpack_area_", "abc")):
        for tier in tiers:
            expected[DRAFT + prefix + tier + ".iff"] = {
                "family": family, "tier": tier.upper(), "area": family == "area_stim", "retired": False}
    for suffix in ("", "_advanced"):
        for name in COMPONENTS:
            expected[DRAFT + "component/" + name + suffix + ".iff"] = {
                "family": "component", "component": name + suffix, "retired": False}
    return expected


def lua(path):
    return re.sub(r"--[^\n]*", "", path.read_text())


def field(source, name):
    match = re.search(r"\b" + re.escape(name) + r'\s*=\s*"([^"\n]+)"', source)
    return match.group(1) if match else None


def policy_results(paths):
    """Execute the real installed-policy source, never a Python approximation."""
    with tempfile.TemporaryDirectory(prefix="swgxr-combat-medic-audit-") as directory:
        source, binary = Path(directory) / "audit.cpp", Path(directory) / "audit"
        source.write_text('#include "server/combat/CoreCuMedicalPolicy.h"\n#include <iostream>\n'
                          'int main(){std::string path;while(std::getline(std::cin,path))'
                          'std::cout<<corecu::medicine::retiredMedicalTemplate(path)<<"\\n";}\n')
        subprocess.run(["c++", "-std=c++17", "-I", str(ROOT), str(source), "-o", str(binary)],
                       check=True, capture_output=True, text=True, timeout=30)
        result = subprocess.run([str(binary)], input="".join(path + "\n" for path in paths),
                                check=True, capture_output=True, text=True, timeout=10)
        values = result.stdout.splitlines()
        assert len(values) == len(paths), "Compiled policy returned incomplete results"
        return dict(zip(paths, (value == "1" for value in values)))


def audit():
    sys.path.insert(0, str(ROOT))
    sys.path.insert(0, str(ROOT / "tools/assets"))
    from server.character_protocol import assets
    from character_formats import datatable

    source_hashes = {}

    def table(name):
        raw = assets().read(name)
        source_hashes[name] = hashlib.sha256(raw).hexdigest()
        return datatable(raw)

    skills = table("datatables/skill/skills.iff")
    source_groups = table("datatables/crafting/schematic_group.iff")
    nodes = [row for row in skills if row["NAME"].startswith("science_combatmedic_")]
    granted = {group for node in nodes for group in node["SCHEMATICS_GRANTED"].split(",") if group}
    rows = [row for row in source_groups if row["GroupId"] in granted]
    expected = expected_recipes()
    assert len(rows) == len(expected) == 86, "Original CM recipe count changed; review source"
    assert {row["SchematicName"] for row in rows} == set(expected), "Unexpected or missing CM recipe"
    assert len(granted) == 19, "Original CM grant-group count changed"
    paths = []
    recipes = []
    for row in rows:
        name = row["SchematicName"]
        recipe = SCRIPTS / Path(name).with_suffix(".lua")
        text = lua(recipe)
        output = field(text, "targetTemplate")
        assert output, "Empty original recipe: " + name
        target = SCRIPTS / Path(output).with_suffix(".lua")
        assert target.is_file(), "Missing native recipe output: " + output
        target_text = lua(target)
        assert f'"{name}"' in text and f'"{output}"' in target_text, "Unregistered recipe/output: " + name
        assert field(text, "assemblySkill") == "combat_medicine_assembly", name
        template_type = re.search(r"\btemplateType\s*=\s*(\w+)", target_text)
        kind = template_type[1] if template_type else "inherited_component"
        wanted = expected[name]
        if wanted["family"] in ("poison", "disease"):
            assert kind == "DOTPACK", name
            assert field(target_text, "commandToExecute") == "apply" + wanted["family"], name
        elif wanted["family"] in ("ranged_stim", "area_stim"):
            assert kind == "RANGEDSTIMPACK", name
        entry = dict(wanted, recipe=name, output=output, group=row["GroupId"],
                     output_type=kind,
                     recipe_sha256=hashlib.sha256(recipe.read_bytes()).hexdigest(),
                     output_sha256=hashlib.sha256(target.read_bytes()).hexdigest())
        recipes.append(entry)
        for path in (name, output):
            paths.extend((path, str(Path(path).with_name("shared_" + Path(path).name))))
        source_hashes[str(recipe.relative_to(ROOT))] = entry["recipe_sha256"]
        source_hashes[str(target.relative_to(ROOT))] = entry["output_sha256"]

    outcomes = policy_results(paths)
    for entry in recipes:
        for name in (entry["recipe"], entry["output"]):
            for path in (name, str(Path(name).with_name("shared_" + Path(name).name))):
                assert outcomes[path] == entry["retired"], "Unexpected native retirement: " + path
        entry["retirement"] = "already_retired_pool_variant" if entry["retired"] else "retained"

    counts = {}
    for family in ("poison", "disease", "ranged_stim", "area_stim", "component"):
        members = [entry for entry in recipes if entry["family"] == family]
        counts[family] = {"original": len(members), "retired": sum(entry["retired"] for entry in members),
                          "retained": sum(not entry["retired"] for entry in members)}
    groups = []
    for group in sorted(granted):
        members = [entry for entry in recipes if entry["group"] == group]
        retained = [entry["recipe"] for entry in members if not entry["retired"]]
        assert retained, "Empty Combat Medic training reward: " + group
        groups.append({"id": group, "original_count": len(members), "retained_count": len(retained),
                       "retained_recipes": retained})
    progression = [{"skill": node["NAME"], "groups": node["SCHEMATICS_GRANTED"].split(","),
                    "retained_recipes": [entry["recipe"] for entry in recipes if not entry["retired"]
                                         and entry["group"] in node["SCHEMATICS_GRANTED"].split(",")]}
                   for node in nodes if node["SCHEMATICS_GRANTED"]]
    for path in (ROOT / "server/combat/CoreCuMedicalPolicy.h", ROOT / "server/combat/DoctorPolicy.h"):
        source_hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    cure_groups = {row["GroupId"] for row in source_groups if "/medpack_cure_" in row["SchematicName"]}
    assert not (granted & cure_groups), "Cure ownership changed; review instead of retiring"
    cure_grants = {node["NAME"]: sorted(cure_groups & set(node["SCHEMATICS_GRANTED"].split(",")))
                   for node in skills if cure_groups & set(node["SCHEMATICS_GRANTED"].split(","))}
    assert {group for groups in cure_grants.values() for group in groups} == cure_groups, "Ungrantable cure group"
    assert cure_grants and all(skill.startswith("science_doctor_") for skill in cure_grants), "Cure ownership changed"
    assert sum(entry["retired"] for entry in recipes) == 60
    return {"passed": True, "scope": "read-only original media/native recipe catalog and compiled retirement policy; no runtime crafting test",
            "original_recipe_count": 86, "already_retired_recipe_count": 60, "retained_recipe_count": 26,
            "original_group_count": 19, "empty_granted_groups": [], "additional_retirements": [],
            "policy_checks": len(paths), "family_counts": counts,
            "retained_components": [entry["component"] for entry in recipes if entry["family"] == "component"],
            "cure_scope": {"combat_medic_grants": [], "owner": "science_doctor", "grants": cure_grants,
                           "note": "Single-target and area poison/disease cures remain distinct Doctor recipes."},
            "saved_supply_policy": "Existing native retirement, cleanup and factory behavior unchanged; this audit mutates no saved supplies or production policy.",
            "groups": groups, "progression": progression, "recipes": recipes, "sources_sha256": source_hashes}


def main():
    result = audit()
    target = ROOT / "runtime/evidence/combat-medic/schematics.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS: 86 original CM recipes; 60 already retired; 26 retained; 19 nonempty groups; {result['policy_checks']} compiled policy checks. Report: {target}")


if __name__ == "__main__":
    main()
