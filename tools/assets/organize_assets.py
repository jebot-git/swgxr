#!/usr/bin/env python3
"""Apply a reviewed local asset relocation plan, retaining metadata originals.

The plan contains workspace-relative from/to moves, original TRE symlink targets,
and a sibling path-replacements.json. No media or converted content is deleted.
Stop local Core3 before applying; this tool does not contact the live server.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def relative(value):
    path = Path(value)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Plan paths must stay within the workspace')
    return path


def relocate(value, moves):
    for old, new in sorted(moves, key=lambda row: len(row[0]), reverse=True):
        if value == old or value.startswith(old + '/'):
            return new + value[len(old):]
    return value


def apply(plan_path, root=ROOT):
    root = Path(root).resolve()
    plan_path = Path(plan_path).resolve()
    plan = json.loads(plan_path.read_text())
    moves = [(str(relative(row['from'])), str(relative(row['to']))) for row in plan['moves']]
    for old, new in moves:
        if (root / new).exists() or (root / new).is_symlink():
            raise ValueError('Destination already exists: ' + new)
        if not (root / old).exists():
            raise ValueError('Missing source: ' + old)
    journal = dict(schema=1, completed_moves=[], rewritten_metadata=[], passed=False)
    report = plan_path.with_name('result.json')

    def save():
        temporary = report.with_suffix('.tmp')
        temporary.write_text(json.dumps(journal, indent=2) + '\n')
        temporary.replace(report)

    save()
    for old, new in moves:
        destination = root / new
        destination.parent.mkdir(parents=True, exist_ok=True)
        (root / old).rename(destination)
        journal['completed_moves'].append(dict(old=old, new=new))
        save()
    for row in plan['tre_links']:
        link = root / relocate(row['path'], moves)
        target = root / relocate(row['target'], moves)
        if not link.is_symlink() or not target.is_file():
            raise ValueError('Invalid source archive relocation')
        link.unlink()
        link.symlink_to(os.path.relpath(target, link.parent))

    replacements = json.loads(plan_path.with_name('path-replacements.json').read_text())
    metadata_roots = ('runtime/assets', 'runtime/asset_sources', 'runtime/asset_reports')
    originals = plan_path.parent / 'original_metadata'
    hash_changes = {}
    # Byte replacements preserve numeric formatting and original source hashes.
    for directory in metadata_roots:
        for path in sorted((root / directory).rglob('*.json')):
            if path.is_relative_to(plan_path.parent): continue
            before = path.read_bytes()
            after = before
            for old, new in replacements:
                after = after.replace(old.encode(), new.encode())
            if before == after: continue
            backup = originals / path.relative_to(root)
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(before)
            json.loads(after)
            path.write_bytes(after)
            old_hash = hashlib.sha256(before).hexdigest()
            new_hash = hashlib.sha256(after).hexdigest()
            hash_changes[old_hash] = new_hash
            journal['rewritten_metadata'].append(dict(path=str(path.relative_to(root)), before=old_hash, after=new_hash))
    # Keep references to changed converted-file hashes consistent, without
    # changing original TRE-entry hashes. Each hash uniquely identifies bytes.
    journal['metadata_hash_changes'] = hash_changes
    for directory in metadata_roots:
        for path in sorted((root / directory).rglob('*.json')):
            if path.is_relative_to(plan_path.parent): continue
            before = path.read_bytes(); after = before
            for old, new in hash_changes.items():
                after = after.replace(('"'+old+'"').encode(), ('"'+new+'"').encode())
            if before != after:
                backup = originals / path.relative_to(root)
                if not backup.exists():
                    backup.parent.mkdir(parents=True, exist_ok=True); backup.write_bytes(before)
                path.write_bytes(after)
    for name in ('runtime/combat', 'runtime/entertainment'):
        path = root / name
        if path.is_dir() and not any(path.iterdir()): path.rmdir()
    links = list((root / 'runtime/asset_sources/active_tre').glob('*.tre'))
    if not all(path.is_file() for path in links): raise ValueError('Broken active TRE link')
    journal.update(passed=True, active_tre_count=len(links))
    save()
    print(json.dumps({key: journal[key] for key in ('passed', 'active_tre_count')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if not args.apply: raise SystemExit('Review the plan, then pass --apply with local Core3 stopped.')
    apply(args.plan)
