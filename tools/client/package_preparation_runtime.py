"""Bundle pinned open-source extraction and conversion dependencies for testers."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import zipfile
ROOT=Path(__file__).resolve().parents[2]
CACHE=ROOT/'runtime/toolchains/data-preparation'

def package(root,target):
    root=Path(root);windows=target=='windows-x86_64';bundle=root/'engine/data-preparation';binary=bundle/'bin';binary.mkdir(parents=True,exist_ok=True)
    # The download manifest records the upstream release SHA256 verified on fetch.
    downloads=json.loads((CACHE/'downloads.json').read_text())
    for row in downloads:
        with (CACHE/row['file']).open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
        if digest!=row['sha256']:raise ValueError('Preparation dependency checksum mismatch: '+row['file'])
    ffmpeg=CACHE/('ffmpeg-master-latest-win64-lgpl-shared' if windows else 'ffmpeg-master-latest-linux64-lgpl-shared')
    for folder in ('bin','lib'):
        if (ffmpeg/folder).exists():shutil.copytree(ffmpeg/folder,bundle/folder,dirs_exist_ok=True)
    for path in (bundle/'bin').glob('ffplay*'):path.unlink()
    name='unshield.exe' if windows else 'unshield'
    shutil.copy2(CACHE/('unshield-win' if windows else 'unshield-linux')/'src'/name,binary/name)
    if windows:
        python=root/'python'
        # Existing isolated stdlib/launcher paths, plus packaged conversion code.
        pth=python/'python313._pth'
        paths=['../engine/data-preparation/tools/client','../runtime/preparation/workspace']
        paths += ['../runtime/preparation/workspace/tools/'+name for name in ('assets','combat','crafting','entertainment','vehicles','pets','scout','server')]
        pth.write_text(pth.read_text()+'\n'.join(paths)+'\n')
        site=python
    else:
        python=root/'engine/data-python'
        shutil.copytree(CACHE/'python',python,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
        site=python/'lib/python3.13/site-packages';site.mkdir(parents=True,exist_ok=True)
    wheels=[]
    for wheel in sorted((CACHE/('wheels-windows' if windows else 'wheels-linux')).glob('*.whl')):
        with zipfile.ZipFile(wheel) as archive:archive.extractall(site)
        with wheel.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
        wheels.append(dict(name=wheel.name,sha256=digest,source='https://pypi.org/'))
    licenses=bundle/'licenses';licenses.mkdir(exist_ok=True)
    shutil.copy2(ROOT/'runtime/vendor/unshield/LICENSE',licenses/'unshield-MIT.txt')
    shutil.copy2(CACHE/'zlib-1.3.1/LICENSE',licenses/'zlib.txt')
    for p in ffmpeg.glob('*LICENSE*'):shutil.copy2(p,licenses/p.name)
    for p in ffmpeg.glob('*COPYING*'):shutil.copy2(p,licenses/p.name)
    (licenses/'SOURCES.txt').write_text('Conversion dependencies are open-source; no game files are included.\nUnshield: https://github.com/twogood/unshield/tree/cbed3d19ef9cdf4e5fb86b9d65e48f1bf8d539db (MIT). Built with BUILD_STATIC and USE_OUR_OWN_MD5.\nzlib: https://zlib.net/fossils/zlib-1.3.1.tar.gz\nFFmpeg LGPL shared builds: https://github.com/BtbN/FFmpeg-Builds ; bundled adjacent shared libraries can be replaced. Build configuration and exact revisions are in bin/ffmpeg -version. Corresponding source and build recipes: https://github.com/BtbN/FFmpeg-Builds/tree/master\nCPython Linux: https://github.com/astral-sh/python-build-standalone/releases/tag/20261009 ; licenses in data-python/licenses.\nPillow and NumPy: wheel license directories retained alongside modules.\nParsed server definitions: SWGEmu Core3 AGPL-3.0-or-later; source and COPYING bundled in vendor/Core3.\n')
    report=dict(downloads=downloads,wheels=wheels,target=target,no_game_media=True)
    (bundle/'dependencies.json').write_text(json.dumps(report,indent=2)+'\n')
    return report
