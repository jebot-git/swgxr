#!/usr/bin/env python3
"""Native power-droid and storage checks with labelled original-item grants."""
import argparse,json,re,secrets,time,urllib.parse
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 fixture=ROOT/'runtime/server/power-droids-fixture.json'
 if fixture.exists():f=json.loads(fixture.read_text())
 else:
  f=dict(account='invtestpower'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(9)))
  response=shared.req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character' in response,response
  f['id']=response['character']['id'];fixture.write_text(json.dumps(f))
 assert f['account'].startswith('invtestpower') and f['name'].startswith('Ivtest') and str(f['id']).isdigit()
 base=dict(account=f['account'],character_id=f['id']);checks=[];completed=False;session='';pose={};script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 def check(value,label):
  checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True);assert value,label
 def call(path,**kwargs):return shared.req(path,dict(base,**kwargs))
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:corecuStorageFixture:'+mode)
  for _ in range(100):
   with log.open() as stream:stream.seek(offset);text=stream.read()
   match=re.search(r'runLuaFunction Tests:corecuStorageFixture: result=\[(.*?)\]',text)
   if match:return match[1]
   time.sleep(.05)
  raise AssertionError('Fixture timeout '+mode+': '+text[-600:])
 def service(action,**kw):
  kw.setdefault('request_id','storage_'+secrets.token_hex(12))
  result=call('/services/'+action,session_id=session,zone='tatooine',**kw)
  if not result.get('ok'):print('Service response',action,result.get('error'),result.get('mutation'),flush=True)
  return result
 def refresh_pose():
  nonlocal pose
  result=shared.req('/combat/session?'+urllib.parse.urlencode(dict(base,session_id=session)))
  assert 'snapshot' in result,result
  player=result['snapshot']['player'];pose={k:player[k] for k in ('position','building_id','cell_index')};pose['zone']='tatooine';print('Fixture pose',pose,flush=True)

 try:
  entered=call('/enter');loc=entered['source_location'];initial=dict(loc)
  x,y,z=loc['position']
  added=f'''
function Tests:corecuStorageFixture(mode,target)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "bad_owner" end
 local key="corecu_storage_fixture"
 local function obj(k) return getSceneObject(tonumber(readScreenPlayData(p,key,k)) or 0) end
 local function save(k,o) if o~=nil then writeScreenPlayData(p,key,k,tostring(SceneObject(o):getObjectID())) end return o end
 if mode=="setup" then
  local previous=obj("item") if previous~=nil then SceneObject(previous):destroyObjectFromWorld() SceneObject(previous):destroyObjectFromDatabase() end
  local inv=SceneObject(p):getSlottedObject("inventory")
  local bag=save("bag",giveItem(inv,"object/tangible/container/drum/tatt_drum_1.iff",-1))
  local item=save("item",giveItem(bag,"object/tangible/droid_battery/battery.iff",-1))
  if item==nil then return "missing_item" end
  TangibleObject(item):setUseCount(5)
  return tostring(SceneObject(bag):getObjectID())..","..tostring(SceneObject(item):getObjectID())
 elseif mode=="storage" then
  local d=getSceneObject(tonumber(target))
  if d==nil then return "missing_droid" end
  local components=SceneObject(d):getSlottedObject("crafted_components")
  if components==nil then return "missing_components" end
  local satchel=SceneObject(components):getContainerObject(0)
  if satchel==nil then return "missing_component_satchel" end
  local module=nil
  for i=0,SceneObject(satchel):getContainerObjectsSize()-1 do
   local candidate=SceneObject(satchel):getContainerObject(i)
   if SceneObject(candidate):getTemplateObjectPath()=="object/tangible/component/droid/item_storage_module_1.iff" then module=candidate end
  end
  if module==nil then module=giveItem(satchel,"object/tangible/component/droid/item_storage_module_1.iff",-1) end
  if module==nil then return "missing_module" end
  local old=SceneObject(d):getSlottedObject("inventory")
  if old~=nil then
   if SceneObject(old):getContainerObjectsSize()>0 then return "nonempty_fixture_inventory" end
   SceneObject(old):destroyObjectFromWorld() SceneObject(old):destroyObjectFromDatabase()
  end
  local inv=giveItem(d,"object/tangible/inventory/creature_inventory_6.iff",4,true)
  if inv==nil then return "missing_inventory" end
  return tostring(SceneObject(inv):getObjectID())
 elseif mode=="extra" then
  local values={{}}
  local count=math.min(100,tonumber(target) or 0)
  writeScreenPlayData(p,key,"extra_count",tostring(count))
  for i=1,count do
   local o=save("extra"..i,giveItem(obj("bag"),"object/tangible/droid_battery/battery.iff",-1))
   table.insert(values,tostring(SceneObject(o):getObjectID()))
  end
  return table.concat(values,",")
 elseif mode=="target" then
  local t=save("target",spawnSceneObject("tatooine","object/mobile/r2_crafted.iff",{x+2},{y},{z},0,0))
  if t==nil then return "missing_target" end
  for _,attribute in ipairs({{0,3,6}}) do CreatureObject(t):setHAM(attribute,1000) end
  CreatureObject(t):setPosture(0)
  return tostring(SceneObject(t):getObjectID())
 elseif mode=="target_far" then SceneObject(obj("target")):teleport({x+45},{y},{z},0) return "far"
 elseif mode=="target_near" then SceneObject(obj("target")):teleport({x+2},{y},{z},0) return "near"
 elseif mode=="remove_battery" then
  local item=obj("item") if item~=nil then SceneObject(item):destroyObjectFromWorld() SceneObject(item):destroyObjectFromDatabase() end
  return "removed"
 elseif mode=="prime" then
  local d=getSceneObject(tonumber(target))
  if d==nil then return "missing_droid" end
  CreatureObject(p):clearCombatState(true)
  SceneObject(d):teleport(SceneObject(p):getPositionX()+1,SceneObject(p):getPositionZ(),SceneObject(p):getPositionY(),0)
  return SceneObject(d):getZoneName()
 elseif mode=="city" then
  SceneObject(p):switchZone("tatooine",{x},{y},{z},0) return "city"
 elseif mode=="deed" then
  local deed=giveItem(SceneObject(p):getSlottedObject("inventory"),"object/tangible/deed/pet_deed/deed_power_basic.iff",-1)
  if deed==nil then return "missing_deed" end
  return tostring(activateOwnedDroidDeed(p,deed))
 elseif mode=="cleanup" then
  SceneObject(p):switchZone("tatooine",{x},{y},{z},0)
  for _,k in ipairs({{"item","box","bag","target"}}) do local o=obj(k) if o~=nil then SceneObject(o):destroyObjectFromWorld() SceneObject(o):destroyObjectFromDatabase() end end
  for i=1,(tonumber(readScreenPlayData(p,key,"extra_count")) or 0) do local o=obj("extra"..i) if o~=nil then SceneObject(o):destroyObjectFromWorld() SceneObject(o):destroyObjectFromDatabase() end end
  local house=obj("house") if house~=nil then destroyBuilding(house) end
  return "clean"
 end
 return "unknown"
end
'''
  script.write_text(original+added);console('reloadscreenplays')
  opened=call('/combat/session/start',**loc);session=opened['session_id']
  ready=call('/combat/session/update',session_id=session,ready=True,**loc);check(ready.get('snapshot',{}).get('ready'),'Native session completed load handshake')
  existing=call('/vehicles/status',live_session_id=session,zone='tatooine')
  if not any(r.get('power_droid') for r in existing.get('state',{}).get('pet_datapad',[])):check(lua('deed')=='true','Original power-droid deed activated through native handler')
  refresh_pose()
  time.sleep(2)
  pets=call('/vehicles/status',live_session_id=session,zone='tatooine')
  print('Pet snapshot error',pets.get('error'),flush=True);check(pets.get('source_kind')=='core3_vehicles','Owned power droid is visible in native datapad state')
  records=pets['state'].get('pet_datapad',[]);power=max((r for r in records if r.get('power_droid')),key=lambda r:(bool(r.get('spawned')),int(r['pet_id'])),default=None);check(power is not None,'Native power-droid capability identified')
  device=power['id'];print('Selected latest owned power droid',power['spawned'],flush=True)
  if not power.get('spawned'):
   called=call('/vehicles/pet_call',device_id=device,live_session_id=session,zone='tatooine');print('Call result',called.get('error'),called.get('mutation'),flush=True)
   if called.get('error'):
    time.sleep(1.1);called=call('/vehicles/pet_call',device_id=device,live_session_id=session,zone='tatooine')
   check(called.get('mutation',{}).get('success'),'Native call accepted after original deed initialization')
  for _ in range(20):
   time.sleep(1)
   call('/combat/session/update',session_id=session,ready=True,**loc)
   pets=call('/vehicles/status',live_session_id=session,zone='tatooine')
   current=next((r for r in pets.get('state',{}).get('pets',[]) if r['device_id']==device),None)
   if current:break
  print('Called droid',current is not None,pets.get('state',{}).get('pet_datapad',[])[-1].get('spawned'),flush=True)
  check(current is not None,'Owned power droid completes native call')
  alternatives=[r for r in pets['state']['pet_datapad'] if r.get('power_droid') and r['id']!=device]
  if not alternatives:
   check(lua('deed')=='true','Second original power-droid deed granted for native slot-limit check')
   alternatives=[r for r in call('/vehicles/status',live_session_id=session)['state']['pet_datapad'] if r.get('power_droid') and r['id']!=device]
  rejected=call('/vehicles/pet_call',device_id=alternatives[0]['id'],live_session_id=session)
  check(bool(rejected.get('error')),'Second crafted droid still rejected by original companion limit')
  values=lua('setup').split(',');check(len(values)==2,'Original battery and carried container granted for isolated fixture');bag,item=values
  charged=call('/vehicles/pet_command',device_id=device,command_id=24,request_id='battery_'+secrets.token_hex(12),live_session_id=session,zone='tatooine')
  print('Recharge error',charged.get('error'),flush=True);check(not charged.get('http_error') and charged.get('mutation',{}).get('success'),'Recharge from battery in a carried container succeeds natively')
  inventory=shared.req('/inventory?'+urllib.parse.urlencode(base))
  check(next(i for i in inventory['items'] if i['id']==item)['use_count']==4,'Battery recharge consumes exactly one native use')
  target=lua('target');check(target.isdigit(),'Original native target droid fixture created')
  def recharge_target():return call('/vehicles/pet_command',device_id=device,command_id=17,target_id=target,request_id='power_'+secrets.token_hex(12),live_session_id=session)
  lua('target_far');check(bool(recharge_target().get('error')),'Power droid refuses target beyond its native 30m range');lua('target_near')
  count=0
  for _ in range(11):
   response=recharge_target()
   if response.get('error'):break
   count+=1
  check(0<count<=10 and bool(response.get('error')),'Power droid recharges another droid and then refuses when power is exhausted')
  charged=call('/vehicles/pet_command',device_id=device,command_id=24,request_id='battery_refill_'+secrets.token_hex(8),live_session_id=session)
  check(charged.get('mutation',{}).get('success'),'Carried battery restores exhausted power droid')
  storage=lua('storage:'+power['pet_id']);check(storage.isdigit(),'Original storage module and matching inventory installed as labelled fixture prerequisites')
  def recall_and_call():
   time.sleep(1.1)
   stored=call('/vehicles/pet_recall',device_id=device,live_session_id=session);check(stored.get('mutation',{}).get('success'),'Native droid recall accepted')
   for _ in range(20):
    time.sleep(.5);status=call('/vehicles/status',live_session_id=session)['state']
    if not next(r for r in status['pet_datapad'] if r['id']==device)['spawned']:break
   time.sleep(1.1)
   called=call('/vehicles/pet_call',device_id=device,live_session_id=session);check(called.get('mutation',{}).get('success'),'Native storage droid call accepted')
   for _ in range(20):
    time.sleep(.5);status=call('/vehicles/status',live_session_id=session)['state']
    pet=next((r for r in status['pets'] if r['device_id']==device),None)
    if pet:return pet
   raise AssertionError('Droid call did not complete')
  pet=recall_and_call();check(pet.get('storage_available'),'Native module enables storage capability after recall')
  # Use actual native owner movement to stand beside the called droid.
  position=list(pet['position']);position[0]+=.5
  call('/combat/session/update',session_id=session,ready=True,position=position,building_id='0',cell_index=0)
  opened=service('open',terminal_id=power['pet_id']);check(opened.get('ok'),'Called owned droid opens standard container snapshot')
  storage=opened['state']['terminal']['storage']['inventory']['id']
  blocked=service('container_transfer',terminal_id=power['pet_id'],container_id=storage,item_id=bag,direction='store');check(not blocked.get('ok'),'Native droid module rejects storing a container inside droid storage')
  stored=service('container_transfer',terminal_id=power['pet_id'],container_id=storage,item_id=item,direction='store');check(stored.get('ok'),'Owned item transfers into original droid storage')
  pet=recall_and_call();position=list(pet['position']);position[0]+=.5
  call('/combat/session/update',session_id=session,ready=True,position=position,building_id='0',cell_index=0)
  opened=service('open',terminal_id=power['pet_id']);check(opened.get('ok') and any(i['id']==item for i in opened['state']['terminal']['storage']['items']),'Droid storage retains exact item across native store and recall')
  capacity=int(opened['state']['terminal']['storage']['inventory']['capacity'])
  check(0<capacity<=100,'Droid storage capacity comes from its native template')
  extras=lua('extra:'+str(capacity)).split(',');check(len(extras)==capacity,'Original capacity-test items granted')
  for extra in extras[:-1]:
   moved=service('container_transfer',terminal_id=power['pet_id'],container_id=storage,item_id=extra,direction='store')
   check(moved.get('ok'),'Native droid storage accepts item within native capacity')
  overflow=service('container_transfer',terminal_id=power['pet_id'],container_id=storage,item_id=extras[-1],direction='store')
  check(not overflow.get('ok'),'Native droid storage rejects capacity overflow')
  taken=service('container_transfer',terminal_id=power['pet_id'],container_id=storage,item_id=item,destination_id=bag,direction='take');check(taken.get('ok'),'Droid storage item transfers back into carried bag')
  lua('remove_battery')
  empty=call('/vehicles/pet_command',device_id=device,command_id=24,request_id='battery_empty_'+secrets.token_hex(10),live_session_id=session)
  check(bool(empty.get('error')),'Recharge without battery reports failure')
  f.update(device_id=device,pet_id=power['pet_id'],storage_id=storage);fixture.write_text(json.dumps(f))

  completed=True
 finally:
  try:
   if session:
    lua('cleanup');call('/combat/session/stop',session_id=session)
  finally:
   script.write_text(original);console('reloadscreenplays')
   report=dict(passed=completed and bool(checks) and all(c['passed'] for c in checks),checks=checks,native_execution=True,fixture_setup='Administrator-granted original container/deed definitions and isolated house; crafting process not claimed',headset_tested=False,remote_changed=False)
   (ROOT/'runtime/evidence/power-droids-native-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
