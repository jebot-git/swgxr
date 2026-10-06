#!/usr/bin/env python3
"""Local-only full user-requested loadout proof on fresh invtest account."""
import json,re,secrets,time,os
from services_smoke import ROOT,req,redact
from equipment_smoke import console
from prepare_test_character import build_lua

def main():
 manifest=json.loads((ROOT/'runtime/evidence/live-test-loadout/manifest.json').read_text());checks=[];responses=[];session='';added='';script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 owner={'account':'invtestloadout'+secrets.token_hex(4),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(9))};ctx={'position':[3530,5,-4810],'zone':'tatooine','building_id':'0','cell_index':0}
 if os.environ.get('SWGXR_PROVISION_RESUME')=='1':
  owner=json.loads((ROOT/'runtime/evidence/test-character-provision-native.json').read_text())['fixture'];assert owner['account'].startswith('invtestloadout')
 report={'passed':False,'native_execution':True,'remote_server_changed':False,'fixture':owner,'checks':checks,'responses':responses,'provisioning':'Explicit trusted admin test loadout; original skill/item/deed/pet operations, not earned progression'}
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def call(path,**kw):
  out=req(path+'?account='+owner['account']+'&character_id='+owner['id']) if path=='/inventory' else req(path,dict(account=owner['account'],character_id=owner.get('id',''),**kw));responses.append({'path':path,'response':redact(out)});return out
 def lua(fn):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+fn)
  for _ in range(1200):
   with log.open()as f:f.seek(offset);tail=f.read()
   found=re.search('runLuaFunction Tests:'+fn+r': result=([^\n]+)',tail)
   if found:return found[1].strip().strip('[]')
   if 'Failed to runLuaFunction'in tail or 'Exception in runLuaFunction'in tail:raise RuntimeError(tail[-1600:])
   time.sleep(.1)
  raise RuntimeError('Timed out '+fn)
 def start():
  nonlocal session
  entry=call('/enter');check('source_location'in entry,'Actual native character entry');loc=entry['source_location'];opened=call('/session/start',**{k:loc[k]for k in ctx});session=opened.get('session_id','');check(bool(session),'Owned persistent gameplay session opens');return call('/session/update',session_id=session,ready=True,**ctx)
 def vehicles(action='status',**kw):
  if action!='status':kw.setdefault('request_id','provision_'+secrets.token_hex(8))
  return call('/vehicles/'+action,live_session_id=session,**ctx,**kw)
 def wait_pet(device,spawned):
  for _ in range(80):
   state=vehicles()['state'];r=next(r for r in state['pet_datapad']if r['id']==device)
   if bool(r.get('spawned',False))==spawned:return state
   time.sleep(.5)
  raise AssertionError('Pet spawn/storage not completed')
 def store_pet(device):
  time.sleep(1.1)
  result=vehicles('pet_recall',device_id=device)
  check(result.get('mutation',{}).get('success'),'Original pet recall accepted '+device)
  wait_pet(device,False);time.sleep(1.1)
 def prove_pet(device,label):
  state=vehicles()['state']
  for active in state.get('pet_datapad',[]):
   if active.get('spawned',False):store_pet(active['id'])
  result=vehicles('pet_call',device_id=device)
  check(result.get('mutation',{}).get('success'),label+' native call accepted')
  wait_pet(device,True);check(True,label+' actually spawned from original control device')
  store_pet(device)
 try:
  for _ in range(5):
   created={'character':{'id':owner['id']}} if 'id'in owner else req('/characters',dict(owner,species='human',profession='crafting_artisan'))
   if 'character'in created:break
   owner['name']='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(9))
  check('character'in created,'Fresh isolated native character created');owner['id']=created['character']['id'];start()
  existing=vehicles()['state'];old_vehicles={r['template']for r in existing['datapad']};manifest['vehicle_deeds']=[d for d,v in zip(manifest['vehicle_deeds'],manifest['vehicle_templates'])if v not in old_vehicles]
  added=build_lua(manifest,owner['id'],owner['name'],'swgxr_proof_'+owner['id']);script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.5)
  check(lua('swgxrProvisionSkills')=='skills:'+str(len(manifest['topological_skills'])),'All486 original boxes granted with bounded per-character cap override')
  status=call('/services/status',live_session_id=session,**ctx);check(set(manifest['master_skills'])<=set(status['state']['skills']),'All27 implemented master skills present in authoritative snapshot')
  check(lua('swgxrProvisionItems')=='items:'+str(len(manifest['inventory_templates'])),'Requested original inventory items exist; original starter duplicates reused')
  inv=call('/inventory');templates={r['template']for r in inv['items']};check(set(manifest['inventory_templates'])<=templates,'Native inventory readback includes the exact requested medical tool, instruments and tools')
  for index,row in enumerate(manifest['vehicle_devices']):
   check(lua('swgxrProvisionVehicle'+str(index))=='vehicle_ready','Original trusted vehicle control device '+row['template'].rsplit('/',1)[-1])
  vehicle_state=vehicles()['state'];check(set(manifest['vehicle_templates'])<={r['template']for r in vehicle_state['datapad']},'All six native vehicle control devices exist')
  for device in vehicle_state['datapad']:
   result=vehicles('call',device_id=device['id']);check(result.get('mutation',{}).get('success'),'Native vehicle can be called '+device['template'].rsplit('/',1)[-1]);time.sleep(.4);result=vehicles('recall',device_id=device['id']);check(result.get('mutation',{}).get('success'),'Native vehicle can be stored '+device['template'].rsplit('/',1)[-1])
  for index,row in enumerate(manifest['droids']):
   check(lua('swgxrProvisionDroid'+str(index))in ('droid_ready','already_done'),'Original '+row['type']+' deed creates owned droid')
   state=vehicles()['state'];device=next(p['id']for p in state['pet_datapad']if p['template']==row['template']);prove_pet(device,row['type'])
  for index,row in enumerate(manifest['pets']):
   check(lua('swgxrProvisionPet'+str(index))in ('pet_ready','already_done'),'Original '+row['mobile']+' pet grant and duplicate ownership rejection')
   state=vehicles()['state'];device=next(p['id']for p in state['pet_datapad']if p['pet_kind']=='creature' and row['mobile']in p['template']);prove_pet(device,row['mobile'])
  call('/combat/session/stop',session_id=session);session='';start();status=call('/services/status',live_session_id=session,**ctx);check(set(manifest['master_skills'])<=set(status['state']['skills']),'All27 masters survive independent native logout/login')
  state=vehicles()['state'];companions={r['template']for r in state['pet_datapad']};check(set(manifest['vehicle_templates'])<={r['template']for r in state['datapad']} and all(r['template'] in companions for r in manifest['droids']) and all(any(r['mobile'] in t for t in companions)for r in manifest['pets']),'Six vehicles, two exact droids and two exact creature pets persist after fresh login');report['passed']=True
 finally:
  if session:
   try:call('/combat/session/stop',session_id=session)
   except Exception:pass
  if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/test-character-provision-native.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
