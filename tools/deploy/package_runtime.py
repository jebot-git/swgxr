#!/usr/bin/env python3
"""Stage runtime files only; never copy local databases, accounts or session logs.

Run after the native build/tests finish. TRE media and private TLS files are
transferred separately. Destination must be a new ignored staging directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
try:
    from .runtime import vehicle_catalog_status
except ImportError:
    from runtime import vehicle_catalog_status

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_ASSET_CATALOGS = (
    'runtime/assets/chatter/catalog.json',
    'runtime/assets/gcw/catalog.json',
    'runtime/assets/characters/catalog.json',
    'runtime/assets/image_design/policy.json',
    'runtime/assets/services/bazaar_categories.json',
    'runtime/assets/vehicles/catalog.json',
    'runtime/assets/pets/body_bounds.json',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    target = args.destination.resolve()
    if not target.is_relative_to(ROOT / 'runtime/deploy') or target.exists():
        raise SystemExit('Use a new directory under runtime/deploy.')
    catalogs = vehicle_catalog_status(ROOT)
    if not catalogs['passed']: raise SystemExit('; '.join(catalogs['errors']))
    native = 'vendor/Core3/MMOCoreORB/bin/'
    paths = ['server', 'tools/deploy', 'client/combat/balance.json',
             *REQUIRED_ASSET_CATALOGS,
             'runtime/assets/mos_eisley/scene.json',
             'tools/combat/export_catalog.py']
    paths += ['tools/assets/' + p + '.py' for p in
              ('swg_formats', 'archive_policy', 'character_formats', 'stf')]
    paths += [native + p for p in ('core3', 'core3client', 'conf', 'scripts', 'terrain', 'custom_scripts')]
    for relative in paths:
        source, destination = ROOT / relative, target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        else:
            shutil.copy2(source, destination)
    # Console fixture hooks/admin users belong exclusively to local tests.
    for relative in ('conf/adminusers.lst', 'conf/webusers.lst',
                     'scripts/screenplays/tests/tests.lua',
                     'scripts/managers/resource_manager_spawns.lua'):
        original = subprocess.check_output(['git', '-C', str(ROOT/'vendor/Core3'),
                                            'show', 'HEAD:MMOCoreORB/bin/' + relative])
        (target/native/relative).write_bytes(original)
    manifest = {}
    for path in sorted(target.rglob('*')):
        if path.is_file():
            with path.open('rb') as stream:
                manifest[str(path.relative_to(target))] = hashlib.file_digest(stream, 'sha256').hexdigest()
    output = target/'runtime/remote/runtime-sha256.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Staged {len(manifest)} files; no SQL/BerkeleyDB state or credentials copied.')


if __name__ == '__main__':
    main()
