#!/usr/bin/env python3
"""Source-derived PvE faction reward metadata and original preview selection.

Prices here are provenance only. Core3 owns eligibility, live discounts, faction
standing, purchases and object creation. No media is fetched or committed.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

from prepare_inventory import canonical
from stf import string_table
from swg_formats import TreSet, cstring, parse_iff

ROOT = Path(__file__).resolve().parents[2]
PERKS = 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/gcw/recruiters/factionPerkData.lua'
REINFORCEMENTS = 'vendor/Core3/MMOCoreORB/src/server/zone/managers/gcw/tasks/LambdaShuttleWithReinforcementsTask.h'
CATEGORIES = (('weaponsArmor', 'weaponsArmorList'), ('uniforms', 'uniformList'), ('furniture', 'furnitureList'))


def npc_sources(root=ROOT):
    folder = root / 'vendor/Core3/MMOCoreORB/bin/scripts/mobile/faction'
    return sorted(set(folder.rglob('*recruiter.lua')) | set(folder.rglob('crackdown*.lua')) | {root / REINFORCEMENTS})


def npc_templates(root=ROOT):
    templates = {template for path in npc_sources(root)
                 for template in re.findall(r'"(object/mobile/[^"\n]+)"', path.read_text())}
    carrier = re.search(r'LAMBDATEMPLATE\s*=\s*"([^"]+)"', (root / REINFORCEMENTS).read_text())
    if not carrier:
        raise ValueError('Original crackdown carrier template unavailable')
    return sorted(templates | {carrier[1]})


def block(text, key, optional=False):
    """Read this pinned literal Lua data shape; never execute game scripts."""
    match = re.search(r'\b' + re.escape(key) + r'\s*=\s*\{', text)
    if not match:
        if optional:
            return ''
        raise ValueError('Missing source faction table: ' + key)
    depth = 1
    start = pos = match.end()
    quote = False
    while pos < len(text):
        char = text[pos]
        if char == '\\' and quote:
            pos += 2
            continue
        if char == '"':
            quote = not quote
        elif not quote:
            depth += (char == '{') - (char == '}')
            if not depth:
                return text[start:pos]
        pos += 1
    raise ValueError('Unclosed source faction table: ' + key)


def reward_rows(text):
    text = re.sub(r'--[^\n]*', '', text)
    result = []
    for faction in ('rebel', 'imperial'):
        data = block(text, faction + 'RewardData')
        for category, list_key in CATEGORIES:
            ordered = re.findall(r'"([a-z0-9_]+)"', block(data, list_key, optional=True))
            if not ordered:
                continue
            if len(set(ordered)) != len(ordered):
                raise ValueError('Duplicate reward key in ' + list_key)
            entries = block(data, category)
            for key in ordered:
                entry = block(entries, key)
                fields = dict(re.findall(r'\b(item|display)\s*=\s*"([^"\n]+)"', entry))
                cost = re.search(r'\bcost\s*=\s*(\d+)\s*[,}]?\s*$', entry)
                if fields.keys() != {'item', 'display'} or not cost:
                    raise ValueError('Unsupported literal reward declaration: ' + key)
                template, shared = canonical(fields['item'])
                result.append({'id': faction + ':' + category + ':' + key,
                               'faction': faction, 'category': category, 'key': key,
                               'template': template, 'shared_template': shared,
                               'display_stf': fields['display'], 'base_cost': int(cost[1])})
    return result


def build(root=ROOT):
    sources = TreSet(root / 'runtime/assets/active_tre')
    hashes = {}
    failures = []

    def read(path):
        raw = sources.read(path)
        hashes[path] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
                        'archive': sources.entries[path][0].name}
        return raw

    def source(path):
        raw = (root / path).read_bytes()
        hashes[path] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}
        return raw.decode()

    tables = {}

    def table(name):
        if name not in tables:
            tables[name] = string_table(read('string/en/' + name + '.stf'))
        return tables[name]

    def localized(reference):
        name, key = reference.removeprefix('@').split(':', 1)
        return table(name).get(key, '')

    def description(path, trail=()):
        if path in trail:
            raise ValueError('Cyclic original template inheritance')
        node = parse_iff(read(path))
        prefix = b'detailedDescription\0\1\1'
        for entry in node.walk('XXXX'):
            if entry.data.startswith(prefix):
                name, pos = cstring(entry.data, len(prefix))
                key, _ = cstring(entry.data, pos + 1)
                return localized('@' + name + ':' + key) if name and key else ''
        inherited = next(node.walk('DERV'), None)
        return description(cstring(inherited.first('XXXX').data)[0], trail + (path,)) if inherited else ''

    inventory_path = root / 'runtime/assets/inventory/catalog.json'
    inventory = json.loads(inventory_path.read_text()) if inventory_path.exists() else {'items': {}}
    rewards = reward_rows(source(PERKS))
    for row in rewards:
        row['name'] = localized(row['display_stf'])
        if not row['name']:
            raise ValueError('Original faction reward name unavailable: ' + row['display_stf'])
        row['description'] = description(row['shared_template'])
        preview = inventory['items'].get(row['template'], {})
        row.update(preview_status=preview.get('status', 'unprepared'),
                   preview_model=preview.get('model', ''), preview_sha256=preview.get('model_sha256', ''))
        if row['preview_status'] != 'ready':
            failures.append({'reward_id': row['id'], 'phase': 'inventory_preview',
                             'template': row['template'], 'errors': preview.get('failures', ['Model not prepared'])})
    strings = {name: table(name) for name in ('faction_recruiter', 'faction_perk',
               'conversation/faction_recruiter_imperial', 'conversation/faction_recruiter_rebel',
               'imperial_presence/contraband_search')}
    for path in npc_sources(root):
        source(str(path.relative_to(root)))
    npc_path = root / 'runtime/assets/ambient_npcs/catalog.json'
    npcs = json.loads(npc_path.read_text()).get('races', {}) if npc_path.exists() else {}
    appearances = {template: {'ready': template in npcs,
                             'complete': npcs.get(template, {}).get('appearance_complete', template in npcs),
                             'body': npcs.get(template, {}).get('body', '')}
                   for template in npc_templates(root)}
    for template, row in appearances.items():
        if not row['ready']:
            failures.append({'template': template, 'phase': 'npc_appearance', 'error': 'Original NPC appearance not prepared'})
        elif not row['complete']:
            failures.extend(npcs[template].get('appearance_failures', []))
    return {'schema': 1, 'rewards': rewards, 'strings': strings,
            'npc_appearances': appearances,
            'excluded_categories': ['installations', 'hirelings', 'schematic'],
            'source_hashes': hashes, 'failures': failures,
            'policy': 'Original ordered recruiter reward lists restricted to equipment, uniforms and furniture. Base costs describe source data; native Core3 determines live prices and all purchase effects.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-previews', action='store_true')
    parser.add_argument('--prepare-npcs', action='store_true')
    args = parser.parse_args()
    if args.prepare_previews:
        rows = reward_rows((ROOT / PERKS).read_text())
        command = [sys.executable, str(ROOT / 'tools/assets/prepare_inventory.py')]
        for template in sorted({row['template'] for row in rows}):
            command.extend(['--template', template])
        # Resolve owner-bound clothing using the original human body material;
        # this frozen preview does not change any player's actual worn model.
        command.extend(['--equipment-race', 'human_male'])
        subprocess.run(command, cwd=ROOT, check=True)
    if args.prepare_npcs:
        path = ROOT / 'runtime/assets/ambient_npcs/catalog.json'
        existing = json.loads(path.read_text()).get('races', {}) if path.exists() else {}
        missing = [template for template in npc_templates() if template not in existing]
        if missing:
            manifest = ROOT / 'runtime/assets/gcw/npc-selection.json'
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_text(json.dumps({'mode': 'source_dependency_selection_not_spawn_authority',
                'provenance': {'files_sha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                               for path in npc_sources()}},
                'instances': [{'template': template, 'mood': 'neutral'} for template in missing]}, indent=2))
            subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_npcs.py'),
                            '--merge', '--placements', str(manifest)], cwd=ROOT, check=True)
    catalog = build()
    destination = ROOT / 'runtime/assets/gcw/catalog.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, indent=2) + '\n')
    temporary.replace(destination)
    print(json.dumps({'rewards': len(catalog['rewards']), 'failures': catalog['failures']}))


if __name__ == '__main__':
    main()
