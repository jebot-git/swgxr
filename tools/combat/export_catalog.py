#!/usr/bin/env python3
"""Export bounded Core3 template defaults for the LOCAL combat lab, never item instances.
No Lua execution, downloads, backend writes or proprietary asset copies.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIELDS = ('pointBlankRange', 'pointBlankAccuracy', 'idealRange', 'idealAccuracy',
          'maxRange', 'maxRangeAccuracy', 'minDamage', 'maxDamage', 'woundsRatio')
DAMAGE_TYPES = {'ENERGY', 'KINETIC', 'ELECTRICITY', 'STUN', 'BLAST', 'HEAT', 'COLD', 'ACID', 'LIGHTSABER'}

def template_path(key, override):
    return override.get('template', f'object/weapon/ranged/{key.split("_")[0]}/{key}.iff')


def parse_template(path):
    source = path.read_text()
    source = re.sub(r'--[^\n]*', '', source)
    result = {}
    for key in (*FIELDS, 'damageType', 'armorPiercing', 'certificationsRequired'):
        match = re.search(r'\b' + key + r'\s*=\s*(\{[^}]*\}|[\w.+-]+)', source)
        if not match:
            raise ValueError(f'{path.name}: missing explicit {key}; inheritance is not guessed')
        value = match[1]
        if key in FIELDS:
            result[key] = float(value)
        elif key == 'certificationsRequired':
            result[key] = re.findall(r'"([^"]+)"', value)
        elif key == 'armorPiercing':
            result[key] = {'NONE': 0, 'LIGHT': 1, 'MEDIUM': 2, 'HEAVY': 3}[value]
        else:
            if value not in DAMAGE_TYPES:
                raise ValueError(f'unknown damage type: {value}')
            result[key] = value.lower()
    if not 0 <= result['minDamage'] <= result['maxDamage'] or not 0 <= result['pointBlankRange'] <= result['idealRange'] <= result['maxRange']:
        raise ValueError(f'{path.name}: invalid damage/range bounds')
    return result


def export(core3, balance):
    templates = core3 / 'MMOCoreORB/bin/scripts'
    entries, errors = {}, []
    for key, override in balance['weapons'].items():
        relative = template_path(key, override).replace('.iff','.lua')
        path = templates / relative
        try:
            stats = parse_template(path)
            profile = dict(balance['classes'][override['class']], **override)
            entries[key] = dict(profile, id=key, template=relative.replace('.lua', '.iff'),
                                core3=stats, source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                                source_file=relative, source_kind='core3_template_defaults')
        except (OSError, ValueError, KeyError) as exc:
            errors.append({'weapon': key, 'error': str(exc)})
    revision = subprocess.check_output(['git', '-C', str(core3), 'rev-parse', 'HEAD'], text=True).strip()
    return {'schema': 1, 'source_kind': 'core3_template_defaults', 'core3_revision': revision,
            'weapons': entries, 'failures': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core3', type=Path, default=ROOT / 'vendor/Core3')
    parser.add_argument('--output', type=Path, default=ROOT / 'runtime/assets/combat/catalog.json')
    args = parser.parse_args()
    balance_path = ROOT / 'client/combat/balance.json'
    catalog = export(args.core3, json.loads(balance_path.read_text()))
    import sys
    sys.path.insert(0,str(ROOT))
    from server.unarmed_protocol import resolve
    catalog['unarmed'] = resolve({'strength':0,'quickness':0,'unarmed_damage':0,'unarmed_speed':0}, source='synthetic_unarmed_lab')
    catalog['balance_sha256'] = hashlib.sha256(balance_path.read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, indent=2) + '\n')
    print(f"Exported {len(catalog['weapons'])} template profiles; {len(catalog['failures'])} failures: {args.output}")
    if catalog['failures']:
        print(json.dumps(catalog['failures'], indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
