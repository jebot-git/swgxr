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
import sys
try:
    from .runtime import vehicle_catalog_status
except ImportError:
    from runtime import vehicle_catalog_status

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.server.native_build_receipt import verify as verify_native_build
from tools.server.native_build_receipt import inputs as native_inputs
from tools.deploy.capacity import PROFILES
from tools.deploy.prepare_capacity_profile import prepare as prepare_capacity
REQUIRED_ASSET_CATALOGS = (
    'runtime/assets/chatter/catalog.json',
    'runtime/assets/gcw/catalog.json',
    'runtime/assets/characters/catalog.json',
    'runtime/assets/image_design/policy.json',
    'runtime/assets/services/bazaar_categories.json',
    'runtime/assets/vehicles/catalog.json',
    'runtime/assets/pets/body_bounds.json',
    'runtime/assets/jtl/catalog.json',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--profile',choices=PROFILES,help='Include reviewed public capacity settings; never copy private realm configuration')
    parser.add_argument('--prepare-only',action='store_true',help='Source/build handoff without binaries; explicitly NOT deployable')
    args = parser.parse_args()
    target = args.destination.resolve()
    if not target.is_relative_to(ROOT / 'runtime/deploy') or target.exists():
        raise SystemExit('Use a new directory under runtime/deploy.')
    if not args.prepare_only:
        try: verify_native_build(ROOT)
        except ValueError as exc: raise SystemExit(str(exc)) from exc
    if not args.prepare_only:
        collision=ROOT/'vendor/Core3/MMOCoreORB/bin/conf/swgxr-space-collision.json'
        if not collision.is_file():raise SystemExit('Prepare native space collision data with tools/space/prepare_collision.py first.')
        geometry=json.loads(collision.read_text());catalog=json.loads((ROOT/'runtime/assets/jtl/catalog.json').read_text())
        if set(geometry.get('sectors',{}))!=set(catalog['sectors']) or any(geometry.get('source_sha256',{}).get(zone)!=row['sha256'] for zone,row in catalog['sectors'].items()):
            raise SystemExit('Native asteroid collision data differs from the client sector catalog; regenerate it before packaging.')
    catalogs = vehicle_catalog_status(ROOT)
    if not catalogs['passed']: raise SystemExit('; '.join(catalogs['errors']))
    native = 'vendor/Core3/MMOCoreORB/bin/'
    paths = ['server', 'tools/deploy', 'docs/PILOT_MISSIONS.md', 'client/combat/balance.json',
             *REQUIRED_ASSET_CATALOGS,
             'runtime/assets/mos_eisley/scene.json',
             'tools/combat/export_catalog.py']
    paths += ['tools/assets/' + p + '.py' for p in
              ('swg_formats', 'archive_policy', 'character_formats', 'stf')]
    if args.prepare_only:
        paths=[p for p in paths if not p.startswith('tools/')]+['tools','tests','docs/VPS_DEPLOYMENT.md',
            'runtime/assets/inventory/catalog.json','runtime/assets/ambient_npcs/catalog.json']
    else:
        paths+=['runtime/server/native-build.json','runtime/server/pilot-source/installed.json','runtime/server/pilot-source/conversion.json','runtime/server/pilot-source/quests.json','runtime/server/pilot-source/dialogue.json']
        paths += [native + p for p in ('corecu', 'core3', 'core3client', 'conf', 'scripts', 'terrain', 'custom_scripts')]
    for relative in paths:
        source, destination = ROOT / relative, target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        else:
            shutil.copy2(source, destination)
    # Console fixture hooks/admin users belong exclusively to local tests.
    for relative in (() if args.prepare_only else ('conf/adminusers.lst', 'conf/webusers.lst',
                     'scripts/screenplays/tests/tests.lua',
                     'scripts/managers/resource_manager_spawns.lua')):
        original = subprocess.check_output(['git', '-C', str(ROOT/'vendor/Core3'),
                                            'show', 'HEAD:MMOCoreORB/bin/' + relative])
        (target/native/relative).write_bytes(original)
    if args.profile:
        prepare_capacity(target/'runtime/remote',profile=PROFILES[args.profile])
    if args.prepare_only:
        source=target/'source';source.mkdir()
        for name,repository in (('Core3',ROOT/'vendor/Core3'),('engine3',ROOT/'vendor/Core3/MMOCoreORB/utils/engine3')):
            subprocess.run(['git','-C',str(repository),'bundle','create',str(source/(name+'.bundle')),'HEAD'],check=True)
        (source/'build-inputs.json').write_text(json.dumps(native_inputs(ROOT),indent=2)+'\n')
        (target/'NOT_DEPLOYABLE.txt').write_text('Source preparation only. No current linked CoreCU binaries are included.\nRestore the bundled pinned sources, supply the original TRE media, configure all planets, build and run native tests, then create a normal runtime package.\nDo not install this preparation directory over a running realm. See docs/VPS_DEPLOYMENT.md.\n')
    (target/'package-status.json').write_text(json.dumps({'kind':'source_preparation' if args.prepare_only else 'runtime',
        'deployable':not args.prepare_only,'profile':args.profile,'linked_build_verified':not args.prepare_only,
        'live_load_validated':False,'includes_private_realm_state':False},indent=2)+'\n')
    manifest = {}
    for path in sorted(target.rglob('*')):
        if path.is_file():
            with path.open('rb') as stream:
                manifest[str(path.relative_to(target))] = hashlib.file_digest(stream, 'sha256').hexdigest()
    output = target/'runtime/remote/runtime-sha256.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Staged {len(manifest)} files; no SQL/BerkeleyDB state or private credentials copied. '+('NOT DEPLOYABLE: source preparation only.' if args.prepare_only else 'Current linked binaries verified; live load validation is separate.'))


if __name__ == '__main__':
    main()
