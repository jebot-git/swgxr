#!/usr/bin/env python3
"""Index original Tatooine spawn dependencies for live-population asset loading.

Does not generate local mobs, spawn positions, AI, or substitute spawn rules.
All random selection, nesting and respawn timing remain Core3 responsibilities.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/server'))
from export_ambient_npcs import clean, table, strings, rows


def export(groups=None, planet="tatooine"):
    scripts = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts'
    dependencies = {}; failures = []
    def read(path):
        raw = path.read_bytes()
        dependencies[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
        return clean(raw.decode())
    region_path = scripts / f'managers/planet/{planet}_regions.lua'
    region_text = read(region_path)
    group_dir = scripts / 'mobile/spawn' / planet
    referenced = sorted({name for name in strings(region_text)
                         if (group_dir / (name + '.lua')).is_file()})
    if groups:
        unknown = set(groups) - set(referenced)
        if unknown: raise ValueError('Groups not referenced by '+planet+' regions: ' + str(sorted(unknown)))
        referenced = sorted(set(groups))
    lair_paths = {}
    for path in (scripts / 'mobile/lair').rglob('*.lua'):
        if 'unused' in path.parts: continue
        # Registration keys need not match filenames (valarian_swooper_camp).
        for name in re.findall(r'addLairTemplate\(\s*"([^"]+)"', clean(path.read_text())):
            if name in lair_paths and lair_paths[name] != path:
                raise ValueError('Ambiguous registered lair ' + name)
            lair_paths[name] = path
    mobile_paths = {}
    for path in (scripts / 'mobile').rglob('*.lua'):
        if any(part in path.parts for part in ('lair', 'spawn', 'outfits', 'dressgroup', 'conversations', 'weapon')): continue
        text = path.read_text(errors='replace')
        if 'CreatureTemplates:addCreatureTemplate' in text:
            mobile_paths[path.stem] = path
    mobiles = {}; lairs = {}; spawn_groups = {}
    def mobile(name, trail=()):
        if name in mobiles: return mobiles[name]
        if name in trail or name not in mobile_paths: raise ValueError('Unresolved mobile ' + name)
        path = mobile_paths[name]; text = read(path)
        parent = re.search(r'=\s*(\w+):new', text)
        inherited = mobile(parent[1], (*trail, name)) if parent and parent[1] != 'Creature' else {}
        templates = strings(table(text, 'templates')[0]) or inherited.get('appearance_templates', [])
        expanded = []
        for template in templates:
            if template.startswith('object/'):
                expanded.append(template)
            else:
                group = scripts / 'mobile/dressgroup' / (template + '.lua')
                expanded.extend(value for value in strings(read(group)) if value.startswith('object/'))
        record = {'source': str(path.relative_to(ROOT)), 'appearance_templates': sorted(set(expanded))}
        if not record['appearance_templates']: raise ValueError('No original appearances for ' + name)
        # Keep expressions explicit instead of pretending parsed declarations
        # are the final AI movement speed or rolled live HAM.
        for key in ('level', 'baseHAM', 'baseHAMmax', 'damageMin', 'damageMax', 'scale',
                    'primaryWeapon', 'secondaryWeapon', 'pvpBitmask', 'optionsBitmask'):
            match = re.search(r'\b' + key + r'\s*=\s*([^,\n}]+)', text)
            if match:
                value = match[1].strip()
                try: record[key] = ast.literal_eval(value)
                except (ValueError, SyntaxError): record[key] = {'source_expression': value}
            elif key in inherited: record[key] = inherited[key]
        mobiles[name] = record
        return record
    for name in referenced:
        path = group_dir / (name + '.lua'); text = read(path)
        names = re.findall(r'\blairTemplateName\s*=\s*"([^"]+)"', table(text, 'lairSpawns')[0])
        if not names: failures.append({'group': name, 'error': 'No literal lair references'})
        spawn_groups[name] = {'source': str(path.relative_to(ROOT)), 'lair_templates': names}
        for lair in names:
            if lair in lairs: continue
            try:
                source = lair_paths[lair]; data = read(source)
                mobile_names = sorted({row[0] for key in ('mobiles', 'bossMobiles') for row, _ in rows(data, key)})
                buildings = sorted({value for key in ('buildingsVeryEasy', 'buildingsEasy', 'buildingsMedium', 'buildingsHard', 'buildingsVeryHard') for value in strings(table(data, key)[0])})
                lairs[lair] = {'source': str(source.relative_to(ROOT)), 'mobiles': mobile_names, 'building_templates': buildings}
                for creature in mobile_names: mobile(creature)
            except (KeyError, ValueError, OSError) as error:
                failures.append({'lair': lair, 'error': str(error)})
    templates = sorted({template for entry in mobiles.values() for template in entry['appearance_templates']})
    manifest = {'schema_version': 1, 'mode': 'source_dependency_index_not_live_population',
                'regions_source': str(region_path.relative_to(ROOT)), 'spawn_groups': spawn_groups,
                'lairs': lairs, 'mobiles': mobiles, 'failures': failures,
                'provenance': {'files_sha256': dependencies}}
    requests = {'schema_version': 1, 'mode': 'appearance_requests_only_no_spawn_positions',
                'instances': [{'id': 'appearance:' + str(i), 'template': template, 'appearance_id': template,
                               'mobile': '', 'mood': 'neutral'} for i, template in enumerate(templates)],
                'provenance': manifest['provenance']}
    return manifest, requests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', action='append', help='Restrict asset preparation to a source region group')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/assets/combat_population')
    args = parser.parse_args()
    manifest, requests = export(args.group)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.out / 'appearance_requests.json').write_text(json.dumps(requests, indent=2) + '\n')
    summary = {key: len(manifest[key]) for key in ('spawn_groups', 'lairs', 'mobiles', 'failures')}
    summary['appearance_templates'] = len(requests['instances'])
    summary['live_population'] = False
    print(json.dumps(summary, indent=2))
    return bool(manifest['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
