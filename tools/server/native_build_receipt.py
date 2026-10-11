#!/usr/bin/env python3
"""Record only after a successful native build; reject stale deployment binaries."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BINARIES=('corecu','core3','core3client')

def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def inputs(root):
    paths=sorted(set((root/'server/patches').glob('*.patch')) | set((root/'server/combat').glob('*.h')) | set((root/'server/combat').glob('*.json')) | set((root/'tools/combat').glob('install_*.py')))
    paths += sorted((root/'server/jtl').glob('*.h')) + sorted((root/'server/jtl/pilot').glob('*.*')) + sorted((root/'tools/space/pilot').glob('*.py'))
    manifest=root/'runtime/server/pilot-source/installed.json'
    paths += [manifest]
    if manifest.exists():
        for entry in json.loads(manifest.read_text())['files']:
            path=root/'vendor/Core3'/entry['path']
            if sha(path)!=entry['sha256']:raise ValueError('Installed pilot bundle differs from its manifest: '+entry['path'])
            paths.append(path)
    paths += [root/'tools/configure_core3.py',root/'tools/server/build.sh',root/'tools/server/native_build_receipt.py']
    return {'upstream':subprocess.check_output(['git','-C',str(root/'vendor/Core3'),'rev-parse','HEAD'],text=True).strip(),
            'engine3':subprocess.check_output(['git','-C',str(root/'vendor/Core3/MMOCoreORB/utils/engine3'),'rev-parse','HEAD'],text=True).strip(),
            'sha256':{str(path.relative_to(root)):sha(path) for path in paths}}

def binaries(root):
    result={name:sha(root/'vendor/Core3/MMOCoreORB/bin'/name) for name in BINARIES}
    if result['corecu']!=result['core3']:raise ValueError('CoreCU compatibility binary differs from corecu.')
    return result

def record(root=ROOT):
    result={'schema':1,'inputs':inputs(root),'binaries':binaries(root),'linked_build':True,'live_load_validated':False}
    path=root/'runtime/server/native-build.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(result,indent=2)+'\n')
    return result

def verify(root=ROOT):
    try:
        receipt=json.loads((root/'runtime/server/native-build.json').read_text())
        if receipt.get('schema')!=1 or receipt.get('linked_build') is not True or receipt.get('inputs')!=inputs(root) or receipt.get('binaries')!=binaries(root):
            raise ValueError('Native build receipt does not match current source and binaries.')
        return receipt
    except (OSError,json.JSONDecodeError) as exc:
        raise ValueError('Fresh linked CoreCU build receipt required; run tools/server/build.sh successfully before packaging.') from exc

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['record','verify']);args=parser.parse_args()
    try:record() if args.action=='record' else verify()
    except ValueError as exc:raise SystemExit(str(exc))
    print('CoreCU native build receipt '+('recorded' if args.action=='record' else 'verified'))

if __name__=='__main__':main()
