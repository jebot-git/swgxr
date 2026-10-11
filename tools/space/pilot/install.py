#!/usr/bin/env python3
"""Install the validated local pilot source bundle into the pinned Core3 tree.
Original dialogue and generated source are never written into the tracked repo.
"""
import argparse
import hashlib
import json
import shutil
import os
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle',type=Path,default=ROOT/'runtime/server/pilot-source')
    parser.add_argument('--core',type=Path,default=ROOT/'vendor/Core3')
    args=parser.parse_args();bundle=args.bundle
    mapping=json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text())
    if not (bundle/'conversion.json').exists():
        raise SystemExit('Pilot bundle is not prepared. Run tools/space/pilot/prepare.py with a javalang-enabled Python environment; see docs/PILOT_MISSIONS.md.')
    conversions=json.loads((bundle/'conversion.json').read_text())
    if conversions['errors']:raise SystemExit('Pilot conversation conversion has errors')
    programs={row['name'] for row in conversions['sources']}
    if not set(mapping.values())<=programs:raise SystemExit('Trainer program missing')
    # The package may be prepared with unresolved references for diagnosis, but
    # installation must not silently enable an incomplete progression graph.
    quests=json.loads((bundle/'quests.json').read_text())
    if quests['errors']:raise SystemExit('Pilot mission graph has unresolved references; inspect quests.json')
    for row in conversions['sources']:
        if row['name'] not in mapping.values():continue
        path=bundle/(row['name']+'.lua')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=row['output_sha256']:
            raise SystemExit('Generated pilot program changed since conversion: '+row['name'])
    scripts=args.core/'MMOCoreORB/bin/scripts'
    target=scripts/'screenplays/space/swgxr_pilot';target.mkdir(parents=True,exist_ok=True)
    paths=[]
    def copy(src,dst):
        # A running reader can see either complete version, never a truncated file.
        with tempfile.NamedTemporaryFile(dir=dst.parent,delete=False) as stream:
            temporary=Path(stream.name);stream.write(src.read_bytes())
        temporary.chmod(0o644);os.replace(temporary,dst)
    for name in ['source_runtime','quest_runtime','objective_runtime']:
        src=ROOT/'server/jtl/pilot'/(name+'.lua');dst=target/src.name;copy(src,dst);paths.append(dst)
    for name in sorted(set(mapping.values())):
        src=bundle/(name+'.lua');dst=target/src.name;copy(src,dst);paths.append(dst)
    for name in ('quests.lua','dialogue.lua'):
        copy(bundle/name,target/name);paths.append(target/name)
    code=['includeFile("space/swgxr_pilot/source_runtime.lua")', 'includeFile("space/swgxr_pilot/quest_runtime.lua")', 'includeFile("space/swgxr_pilot/objective_runtime.lua")']
    code.append('includeFile("space/swgxr_pilot/quests.lua")')
    code.append('includeFile("space/swgxr_pilot/dialogue.lua")')
    for name in sorted(set(mapping.values())):
        code.extend(['includeFile("space/swgxr_pilot/'+name+'.lua")','PilotSource.bind("'+name+'")'])
    (target/'registration.lua').write_text('\n'.join(code)+'\n');paths.append(target/'registration.lua')
    manifest={'version':1,'trainers':mapping,'quest_count':quests['compiled'],'files':[{'path':str(p.relative_to(args.core)), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}
    (bundle/'installed.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'trainers':len(mapping),'missions':quests['compiled'],'installed_files':len(paths)}))
if __name__=='__main__':main()
