#!/usr/bin/env python3
"""Prepare original PvE bounty appearance dependencies; never spawn native objects.

Target pools come from the pinned Core3 mission definitions. Models are merged
into the existing ambient/inventory catalogs; delivery particles use the same
bounded original-source renderer as combat effects. All derived media stays in
ignored runtime/assets. The catalog is coverage evidence, not mission authority.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/combat'))
from prepare_assets import Assets
from planet_config import PLANETS, path_for

ITEMS = ('object/tangible/mission/mission_bounty_droid_probot.iff',
         'object/tangible/mission/mission_bounty_droid_seeker.iff')
DELIVERY_EFFECT = 'clienteffect/probot_delivery.cef'
TERMINAL = 'object/tangible/terminal/terminal_mission_bounty.iff'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2)+'\n')
    temporary.replace(path)


def source_definitions(core3):
    """Read the bounded authored tables without executing Lua or adding targets."""
    scripts = core3/'MMOCoreORB/bin/scripts'
    manager = scripts/'managers/mission/mission_manager.lua'
    text = re.sub(r'--[^\n]*', '', manager.read_text())
    zone_table = re.search(r'\bbh_target_zones\s*=\s*\{([^}]*)\}', text)
    target_table = re.search(r'\bbh_targets_at_mission_level\s*=\s*\{(.*?)\n\}', text, re.S)
    if not zone_table or not target_table:
        raise ValueError('Original bounty target tables are missing')
    zones = re.findall(r'"([a-z0-9_]+)"', zone_table[1])
    if not zones or any(zone not in PLANETS for zone in zones):
        raise ValueError('Bounty target zones must use the ten original ground planets')
    levels = {level: re.findall(r'"(bh_[a-z0-9_]+)"', values)
              for level, values in re.findall(r'\b(level[123])\s*=\s*\{([^}]*)\}', target_table[1])}
    if set(levels) != {'level1', 'level2', 'level3'} or not all(levels.values()):
        raise ValueError('All three original PvE bounty levels are required')
    sources = [manager]
    mobiles = {}
    names = sorted({name for values in levels.values() for name in values})
    for name in names + ['informant_npc', 'probot', 'seeker']:
        path = scripts/'mobile'/('misc' if name in ('probot', 'seeker') else 'mission')/(name+'.lua')
        raw = re.sub(r'--[^\n]*', '', path.read_text())
        match = re.search(r'\btemplates\s*=\s*\{([^}]*)\}', raw)
        references = re.findall(r'"([^"\n]+)"', match[1]) if match else []
        templates = []
        groups = []
        for reference in references:
            if re.fullmatch(r'object/(?:mobile|creature)/[a-z0-9_/]+\.iff', reference):
                templates.append(reference)
            elif re.fullmatch(r'\s*[a-z0-9_]+\s*', reference):
                group = scripts/'mobile/dressgroup'/(reference.strip()+'.lua')
                templates += re.findall(r'"(object/(?:mobile|creature)/[a-z0-9_/]+\.iff)"', group.read_text())
                sources.append(group)
                groups.append({'source_reference': reference, 'source': str(group.relative_to(ROOT)),
                               'policy': 'Authored dressgroup appearance union only; native alias resolution remains server-owned.'})
            else:
                raise ValueError('Unsupported original mobile appearance reference: '+reference)
        if not templates:
            raise ValueError('Original mobile appearance pool is missing: '+str(path))
        sources.append(path)
        mobiles[name] = {'templates': sorted(set(templates)), 'source': str(path.relative_to(ROOT)),
                         'dressgroups': groups}
    return {'target_zones': zones, 'target_levels': levels, 'mobiles': mobiles}, sources


def npc_files_ready(directory, descriptor):
    if not descriptor.get('body'):
        return False
    paths = [descriptor['body']] + [part['model'] for part in descriptor.get('default_outfit', [])]
    paths += [part['model'] for part in descriptor.get('rigid_equipment', [])]
    return all((directory/path).is_file() for path in paths)


def npc_ready(directory, descriptor):
    return npc_files_ready(directory, descriptor) and descriptor.get('appearance_complete') is not False


def required_failures(failures, models, available_sources):
    """Only proven missing wardrobe art may remain an explicit partial model."""
    blocking = []
    for failure in failures:
        known_missing_wardrobe = (failure.get('phase') == 'npc'
            and models.get(failure.get('template'), {}).get('functional_ready', False)
            and bool(failure.get('errors'))
            and all(error.get('phase') == 'wearable' and error.get('resource')
                    and error['resource'] not in available_sources for error in failure['errors']))
        if not known_missing_wardrobe:
            blocking.append(failure)
    return blocking


def prepare_models(definitions, sources, tre, ambient, inventory, out):
    catalog_path = ambient/'catalog.json'
    catalog = json.loads(catalog_path.read_text()) if catalog_path.exists() else {'races': {}}
    templates = sorted({t for row in definitions['mobiles'].values() for t in row['templates']})
    missing = [t for t in templates if not npc_ready(ambient, catalog['races'].get(t, {}))]
    missing_poses = any(not catalog['races'].get(t, {}).get('incapacitated_pose', {}).get('ready') for t in templates)
    if missing:
        manifest = out/'appearance_requests.json'
        write(manifest, {'instances': [{'id': 'bounty_appearance_'+str(i), 'template': template,
                                       'mobile': 'bounty_dependency', 'mood': 'neutral'}
                                      for i, template in enumerate(missing)],
                         'source_policy': 'Original dynamic appearance dependencies only; no world placements.',
                         'provenance': {'files_sha256': {str(path.relative_to(ROOT)): digest(path) for path in sources}}})
        subprocess.run([sys.executable, str(ROOT/'tools/assets/prepare_npcs.py'), '--tre-dir', str(tre),
                        '--out', str(ambient), '--placements', str(manifest), '--merge'], cwd=ROOT, check=True)
    if missing or missing_poses:
        subprocess.run([sys.executable, str(ROOT/'tools/assets/refresh_npc_death_poses.py'), str(ambient)],
                       cwd=ROOT, check=True)
    item_catalog_path = inventory/'catalog.json'
    item_catalog = json.loads(item_catalog_path.read_text()) if item_catalog_path.exists() else {'items': {}}
    missing_items = [t for t in ITEMS if item_catalog['items'].get(t, {}).get('status') != 'ready'
                     or not (inventory/item_catalog['items'][t].get('model', '')).is_file()]
    if missing_items:
        command = [sys.executable, str(ROOT/'tools/assets/prepare_inventory.py'), '--tre-dir', str(tre), '--out', str(inventory)]
        for template in missing_items:
            command += ['--template', template]
        subprocess.run(command, cwd=ROOT, check=True)
    return templates, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core3', type=Path, default=ROOT/'vendor/Core3')
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/asset_sources/active_tre')
    parser.add_argument('--ambient', type=Path, default=ROOT/'runtime/assets/ambient_npcs')
    parser.add_argument('--inventory', type=Path, default=ROOT/'runtime/assets/inventory')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/bounty')
    args = parser.parse_args()
    definitions, sources = source_definitions(args.core3)
    templates, requested = prepare_models(definitions, sources, args.tre_dir, args.ambient, args.inventory, args.out)
    catalog = json.loads((args.ambient/'catalog.json').read_text())
    inventory = json.loads((args.inventory/'catalog.json').read_text())
    failures = []
    models = {}
    for template in templates:
        descriptor = catalog['races'].get(template, {})
        ready = npc_ready(args.ambient, descriptor)
        functional = npc_files_ready(args.ambient, descriptor)
        functional = functional and {'idle', 'walk'} <= set(descriptor.get('animation_states', []))
        functional = functional and descriptor.get('incapacitated_pose', {}).get('ready', False)
        models[template] = {'ready': ready, 'functional_ready': functional, 'body': descriptor.get('body', ''),
                            'appearance': descriptor.get('appearance', ''),
                            'animation_states': descriptor.get('animation_states', [])}
        if not ready or not functional:
            failures.append({'phase': 'npc', 'template': template,
                             'errors': descriptor.get('appearance_failures') or
                             [row for row in catalog.get('failures', []) if row.get('template') == template or
                              row.get('resource') == str(Path(template).with_name('shared_'+Path(template).name))]})
    items = {}
    for template in ITEMS:
        row = inventory['items'].get(template, {})
        ready = row.get('status') == 'ready' and (args.inventory/row.get('model', '')).is_file()
        items[template] = {'ready': ready, 'model': row.get('model', ''), 'appearance': row.get('appearance', ''),
                           'model_sha256': digest(args.inventory/row['model']) if ready else ''}
        if not ready:
            failures.append({'phase': 'inventory', 'template': template, 'errors': row.get('failures', [])})
    terminals = {}
    files = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    for planet in PLANETS:
        source = path_for(planet, 'services')/'catalog.json'
        if not source.exists():
            failures.append({'phase': 'terminal_catalog', 'planet': planet, 'error': 'Original services catalog missing'})
            continue
        value = json.loads(source.read_text())
        terminals[planet] = [row for row in value['static_terminals'] if row['template'] == TERMINAL]
        files[str(source.relative_to(ROOT))] = digest(source)
    args.out.mkdir(parents=True, exist_ok=True)
    importer = Assets(args.tre_dir, args.out, bounded_particle_graphs=True)
    effect_mapping = {}
    try:
        effect_mapping['probot_delivery'] = importer.effect(DELIVERY_EFFECT)
    except (KeyError, ValueError) as error:
        failures.append({'phase': 'delivery_effect', 'source': DELIVERY_EFFECT, 'error': str(error)})
    failures += importer.failures + importer.audio_importer.failures
    # Missing authored wardrobe pieces remain explicit partial appearances.
    # No other conversion error may become a successful setup run: bodies,
    # authored movement/death poses, droids, inventory and delivery FX are required.
    blocking = required_failures(failures, models, importer.t.entries)
    provenance = dict(importer.dependencies, **importer.audio_importer.dependencies)
    write(args.out/'assets.json', {'schema': 1, 'bounty_effects': effect_mapping, 'effects': importer.effects,
          'particles': importer.particles, 'sounds': importer.audio_importer.sounds, 'provenance': provenance,
          'failures': [row for row in failures if row.get('phase') not in ('npc', 'inventory', 'terminal_catalog')],
          'limitations': ['Original particle textures and curves use the shared bounded presentation.',
                         'No source camera shake or dynamic CEF lights are applied.',
                         'Native deployed droid actors use the existing original ambient NPC catalog.']})
    source_hashes = dict(catalog['provenance']['dependencies'], **inventory['provenance']['dependencies'], **provenance)
    required_sources = sorted({row.get('appearance', '') for row in models.values()} |
                              {row.get('appearance', '') for row in items.values()} |
                              {str(Path(t).with_name('shared_'+Path(t).name)) for t in templates + list(ITEMS)})
    report = {'schema_version': 1, 'passed': not failures, 'functional_ready': not blocking,
              'blocking_failures': blocking, **definitions, 'npc_templates': models,
              'inventory_items': items, 'terminals': terminals, 'requested_npc_conversions': requested,
              'files_sha256': files, 'source_hashes': {key: source_hashes[key] for key in required_sources if key in source_hashes},
              'failures': failures, 'policy': 'PvE original-source appearance coverage only. Native Core3 owns placements, target selection, droid charges, mission progression and rewards.'}
    write(args.out/'coverage.json', report)
    print(json.dumps({'passed': report['passed'], 'functional_ready': report['functional_ready'],
                      'target_mobiles': sum(map(len, definitions['target_levels'].values())),
                      'npc_templates': len(models), 'requested_npc_conversions': len(requested),
                      'original_terminal_placements': sum(map(len, terminals.values())), 'failures': failures}, indent=2))
    return 0 if report['functional_ready'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
