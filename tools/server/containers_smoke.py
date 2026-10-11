#!/usr/bin/env python3
"""Real native storage transfers using explicitly granted disposable original items.

This tests native storage/permissions and recharge, not earning crafted items or XR.
"""
import argparse,json,re,secrets,time,urllib.parse
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 fixture=ROOT/'runtime/server/containers-fixture.json'
 if fixture.exists():f=json.loads(fixture.read_text())
 else:
  f=dict(account='invteststorage'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(9)))
  response=shared.req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character' in response,response
  f['id']=response['character']['id'];fixture.write_text(json.dumps(f))
 assert f['account'].startswith('invteststorage') and f['name'].startswith('Ivtest') and str(f['id']).isdigit()
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
  CreatureObject(p):clearCombatState(true)
  SceneObject(p):teleport(5900,getTerrainHeight(p,5900,-4804),-4804,0)
  local inv=SceneObject(p):getSlottedObject("inventory")
  local bag=save("bag",giveItem(inv,"object/tangible/container/drum/tatt_drum_1.iff",-1))
  local box=save("box",spawnSceneObject("tatooine","object/tangible/container/drum/tatt_drum_1.iff",5901,getTerrainHeight(p,5901,-4804),-4804,0,0))
  if bag==nil or box==nil then return "missing_container" end
  SceneObject(box):setContainerOwnerID(0)
  SceneObject(box):setContainerInheritPermissionsFromParent(false)
  SceneObject(box):clearContainerDefaultDenyPermission(15)
  for _,perm in ipairs({{1,2,4,8}}) do SceneObject(box):setContainerDefaultAllowPermission(perm) end
  local item=save("item",giveItem(box,"object/tangible/droid_battery/battery.iff",-1))
  if item==nil then return "missing_item" end
  TangibleObject(item):setUseCount(5)
  local nested=save("nested",giveItem(box,"object/tangible/container/drum/tatt_drum_1.iff",-1))
  return tostring(SceneObject(box):getObjectID())..","..tostring(SceneObject(bag):getObjectID())..","..tostring(SceneObject(item):getObjectID())..","..tostring(SceneObject(nested):getObjectID())
 elseif mode=="lock" then SceneObject(obj("box")):setContainerLockedStatus(true) return "locked"
 elseif mode=="unlock" then SceneObject(obj("box")):setContainerLockedStatus(false) return "unlocked"
 elseif mode=="far" then SceneObject(p):teleport(5910,getTerrainHeight(p,5910,-4804),-4804,0) return "far"
 elseif mode=="near" then SceneObject(p):teleport(5900,getTerrainHeight(p,5900,-4804),-4804,0) return "near"
 elseif mode=="house" then
  local house=save("house",spawnBuilding(p,"object/building/player/player_house_tatooine_small_style_01.iff",5930,-4804,0))
  if house==nil then return "missing_house" end
  local cell=BuildingObject(house):getCell(1)
  SceneObject(obj("box")):setPosition(0,0,0)
  SceneObject(cell):transferObject(obj("box"),-1,true)
  SceneObject(obj("box")):setContainerInheritPermissionsFromParent(true)
  SceneObject(obj("box")):teleport(0,0,0,SceneObject(cell):getObjectID())
  SceneObject(p):setPosition(0,0,1)
  SceneObject(cell):transferObject(p,-1,true)
  SceneObject(p):teleport(0,0,1,SceneObject(cell):getObjectID())
  return tostring(SceneObject(house):getObjectID())..","..tostring(SceneObject(obj("box")):getParentID())..","..tostring(SceneObject(p):getParentID())
 elseif mode=="cleanup" then
  SceneObject(p):switchZone("tatooine",{x},{y},{z},0)
  for _,k in ipairs({{"box","bag"}}) do local o=obj(k) if o~=nil then SceneObject(o):destroyObjectFromWorld() SceneObject(o):destroyObjectFromDatabase() end end
  local house=obj("house") if house~=nil then destroyBuilding(house) end
  return "clean"
 end
 return "unknown"
end
'''
  script.write_text(original+added);console('reloadscreenplays')
  opened=call('/combat/session/start',**loc);session=opened['session_id']
  ready=call('/combat/session/update',session_id=session,ready=True,**loc);check(ready.get('snapshot',{}).get('ready'),'Native session completed load handshake')
  values=lua('setup').split(',');check(len(values)==4,'Original native container fixture created');box,bag,item,nested=values;refresh_pose()
  opened=service('open',terminal_id=box);check(opened.get('ok') and len(opened['state']['terminal']['storage']['items'])==2,'Environmental native container opens with item attributes')
  sub=service('open',terminal_id=box,container_id=nested);check(sub.get('ok') and sub['state']['terminal']['storage']['inventory']['id']==nested,'Nested container opens inside authorized storage root')
  invalid=service('open',terminal_id=box,container_id=bag);check(not invalid.get('ok'),'Unrelated inventory cannot be read through storage context')
  key='storage_take_'+secrets.token_hex(8)
  taken=service('container_transfer',terminal_id=box,container_id=box,item_id=item,destination_id=bag,direction='take',request_id=key)
  check(taken.get('ok') and any(i['id']==item and i['container_id']==bag for i in taken['state']['inventory']['items']),'Take transfers original item into chosen carried container')
  replay=service('container_transfer',terminal_id=box,container_id=box,item_id=item,destination_id=bag,direction='take',request_id=key)
  check(replay.get('ok') and replay['mutation'].get('replayed'),'Repeated transfer returns durable receipt without duplication')
  stored=service('container_transfer',terminal_id=box,container_id=box,item_id=item,direction='store');check(stored.get('ok'),'Held inventory item transfers back into container')
  lua('lock');locked=service('open',terminal_id=box);check(not locked.get('ok'),'Locked native container cannot expose contents')
  blocked=service('container_transfer',terminal_id=box,container_id=box,item_id=item,destination_id=bag,direction='take');check(not blocked.get('ok'),'Lock also blocks transfer using stale snapshot');lua('unlock')
  lua('far');refresh_pose();far=service('open',terminal_id=box);check(not far.get('ok'),'Walking away invalidates storage access');lua('near');refresh_pose()
  house=lua('house');print('House fixture',house,flush=True);check(house.split(',')[0].isdigit(),'Original house placed for fixture owner')
  refresh_pose()
  housed=service('open',terminal_id=box);check(housed.get('ok'),'Placed house container uses the same native inventory interface')
  taken=service('container_transfer',terminal_id=box,container_id=box,item_id=item,destination_id=bag,direction='take');check(taken.get('ok'),'House administrator retrieves container contents')

  completed=True
 finally:
  try:
   if session:
    lua('cleanup');call('/combat/session/stop',session_id=session)
  finally:
   script.write_text(original);console('reloadscreenplays')
   report=dict(passed=completed and bool(checks) and all(c['passed'] for c in checks),checks=checks,native_execution=True,fixture_setup='Administrator-granted original container/deed definitions and isolated house; crafting process not claimed',headset_tested=False,remote_changed=False)
   (ROOT/'runtime/evidence/container-native-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
