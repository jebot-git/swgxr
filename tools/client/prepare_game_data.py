"""Prepare a complete client data tree from local TTE media or installed TREs.

Runs only bundled conversion code. Original installers and game data are never
executed or downloaded. A failed conversion leaves installed assets untouched.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
try:
    from .iso_media import extract_cabinets
    from .game_data_plan import STEPS, REQUIRED
except ImportError:
    from iso_media import extract_cabinets
    from game_data_plan import STEPS, REQUIRED


def sha(path):
    with Path(path).open('rb') as file:return hashlib.file_digest(file,'sha256').hexdigest()

def write(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8');temporary.replace(path)

def tre_files(folder):
    found={}
    for path in Path(folder).rglob('*'):
        if not path.is_file() or path.suffix.lower()!='.tre':continue
        name=path.name.lower()
        if not re.fullmatch(r'[a-z0-9_.-]+\.tre',name):raise ValueError('Unsupported archive filename: '+path.name)
        if len(found)>=256:raise ValueError('Too many TRE archives in selected folder')
        if name in found and sha(found[name])!=sha(path):raise ValueError('Conflicting duplicate archive: '+name)
        with path.open('rb') as file:
            if file.read(8)!=b'EERT5000':raise ValueError('Unsupported TRE archive: '+path.name)
        found[name]=path
    return found

def collect_sources(root,bundle,installation=None):
    from importlib.util import spec_from_file_location,module_from_spec
    spec=spec_from_file_location('archive_policy',bundle/'tools/assets/archive_policy.py');policy=module_from_spec(spec);spec.loader.exec_module(policy)
    owned=root/'runtime/original-game';owned.mkdir(parents=True,exist_ok=True)
    retained=owned/'tre';receipt=owned/'sources.json'
    if installation is None and receipt.is_file():
        sources=json.loads(receipt.read_text());files={row['filename']:retained/row['filename'] for row in sources['archives']}
        if all(p.is_file() and p.stat().st_size==row['bytes'] for row,p in ((r,files[r['filename']]) for r in sources['archives'])):return files,sources
    if installation is None:
        images=sorted(p for p in (root/'data').iterdir() if p.is_file() and p.suffix.lower()=='.iso')
        if len(images)!=5:raise ValueError('Select your Total Experience installation folder, or place all five Total Experience ISO images in data/. Found '+str(len(images))+' ISO images.')
        media=owned/'cabinets';media.mkdir(exist_ok=True)
        discs=[]
        for index,image in enumerate(images):
            print(f'Reading installation disc {index+1}/5: {image.name}',flush=True)
            discs.append(dict(filename=image.name,bytes=image.stat().st_size,sha256=sha(image),cabinets=extract_cabinets(image,media)))
        supplied={row['name'] for disc in discs for row in disc['cabinets']}
        if not set(['data1.hdr',*[f'data{i}.cab' for i in range(1,7)]]).issubset(supplied):raise ValueError('Incomplete five-disc cabinet set')
        extracted=owned/'extracted';extracted.mkdir(exist_ok=True)
        unshield=bundle/'bin'/('unshield.exe' if os.name=='nt' else 'unshield')
        if not unshield.is_file():raise ValueError('Bundled media extractor missing; reinstall the complete client package')
        print('Extracting local InstallShield cabinets…',flush=True)
        log=owned/'extraction.log'
        listing=subprocess.run([str(unshield),'l',str(media/'data1.cab')],capture_output=True,text=True,check=True).stdout
        names=sorted(set(re.findall(r'([A-Za-z0-9_.-]+\.tre)\s*$',listing,re.M|re.I)))
        if not names or len(names)>256:raise ValueError('Installer cabinet has no bounded TRE inventory')
        # Windows unshield lacks POSIX fnmatch; exact file names work on both.
        with log.open('w') as output:
            subprocess.run([str(unshield),'-D','1','-d',str(extracted),'-j','x',str(media/'data1.cab'),*names],stdout=output,stderr=subprocess.STDOUT,check=True)
        installation=extracted
    else:discs=[]
    files=tre_files(installation)
    missing=sorted(set(policy.CORE3_TRE_PRIORITY)-files.keys())
    if missing:raise ValueError('The selected game data is missing required original archives: '+', '.join(missing))
    retained.mkdir(exist_ok=True);records=[]
    for name,source in sorted(files.items()):
        digest=sha(source);target=retained/name
        if target.resolve()!=source.resolve() and (not target.exists() or sha(target)!=digest):
            temporary=target.with_suffix('.partial');shutil.copy2(source,temporary);temporary.replace(target)
        records.append(dict(filename=name,bytes=target.stat().st_size,sha256=digest,active=name in policy.CORE3_TRE_PRIORITY))
    result=dict(schema=1,installation=str(Path(installation).resolve()),discs=discs,archives=records,active_count=len(policy.CORE3_TRE_PRIORITY),policy='Pinned pre-CU archives take precedence. Additional original archives supply only otherwise absent client assets; no server archive configuration is changed.')
    write(receipt,result)
    return {r['filename']:retained/r['filename'] for r in records},result

def rebase_assets(folder,old,new):
    # A text substitution avoids materializing millions of geometry numbers.
    substitutions=[]
    for value in (str(old),old.as_posix()):
        for separator in ('/','\\'):
            prefix=json.dumps(value+separator+'runtime'+separator)[1:-1].encode()
            replacement=json.dumps(new.as_posix()+'/runtime/')[1:-1].encode()
            substitutions.append((prefix,replacement))
    for path in folder.rglob('*.json'):
        raw=path.read_bytes();changed=raw
        for a,b in substitutions:changed=changed.replace(a,b)
        if changed!=raw:path.write_bytes(changed)

def prepare(root,bundle=None,installation=None,python=None,steps=None):
    root=Path(root).resolve();bundle=Path(bundle or root/'engine/data-preparation').resolve()
    recipe=json.loads((bundle/'recipe.json').read_text());source_files,sources=collect_sources(root,bundle,installation)
    source_signature=hashlib.sha256(json.dumps(sources['archives'],sort_keys=True).encode()).hexdigest()
    signature=recipe['signature']+':'+source_signature
    receipt=root/'GAME_DATA_RECEIPT.json'
    if receipt.is_file():
        previous=json.loads(receipt.read_text())
        if previous.get('signature')==signature and previous.get('workspace')==root.as_posix() and all((root/'runtime/assets'/p).is_file() for p in REQUIRED):
            print('Local game data is current.',flush=True);return previous
    if shutil.disk_usage(root).free<40*1024**3:raise ValueError('Local preparation requires at least 40 GB free for source, conversion and rollback data')
    work=root/'runtime/preparation/workspace';work.mkdir(parents=True,exist_ok=True)
    for name,digest in recipe['files'].items():
        source=bundle/name
        if sha(source)!=digest:raise ValueError('Preparation code checksum mismatch: '+name)
        target=work/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    active=work/'runtime/asset_sources/active_tre';active.mkdir(parents=True,exist_ok=True)
    for row in sources['archives']:
        # TreSet loads unknown archives first, then the pinned 51 in server order.
        # Extra TTE files can fill absent audio/art without overriding that set.
        source=source_files[row['filename']];target=active/row['filename']
        if not target.exists() or target.stat().st_size!=row['bytes'] or sha(target)!=row['sha256']:
            temporary=target.with_suffix('.partial');shutil.copy2(source,temporary);temporary.replace(target)
    write(active/'provenance.json',sources)
    state_path=work/'preparation.json'
    state=json.loads(state_path.read_text()) if state_path.exists() else {}
    if state.get('signature')!=signature:state={'signature':signature,'completed':[]}
    output=work/'runtime/assets'
    if not output.exists() and (root/'runtime/assets').exists():
        print('Staging installed data for local updates…',flush=True)
        shutil.copytree(root/'runtime/assets',output)
        rebase_assets(output,root,work)
        state['completed']=[]
    if not output.exists():state['completed']=[]
    env=dict(os.environ);env['PATH']=str(bundle/'bin')+os.pathsep+env.get('PATH','');env['PYTHONPATH']=str(work);env['PYTHONUTF8']='1'
    logs=root/'runtime/preparation/logs';logs.mkdir(parents=True,exist_ok=True)
    python=str(python or sys.executable)
    for index,(name,arguments) in enumerate(steps or STEPS):
        if name in state['completed']:continue
        print(f'Preparing {name} ({index+1}/{len(steps or STEPS)})…',flush=True)
        log=logs/(name+'.log')
        with log.open('w') as stream:
            result=subprocess.run([python,str(work/arguments[0]),*arguments[1:]],cwd=work,env=env,stdout=stream,stderr=subprocess.STDOUT)
        if result.returncode:raise ValueError(f'Preparation failed at {name}; details: {log}. Existing assets are preserved. Retry resumes completed steps.')
        state['completed'].append(name);write(state_path,state)
    missing=[p for p in REQUIRED if not (output/p).is_file()]
    if missing:raise ValueError('Prepared data is incomplete: '+', '.join(missing))
    planets=json.loads((output/'planets/catalog.json').read_text())
    if len(planets.get('planets',{}))!=10 or not all(r.get('ready') for r in planets['planets'].values()):raise ValueError('Original ground planet preparation is incomplete')
    rebase_assets(output,work,root)
    installed=root/'runtime/assets';backup=root/'runtime/preparation'/('previous-assets-'+str(time.time_ns()))
    if installed.exists():installed.replace(backup)
    try:output.replace(installed)
    except BaseException:
        if backup.exists():backup.replace(installed)
        raise
    result=dict(schema=1,signature=signature,workspace=root.as_posix(),source_archives=len(source_files),recipe=recipe['signature'],completed=state['completed'],asset_backup=str(backup) if backup.exists() else None,ready=True)
    write(receipt,result)
    print('Original game data prepared. Source archives retained for future updates.',flush=True)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);p.add_argument('--bundle',type=Path);p.add_argument('--installation',type=Path)
    a=p.parse_args()
    try:prepare(a.root,a.bundle,a.installation)
    except (OSError,ValueError,subprocess.CalledProcessError) as e:print(str(e),file=sys.stderr);raise SystemExit(2)
