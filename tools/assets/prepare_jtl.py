#!/usr/bin/env python3
"""Convert the supplied original Luxury Yacht POB into a bounded tester stage."""
import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path
from static_assets import StaticAssets
from swg_formats import parse_iff, cstring
from prepare_stage import mirror

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from server.jtl_catalog import SMALL_SHIPS
TEMPLATE = 'object/ship/player/player_sorosuub_space_yacht.iff'
SHARED = 'object/ship/player/shared_player_sorosuub_space_yacht.iff'


def small_ships(assets, out):
    """Keep source cockpit frames separate from exteriors seen by other ships."""
    templates = {}
    def appearance_stage(path, target, spawn):
        parts = assets.resolve(path)
        if not parts:
            raise ValueError('Original ship appearance has no triangles: '+path)
        instances = [dict(mesh=p['mesh'], position=[0,0,0], quaternion=[0,0,0,1],
                          source_template=path, object_id=1) for p in parts]
        stage = dict(schema_version=1, origin=[0,0,0], spawn=spawn, instances=instances,
                     cells={}, collisions={},
                     meshes={p['mesh']:json.loads((out/assets.meshes[p['mesh']]['path']).read_text()) for p in parts},
                     provenance=assets.dependencies.copy(), conversion_failures=[])
        destination=out/target
        destination.write_text(json.dumps(stage,separators=(',',':')))
        return hashlib.sha256(destination.read_bytes()).hexdigest()
    for name in SMALL_SHIPS:
        shared='object/ship/player/shared_player_'+name+'.iff'
        source='object/ship/player/player_'+name+'.iff'
        root=parse_iff(assets.read(shared))
        cockpit=None
        for node in root.walk('XXXX'):
            if node.data.startswith(b'cockpitFilename\0\1'):
                cockpit=cstring(node.data,len(b'cockpitFilename\0\1'))[0]
        if not cockpit:
            raise ValueError('Missing authored cockpit: '+shared)
        cpit=parse_iff(assets.read(cockpit))
        if cpit.tag!='CPIT' or cpit.children[0].tag!='0000':
            raise ValueError('Unsupported cockpit source: '+cockpit)
        frame=cstring(cpit.first('FRAM').data)[0]
        eye=mirror(struct.unpack('<3f',cpit.first('1OFF').data))
        descriptor='fighter_'+name+'_cockpit.json'
        before=len(assets.failures)
        digest=appearance_stage(frame,descriptor,eye)
        exterior='fighter_'+name+'_exterior.json'
        exterior_digest=appearance_stage(assets.properties(shared)['appearanceFilename'],exterior,[0,0,0])
        if len(assets.failures)!=before:
            raise ValueError('Incomplete original fighter assets: '+name+' '+repr(assets.failures[before:]))
        templates[source]=dict(kind='fighter',descriptor=descriptor,sha256=digest,
            exterior_descriptor=exterior,exterior_sha256=exterior_digest,shared_template=shared,
            cockpit_position=eye,cockpit_source=cockpit,frame_source=frame,
            stations=[dict(id='pilot',cell_index=0,position=eye)],
            station_policy='Native ship slots determine seated passengers; frame is original CPIT first-person view')
    return templates


