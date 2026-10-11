#!/usr/bin/env python3
"""Build a file delta between verified portable packages (no original game data)."""
import argparse
import json
from pathlib import Path
import tarfile
import tempfile
from tools.client import update_test_client as updater

def build(base, target, output):
    base, target, output = map(Path, (base, target, output))
    previous = json.loads((base/'PACKAGE.json').read_text())
    current = json.loads((target/'PACKAGE.json').read_text())
    if previous['target'] != current['target']:
        raise ValueError('Platform mismatch')
    before = {r['path']: r['sha256'] for r in previous['files']}
    files = {r['path'] for r in current['files']} | {'PACKAGE.json'}
    updater.validate(target, current['target'], files)
    changed = ['PACKAGE.json']
    for row in current['files']:
        name = updater.safe_name(row['path'])
        if not (updater.managed(name) or name in updater.PRESERVED):
            raise ValueError('Unmanaged package file: '+name)
        if name in updater.PRESERVED or before.get(name) != row['sha256']:
            changed.append(name)
    output.mkdir(parents=True, exist_ok=True)
    destination = output/('patch-'+current['target']+'-'+updater.sha(base/'PACKAGE.json')+'.tar.gz')
    metadata = dict(schema=1, base_package_sha256=updater.sha(base/'PACKAGE.json'),
                    target_package_sha256=updater.sha(target/'PACKAGE.json'))
    with tempfile.TemporaryDirectory() as temporary:
        descriptor = Path(temporary)/'DELTA.json'
        descriptor.write_text(json.dumps(metadata, sort_keys=True)+'\n')
        with tarfile.open(destination, 'w:gz') as bundle:
            bundle.add(descriptor, arcname='patch/DELTA.json')
            for name in sorted(changed):
                source = target/name
                if source.is_symlink():
                    raise ValueError('Linked package file')
                bundle.add(source, arcname='patch/'+name, recursive=False)
    return dict(path=str(destination), bytes=destination.stat().st_size,
                sha256=updater.sha(destination), changed_files=len(changed), **metadata)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, type=Path)
    parser.add_argument('--target', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.base, args.target, args.output), indent=2))
