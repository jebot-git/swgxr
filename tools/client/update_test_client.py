#!/usr/bin/env python3
"""Verified in-place updater for portable SWGXR clients; never launches the game."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

REPOSITORY = 'jebot-git/swgxr'
API = 'https://api.github.com/repos/' + REPOSITORY + '/releases?per_page=30'
ROOT_FILES = {'PACKAGE.json', 'START-HERE.txt', 'TESTER_INSTALL.md', 'JTL_TEST_STATUS.md',
              'MEDIA_SCOPE.md', 'ORIGINAL_AUDIO.md',
              'start_client.py', 'test_client_launcher.py', 'tester_data.py',
              'update_test_client.py', 'launcher_platform.py', 'play-vr.sh', 'play-desktop.sh',
              'import-data.sh', 'install-shortcuts.sh', 'updates.sh', 'launcher.sh',
              'play-vr.cmd', 'play-desktop.cmd', 'import-data.cmd', 'install-shortcuts.cmd',
              'updates.cmd', 'launcher.cmd'}
PRESERVED = {'server.json', 'server-ca.pem', 'data/DROP-DATA-HERE.txt'}
LIMIT = 1024**3

def sha(path):
    digest=hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block:=stream.read(1024*1024):digest.update(block)
    return digest.hexdigest()

@contextmanager
def installation_lock(root):
    with (root/'.update.lock').open('a+b') as stream:
        stream.seek(0);stream.write(b'0');stream.flush();stream.seek(0)
        try:
            if os.name=='nt':
                import msvcrt
                msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
            else:
                import fcntl
                fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except OSError: raise ValueError('Close the running client or other updater first.') from None
        try: yield
        finally:
            stream.seek(0)
            if os.name=='nt':msvcrt.locking(stream.fileno(),msvcrt.LK_UNLCK,1)
            else:fcntl.flock(stream,fcntl.LOCK_UN)

def managed(name):
    path=PurePosixPath(name)
    return name in ROOT_FILES or path.parts[0] in {'client','engine','python'}

def safe_name(name):
    path=PurePosixPath(name)
    if not name or '\\' in name or ':' in name or path.is_absolute() or any(p in ('..','.') for p in name.split('/')) or str(path)!=name:
        raise ValueError('Unsafe update path: '+name)
    return name

def request(url):
    if not url.startswith('https://'):raise ValueError('HTTPS release URL required')
    return urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'SWGXR-Updater','Accept':'application/vnd.github+json'}),timeout=45)

def download(url,path,maximum=LIMIT):
    with request(url) as source, Path(path).open('wb') as output:
        size=0
        while block:=source.read(1024*1024):
            size+=len(block)
            if size>maximum:raise ValueError('Release download exceeds size limit')
            output.write(block)

def discover(target):
    with request(API) as source: releases=json.loads(source.read(4*1024*1024))
    eligible=[r for r in releases if not r.get('draft') and re.fullmatch(r'v\d{4}\.\d{2}\.\d{2}-test\.\d+',r.get('tag_name',''))]
    eligible.sort(key=lambda r:tuple(map(int,re.findall(r'\d+',r['tag_name']))),reverse=True)
    for release in eligible:
        suffix='.zip' if target=='windows-x86_64' else '.tar.gz'
        prefix='test-client-windows-' if target=='windows-x86_64' else 'test-client-linux-'
        assets={a['name']:a for a in release['assets']}
        choices=[a for name,a in assets.items() if name.startswith(prefix) and name.endswith(suffix)]
        if len(choices)!=1 or 'CHECKSUMS.sha256' not in assets:continue
        for asset in [choices[0],assets['CHECKSUMS.sha256']]:
            if not asset['browser_download_url'].startswith('https://github.com/'+REPOSITORY+'/releases/download/'+release['tag_name']+'/'):raise ValueError('Unexpected release download origin')
        return release['tag_name'],choices[0],assets['CHECKSUMS.sha256']
    raise ValueError('No complete portable client release is available.')

def unpack(archive,destination):
    seen=set();total=0;roots=set()
    def write(name,size,mode,source):
        nonlocal total
        full=safe_name(name);parts=PurePosixPath(full).parts
        if len(parts)<2:raise ValueError('Expected one package folder')
        roots.add(parts[0]);name='/'.join(parts[1:]);safe_name(name)
        if len(roots)>1 or name in seen or not (managed(name) or name in PRESERVED):raise ValueError('Unexpected or duplicate update file: '+name)
        seen.add(name);total+=size
        if size<0 or total>3*LIMIT or len(seen)>50000:raise ValueError('Expanded update exceeds limit')
        path=destination/name;path.parent.mkdir(parents=True,exist_ok=True)
        with source, path.open('wb') as output:shutil.copyfileobj(source,output)
        if path.stat().st_size!=size:raise ValueError('Truncated update file')
        path.chmod(0o755 if mode & 0o111 else 0o644)
    if archive.name.endswith('.zip'):
        with zipfile.ZipFile(archive) as bundle:
            for row in bundle.infolist():
                if row.is_dir():continue
                mode=row.external_attr>>16
                if stat.S_ISLNK(mode):raise ValueError('Links are not permitted in updates')
                write(row.filename,row.file_size,mode,bundle.open(row))
    else:
        with tarfile.open(archive,'r:gz') as bundle:
            for row in bundle:
                if row.isdir():continue
                if not row.isfile():raise ValueError('Links/devices are not permitted in updates')
                write(row.name,row.size,row.mode,bundle.extractfile(row))
    return seen

def validate(stage,target,extracted):
    package=json.loads((stage/'PACKAGE.json').read_text())
    if package.get('target')!=target or not package.get('runnable'):raise ValueError('Release is not runnable on this platform')
    expected={'PACKAGE.json'}
    for row in package['files']:
        name=safe_name(row['path'])
        if name in expected or name not in extracted:raise ValueError('Invalid package inventory')
        expected.add(name);path=stage/name
        if path.stat().st_size!=row['bytes'] or sha(path)!=row['sha256']:raise ValueError('Package file checksum mismatch: '+name)
    if expected!=extracted:raise ValueError('Unlisted files in release')
    return package

def ensure_closed(root):
    # Older portable clients have no launcher lock; inspect Linux executables too.
    if sys.platform.startswith('linux'):
        for proc in Path('/proc').glob('[0-9]*'):
            try: executable=(proc/'exe').resolve(strict=True)
            except OSError:continue
            if executable.is_relative_to(root/'engine'):raise ValueError('Close the running client before updating.')

def install(root,stage,package,version,archive_hash):
    old=json.loads((root/'PACKAGE.json').read_text())
    new={row['path'] for row in package['files'] if managed(row['path'])}|{'PACKAGE.json'}
    previous={safe_name(row['path']) for row in old.get('files',[]) if managed(safe_name(row['path']))}|{'PACKAGE.json'}
    for name in new|previous:
        path=root/name
        if path.is_symlink() or any(p.is_symlink() for p in path.parents if p!=root and p.is_relative_to(root)):raise ValueError('Linked installation path cannot be updated: '+name)
    changed=[name for name in sorted(new) if not (root/name).is_file() or sha(root/name)!=sha(stage/name)]
    removed=sorted(previous-new);touched=changed+removed
    for name in touched:
        path=root/name
        if path.is_symlink() or any(p.is_symlink() for p in path.parents if p!=root and p.is_relative_to(root)):raise ValueError('Linked installation path cannot be updated: '+name)
        if path.exists() and not path.is_file():raise ValueError('Unexpected installation directory: '+name)
    backup=root/'.updates'/('backup-'+version)
    if backup.exists():backup=Path(tempfile.mkdtemp(prefix='backup-'+version+'-',dir=root/'.updates'))
    backup.mkdir(parents=True,exist_ok=True)
    journal={'state':'applying','version':version,'backup':str(backup),'moved':[],'installed':[]}
    journal_path=root/'.updates'/'transaction.json'
    def record():journal_path.write_text(json.dumps(journal,indent=2))
    try:
        for name in touched:
            target=root/name
            if target.exists():
                saved=backup/name;saved.parent.mkdir(parents=True,exist_ok=True);os.replace(target,saved);journal['moved'].append(name);record()
            if name in new:
                target.parent.mkdir(parents=True,exist_ok=True);os.replace(stage/name,target);journal['installed'].append(name);record()
        receipt={'version':version,'archive_sha256':archive_hash,'changed_files':len(changed),'removed_files':len(removed),'backup':str(backup),'assets_preserved':True}
        (root/'UPDATE_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n')
        journal['state']='complete';record();return receipt
    except BaseException:
        for name in reversed(journal['installed']):(root/name).unlink(missing_ok=True)
        for name in reversed(journal['moved']):os.replace(backup/name,root/name)
        journal['state']='rolled_back';record();raise

def update(root):
    root=Path(root).resolve()
    if not (root/'PACKAGE.json').is_file():raise ValueError('Select an extracted SWGXR portable client folder.')
    with installation_lock(root):
        ensure_closed(root)
        unfinished=root/'.updates'/'transaction.json'
        if unfinished.exists() and json.loads(unfinished.read_text()).get('state')=='applying':raise ValueError('An interrupted update needs recovery from '+str(unfinished))
        target=json.loads((root/'PACKAGE.json').read_text())['target']
        if target not in ('linux-x86_64','windows-x86_64'):raise ValueError('Unsupported client platform')
        print('Checking published client updates…',flush=True)
        version,asset,checksums=discover(target)
        current=root/'UPDATE_RECEIPT.json'
        receipt=json.loads(current.read_text()) if current.exists() else {}
        installed=receipt.get('version','')
        if installed and tuple(map(int,re.findall(r'\d+',installed)))>tuple(map(int,re.findall(r'\d+',version))):raise ValueError('Refusing release downgrade')
        with tempfile.TemporaryDirectory(prefix='.swgxr-update-',dir=root.parent) as temporary:
            work=Path(temporary);archive=work/asset['name'];checksum_file=work/'CHECKSUMS.sha256'
            download(checksums['browser_download_url'],checksum_file,65536)
            matches=[line.split()[0] for line in checksum_file.read_text().splitlines() if len(line.split())==2 and line.split()[1].lstrip('*')==asset['name']]
            if len(matches)!=1 or not re.fullmatch('[0-9a-fA-F]{64}',matches[0]):raise ValueError('Missing release checksum')
            # A release may receive a launcher revision without changing its tag.
            # Compare the published archive digest before accepting a local receipt.
            if installed==version and receipt.get('archive_sha256','').lower()==matches[0].lower():
                inventory=json.loads((root/'PACKAGE.json').read_text())
                rows=[r for r in inventory['files'] if managed(safe_name(r['path']))]
                if all((root/r['path']).is_file() and not (root/r['path']).is_symlink() and sha(root/r['path'])==r['sha256'] for r in rows):
                    print('Already up to date: '+version,flush=True);return receipt
            print('Downloading '+version+' ('+asset['name']+')…',flush=True);download(asset['browser_download_url'],archive)
            digest=sha(archive)
            if digest.lower()!=matches[0].lower():raise ValueError('Release archive checksum mismatch')
            stage=work/'package';stage.mkdir();files=unpack(archive,stage);package=validate(stage,target,files)
            print('Verified. Installing code; keeping assets and connection settings…',flush=True)
            ensure_closed(root)
            receipt=install(root,stage,package,version,digest)
            print('Updated to '+version+'. No game was launched.',flush=True)
            return receipt

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parent)
    args=parser.parse_args()
    try:update(args.root);return 0
    except (ValueError,OSError,KeyError,tarfile.TarError,zipfile.BadZipFile) as error:print('Update failed: '+str(error),file=sys.stderr);return 2

if __name__=='__main__':raise SystemExit(main())
