#!/usr/bin/env python3
"""Generate the Core3 profile table from versioned VR balance; no media or DB writes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def install():
    balance_path = ROOT/'client/combat/balance.json'
    references_path = ROOT/'server/combat/crafting_balance.json'
    balance = json.loads(balance_path.read_text())
    config = json.loads(references_path.read_text())
    revision = hashlib.sha256(balance_path.read_bytes()+references_path.read_bytes()).hexdigest()
    output = ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/tangible/weapon'
    output.mkdir(parents=True, exist_ok=True)
    implementation = (ROOT/'server/combat/WeaponCraftingProfile.h').read_bytes()
    header = output/'WeaponCraftingProfile.h'
    if not header.exists() or header.read_bytes() != implementation: header.write_bytes(implementation)
    lines = ['#pragma once', '#include "WeaponCraftingProfile.h"', 'namespace swgxr {',
             f'constexpr int PROFILE_VERSION = {config["version"]};',
             f'constexpr const char* BALANCE_REVISION = "{revision}";', 'constexpr Reference REFERENCES[] = {']
    for key, override in balance['weapons'].items():
        profile = dict(balance['classes'][override['class']], **override)
        ref = config['references'][key]
        template = override.get("template", f'object/weapon/ranged/{key.split("_")[0]}/{key}.iff')
        numbers = [profile.get('rpm',0), profile.get('capacity',0), ref['attackSpeed'],ref['healthAttackCost'],ref['actionAttackCost'],ref['mindAttackCost']]
        lines.append('    {"'+key+'", "'+template+'", '+', '.join(str(n) for n in numbers)+', '+str(profile.get('kind')=='melee').lower()+', '+str(profile.get('stance_recovery',0))+', '+str(profile.get('power',0))+'},')
    lines += ['};', 'inline Profile resolve(const Reference& ref, double delay, double h, double a, double m) {',
              '    return resolve(ref, delay, h, a, m, '+', '.join(map(str,config['rpm_limits']+config['capacity_limits']))+');', '}', '}']
    table = output/'WeaponCraftingReferences.h'
    text = '\n'.join(lines)+'\n'
    if not table.exists() or table.read_text() != text: table.write_text(text)
    print('Installed Core3 crafting profile v'+str(config['version'])+' balance '+revision[:12])

if __name__ == '__main__': install()
