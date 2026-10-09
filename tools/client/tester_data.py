#!/usr/bin/env python3
"""Install a local, manifest-verified SWGXR data ZIP without extracting code."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import zipfile

MAX_FILES = 200000
MAX_BYTES = 256 * 1024**3
MAX_FILE_BYTES = 16 * 1024**3
MAX_MANIFEST = 64 * 1024**2
DATA_SUFFIXES = {'.json', '.png', '.jpg', '.jpeg', '.ogg', '.wav', '.mp3', '.flr', '.trn', '.fnt', '.lay', '.pob'}
IGNORED_MEMBERS = {'ASSET_README.txt', 'restore_asset_paths.py'}


def data_path(value):
    if not isinstance(value, str) or not value or '\\' in value or re.search(r'[<>:"|?*\x00-\x1f]', value):
        raise ValueError('Invalid portable asset path')
    path = PurePosixPath(value)
    if path.is_absolute() or str(path) != value or any(p in ('', '.', '..') or p.endswith((' ', '.')) or p.startswith('.') for p in path.parts):
        raise ValueError('Asset path leaves the data layout')
    if any(p.split('.')[0].upper() in {'CON','PRN','AUX','NUL',*(f'COM{i}' for i in range(1,10)),*(f'LPT{i}' for i in range(1,10))} for p in path.parts):
        raise ValueError('Reserved Windows path')
    if value.startswith('runtime/assets/') and path.suffix.lower() in DATA_SUFFIXES:
        return path
    if re.fullmatch(r'runtime/asset_sources/active_tre/[A-Za-z0-9_.-]+\.tre', value) or value == 'runtime/asset_sources/active_tre/provenance.json':
        return path
    if re.fullmatch(r'runtime/asset_sources/extracted/[A-Za-z0-9_.-]+/media_inventory\.json', value):
        return path
    if value in {'runtime/asset_reports/critical-format-versions.json','runtime/asset_reports/retail-format-audit.json','runtime/asset_reports/static_material_report.json'}:
        return path
    raise ValueError('Archive entry is not an allowed game data file: ' + value)


def inspect(archive):
    entries = archive.infolist()
    if len(entries) > MAX_FILES + 3: raise ValueError('Too many archive entries')
    by_name = {}
    folded = set()
    for entry in entries:
        if entry.filename.casefold() in folded: raise ValueError('Duplicate archive entry')
        folded.add(entry.filename.casefold())
        mode = entry.external_attr >> 16
        if entry.is_dir() or stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG)) or entry.flag_bits & 1:
            raise ValueError('Archive must contain unencrypted regular files only')
        by_name[entry.filename] = entry
    manifest_info = by_name.get('ASSET_MANIFEST.json')
    if not manifest_info or manifest_info.file_size > MAX_MANIFEST: raise ValueError('Missing or oversized asset manifest')
    raw = archive.read(manifest_info)
    manifest = json.loads(raw)
    if manifest.get('schema') != 1 or manifest.get('layout') != 'swgxr-assets-v2': raise ValueError('Unsupported data archive layout')
    old = manifest.get('workspace_root')
    if not isinstance(old,str) or not old.startswith('/') or '\x00' in old or len(old)>4096: raise ValueError('Invalid recorded workspace')
    files = manifest.get('files')
    if not isinstance(files,list) or not files or len(files)>MAX_FILES: raise ValueError('Invalid asset file list')
    total=0; names=set()
    for row in files:
        if not isinstance(row,dict): raise ValueError('Invalid manifest entry')
        name = str(data_path(row.get('path')))
        size=row.get('bytes'); digest=row.get('sha256')
        if type(size) is not int or size<0 or size>MAX_FILE_BYTES or not isinstance(digest,str) or not re.fullmatch('[0-9a-f]{64}',digest): raise ValueError('Invalid asset size or digest')
        if name in names or name not in by_name or by_name[name].file_size != size: raise ValueError('Manifest does not match ZIP members')
        names.add(name); total+=size
    if total>MAX_BYTES or set(by_name)-names-IGNORED_MEMBERS-{'ASSET_MANIFEST.json'}: raise ValueError('Oversized archive or unlisted member')
    if manifest.get('source_bytes') != total: raise ValueError('Asset manifest total differs')
    return manifest, hashlib.sha256(raw).hexdigest()


def rebase(value, old, new):
    if isinstance(value,str): return value.replace(old.rstrip('/')+'/runtime/',new.rstrip('/')+'/runtime/')
    if isinstance(value,list): return [rebase(v,old,new) for v in value]
    if isinstance(value,dict): return {k:rebase(v,old,new) for k,v in value.items()}
    return value


def install(zip_path, root):
    root=Path(root).resolve();zip_path=Path(zip_path).resolve()
    root.mkdir(parents=True,exist_ok=True)
    if (root/'runtime').is_symlink(): raise ValueError('Runtime directory must not be a symlink')
    with zipfile.ZipFile(zip_path) as archive:
        manifest,digest=inspect(archive)
        receipt=root/'ASSET_RESTORE_RECEIPT.json'
        if receipt.is_symlink():raise ValueError('Asset receipt must not be a symlink')
        if receipt.is_file():
            previous=json.loads(receipt.read_text())
            if previous.get('manifest_sha256')==digest and previous.get('workspace')==root.as_posix() and (root/'runtime/assets').is_dir():
                return dict(previous,already_installed=True)
            raise ValueError('Existing data belongs to a different archive or package location; import into a fresh client folder')
        for name in ('assets','asset_sources','asset_reports'):
            if (root/'runtime'/name).exists() or (root/'runtime'/name).is_symlink(): raise ValueError('Import requires an empty runtime data layout: '+name)
        total=manifest['source_bytes']
        if shutil.disk_usage(root).free < total+256*1024**2: raise ValueError('Insufficient free disk space for data import')
        lock=root/'.asset-import.lock'
        fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        os.close(fd)
        try:
            with tempfile.TemporaryDirectory(prefix='.asset-import-',dir=root) as temporary:
                stage=Path(temporary);rebased=[]
                for index,row in enumerate(manifest['files']):
                    destination=stage/row['path'];destination.parent.mkdir(parents=True,exist_ok=True)
                    actual=hashlib.sha256();count=0
                    with archive.open(row['path']) as source,destination.open('xb') as output:
                        while block:=source.read(4*1024**2):
                            count+=len(block)
                            if count>row['bytes']: raise ValueError('Expanded entry exceeds its manifest size')
                            actual.update(block);output.write(block)
                    if count!=row['bytes'] or actual.hexdigest()!=row['sha256']: raise ValueError('Asset SHA256 mismatch: '+row['path'])
                    if destination.suffix=='.json':
                        if count>MAX_MANIFEST: raise ValueError('JSON metadata exceeds import bound')
                        before=json.loads(destination.read_text());after=rebase(before,manifest['workspace_root'],root.as_posix())
                        if before!=after:
                            destination.write_text(json.dumps(after,separators=(',',':'))+'\n');rebased.append(row['path'])
                    if (index+1)%2000==0: print(f'Verified {index+1}/{len(manifest["files"])} data files',flush=True)
                (root/'runtime').mkdir(exist_ok=True)
                installed=[]
                try:
                    for name in ('assets','asset_sources','asset_reports'):
                        source=stage/'runtime'/name
                        if source.exists():source.replace(root/'runtime'/name);installed.append(name)
                    result=dict(schema=1,manifest_sha256=digest,verified_files=len(manifest['files']),workspace=root.as_posix(),rebased_metadata=rebased,archive_name=zip_path.name)
                    (root/'ASSET_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
                    receipt.write_text(json.dumps(result,indent=2)+'\n')
                except BaseException:
                    for name in reversed(installed):(root/'runtime'/name).replace(stage/'runtime'/name)
                    raise
                return result
        finally: lock.unlink(missing_ok=True)


def ensure_data(root):
    root=Path(root).resolve()
    choices=sorted((root/'data').glob('*.zip'))
    if len(choices)!=1: raise ValueError('Place exactly one supplied SWGXR data ZIP in the data folder, then retry')
    return install(choices[0],root)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parent);parser.add_argument('--archive',type=Path)
    args=parser.parse_args();print(json.dumps(install(args.archive,args.root) if args.archive else ensure_data(args.root)))
