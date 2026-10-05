#!/usr/bin/env python3
"""Validate NPC Core3 outfit identity, source customization and skinned data."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from swg_formats import TreSet, parse_iff, cstring

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'runtime/assets/ambient_npcs')
    parser.add_argument('--output', type=Path, default=ROOT / 'runtime/evidence/npc-outfit-validation.json')
    args = parser.parse_args(); directory = args.directory
    placements_bytes = (directory / 'placements.json').read_bytes(); placements = json.loads(placements_bytes)
    catalog = json.loads((directory / 'catalog.json').read_text()); report = catalog['outfit_report']
    assert hashlib.sha256(placements_bytes).hexdigest() == catalog['provenance']['placement_sha256']
    assert not report['conversion_failures'], report['conversion_failures']
    variants = {}; models = {}; rigid_models = {}; verified_sources = 0; vertices = 0
    tre = TreSet(Path(catalog['provenance']['tre_directory']))
    for item in placements['instances']:
        outfit = item.get('core3_outfit')
        primary = item.get('source_primary_weapon')
        primary = primary if primary and primary.get('status') == 'selected' else None
        if not outfit and not primary:
            assert item['appearance_id'] == item['template']
            continue
        key = item['appearance_id']; descriptor = catalog['races'][key]; base = catalog['races'][item['template']]
        assert ('#outfit=' in key or '#weapon=' in key) and descriptor['source_outfit'] == outfit
        assert descriptor.get('source_primary_weapon') == primary
        assert descriptor['template'] == item['template'] and descriptor['body'] == base['body']
        assert descriptor['default_appearance'] == base['default_appearance']
        assert descriptor['default_outfit'][:len(base['default_outfit'])] == base['default_outfit']
        actual = {part['source_outfit_index']: part for part in descriptor['default_outfit'] if 'source_outfit_index' in part}
        rigid_all = descriptor.get('rigid_equipment', [])
        rigid = {part['source_outfit_index']: part for part in rigid_all if 'source_outfit_index' in part}
        omitted = {part['source_outfit_index']: part for part in descriptor['unsupported_equipment'] if 'source_outfit_index' in part}
        assert not actual.keys() & omitted.keys() and not actual.keys() & rigid.keys() and not rigid.keys() & omitted.keys()
        assert actual.keys() | rigid.keys() | omitted.keys() == set(range(len(outfit['items']) if outfit else 0))
        for index, source in enumerate(outfit['items'] if outfit else []):
            exported = actual.get(index, rigid.get(index, omitted.get(index)))
            assert exported['template'] == source['template']
            assert exported['customization'] == source['customization']
            assert exported['source_file'] == source['source_file'] and exported['source_line'] == source['source_line']
            assert exported['appearance'] in catalog['provenance']['dependencies']
        if primary:
            records = [part for part in rigid_all + descriptor['unsupported_equipment'] if part.get('source_kind') == 'primary_weapon']
            assert len(records) == 1 and records[0]['template'] == primary['template']
            assert records[0]['source_weapon_group'] == primary['group'] and '#weapon='+primary['template'] in key
        for part in actual.values():
            path = part['model']
            if path in models:
                continue
            model = json.loads((directory / path).read_text()); models[path] = model
            assert model['bones'], path
            for section in model['parts']:
                mesh = section['mesh']; bone_count = mesh['bone_count']
                for surface in mesh['surfaces']:
                    count = len(surface['vertices']) // 3; vertices += count
                    assert count > 0 and len(surface['weights']) == count * 8 and len(surface['bones']) == count * 8
                    assert all(math.isfinite(w) and w >= 0 for w in surface['weights'])
                    for offset in range(0, count * 8, 8):
                        assert abs(sum(surface['weights'][offset:offset + 8]) - 1) < 0.002
                        for bone, weight in zip(surface['bones'][offset:offset + 8], surface['weights'][offset:offset + 8]):
                            assert weight == 0 or 0 <= bone < bone_count, (path, bone, bone_count)
                    assert (directory / surface['texture']).is_file()
        body = json.loads((directory / descriptor['body']).read_text())
        bone_names = {bone['name'] for bone in body['bones']}
        for attachment in rigid_all:
            assert attachment['bone'] in bone_names
            assert attachment['local_transform_layout'] == 'row_major_3x4'
            assert len(attachment['local_transform']) == 12 and all(math.isfinite(v) for v in attachment['local_transform'])
            root = parse_iff(tre.read(attachment['source_arrangement']))
            source_slots = []; chunk = list(root.walk('ARG '))[attachment['source_arrangement_index']]; offset = 0
            while offset < len(chunk.data):
                slot, offset = cstring(chunk.data, offset); source_slots.append(slot)
            assert source_slots == attachment['source_slots'] and attachment['bone'] in source_slots
            path = attachment['model']; model = json.loads((directory / path).read_text()); rigid_models[path] = model
            assert model['source_appearance'] == attachment['appearance'] and model['surfaces']
            for surface in model['surfaces']:
                count = len(surface['vertices']) // 3
                assert count and len(surface['indices']) % 3 == 0 and all(0 <= index < count for index in surface['indices'])
                assert all(math.isfinite(v) for v in surface['vertices'])
                assert (directory / surface['texture']).is_file()
            if attachment['template'].startswith('object/tangible/instrument/'):
                assert not attachment['source_hardpoints'] # Current four authored instruments have empty HPTS.
            assert attachment['local_transform'] == [1,0,0,0,0,1,0,0,0,0,1,0]
        variants[key] = {'mobile': item['mobile'], 'converted_items': len(actual), 'preserved_cdf_items': len(base['default_outfit']), 'rigid_items':len(rigid_all), 'unsupported_attachments': len(omitted)}
    for path, digest in placements['provenance']['files_sha256'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
        verified_sources += 1
    for path, dependency in catalog['provenance']['dependencies'].items():
        assert hashlib.sha256(tre.read(path)).hexdigest() == dependency['sha256'], path
    for path, digest in catalog['provenance']['core3_outfit_files_sha256'].items():
        assert placements['provenance']['files_sha256'][path] == digest
    assert len(variants) == len(report['variants'])
    result = {'passed': True, 'placement_count': len(placements['instances']), 'outfit_variants':sum(bool(value['outfit']) for value in report['variants'].values()),'equipment_variants':len(variants), 'converted_items': report['converted_items'], 'unique_rigid_models':len(rigid_models),'converted_rigid_items':report['converted_rigid_items'],'verified_asset_dependencies':len(catalog['provenance']['dependencies']),'unique_skinned_models': len(models), 'validated_skinned_vertices': vertices, 'verified_core3_source_files': verified_sources, 'variants': variants, 'unsupported_attachments': report['unsupported_attachments'], 'scope': 'Source identity/customization, preserved CDF appearance, model weights and texture files; no headset or visual validation.'}
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps({key: value for key, value in result.items() if key not in ('variants','unsupported_attachments')}, indent=2))


if __name__ == '__main__':
    main()
