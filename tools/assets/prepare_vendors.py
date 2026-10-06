#!/usr/bin/env python3
"""Prepare original native vendor model previews, recording unsupported assets."""
from pathlib import Path
import json, subprocess, sys, hashlib
ROOT=Path(__file__).resolve().parents[2]
CORE=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'
def templates():
 result=[]
 for folder in ['object/tangible/vendor','object/mobile/vendor']:
  for source in sorted((CORE/folder).glob('*.lua')):
   if source.name in ('objects.lua','serverobjects.lua'):continue
   result.append(source.relative_to(CORE).with_suffix('.iff').as_posix())
 return result
if __name__=='__main__':
 names=templates();command=[sys.executable,str(ROOT/'tools/assets/prepare_inventory.py')]
 catalog_path=ROOT/'runtime/assets/inventory/catalog.json'
 existing=json.loads(catalog_path.read_text()).get('items',{}) if catalog_path.exists() else {}
 for name in names:
  if existing.get(name,{}).get('status')!='ready' or (name.startswith('object/mobile/vendor/') and not existing.get(name,{}).get('vendor_morphs')):command+=['--template',name]
 subprocess.run(command,cwd=ROOT,check=True)
 catalog=json.loads(catalog_path.read_text())
 sys.path.insert(0,str(ROOT))
 from server.creation_catalog import appearance_controls
 from server.character_protocol import assets
 controls={}
 for name in names:
  try:controls[name]=appearance_controls(catalog['items'][name]['appearance'])
  except ValueError:controls[name]=[]
 output=ROOT/'runtime/assets/vendors/customization.json';output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(controls,indent=2)+'\n')
 provenance={'customization/asset_customization_manager.iff'}|{control['palette'] for rows in controls.values() for control in rows if control.get('palette')}
 report={'customization_sources':{name:hashlib.sha256(assets().read(name)).hexdigest() for name in sorted(provenance)},'source':'Core3 vendor templates and supplied original TRE appearances','templates':names,'ready':[],'unsupported':[]}
 for name in names:
  item=catalog.get('items',{}).get(name,{})
  report['ready' if item.get('status')=='ready' else 'unsupported'].append({'template':name,'failures':item.get('failures',[])})
 path=ROOT/'runtime/assets/vendors/coverage.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'ready':len(report['ready']),'unsupported':len(report['unsupported']),'coverage':str(path)}))
