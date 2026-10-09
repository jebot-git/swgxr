#!/usr/bin/env python3
"""Audit bounty meshes/decorations and repair proven original CDF path defects."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from character_formats import datatable
from npc_reference_repairs import REPAIRS, TABLE, resolve_cdf_mesh
from prepare_characters import CharacterImporter
from swg_formats import parse_iff, cstring

ROOT = Path(__file__).resolve().parents[2]


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2)+'\n')


def repair_catalog(directory, importer):
    path = directory/'catalog.json'
    catalog = json.loads(path.read_text())
    selected = set()
    for descriptor in catalog.get('races', {}).values():
        for failure in descriptor.get('appearance_failures', []):
            source = failure.get('resource', '')
            if source not in REPAIRS:
                continue
            resolved, evidence = resolve_cdf_mesh(importer, source, descriptor['appearance'], descriptor['source_cdf'])
            if evidence and resolved != source:
                selected.add(descriptor['template'])
    medic = 'object/mobile/dressed_rebel_medic2_21b_01.iff'
    medic_shared = 'object/mobile/shared_dressed_rebel_medic2_21b_01.iff'
    # Older caches discarded a valid body when its optional CDF was absent.
    # The current importer retains that exact SAT body and reports the CDF gap.
    if medic not in catalog.get('races', {}) and any(row.get('phase') == 'npc' and row.get('resource') == medic_shared for row in catalog.get('failures', [])):
        appearance = importer.appearance(medic_shared)
        importer.read(appearance)
        selected.add(medic)
    if not selected:
        return []
    # Include cached outfit/weapon variants so their CDF prefixes are repaired
    # together with the base. These are appearance requests, never placements.
    instances = []
    for key, descriptor in catalog['races'].items():
        if descriptor['template'] not in selected:
            continue
        instances.append({'id': 'source_path_repair_'+str(len(instances)), 'mobile': '',
                          'template': descriptor['template'], 'appearance_id': key, 'mood': 'neutral',
                          'core3_outfit': descriptor.get('source_outfit'),
                          'source_primary_weapon': descriptor.get('source_primary_weapon')})
    for template in sorted(selected - {row['template'] for row in instances}):
        instances.append({'id': 'source_path_repair_'+str(len(instances)), 'mobile': '',
                          'template': template, 'appearance_id': template, 'mood': 'neutral'})
    manifest = directory/'source_path_repairs.json'
    write(manifest, {'instances': instances,
                     'source_policy': 'Repair existing original CDF references only; no world placement or new equipment.',
                     'provenance': {'files_sha256': catalog['provenance'].get('core3_outfit_files_sha256', {})}})
    subprocess.run([sys.executable, str(ROOT/'tools/assets/prepare_npcs.py'), '--out', str(directory),
                    '--placements', str(manifest), '--merge'], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT/'tools/assets/refresh_npc_death_poses.py'), str(directory)], cwd=ROOT, check=True)
    return sorted(selected)


def audit():
    ambient = ROOT/'runtime/assets/ambient_npcs'
    coverage = json.loads((ROOT/'runtime/assets/bounty/coverage.json').read_text())
    catalog = json.loads((ambient/'catalog.json').read_text())
    importer = CharacterImporter(ROOT/'runtime/asset_sources/active_tre', ROOT/'runtime/assets/bounty')
    model_cache = {}; failures = []; missing = []; records = {}
    def model(relative):
        if relative in model_cache:
            return model_cache[relative]
        path = ambient/relative
        if not path.is_file():
            failures.append({'phase': 'converted_model', 'path': str(path), 'error': 'Missing converted file'})
            return {}
        value = json.loads(path.read_text()); model_cache[relative] = value
        surfaces = value.get('surfaces', []) + [surface for part in value.get('parts', []) for surface in part['mesh']['surfaces']]
        if not surfaces or not all(surface.get('vertices') and surface.get('indices') for surface in surfaces):
            failures.append({'phase': 'converted_model', 'path': str(path), 'error': 'Empty geometry'})
        for surface in surfaces:
            if not surface.get('texture') or not (ambient/surface['texture']).is_file():
                failures.append({'phase': 'converted_texture', 'path': str(path), 'texture': surface.get('texture')})
        return value
    for template in coverage['npc_templates']:
        descriptor = catalog['races'][template]
        body = model(descriptor['body'])
        source_cdf = descriptor.get('source_cdf', '')
        cdf = parse_iff(importer.read(source_cdf)) if source_cdf else None
        source_wearables = [(index, cstring(mesh.data)[0]) for index, wear in enumerate(cdf.walk('WEAR'))
                            for mesh in wear.walk('MESH')] if cdf else []
        converted_rows = [row for row in descriptor['default_outfit'] if row.get('source_cdf') == source_cdf]
        converted = {(row['source_wear_index'], row['template']): row for row in converted_rows}
        omitted = []
        for index, source in source_wearables:
            entry = converted.get((index, source))
            if entry is not None:
                model(entry['model'])
            elif source not in importer.t.entries:
                row = {'template': template, 'source_cdf': source_cdf, 'source_wear_index': index, 'resource': source}
                omitted.append(row); missing.append(row)
            else:
                failures.append({'phase': 'cdf_wearable_omission', 'template': template, 'resource': source})
        actual_counts = Counter((row['source_wear_index'], row['template']) for row in converted_rows)
        actual_counts.update((row['source_wear_index'], row['resource']) for row in omitted)
        if actual_counts != Counter(source_wearables):
            failures.append({'phase': 'cdf_wearable_count', 'template': template})
        source_children = []
        for node in cdf.walk('HOBJ') if cdf else []:
            source, offset = cstring(node.data); bone, _ = cstring(node.data, offset)
            source_children.append((source, bone))
        actual_children = {(row['template'], row['bone']) for row in descriptor.get('rigid_equipment', []) if row.get('source_kind') == 'cdf_hobj'}
        if actual_children != set(source_children):
            failures.append({'phase': 'cdf_rigid_child_omission', 'template': template,
                             'source': source_children, 'converted': sorted(actual_children)})
        for entry in descriptor.get('rigid_equipment', []):
            model(entry['model'])
            if entry['bone'] not in {bone['name'] for bone in body.get('bones', [])}:
                failures.append({'phase': 'attachment_bone', 'template': template, 'bone': entry['bone']})
        records[template] = {'body_ready': bool(body.get('parts')), 'source_cdf': source_cdf,
                            'source_wearables': len(source_wearables), 'converted_wearables': len(converted_rows),
                            'repeated_authored_wearable_records': len(source_wearables)-len(set(source_wearables)),
                            'source_rigid_children': len(source_children), 'converted_rigid_children': len(actual_children),
                            'partial': bool(omitted)}
    repairs = []
    remaining = []
    for directory in (ambient, ROOT/'runtime/assets/combat_population/tatooine'):
        current = json.loads((directory/'catalog.json').read_text())
        for key, descriptor in current['races'].items():
            for outfit in descriptor.get('default_outfit', []):
                if outfit.get('source_reference_repair'):
                    repairs.append({'catalog': str(directory.relative_to(ROOT)), 'appearance_id': key,
                                    'model': outfit['model'], **outfit['source_reference_repair']})
            for failure in descriptor.get('appearance_failures', []):
                remaining.append({'catalog': str(directory.relative_to(ROOT)), 'appearance_id': key, **failure})
    glove = next(row for row in datatable(importer.read(TABLE)) if row['Object Template Name'] == 'shared_gloves_tusken_raider')
    report = {'schema_version': 1, 'conversion_audit_passed': not failures, 'full_bounty_fidelity': not failures and not missing,
              'bounty_templates': records, 'models_checked': len(model_cache), 'source_missing': missing,
              'conversion_failures': failures, 'repairs': repairs, 'remaining_audited_catalog_failures': remaining,
              'female_tusken_glove_evidence': {'table': TABLE, 'row': 'shared_gloves_tusken_raider',
                                              'Female Human': glove['Female Human'], 'Male Human': glove['Male Human'],
                                              'policy': 'The source marks female gloves unsupported (x); the male model is not substituted.'},
              'provenance': importer.dependencies,
              'policy': 'Source/CDF/model audit only; no rendered GPU or live headset validation.'}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repair', action='store_true', help='Rebuild proven CDF path defects, their cached variants and the discarded original 21B body')
    parser.add_argument('--output', type=Path, default=ROOT/'runtime/evidence/bounty-appearance-audit.json')
    args = parser.parse_args()
    if args.repair:
        importer = CharacterImporter(ROOT/'runtime/asset_sources/active_tre', ROOT/'runtime/assets/bounty')
        for directory in (ROOT/'runtime/assets/ambient_npcs', ROOT/'runtime/assets/combat_population/tatooine'):
            repair_catalog(directory, importer)
    report = audit(); write(args.output, report)
    print(json.dumps({'conversion_audit_passed': report['conversion_audit_passed'],
                      'bounty_templates': len(report['bounty_templates']), 'models_checked': report['models_checked'],
                      'repairs': len(report['repairs']), 'source_missing': report['source_missing'],
                      'conversion_failures': report['conversion_failures']}, indent=2))
    return 0 if report['conversion_audit_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
