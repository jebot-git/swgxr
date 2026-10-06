#!/usr/bin/env python3
"""Explicit create/verify phases for the user-authorized new blux test character.

Trusted admin grants are separate: this tool only emits their exact-ID Lua file.
It never reads/changes a password or applies grants to an existing character.
"""
import argparse,json,secrets,sys,time,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/client'))
from remote_connection import RemoteConnection
from prepare_test_character import build_lua
from services_smoke import redact
OUT=ROOT/'runtime/evidence/live-test-loadout'

def main():
 p=argparse.ArgumentParser();p.add_argument('phase',choices=['create','verify']);p.add_argument('--profile',type=Path,required=True);a=p.parse_args()
 remote=RemoteConnection.load(a.profile);assert remote.account=='blux','This authorized fixture is for account blux only'
 manifest=json.loads((OUT/'manifest.json').read_text());fixture_path=OUT/'remote-character.json';responses=[];checks=[]
 def call(path,data=None):
  result=remote.request_json(path,method='POST' if data is not None else 'GET',body=data,timeout=70);responses.append({'path':path,'response':redact(result)});return result
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 if a.phase=='create':
  assert not fixture_path.exists(),'Refusing to create a duplicate fixture'
  listing=call('/characters?account=blux');old=listing.get('characters',[]);name=manifest['requested_name']
  check(not any(r.get('name','').lower()==name.lower()for r in old),'Requested new name is not an existing character')
  created=call('/characters',{'account':'blux','name':name,'species':'human','sex':'male','profession':'crafting_artisan'})
  char=created['character'];check(char['id'] not in {r['id']for r in old},'Native creation returned a new unique character ID')
  fixture={'account':'blux','name':char['name'],'id':char['id'],'original_character_ids':[r['id']for r in old],'created_by_this_task':True}
  fixture_path.write_text(json.dumps(fixture,indent=2)+'\n')
  entered=call('/enter',{'account':'blux','character_id':fixture['id']});loc=entered['source_location'];fixture['original_location']=loc
  keys=('position','zone','building_id','cell_index');ctx={k:loc[k]for k in keys};opened=call('/session/start',{'account':'blux','character_id':fixture['id'],**ctx});fixture['session_id']=opened['session_id'];fixture['context']={'position':[3530,5,-4810],'zone':'tatooine','building_id':'0','cell_index':0}
  fixture_path.write_text(json.dumps(fixture,indent=2)+'\n')
  call('/session/update',{'account':'blux','character_id':fixture['id'],'session_id':fixture['session_id'],'ready':True,**fixture['context']})
  tag='swgxr_blux_'+fixture['id'];lua=build_lua(manifest,fixture['id'],fixture['name'],tag);(OUT/'remote-provision.lua').write_text(lua)
  (OUT/'remote-create.json').write_text(json.dumps({'passed':True,'checks':checks,'responses':responses,'fixture':fixture},indent=2)+'\n')
  print(json.dumps({'name':fixture['name'],'id':fixture['id'],'script':str(OUT/'remote-provision.lua'),'session_open':True}))
  return
 fixture=json.loads(fixture_path.read_text());assert fixture['created_by_this_task'] and fixture['account']=='blux' and fixture['id']not in fixture['original_character_ids']
 base={'account':'blux','character_id':fixture['id']};session=fixture['session_id'];ctx=fixture['context'];report={'passed':False,'fixture':fixture,'checks':checks,'responses':responses}
 def service(action,**kw):return call('/services/'+action,{**base,'live_session_id':session,**ctx,**kw})
 def vehicle(action='status',**kw):
  if action!='status':kw['request_id']='loadout_'+secrets.token_hex(10)
  return call('/vehicles/'+action,{**base,'live_session_id':session,**ctx,**kw})
 try:
  skills=service('status')['state']['skills'];check(set(manifest['master_skills'])<=set(skills),'All27 implemented masters authoritative on new blux character')
  inv=call('/inventory?account=blux&character_id='+fixture['id']);templates={r['template']for r in inv['items']};check(set(manifest['inventory_templates'])<=templates,'Every requested original inventory template present')
  state=vehicle()['state'];check(set(manifest['vehicle_templates'])<={r['template']for r in state['datapad']},'All six functional native vehicle devices present')
  pets={r['template']for r in state['pet_datapad']};check(all(r['template']in pets for r in manifest['droids'])and all(any(r['mobile']in t for t in pets)for r in manifest['pets']),'Exact requested R4 R5 cu_pa and bantha control devices present')
  for pet in state['pet_datapad']:
   if not pet.get('spawned'):continue
   time.sleep(1.2);result=vehicle('pet_recall',device_id=pet['id']);check(result.get('mutation',{}).get('success'),'Store active companion without destroying its device')
   for _ in range(40):
    if not next(r for r in vehicle()['state']['pet_datapad']if r['id']==pet['id']).get('spawned'):break
    time.sleep(.5)
   else:raise AssertionError('Native companion storage timed out')
  original={k:fixture['original_location'][k]for k in ('position','zone','building_id','cell_index')}
  call('/session/update',{**base,'session_id':session,'ready':True,**original});call('/combat/session/stop',{**base,'session_id':session});session=''
  entered=call('/enter',base);check(entered['source_location']['zone']=='tatooine' and entered['source_location']['cell_index']==original['cell_index'] and str(entered['source_location']['building_id'])==str(original['building_id']) and math.dist(entered['source_location']['position'],original['position'])<0.25,'Independent login restores original Tatooine creation cell')
  opened=call('/session/start',{**base,**original});session=opened['session_id'];ctx=original;call('/session/update',{**base,'session_id':session,'ready':True,**ctx})
  skills=service('status')['state']['skills'];check(set(manifest['master_skills'])<=set(skills),'All27 masters persist across independent remote login')
  state=vehicle()['state'];pets={r['template']for r in state['pet_datapad']};check(set(manifest['vehicle_templates'])<={r['template']for r in state['datapad']}and all(r['template']in pets for r in manifest['droids'])and all(any(r['mobile']in t for t in pets)for r in manifest['pets']),'All ten requested vehicle and companion devices persist')
  inv=call('/inventory?account=blux&character_id='+fixture['id']);check(set(manifest['inventory_templates'])<={r['template']for r in inv['items']},'All requested original inventory items persist after independent login')
  report['passed']=True;report['final_enter']=entered
 finally:
  if session:
   try:call('/combat/session/stop',{**base,'session_id':session});fixture['session_id']='';fixture['session_closed']=True
   except Exception:fixture['session_closed']=False
  fixture_path.write_text(json.dumps(fixture,indent=2)+'\n');(OUT/'remote-verified.json').write_text(json.dumps(redact(report),indent=2)+'\n')
 print(json.dumps({'passed':report['passed'],'checks':len(checks),'name':fixture['name'],'id':fixture['id'],'session_closed':fixture.get('session_closed',False)}))
if __name__=='__main__':main()
