#!/usr/bin/env python3
"""Install official pinned TwoVoIP v6.5 Linux/Windows x86_64 binaries and notices."""
import hashlib
import json
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TAG = 'v6.5'
COMMIT = '7ca36d91fec846bdce80a02f3451b4f06de58139'
URL = 'https://github.com/goatchurchprime/two-voip-godot-4/releases/download/v6.5/TwoVoIP.zip'
SHA256 = '811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7'
NOTICES = {'TwoVoIP-LICENSE.txt': {'url': 'https://raw.githubusercontent.com/goatchurchprime/two-voip-godot-4/7ca36d91fec846bdce80a02f3451b4f06de58139/LICENSE', 'sha256': '2958bc2a212f1d54b857557465da48161cf982f818bcb7c72911916c50f10167'}, 'Opus-COPYING.txt': {'url': 'https://raw.githubusercontent.com/xiph/opus/ddbe48383984d56acd9e1ab6a090c54ca6b735a6/COPYING', 'sha256': '01e1167d54a096d123cf6dfbbeb19587278845c6481d2d66d545669846079551'}, 'RNNoise-COPYING.txt': {'url': 'https://raw.githubusercontent.com/xiph/rnnoise/372f7b4b76cde4ca1ec4605353dd17898a99de38/COPYING', 'sha256': '45d37ca1cdb278c088e1aa85e0e65ca3a534ed86a28dcc96ca16810248a61d35'}, 'SpeexDSP-COPYING.txt': {'url': 'https://raw.githubusercontent.com/xiph/speexdsp/1b28a0f61bc31162979e1f26f3981fc3637095c8/COPYING', 'sha256': '2654a4264b2bfe298dedc508748d140111840c315cc8eb646a3a68c13fa75b01'}, 'GodotCPP-LICENSE.txt': {'url': 'https://raw.githubusercontent.com/godotengine/godot-cpp/58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74/LICENSE.md', 'sha256': '26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf'}}


def verified_download(url, digest, path):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        temp=path.with_suffix('.download')
        with urllib.request.urlopen(url,timeout=60) as response,temp.open('wb') as output:
            while chunk:=response.read(1024*1024):output.write(chunk)
        if hashlib.sha256(temp.read_bytes()).hexdigest()!=digest:
            temp.unlink();raise ValueError('Pinned dependency digest mismatch')
        temp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError('Cached dependency digest mismatch: '+path.name)
    return path


def install():
    cache=ROOT/'runtime/dependencies'
    archive=verified_download(URL,SHA256,cache/'TwoVoIP-v6.5.zip')
    destination=ROOT/'client/addons/twovoip'
    wanted={}
    prefix='project/addons/twovoip/'
    with zipfile.ZipFile(archive) as source:
        for name in source.namelist():
            if not name.startswith(prefix) or name.endswith('/'):continue
            relative=name[len(prefix):]
            if '..' in Path(relative).parts or Path(relative).is_absolute():raise ValueError('Unsafe dependency path')
            if relative.startswith('libs/') and not any(kind in relative for kind in ('linux.template_debug.x86_64.so','linux.template_release.x86_64.so','windows.template_debug.x86_64.dll','windows.template_release.x86_64.dll')):continue
            wanted[relative]=source.read(name)
    for name,item in NOTICES.items():wanted['notices/'+name]=verified_download(item['url'],item['sha256'],cache/name).read_bytes()
    for name,data in wanted.items():
        path=destination/name
        if path.exists() and path.read_bytes()!=data:raise ValueError('Installed upstream dependency modified: '+str(path))
    for name,data in wanted.items():
        path=destination/name;path.parent.mkdir(parents=True,exist_ok=True)
        if not path.exists():path.write_bytes(data)
    lock={'repository':'https://github.com/goatchurchprime/two-voip-godot-4','tag':TAG,'commit':COMMIT,'artifact_url':URL,'artifact_sha256':SHA256,
          'platforms':['Linux x86_64','Windows x86_64'],'notices':NOTICES,
          'files':{name:hashlib.sha256(data).hexdigest() for name,data in sorted(wanted.items())}}
    (ROOT/'client/twovoip.lock.json').write_text(json.dumps(lock,indent=2)+'\n')
    print('Installed verified TwoVoIP '+TAG+' ('+str(len(wanted))+' unchanged files)')

if __name__=='__main__':install()
