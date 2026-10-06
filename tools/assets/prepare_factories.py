#!/usr/bin/env python3
"""Prepare factory deed/crate previews and audit original factory/blueprint assets.

Reference assets grant no deeds or schematics. Generated assets and evidence stay
under ignored runtime/assets; native Core3 supplies ownership and factory state.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

from interior_layout import template_properties
from prepare_inventory import InventoryImporter, canonical

ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT = 'object/manufacture_schematic/generic_schematic.iff'


def prepare(args):
    sources = args.core3_root / 'MMOCoreORB/bin/scripts/object/tangible/deed/factory_deed'
    factories = {}
    source_hashes = {}
    for path in sorted(sources.glob('factory_*_deed.lua')):
        raw = path.read_bytes()
        target = re.search(r'generatedObjectTemplate\s*=\s*"([^"]+)"', raw.decode())
        if not target:
            raise ValueError('Factory deed lacks generatedObjectTemplate: ' + str(path))
        template = 'object/tangible/deed/factory_deed/' + path.stem + '.iff'
        factories[template] = {'structure_template': target.group(1)}
        source_hashes[str(path.relative_to(args.core3_root))] = hashlib.sha256(raw).hexdigest()
    if not factories:
        raise ValueError('No native Core3 factory deed definitions: ' + str(sources))

    crates = []
    for path in sorted((args.core3_root / 'MMOCoreORB/bin/scripts/object/factory').glob('factory_crate_*.lua')):
        crates.append('object/factory/' + path.stem + '.iff')
        source_hashes[str(path.relative_to(args.core3_root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not crates:
        raise ValueError('No native Core3 factory crate definitions')

    command = [sys.executable, str(ROOT / 'tools/assets/prepare_inventory.py'),
               '--tre-dir', str(args.tre_dir), '--out', str(args.inventory)]
    for template in list(factories) + crates:
        command += ['--template', template]
    subprocess.run(command, check=True)
    inventory = json.loads((args.inventory / 'catalog.json').read_text())
    housing = json.loads((args.housing / 'catalog.json').read_text())
    failures = []
    for template in crates:
        if inventory['items'][template]['status'] != 'ready':
            failures.append({'template': template, 'error': inventory['items'][template]['failures']})
    for deed, record in factories.items():
        preview = inventory['items'][deed]
        record['deed_preview'] = preview
        structure = housing['structures'].get(record['structure_template'], {})
        record['structure'] = structure
        if preview['status'] != 'ready':
            failures.append({'template': deed, 'error': preview['failures']})
        if not structure:
            failures.append({'template': record['structure_template'],
                             'error': 'Missing original housing geometry; run tools/assets/prepare_housing.py'})
        elif hashlib.sha256((args.housing / structure['path']).read_bytes()).hexdigest() != structure['sha256']:
            failures.append({'template': record['structure_template'], 'error': 'Housing geometry hash mismatch'})

    importer = InventoryImporter(args.tre_dir, args.inventory)
    shared = canonical(BLUEPRINT)[1]
    properties = template_properties(importer.read, shared)
    appearance = properties.get('inventoryAppearanceFilename') or properties.get('appearanceFilename') or ''
    blueprint = {'template': BLUEPRINT, 'shared_template': shared,
                 'original_appearance': appearance,
                 'presentation_policy': 'Client holographic UI card labeled as a blueprint; not an original item mesh',
                 'provenance': importer.character.dependencies}
    if appearance:
        blueprint['presentation_policy'] = 'Original appearance present; prepare inventory preview from this exact template'
        failures.append({'template': BLUEPRINT, 'error': 'Source blueprint now has an appearance; review holographic UI policy'})
    else:
        blueprint['source_limitation'] = 'Original shared template inheritance provides no inventory or world appearance'
    catalog = {'schema_version': 1, 'factories': factories, 'blueprint': blueprint,
               'output_crates': {template: inventory['items'][template] for template in crates},
               'provenance': {'core3_files_sha256': source_hashes,
                              'inventory_catalog': str((args.inventory / 'catalog.json').resolve()),
                              'housing_catalog': str((args.housing / 'catalog.json').resolve())},
               'failures': failures,
               'policy': 'Local original asset references only; Core3 owns deeds, manufacturing schematics, hoppers and production'}
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    print(json.dumps({'factories': len(factories), 'output_crates': len(crates), 'blueprint_has_original_mesh': bool(appearance), 'failures': failures}))
    return not failures


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT / 'runtime/assets/active_tre')
    parser.add_argument('--inventory', type=Path, default=ROOT / 'runtime/assets/inventory')
    parser.add_argument('--housing', type=Path, default=ROOT / 'runtime/assets/housing')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/assets/factories')
    parser.add_argument('--core3-root', type=Path, default=ROOT / 'vendor/Core3')
    sys.exit(0 if prepare(parser.parse_args()) else 1)
