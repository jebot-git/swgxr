#!/usr/bin/env python3
"""Check inventory provenance, preview geometry, material files and NPC bag evidence."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image
from character_formats import strings
from interior_layout import template_properties
from prepare_inventory import snapshot_template_pairs
from swg_formats import TreSet, cstring, parse_iff

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=ROOT / 'runtime/assets/inventory/catalog.json')
    parser.add_argument('--tre-dir', type=Path, default=ROOT / 'runtime/assets/active_tre')
    parser.add_argument('--snapshot', type=Path, action='append', default=[])
    parser.add_argument('--report', type=Path, default=ROOT / 'runtime/evidence/inventory-assets-validation.json')
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text()); directory = args.catalog.parent
    tre = TreSet(args.tre_dir); errors = []; models = {}; textures = set(); input_hashes = 0
    for source, record in catalog['provenance']['dependencies'].items():
        try:
            if hashlib.sha256(tre.read(source)).hexdigest() != record['sha256']:
                errors.append('Source hash mismatch: ' + source)
        except Exception as error:
            errors.append('Source unavailable: ' + source + ': ' + str(error))
    for source, record in catalog['provenance']['inputs'].items():
        if Path(source).exists():
            input_hashes += 1
            if hashlib.sha256(Path(source).read_bytes()).hexdigest() != record['sha256']:
                errors.append('Selection input hash mismatch: ' + source)
    for template, item in catalog['items'].items():
        alias = catalog['items'].get(catalog['aliases'].get(item['shared_template']), {})
        if item['template'] != template or alias.get('shared_template') != item['shared_template']:
            errors.append('Template alias mismatch: ' + template)
        if item['status'] != 'ready':
            if not item.get('failures'):
                errors.append('Unsupported item lacks explanation: ' + template)
            if item.get('model'):
                errors.append('Unsupported item exposes substitute model: ' + template)
            continue
        try:
            path = directory / item['model']; raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != item['model_sha256']:
                raise ValueError('Model hash mismatch')
            model = json.loads(raw)
            models[item['model']] = model
            if model['source_appearance'] != item['appearance'] or model['source_meshes'] != item['source_meshes']:
                raise ValueError('Original appearance lineage differs')
            points = []
            for surface in model['surfaces']:
                vertices = surface['vertices']; count = len(vertices) // 3
                if len(vertices) % 3 or not count or not all(math.isfinite(v) for v in vertices):
                    raise ValueError('Invalid vertex data')
                if len(surface['indices']) % 3 or not surface['indices'] or min(surface['indices']) < 0 or max(surface['indices']) >= count:
                    raise ValueError('Invalid source triangle indices')
                if any(key in surface for key in ('bones', 'weights', 'blend_shapes')):
                    raise ValueError('Frozen preview unexpectedly requires a skeleton')
                if surface.get('normals') and len(surface['normals']) != len(vertices):
                    raise ValueError('Normal count differs')
                if surface.get('uv') and len(surface['uv']) != count * 2:
                    raise ValueError('UV count differs')
                points.extend(vertices[i:i + 3] for i in range(0, len(vertices), 3))
                maps = [surface['texture']] + list(surface.get('texture_bindings', {}).values())
                for selector in surface.get('texture_selectors', []):
                    maps.extend(selector['textures'])
                for texture in maps:
                    if texture not in textures:
                        with Image.open(directory / texture) as image:
                            image.verify()
                        textures.add(texture)
            minimum = [min(p[i] for p in points) for i in range(3)]
            maximum = [max(p[i] for p in points) for i in range(3)]
            if minimum != item['bounds_min'] or maximum != item['bounds_max'] or minimum != model['bounds_min'] or maximum != model['bounds_max']:
                raise ValueError('Preview bounds do not exactly enclose original converted vertices')
            if not any(maximum[i] > minimum[i] for i in range(3)):
                raise ValueError('Empty appearance bounds')
            if item['appearance'] not in catalog['provenance']['dependencies']:
                raise ValueError('Appearance hash missing')
        except Exception as error:
            errors.append(template + ': ' + str(error))
    try:
        bag = catalog['generic_backpack']; proof = bag['provenance']
        npc = template_properties(tre.read, proof['npc_shared_template'])
        if npc['clientDataFile'] != proof['source_cdf']:
            raise ValueError('NPC client-data reference differs')
        wear = list(parse_iff(tre.read(proof['source_cdf'])).walk('WEAR'))[proof['source_wear_index']]
        npc_meshes = [cstring(node.data)[0] for node in wear.walk('MESH')]
        backpack = template_properties(tre.read, proof['backpack_shared_template'])
        bag_meshes = strings(parse_iff(tre.read(backpack['appearanceFilename'])).first('MSGN').data)
        if proof['shared_mesh'] not in npc_meshes or proof['shared_mesh'] not in bag_meshes:
            raise ValueError('Bag is not the original NPC wearable mesh')
        if catalog['items'][bag['template']]['status'] != 'ready':
            raise ValueError('Generic source backpack unavailable')
    except Exception as error:
        errors.append('Generic backpack proof: ' + str(error))
    requested = set()
    equipment_models = 0
    for race_id, entries in catalog.get('equipment', {}).items():
        for template, item in entries.items():
            if item.get('status') != 'ready':
                if not item.get('failures'): errors.append('Equipment failure lacks explanation: ' + race_id + '/' + template)
                continue
            try:
                raw = (directory / item['model']).read_bytes()
                if hashlib.sha256(raw).hexdigest() != item['model_sha256']: raise ValueError('Equipment model hash mismatch')
                model = json.loads(raw); equipment_models += 1
                if item['kind'] != 'skinned': continue
                body_raw = Path(item['source_owner_model']).read_bytes()
                if hashlib.sha256(body_raw).hexdigest() != item['source_owner_model_sha256']: raise ValueError('Owner body provenance differs')
                body = json.loads(body_raw)
                if model['bones'] != body['bones']: raise ValueError('Wearable altered the source tracked skeleton')
                for part in model['parts']:
                    for surface in part['mesh']['surfaces']:
                        count = len(surface['vertices']) // 3
                        if len(surface['bones']) != count * 8 or len(surface['weights']) != count * 8:
                            raise ValueError('Invalid native skin influence count')
                        if any(index < 0 or index >= len(body['bones']) for index in surface['bones']):
                            raise ValueError('Skin influence outside original skeleton')
                        for offset in range(0, len(surface['weights']), 8):
                            weights = surface['weights'][offset:offset + 8]
                            if any(not math.isfinite(w) or w < 0 for w in weights) or abs(sum(weights) - 1) > 1e-5:
                                raise ValueError('Invalid original skin weights')
                        if not (directory / surface['texture']).is_file(): raise ValueError('Wearable material missing')
                if item['source_owner_shader'] not in catalog['provenance']['dependencies']:
                    raise ValueError('Owner shader has no original source hash')
            except Exception as error:
                errors.append('Equipment ' + race_id + '/' + template + ': ' + str(error))
    for path in args.snapshot:
        snapshot = json.loads(path.read_text())
        pairs = snapshot_template_pairs(snapshot)
        requested.update(pairs)
        if snapshot.get('race'):
            for template in pairs:
                if template.startswith(('object/tangible/wearables/', 'object/weapon/')) and catalog.get('equipment', {}).get(snapshot['race'], {}).get(template, {}).get('status') != 'ready':
                    errors.append('Snapshot equipped appearance unavailable: ' + snapshot['race'] + '/' + template)
    for template in sorted(requested):
        if catalog['items'].get(template, {}).get('status') != 'ready':
            errors.append('Snapshot item preview unavailable: ' + template)
    report = {'ok': not errors, 'items': len(catalog['items']), 'ready': sum(i['status'] == 'ready' for i in catalog['items'].values()),
              'unsupported': [t for t, i in catalog['items'].items() if i['status'] != 'ready'], 'unique_models': len(models),
              'texture_files': len(textures), 'source_hashes': len(catalog['provenance']['dependencies']), 'selection_input_hashes': input_hashes,
              'snapshot_templates': len(requested), 'generic_backpack_source_verified': not any(e.startswith('Generic backpack') for e in errors),
              'equipment_models': equipment_models,
              'gpu_validated': False, 'errors': errors}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
