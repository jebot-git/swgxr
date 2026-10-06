#!/usr/bin/env python3
"""Original player structure POB geometry/floors, kept in ignored runtime assets."""
import argparse,hashlib,json,re
from pathlib import Path
from static_assets import StaticAssets
ROOT=Path(__file__).resolve().parents[2]
def prepare(tre,out):
 out.mkdir(parents=True,exist_ok=True);assets=StaticAssets(tre,out);catalog={'schema_version':1,'structures':{},'failures':[]}
 scripts=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/deed'
 templates=sorted({v for p in scripts.rglob('*.lua') for v in re.findall(r'generatedObjectTemplate\s*=\s*"(object/(?:building|installation)/[^"]+)"',p.read_text())})
 for template in templates:
  try:
   path=Path(template);shared=str(path.parent/('shared_'+path.name.removeprefix('shared_')))
   instances,cells,_=assets.place({'id':1,'parent':0,'template':shared,'p':[0,0,0],'q':[1,0,0,0]},[0,0,0])
   if not instances:raise ValueError('No original structure geometry')
   meshes={k:json.loads((out/assets.meshes[k]['path']).read_text()) for k in {i['mesh'] for i in instances}}
   collision_ids={i['collision_id'] for i in instances if 'collision_id' in i}
   data={'origin':[0,0,0],'instances':instances,'cells':cells,'meshes':meshes,'collisions':{k:assets.collisions[k] for k in collision_ids},'provenance':assets.dependencies.copy()}
   filename=hashlib.sha256(template.encode()).hexdigest()[:20]+'.json';(out/filename).write_text(json.dumps(data,separators=(',',':')))
   catalog['structures'][template]={'path':filename,'shared_template':shared,'cells':len(cells),'sha256':hashlib.sha256((out/filename).read_bytes()).hexdigest()}
  except Exception as exc:catalog['failures'].append({'template':template,'error':str(exc)})
 catalog['conversion_failures']=assets.failures;catalog['provenance']=assets.dependencies
 (out/'catalog.json').write_text(json.dumps(catalog,indent=2));print(json.dumps({'ready':len(catalog['structures']),'failures':catalog['failures']}))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/assets/active_tre');p.add_argument('--out',type=Path,default=ROOT/'runtime/assets/housing');a=p.parse_args();prepare(a.tre_dir,a.out)