def prepare(tre, out):
    out = Path(out)
    assets = StaticAssets(tre, out)
    instances, cells, _ = assets.place(
        {'id': 1, 'parent': 0, 'template': SHARED, 'p': [0, 0, 0], 'q': [1, 0, 0, 0]}, [0, 0, 0])
    if not instances or not cells:
        raise ValueError('Original yacht POB geometry and cells are required')
    source = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/object/ship/player/player_sorosuub_space_yacht.lua'
    children = []
    block = source.read_text().split('childObjects = {', 1)[1].split('launchPoints =', 1)[0]
    for index, row in enumerate(re.findall(r'\{\s*templateFile\s*=\s*"([^"]+)"([^}]+)\}', block), 2):
        template, fields = row
        values = {key: float(value) for key, value in re.findall(r'(\w+)\s*=\s*(-?[0-9.]+)', fields)}
        original = Path(template)
        shared = str(original.parent / ('shared_' + original.name))
        cell = int(values['cellid'])
        node = dict(id=index, parent=1, template=shared, cell_id=f'1:{cell}',
                    building_object_id=1, source_cell_object_id=cell,
                    p=[values['x'], values['z'], values['y']],
                    q=[values['ow'], values['ox'], values['oy'], values['oz']])
        placed, _, _ = assets.place(node, [0, 0, 0])
        instances.extend(placed)
        children.append(dict(template=template, cell_index=cell, source_position=node['p']))
    meshes = {key: json.loads((out / assets.meshes[key]['path']).read_text())
              for key in {instance['mesh'] for instance in instances}}
    collision_ids = {i['collision_id'] for i in instances if 'collision_id' in i}
    stage = dict(schema_version=1, origin=[0, 0, 0], spawn=[0, .4, -20], instances=instances,
                 cells=cells, meshes=meshes,
                 collisions={key: assets.collisions[key] for key in collision_ids},
                 provenance=assets.dependencies, conversion_failures=assets.failures)
    path = out / 'yacht.json'
    path.write_text(json.dumps(stage, separators=(',', ':')))
    space_source = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/managers/space/space_manager.lua'
    block = space_source.read_text().split('space_tatooine = {', 1)[1].split('space_yavin4 =', 1)[0]
    fields = re.search(r'\{templateFile = "spacestation_tatooine"([^}]+)\}', block)[1]
    values = {key: float(value) for key, value in re.findall(r'(\w+)\s*=\s*(-?[0-9.]+)', fields)}
    node = dict(id=100, parent=0, template='object/ship/shared_spacestation_neutral.iff',
                p=[values['x'], values['z'], values['y']],
                q=[values['ow'], values['ox'], values['oy'], values['oz']])
    space_instances, _, _ = assets.place(node, [0, 0, 0])
    space = dict(origin=[0, 0, 0], spawn=[0, 0, 0], instances=space_instances, cells={}, collisions={},
                 meshes={key: json.loads((out / assets.meshes[key]['path']).read_text())
                         for key in {i['mesh'] for i in space_instances}},
                 provenance=assets.dependencies.copy(), source_zone='space_tatooine',
                 source_config=dict(path=str(space_source.relative_to(ROOT)),
                                    sha256=hashlib.sha256(space_source.read_bytes()).hexdigest()))
    # Navigation landmark only. Ship collision/docking is outside this first flight prototype.
    for instance in space['instances']:
        instance.pop('collision_id', None)
        instance.pop('collision_owner', None)
    (out / 'space_tatooine.json').write_text(json.dumps(space, separators=(',', ':')))
    descriptor = dict(descriptor=path.name, shared_template=SHARED, kind='pob',
                      sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    catalog = dict(schema_version=1, source_kind='original_swg_pob', stage=path.name,
                   space_stage='space_tatooine.json',
                   templates={TEMPLATE: descriptor},
                   original_fixtures=children,
                   coordinate_system='Godot local; source SWG Z mirrored',
                   stations=[dict(id='pilot', cell_index=1, position=[-.76, .43, -21.14]),
                             dict(id='passenger', cell_index=1, position=[.75, .43, -21.15])],
                   leave_position=[0, .4, -20], leave_cell_index=1,
                   station_source=dict(path=str(source.relative_to(ROOT)),
                                       sha256=hashlib.sha256(source.read_bytes()).hexdigest()),
                   provenance=assets.dependencies, conversion_failures=assets.failures)
    catalog['templates'].update(small_ships(assets,out))
    (out / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    result = dict(stage=str(path), meshes=len(meshes), instances=len(instances), cells=len(cells),
                  interior_cells=len([c for c in cells.values() if not c['is_exterior']]),
                  failures=assets.failures)
    print(json.dumps(result), flush=True)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT / 'runtime/asset_sources/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/assets/jtl')
    args = parser.parse_args()
    prepare(args.tre_dir, args.out)
