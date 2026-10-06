#!/usr/bin/env python3
"""Native CH proof. Only fresh invtestch fixtures receive labelled admin setup."""
import json,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 checks=[];records=[];owners=[];sessions={};added='';spawned=[]
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 marker='swgxr_ch_'+secrets.token_hex(5)
 report=dict(passed=False,native_execution=True,remote_server_changed=False,headset_tested=False,checks=checks,responses=records,fixtures=owners,
  fixture_setup='Fresh isolated novice scout accounts. Trusted server screenplay gives ONLY primary original Creature Handler master prerequisites, spawns original wild bantha baby, and later matures the genuinely tamed owned pet through original growPet. These are labelled administrator prerequisites, not earned progression. Tame, training probability, XP, buffs, costs, cooldown and mount training use normal native actions without force/adult arguments.')
 def check(value,label):
  checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True)
  if not value:raise AssertionError(label)
 def call(o,path,**kw):
  for attempt in range(15):
   out=req(path,dict(account=o['account'],character_id=o['id'],**kw));records.append(dict(path=path,owner=o['id'],response=redact(out)))
   if out.get('error_code')!='backend_busy' or out.get('mutation_started')is not False:return out
   time.sleep(1)
  return out
 def pet(o,a,**kw):
  if a not in ('status','ch_status'):kw.setdefault('request_id','ch_'+secrets.token_hex(12))
  return call(o,'/vehicles/'+a,live_session_id=sessions[o['id']],zone='tatooine',**kw)
 def state(o):return pet(o,'ch_status')
 def denied(out):return out.get('http_error')==400 or out.get('mutation',{}).get('success')is False
 def start(o):
  entry=call(o,'/enter');loc=entry['source_location'];context={k:loc[k]for k in ('position','zone','building_id','cell_index')};opened=call(o,'/combat/session/start',**context);sessions[o['id']]=opened['session_id'];call(o,'/session/update',session_id=opened['session_id'],ready=True,**context)
 def lua(function):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+function)
  for _ in range(100):
   with log.open()as f:f.seek(offset);text=f.read()
   if 'runLuaFunction Tests:'+function+': result='in text:return
   if 'Failed to runLuaFunction'in text or 'Exception in runLuaFunction'in text:raise RuntimeError(text[-2000:])
   time.sleep(.1)
  raise RuntimeError('Native screenplay fixture timed out')
 def row(out,device):return next(r for r in out['state']['pet_datapad']if r['id']==device)
 try:
  for _ in range(2):
   o=dict(account='invtestch'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(7)));created=req('/characters',dict(o,species='human',profession='outdoors_scout'));assert 'character'in created,created;o['id']=created['character']['id'];owners.append(o);start(o)
  owner,other=owners
  added=f'''
-- BEGIN {marker}
function Tests:swgxrCHSetup()
 local p=getSceneObject({owner['id']}) if p==nil then return end
 local z=getTerrainHeight(p,3527,-4810)
 SceneObject(p):teleport(3527,z,-4810,0)
 local q=getSceneObject({other['id']}) if q~=nil then SceneObject(q):teleport(3527,z,-4812,0) end
 local m=spawnBabyMobile("tatooine","bantha",0,3529,z,-4810,0,0)
 if m~=nil then SceneObject(m):setCustomObjectName("SWGXR isolated CH baby");writeData("{marker}:baby",SceneObject(m):getObjectID()) end
 local adult=spawnMobile("tatooine","bantha",0,3531,z,-4810,0,0)
 if adult~=nil then SceneObject(adult):setCustomObjectName("SWGXR isolated CH adult");writeData("{marker}:adult",SceneObject(adult):getObjectID()) end
end
function Tests:swgxrCHSkills()
 local p=getSceneObject({owner['id']}) if p~=nil then awardSkill(p,"outdoors_creaturehandler_master") end
end
function Tests:swgxrCHMature()
 local p=getSceneObject({owner['id']});local m=getSceneObject(readData("{marker}:baby"));if p~=nil and m~=nil then growCreaturePet(p,m) end
end
function Tests:swgxrCHCleanup()
 local a=getSceneObject(readData("{marker}:adult"));if a~=nil then SceneObject(a):destroyObjectFromWorld() end
 local p=getSceneObject({owner['id']});local m=getSceneObject(readData("{marker}:baby"));if m~=nil and p~=nil then CreatureObject(p):clearCombatState(true);CreatureObject(m):clearCombatState(true);if not AiAgent(m):isPet() then SceneObject(m):destroyObjectFromWorld() end end
 deleteData("{marker}:adult");deleteData("{marker}:baby")
end
-- END {marker}
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');lua('swgxrCHSetup')
  base=state(owner);check(base.get('mutation',{}).get('success')and 'outdoors_creaturehandler_novice'not in base['state']['creature_handler']['skills'],'Original novice scout has no CH diagnostic grants')
  check(denied(pet(owner,'ch_embolden'))and denied(pet(owner,'ch_enrage')),'Unlearned pet buffs rejected natively')
  snap=base['live_response'];actors=snap.get('snapshot',snap).get('world',{}).get('actors',[])
  if not actors:actors=snap.get('snapshot',{}).get('actors',[])
  baby=next(a for a in actors if a.get('name')=='SWGXR isolated CH baby');adult=next(a for a in actors if a.get('name')=='SWGXR isolated CH adult')
  check(denied(pet(owner,'ch_tame',target_id=baby['id'])),'Taming rejects missing original CH novice')
  lua('swgxrCHSkills');advanced=state(owner);check('outdoors_creaturehandler_master'in advanced['state']['creature_handler']['skills'],'Labelled fixture original master prerequisites observed')
  candidates=advanced['state']['creature_handler']['candidates'];candidate=next(c for c in candidates if c['id']==baby['id']);check(candidate['can_tame']and candidate['baby']and candidate['bounds_radius']>0 and candidate['bounds_source']=='original_converted_creature_mesh','Original wild baby eligibility and source appearance bounds available')
  check(denied(pet(owner,'ch_tame',target_id=adult['id'])),'Adult cannot be tamed through gesture API')
  p=candidate['position'];far=dict(position=[p[0]+30,p[1],p[2]],building_id='0',cell_index=0)
  check(denied(pet(owner,'ch_tame',target_id=baby['id'],**far)),'Native tame range enforced')
  near=dict(position=[p[0]-2,p[1],p[2]],building_id='0',cell_index=0)
  xp=advanced['state']['creature_handler']['experience'].get('creaturehandler',0);key='ch_tame_'+secrets.token_hex(12)
  started=pet(owner,'ch_tame',target_id=baby['id'],request_id=key,**near);check(started.get('mutation',{}).get('success')and started['mutation'].get('pending')and started['state']['creature_handler']['taming']['state']=='pending','Original TameCreatureTask starts pending; command acceptance is not success')
  repeat=pet(owner,'ch_tame',target_id=baby['id'],request_id=key);check(repeat['mutation'].get('replayed')and repeat['state']['creature_handler']['taming']['state']=='pending','Duplicate tame does not schedule a second task')
  for attempt in range(5):
   deadline=time.monotonic()+38
   while time.monotonic()<deadline:
    result=state(owner);progress=result['state']['creature_handler']['taming']
    if progress['state']!='pending':break
    time.sleep(1)
   if progress['state']=='succeeded':break
   if attempt==4:break
   pet(owner,'ch_tame',target_id=baby['id'])
  check(progress['state']=='succeeded','Original asynchronous probability produces real owned pet control device')
  device=progress['device_id'];petrow=row(result,device)
  check(petrow['pet_id']==baby['id']and petrow['pet_kind']=='creature','Actually tamed native creature appears once in owned datapad')
  check(result['state']['creature_handler']['experience'].get('creaturehandler',0)>xp,'Original tame task awards real CH XP')
  check(denied(pet(other,'ch_train_command',device_id=device,command_id=1)),'Other player cannot train owned creature')
  check(denied(pet(owner,'ch_train_mount',device_id=device,hand=p)),'Baby pet cannot bypass original mount size requirement')
  saw_failure=False;trained=False
  for option in petrow['creature_handler']['train_commands']:
   before=state(owner)['state']['creature_handler']['experience'].get('creaturehandler',0);n=option['command_id'];reqid='ch_train_'+secrets.token_hex(10)
   response=pet(owner,'ch_train_command',device_id=device,command_id=n,request_id=reqid)
   if not response.get('mutation',{}).get('success'):continue
   replay=pet(owner,'ch_train_command',device_id=device,command_id=n,request_id=reqid)
   check(replay['mutation'].get('replayed')and replay['mutation']['learned']==response['mutation']['learned'],'Training attempt replay retains original probability result')
   after=replay['state']['creature_handler']['experience'].get('creaturehandler',0)
   if not response['mutation']['learned']:
    saw_failure=True;check(after==before,'Failed original training roll awards no XP and does not unlock command')
    for _ in range(16):
     response=pet(owner,'ch_train_command',device_id=device,command_id=n)
     if response['mutation'].get('learned'):break
   if response['mutation'].get('learned'):
    trained=True;check(any(c['command_id']==n for c in row(response,device)['commands']),'Successful native training unlocks existing pet command wheel')
   if saw_failure and trained:break
  report['observed_failed_training_roll']=saw_failure
  check(trained,'Both native training failure and eventual successful learning observed'if saw_failure else 'Native commands learned; no failed random roll occurred in this run')
  before=state(owner);mind=before['live_response']['snapshot']['player']['raw_ham'][2]
  buff=pet(owner,'ch_embolden',request_id='ch_embolden_once_'+marker);check(buff.get('mutation',{}).get('success')and row(buff,device)['creature_handler']['emboldened'],'Original embolden applies native buff')
  check(buff['live_response']['snapshot']['player']['raw_ham'][2]<mind,'Original embolden charges native mind cost')
  duplicate=pet(owner,'ch_embolden',request_id='ch_embolden_once_'+marker);check(duplicate['mutation'].get('replayed'),'Buff receipt prevents double application/cost')
  check(denied(pet(owner,'ch_embolden')),'Original active buff/cooldown prevents repeated embolden')
  enraged=pet(owner,'ch_enrage');check(enraged.get('mutation',{}).get('success')and row(enraged,device)['creature_handler']['enraged'],'Original enrage damage/susceptibility buff applied')
  for _ in range(20):
   current=state(owner)
   if any(cmd['command_id']==16 for cmd in row(current,device)['commands']):break
   pet(owner,'ch_train_command',device_id=device,command_id=16)
  stay=pet(owner,'pet_command',device_id=device,command_id=16)
  check(stay.get('mutation',{}).get('success'),'Native trained stay command holds pet still for controlled head-touch proof')
  lua('swgxrCHMature');mature=state(owner);grown=row(mature,device);check(grown['creature_handler']['train_mount'],'Labelled admin maturation now meets original mount species/scale rules')
  p=grown['position'];bounds=grown['creature_handler']['body_bounds'];head=bounds['head_position'];scale=bounds['scale'];angle=grown['heading_radians'];import math
  hand=[p[0]+scale*(head[0]*math.cos(angle)+head[2]*math.sin(angle)),p[1]+scale*head[1],p[2]+scale*(-head[0]*math.sin(angle)+head[2]*math.cos(angle))]
  near=dict(position=[hand[0]-1,p[1],hand[2]],building_id='0',cell_index=0)
  check(hand[1]-p[1]>1.8*scale,'Actual bantha head exceeds inherited source collision height; converted bounds required')
  check(denied(pet(owner,'ch_train_mount',device_id=device,hand=[p[0]+20,p[1],p[2]],**near)),'Mount gesture requires reachable source-volume touch')
  mount=pet(owner,'ch_train_mount',device_id=device,hand=hand,**near);check(mount.get('mutation',{}).get('success')and row(mount,device)['creature_handler']['trained_as_mount'],'Original trainAsMount sets authoritative mount flag')
  stored=pet(owner,'pet_store',device_id=device,left=hand,right=[hand[0]+.05,hand[1],hand[2]],**near)
  for _ in range(15):
   if not row(stored,device)['spawned']:break
   time.sleep(1);stored=state(owner)
  check(stored.get('mutation',{}).get('success')and not row(stored,device)['spawned'],'Both hands at original high head can store owned pet using global source bounds')
  check(stored['state']['creature_handler']['taming']['state']=='succeeded','Completed taming remains succeeded after native pet storage clears creature link')
  deadline=time.monotonic()+65
  while time.monotonic()<deadline:
   called=pet(owner,'pet_call',device_id=device)
   if called.get('mutation',{}).get('success'):break
   time.sleep(1)
  for _ in range(15):
   called=state(owner)
   if row(called,device)['spawned']:break
   time.sleep(1)
  check(row(called,device)['spawned'],'Original native creature pet call restores stored pet')
  call(owner,'/combat/session/stop',session_id=sessions.pop(owner['id']));start(owner);saved=state(owner)
  check(row(saved,device)['creature_handler']['trained_as_mount'],'Owned pet and mount training persist across independent native login')
  check(saved['state']['creature_handler']['taming']['state']=='succeeded','Completed tame job persists across independent native login')
  trainer_state=call(other,'/services/status',session_id=sessions[other['id']],position=[1374,7,3262],building_id='0',cell_index=0,zone='tatooine')
  trainer=next(t for t in trainer_state['state']['terminals']if t.get('profession')=='creaturehandler')
  opened=call(other,'/services/open',session_id=sessions[other['id']],terminal_id=trainer['id'],position=trainer['position'],building_id='0',cell_index=0,zone='tatooine')
  check(opened.get('ok')and len(opened['state']['terminal']['skills'])==18,'Original native CH trainer exposes all18source skill boxes')
  novice=next(s for s in opened['state']['terminal']['skills']if s['id']=='outdoors_creaturehandler_novice')
  check(not novice['eligible'],'Native CH trainer preserves prerequisites for untouched novice scout fixture')
  report['passed']=True
 finally:
  if added:lua('swgxrCHCleanup')
  if owners and owners[0]['id']in sessions:
   final=state(owners[0])
   for owned in final.get('state',{}).get('pet_datapad',[]):
    if owned.get('pet_kind')=='creature'and owned.get('spawned'):pet(owners[0],'pet_recall',device_id=owned['id'])
  for o in owners:
   if o['id']in sessions:call(o,'/combat/session/stop',session_id=sessions[o['id']])
  if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/creature-handler-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(checks))),flush=True)

if __name__=='__main__':main()
