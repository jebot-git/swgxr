#!/usr/bin/env python3
"""Create and fully verify a private ZIP64 of converted SWG assets and source TREs.

Includes original provenance and conversion reports; excludes installation discs,
duplicate extractions, development captures, credentials, databases and code.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import zipfile
try:
    from .archive_policy import CORE3_TRE_PRIORITY
except ImportError:
    from archive_policy import CORE3_TRE_PRIORITY

ROOT = Path(__file__).resolve().parents[2]
BLOCKED = {'.log', '.pid', '.iso', '.bin', '.cue', '.pem', '.key', '.db', '.sqlite', '.sqlite3', '.pyc', '.tmp'}
STORED = {'.tre', '.png', '.jpg', '.ogg', '.mp3', '.zip'}


def file_list(root):
    paths = []
    for path in sorted((root / 'runtime/assets').rglob('*')):
        if path.is_symlink(): raise ValueError('Unexpected runtime asset symlink: ' + str(path))
        if not path.is_file() or path.suffix.lower() in BLOCKED: continue
        if any(part.startswith('.') or part in ('__pycache__', 'logs') for part in path.relative_to(root).parts): continue
        paths.append(path)
    source = root / 'runtime/asset_sources/active_tre'
    archives = sorted(source.glob('*.tre'))
    provenance = json.loads((source / 'provenance.json').read_text())
    expected = {row['filename']: row['sha256'] for row in provenance['archives']}
    if set(expected) != set(CORE3_TRE_PRIORITY) or {p.name for p in archives} != set(expected):
        raise ValueError('Complete 51-file source TRE set required')
    for path in archives:
        if not path.resolve().is_relative_to(root / 'runtime/asset_sources'):
            raise ValueError('TRE source escapes private asset source tree')
    paths.extend(archives + [source / 'provenance.json'])
    paths.extend(sorted((root / 'runtime/asset_sources/extracted').glob('*/media_inventory.json')))
    for name in ('critical-format-versions.json', 'retail-format-audit.json', 'static_material_report.json'):
        path = root / 'runtime/asset_reports' / name
        if path.exists(): paths.append(path)
    folded = set()
    for path in paths:
        name = path.relative_to(root).as_posix()
        if name.casefold() in folded or re.search(r'[<>:"|?*]', name):
            raise ValueError('Non-portable or duplicate archive path: ' + name)
        folded.add(name.casefold())
    return paths, expected


def bundle(output, root=ROOT):
    root, output = Path(root).resolve(), Path(output).resolve()
    if not output.is_relative_to(root / 'runtime/asset_archives'):
        raise ValueError('Archive must remain in ignored runtime/asset_archives')
    if output.exists(): raise ValueError('Archive already exists')
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = output.with_suffix(output.suffix + '.partial')
    if temporary.exists(): raise ValueError('Partial archive already exists; inspect before retrying')
    paths, expected = file_list(root)
    source_bytes = sum(path.stat().st_size for path in paths)
    if shutil.disk_usage(output.parent).free < source_bytes + 1024**3:
        raise ValueError('Insufficient space for a conservative uncompressed archive')
    manifest = dict(schema=1, layout='swgxr-assets-v2', workspace_root=str(root),
                    source_commit=subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
                    converted_root='runtime/assets', tre_root='runtime/asset_sources/active_tre',
                    tre_count=len(expected), source_bytes=source_bytes, files=[])
    print(json.dumps(dict(phase='packing', files=len(paths), source_bytes=source_bytes)), flush=True)
    last = time.monotonic()
    with zipfile.ZipFile(temporary, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        temporary.chmod(0o600)
        for index, path in enumerate(paths):
            name = path.relative_to(root).as_posix()
            before = path.stat()
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_STORED if path.suffix.lower() in STORED else zipfile.ZIP_DEFLATED
            info.external_attr = (0o100644 << 16)
            digest = hashlib.sha256()
            with path.open('rb') as source, archive.open(info, 'w', force_zip64=True) as target:
                while block := source.read(8 * 1024 * 1024):
                    digest.update(block); target.write(block)
            after = path.stat()
            if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
                raise ValueError('Asset changed during archive creation: ' + name)
            value = digest.hexdigest()
            if path.suffix == '.tre' and expected[path.name] != value:
                raise ValueError('Original TRE provenance hash mismatch: ' + name)
            manifest['files'].append(dict(path=name, bytes=before.st_size, sha256=value))
            if time.monotonic() - last > 20:
                print(json.dumps(dict(phase='packing', complete=index + 1, files=len(paths))), flush=True); last=time.monotonic()
        archive.writestr('ASSET_MANIFEST.json', json.dumps(manifest, indent=2) + '\n')
        archive.write(root / 'tools/assets/restore_asset_paths.py', 'restore_asset_paths.py')
        archive.writestr('ASSET_README.txt',
            'SWGXR private asset bundle (ZIP64; Linux and Windows)\n\n'
            'Contains converted assets for all ten original ground planets, the original Luxury\n'
            'Yacht, eleven small-ship cockpits/exteriors, Tatooine navigation landmark, and the 51 required\n'
            'original TRE archives, with provenance and conversion failures retained.\n'
            'No replacement media was downloaded. Game code, Godot, databases, accounts,\n'
            'credentials, installation discs and redundant extraction caches are not included.\n\n'
            'Extract into an empty workspace or staging folder, keeping runtime/ intact.\n'
            'For a portable testing client, put this ZIP in its data/ folder and run its launcher.\n'
            'Run: python restore_asset_paths.py --root <extracted-workspace>\n'
            'This first verifies every asset SHA256, then adjusts recorded absolute workspace\n'
            'paths in JSON metadata for the destination. Use matching SWGXR code with the v2\n'
            'asset layout. Extract again before rerunning restore after a path change.\n'
            'TRE entries are regular files; no symlinks or administrator rights are required.\n'
            'Keep this user-supplied proprietary material private and outside source control.\n')
    print(json.dumps(dict(phase='verifying', files=len(paths))), flush=True)
    with zipfile.ZipFile(temporary) as archive:
        for index, entry in enumerate(manifest['files']):
            with archive.open(entry['path']) as source:
                value = hashlib.file_digest(source, 'sha256').hexdigest()
            if value != entry['sha256']: raise ValueError('ZIP verification failed: ' + entry['path'])
            if time.monotonic() - last > 20:
                print(json.dumps(dict(phase='verifying', complete=index + 1, files=len(paths))), flush=True); last=time.monotonic()
        if archive.testzip() is not None: raise ValueError('ZIP CRC verification failed')
    temporary.replace(output)
    with output.open('rb') as source: digest = hashlib.file_digest(source, 'sha256').hexdigest()
    output.with_suffix('.sha256').write_text(digest + '  ' + output.name + '\n')
    output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    report = dict(passed=True, archive=str(output), files=len(paths), source_bytes=source_bytes,
                  archive_bytes=output.stat().st_size, sha256=digest, tre_count=len(expected),
                  validation='Every extracted entry SHA256 and ZIP CRC checked', symlinks_in_archive=False)
    output.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report), flush=True)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    bundle(parser.parse_args().output)
