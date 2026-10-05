#!/usr/bin/env python3
"""Prepare original service anchors, credit chip and animated Core3 shuttle art.

The catalog describes source geometry, never live terminal/shuttle availability.
Native object IDs, travel prices, schedules and transactions remain Core3-owned.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from character_animations import decode_clip, load_lat, resolve
from prepare_characters import CharacterImporter
from prepare_inventory import InventoryImporter, canonical
from static_assets import StaticAssets
from swg_formats import cstring, parse_iff
from audit_trainers import export as export_trainers

ROOT = Path(__file__).resolve().parents[2]
WALLET = 'object/tangible/item/loot_credit_chip.iff'
SHUTTLES = ('object/mobile/player_transport.iff', 'object/creature/npc/theme_park/player_shuttle.iff')


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, separators=(',', ':')))
    tmp.replace(path)


def service_kind(template):
    name = Path(template).name.removeprefix('shared_')
    if template.startswith('object/tangible/terminal/'):
        if name == 'terminal_bank.iff': return 'bank'
        if name == 'terminal_bazaar.iff': return 'bazaar'
        if name == 'terminal_travel.iff': return 'travel'
        if name.startswith('terminal_mission'): return 'mission'
    if '/crafting/station/' in template: return 'crafting'
    return ''


def static_anchors(world_dir, provenance):
    raw = (world_dir / 'world.json').read_bytes()
    world = json.loads(raw)
    provenance[str((world_dir / 'world.json').resolve())] = hashlib.sha256(raw).hexdigest()
    anchors = {}
    for entry in world['chunks'].values():
        path = world_dir / entry['path']
        raw = path.read_bytes()
        for row in json.loads(raw)['instances']:
            kind = service_kind(row['source_template'])
            if not kind: continue
            # Component surfaces share one source object ID; never duplicate its UI.
            key = str(row['object_id'])
            if key in anchors: continue
            p = row['position']; origin = world['origin']
            anchors[key] = {'id': key, 'kind': kind, 'template': canonical(row['source_template'])[0],
                            'id_kind': 'snapshot_object' if int(key)>0 else 'client_layout_placement',
                            'position': [p[0] + origin[0], p[1] + origin[1], origin[2] - p[2]],
                            'godot_position': p, 'godot_quaternion': row['quaternion'],
                            'building_id': str(row.get('building_object_id', 0)),
                            'cell_index': int(row.get('cell_id', '0:0').split(':')[-1]),
                            'source_cell_id': str(row.get('source_cell_object_id', 0)),
                            'authority': 'source placement only; resolve live Core3 object before use'}
            provenance[str(path.resolve())] = hashlib.sha256(raw).hexdigest()
    return world['origin'], sorted(anchors.values(), key=lambda v: int(v['id']))


def travel_points(core3, provenance):
    path = core3 / 'MMOCoreORB/bin/scripts/managers/planet/planet_manager.lua'
    raw = path.read_bytes(); provenance[str(path.resolve())] = hashlib.sha256(raw).hexdigest()
    text = raw.decode().split('tatooine = {', 1)[1].split('planetTravelPoints = {', 1)[1].split('\n\t}', 1)[0]
    result = []
    for row in re.findall(r'\{([^{}]+)\}', text):
        values = dict(re.findall(r'(\w+)\s*=\s*("[^"]*"|[-\d.]+)', row))
        result.append({'name': values['name'].strip('"'), 'zone': 'tatooine',
                       'position': [float(values[k]) for k in ('x','z','y')],
                       'interplanetary': bool(int(values['interplanetaryTravelAllowed'])),
                       'incoming': bool(int(values['incomingTravelAllowed'])),
                       'landing_range': float(values['landingRange'])})
    return result


def export_shuttle(imp, static, template):
    shared = canonical(template)[1]
    props = imp.properties(shared)
    appearance = cstring(props['appearanceFilename'], 1)[0]
    cdf_path = cstring(props['clientDataFile'], 1)[0]
    model = imp.model(appearance)
    bones = model['bones']; names = {b['name']: i for i,b in enumerate(bones)}
    lat_data = parse_iff(imp.read(appearance)).first('LATX').data
    _, pos = cstring(lat_data, 2); lat, _ = cstring(lat_data, pos)
    ash, entries = load_lat(imp, lat)
    imp.read(ash)
    clips = {}
    for logical in ('loop_ground','loop_sky','land','take_off'):
        leaf = resolve(entries[logical], {})[0]
        clip = decode_clip(imp, leaf['source'], bones, names)
        clip.update(loop=logical.startswith('loop_'), logical=logical)
        clips[logical] = clip
    # Do not route through humanoid animation conversion: horizontal source root
    # travel belongs to the shuttle animation and must not be removed.
    model['animations'] = {}; model['animation_library'] = {}
    key = Path(template).stem
    model_path = 'models/' + key + '.json'; imp.write(model_path, model)
    attachments = []
    for hobj in parse_iff(imp.read(cdf_path)).walk('HOBJ'):
        source, pos = cstring(hobj.data); bone, _ = cstring(hobj.data, pos)
        if bone not in names: raise ValueError('Missing original attachment bone ' + bone)
        for piece in static.resolve(source):
            info = static.meshes[piece['mesh']]
            attachments.append({'template': source, 'bone': bone, 'model': info['path'],
                                'local_transform': [1,0,0,0,0,1,0,0,0,0,1,0],
                                'local_transform_layout': 'row_major_3x4',
                                'source_cdf': cdf_path, 'bounds_min': info['bounds_min'], 'bounds_max': info['bounds_max']})
    return {'template': template, 'shared_template': shared, 'appearance': appearance, 'body': model_path,
            'default_outfit': [], 'default_hair': '', 'hair': [], 'customizations': [],
            'source_cdf': cdf_path, 'source_lat': lat, 'attachments': attachments, 'clips': clips,
            'door_bone': 'hold_transport_door' if 'hold_transport_door' in names else '',
            'door_policy': 'Original animated door bone for transport; shuttleport boarding uses native ticket collector anchor',
            'pose_policy': 'Exact source root and hardpoint animation; source meters, no humanoid grounding offset'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/assets/active_tre')
    parser.add_argument('--world', type=Path, default=ROOT/'runtime/assets/tatooine_world')
    parser.add_argument('--core3', type=Path, default=ROOT/'vendor/Core3')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/services')
    parser.add_argument('--inventory', type=Path, default=ROOT/'runtime/assets/inventory')
    parser.add_argument('--ambient', type=Path, default=ROOT/'runtime/assets/ambient_npcs')
    args = parser.parse_args()
    provenance = {}; origin, anchors = static_anchors(args.world, provenance)
    points = travel_points(args.core3, provenance)
    imp = CharacterImporter(args.tre_dir, args.out)
    static = StaticAssets(args.tre_dir, args.out); static.t = imp.t; static.dependencies = imp.dependencies
    shuttles = {}; failures = []
    for template in SHUTTLES:
        try: shuttles[template] = export_shuttle(imp, static, template)
        except Exception as exc: failures.append({'template': template, 'phase': 'shuttle', 'error': repr(exc)})
    inventory = InventoryImporter(args.tre_dir, args.inventory)
    catalog_path = args.inventory/'catalog.json'
    catalog = json.loads(catalog_path.read_text()) if catalog_path.exists() else {'schema_version':1,'items':{},'aliases':{},'provenance':{}}
    for template in (WALLET, 'object/tangible/terminal/terminal_travel.iff', 'object/tangible/travel/ticket_collector/ticket_collector.iff'):
        item = inventory.convert(template)
        catalog['items'][template] = item; catalog['aliases'][item['shared_template']] = template
        if item['status'] != 'ready': failures.append({'template': template, 'phase':'inventory', 'error': item['failures']})
    catalog.setdefault('provenance',{}).setdefault('dependencies',{}).update(inventory.character.dependencies)
    catalog['service_wallet'] = {'template': WALLET, 'policy': 'Local wallet presentation only; no extra owned inventory item or client credit store'}
    catalog['failures'] = [{'template':t, **f} for t,item in catalog['items'].items() for f in item['failures']]
    catalog.setdefault('statistics',{}).update(items=len(catalog['items']), ready=sum(i['status']=='ready' for i in catalog['items'].values()),
        unsupported=sum(i['status']!='ready' for i in catalog['items'].values()), unique_models=len({i['model'] for i in catalog['items'].values() if i['status']=='ready'}),
        source_hashes=len(catalog['provenance']['dependencies']))
    write(catalog_path, catalog)
    result = {'schema_version':1, 'zone':'tatooine', 'origin':origin, 'static_terminals':anchors,
              'travel_points':points, 'races':shuttles, 'wallet_template':WALLET,
              'provenance':{'files_sha256':provenance, 'dependencies':imp.dependencies},
              'failures':failures + imp.failures + static.failures,
              'policy':'Geometry/placement reference only. Native Core3 IDs, discovery, credit balances, tickets and shuttle state are authoritative.'}
    write(args.out/'catalog.json', result)
    export_trainers(args.tre_dir, args.core3, args.ambient, args.out/'trainers.json')
    print(json.dumps({'static_terminals':len(anchors), 'travel_points':len(points), 'shuttles':len(shuttles), 'failures':result['failures']}, indent=2))
    if failures: raise SystemExit(1)

if __name__ == '__main__': main()
