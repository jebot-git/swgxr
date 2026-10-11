#!/usr/bin/env python3
"""Audit prepared native race/wearable coverage and original skin binding."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 directory=ROOT/'runtime/assets/inventory';catalog=json.loads((directory/'catalog.json').read_text())
 characters=ROOT/'runtime/assets/characters';races=json.loads((characters/'catalog.json').read_text())['races']
 selection=catalog['wearable_assets'];rules=selection['race_restrictions'];errors=[];unresolved=[];coverage={}
 for race in races:
  raw=(characters/races[race]['body']).read_bytes();body=json.loads(raw);owner_hash=hashlib.sha256(raw).hexdigest()
  variants=catalog.get('equipment',{}).get(race,{});required=0;ready=0;triangles=0
  for template in selection['templates']:
   allowed=rules.get(template,[])
   if allowed and 'object/creature/player/'+race+'.iff' not in allowed:continue
   required+=1;item=variants.get(template)
   if not item:errors.append(f'{race}: missing selection {template}');continue
   if item.get('status')!='ready':
    unresolved.append({'race':race,'template':template,'failures':item.get('failures',[])})
    if not item.get('failures'):errors.append(f'{race}: unexplained unsupported {template}')
    continue
   try:
    raw=(directory/item['model']).read_bytes();assert hashlib.sha256(raw).hexdigest()==item['model_sha256'],'model hash'
    model=json.loads(raw)
    if item['kind']=='skinned':
     assert item['source_owner_model_sha256']==owner_hash,'owner body hash'
     assert model['bones']==body['bones'],'original bone names, indices, hierarchy and rest poses'
     for part in model['parts']:
      for surface in part['mesh']['surfaces']:
       assert len(surface['bones'])==len(surface['weights'])==len(surface['vertices'])//3*8,'influence count'
       assert all(0<=bone<len(body['bones']) for bone in surface['bones']),'bone index'
       assert (directory/surface['texture']).is_file(),'material texture'
       triangles+=len(surface['indices'])//3
    ready+=1
   except Exception as error:errors.append(f'{race}: {template}: {error}')
  coverage[race]={'native_allowed':required,'ready':ready,'unresolved':required-ready,'triangles':triangles}
 mabari=[u for u in unresolved if '/armor/zam/' in u['template']]
 errors.extend('Mabari unresolved: '+str(u) for u in mabari)
 concrete=[u for u in unresolved if '/base/' not in u['template'] and not u['template'].endswith('_base.iff')]
 report={'passed':not errors,'coverage_complete':not concrete,'races':coverage,'registered_templates':len(selection['templates']),'unresolved':unresolved,'unresolved_concrete':concrete,'errors':errors,'native_restrictions_respected':True,'original_media_committed':False,'gpu_validated':False}
 (ROOT/'runtime/evidence/player-equipment-audit.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items() if k not in ('unresolved','unresolved_concrete')}));return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
