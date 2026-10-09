#!/usr/bin/env python3
"""Install CoreCU's versioned, asset-independent combat policy headers."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def install():
    source = ROOT / 'server/combat'
    policy = (source / 'CoreCuPolicy.h').read_bytes()
    medical = (source / 'CoreCuMedicalPolicy.h').read_bytes()
    food = (source / 'CoreCuFoodPolicy.h').read_bytes()
    resources = (source / 'CoreCuResources.h').read_bytes()
    regeneration = (source / 'CoreCuRegenPolicy.h').read_bytes()
    doctor = (source / 'DoctorPolicy.h').read_bytes()
    doctor_care = (ROOT / 'server/medic/DoctorCarePolicy.h').read_bytes()
    combat_medic = (ROOT / "server/medic/CombatMedicPolicy.h").read_bytes()
    combat_medic_healing = (ROOT / "server/medic/CombatMedicHealingPolicy.h").read_bytes()
    config = json.loads((source / 'corecu_professions.json').read_text())
    assert len(config['statuses']) == 10
    revision = hashlib.sha256(policy + medical + food + resources + regeneration + doctor + doctor_care + combat_medic + combat_medic_healing + json.dumps(config, sort_keys=True).encode()).hexdigest()
    lines = ['#pragma once', 'namespace corecu {',
             'struct Profession {const char* name; double ratings[10];};',
             f'constexpr const char* REVISION="{revision}";', 'constexpr Profession PROFESSIONS[]={']
    for name, values in config['professions'].items():
        assert len(values) == 10 and all(0 <= v <= 100 for v in values)
        lines.append('{'+json.dumps(name)+',{'+','.join(map(str, values))+'}},')
    lines += ['};', '}','']
    out = ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
    for name, data in [('CoreCuPolicy.h', policy), ('CoreCuMedicalPolicy.h', medical), ('CoreCuResources.h', resources), ('CoreCuFoodPolicy.h', food), ('CoreCuRegenPolicy.h', regeneration), ('CoreCuProfessions.h', '\n'.join(lines).encode())]:
        target = out/name
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    print('CoreCU policy v1:', revision)
    return revision

if __name__ == '__main__':
    install()
