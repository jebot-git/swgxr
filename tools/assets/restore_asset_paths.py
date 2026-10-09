#!/usr/bin/env python3
"""Verify extracted asset bytes, then rebase recorded workspace paths locally.

Run after extracting the ZIP into a workspace: python restore_asset_paths.py
This changes JSON metadata only. Original archive bytes and TRE hashes stay intact.
"""
import argparse
import hashlib
import json
from pathlib import Path


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def restore(root):
    root = Path(root).resolve()
    manifest = json.loads((root / 'ASSET_MANIFEST.json').read_text())
    for entry in manifest['files']:
        relative = Path(entry['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Archive manifest path leaves workspace')
        path = root / relative
        if path.is_symlink() or not path.is_file() or sha(path) != entry['sha256']:
            raise ValueError('Extracted asset does not match archive: ' + str(relative))
    old = manifest['workspace_root'].encode()
    new = root.as_posix().encode()
    updates = []
    for entry in manifest['files']:
        path = root / entry['path']
        if path.suffix != '.json': continue
        before = path.read_bytes()
        after = before.replace(old + b'/runtime/', new + b'/runtime/')
        if before != after:
            json.loads(after)
            path.write_bytes(after)
            updates.append(dict(path=entry['path'], sha256=sha(path)))
    result = dict(verified_files=len(manifest['files']), workspace=str(root), rebased_metadata=updates)
    (root / 'ASSET_RESTORE_RECEIPT.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(verified_files=result['verified_files'], rebased_metadata=len(updates))))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent)
    restore(parser.parse_args().root)
