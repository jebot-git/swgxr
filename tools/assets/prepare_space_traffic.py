#!/usr/bin/env python3
"""Convert original NPC hulls referenced by the installed Core3 ship mobiles."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from prepare_space_sectors import SectorAssets, ROOT, SCRIPTS, dump

def prepare(tre,out):
    out=Path(out);assets=SectorAssets(tre,out);catalog=json.loads((out/'catalog.json').read_text())
    names=set()
    for file in (SCRIPTS/'ship_mobile/ships').glob('*.lua'):
        names.update(re.findall(r'\btemplate\s*=\s*"([a-z0-9_]+)"',file.read_text()))
    descriptors={};templates={};failures=[]
    for name in sorted(names):
        template='object/ship/'+name+'.iff';source='object/ship/shared_'+name+'.iff'
        definition=SCRIPTS/'object/ship'/(name+'.lua')
        if definition.exists():
            match=re.search(r'=\s*object_ship_shared_([a-z0-9_]+):new',definition.read_text())
            if match:source='object/ship/shared_'+match[1]+'.iff'
        before=len(assets.failures)
        try:
            parts=assets.resolve(source)
            if not parts:raise ValueError('No original triangles')
            signature=tuple(p['mesh'] for p in parts)
            if signature not in descriptors:
                path='npc_'+hashlib.sha256('|'.join(signature).encode()).hexdigest()[:20]+'.json'
                stage=assets.static_stage([dict(mesh=p['mesh'],position=[0,0,0],quaternion=[0,0,0,1],source_template=source) for p in parts])
                stage['conversion_failures']=assets.failures[before:]
                digest=dump(out/path,stage);descriptors[signature]=(path,digest)
            path,digest=descriptors[signature]
            templates[template]=dict(kind='npc',exterior_descriptor=path,exterior_sha256=digest,shared_template=source)
        except (KeyError,ValueError,AssertionError) as error:
            failures.append(dict(template=template,source=source,error=str(error)))
    catalog['templates'].update(templates);catalog['npc_provenance']=assets.dependencies
    catalog['npc_conversion_failures']=failures+assets.failures;dump(out/'catalog.json',catalog)
    print(json.dumps(dict(native_templates=len(names),converted=len(templates),unique_hulls=len(descriptors),failures=failures+assets.failures)),flush=True)
    return failures+assets.failures
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');parser.add_argument('--out',type=Path,default=ROOT/'runtime/assets/jtl')
    args=parser.parse_args();raise SystemExit(1 if prepare(args.tre_dir,args.out) else 0)
