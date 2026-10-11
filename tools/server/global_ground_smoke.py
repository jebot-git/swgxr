#!/usr/bin/env python3
"""Isolated native ground PvE warning test, using existing original mobile templates.

Administrative fixture placement and attack selection are explicit setup, not a
claim of physical locomotion, headset rendering or remote latency validation.
"""
import argparse,json,re,time
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args()
 shared.BASE=f'http://127.0.0.1:{args.port}'
 f=json.loads((ROOT/'runtime/server/heralds-fixture.json').read_text())
 assert f['account'].startswith('invtestherald') and re.fullmatch(r'Hrtest[a-z]+',f['name']) and str(f['id']).isdecimal()
 identity={'account':f['account'],'character_id':f['id']};session='';checks=[];events=[];requests=[]
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 report={'passed':False,'native_execution':True,'administrative_fixture_placement':True,'remote_changed':False,'headset_tested':False}
 def check(value,label):
  checks.append({'passed':bool(value),'label':label});print(label,bool(value),flush=True);assert value,label
 def call(path,**kw):
  result=shared.req(path,dict(identity,**kw));requests.append({'path':path,'error':result.get('error')});assert not result.get('http_error'),result;return result
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size
  console('runLuaFunction Tests:corecuGlobalFixture:'+mode)
  for _ in range(100):
   with log.open() as stream:stream.seek(offset);text=stream.read()
   found=re.search(r'runLuaFunction Tests:corecuGlobalFixture: result=\[(.*?)\]',text)
   if found:return found[1]
   time.sleep(.05)
  raise AssertionError('No fixture response '+mode+': '+text[-1000:])
 def batch(receipts=None):
  result=call('/combat/session/action_combat',session_id=session,action_combat={'action':'batch','receipts':receipts or []})
  return result['mutation']
 def collect(mob,seconds=3,ack=False):
  end=time.monotonic()+seconds;seen={};pending=[]
  while time.monotonic()<end:
   result=batch(pending);pending=[]
   for row in result.get('action_events',[]):
    if row['id']!=mob:continue
    events.append(row);seen[row['attack_id']]=row
    if ack and row['phase']=='windup':pending.append(dict(kind='lock' if row['aim_locked'] else 'warning',actor_id=mob,attack_id=row['attack_id'],aim_revision=row['aim_revision']))
   time.sleep(.06)
  return list(seen.values())
 try:
  entry=call('/enter');loc=entry['source_location'];assert loc['zone']=='tatooine' and loc['building_id']=='0'
  x,y,z=loc['position']
  added=f'''
function Tests:corecuGlobalFixture(mode)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "bad_owner" end
 local key="corecu_global_fixture" local m=getSceneObject(tonumber(readScreenPlayData(p,key,"mob")) or 0)
 if mode=="cleanup" or mode=="basic" or mode=="special" or mode=="cone" then
  if m~=nil then CreatureObject(m):clearCombatState(true) SceneObject(m):destroyObjectFromWorld() end
  writeScreenPlayData(p,key,"mob","0") CreatureObject(p):clearCombatState(true)
 end
 if mode=="place" then
  SceneObject(p):teleport(5800,getTerrainHeight(p,5800,-4804),-4804,0)
 elseif mode=="cleanup" then
  SceneObject(p):teleport({x},{y},{z},0)
 elseif mode=="basic" or mode=="special" or mode=="cone" then
  local name="worrt" if mode~="basic" then name="dark_jedi_knight" end
  m=spawnMobile("tatooine",name,0,5802,getTerrainHeight(p,5802,-4804),-4804,0,0)
  if m==nil then return "spawn_failed" end
  writeScreenPlayData(p,key,"mob",tostring(SceneObject(m):getObjectID()))
  AiAgent(m):setWait(60000) AiAgent(m):setDefender(p) AiAgent(m):setFollowObject(p)
  CreatureObject(m):engageCombat(p)
  local index=8
  local w=SceneObject(m):getSlottedObject("hold_r")
  if w~=nil and string.find(SceneObject(w):getTemplateObjectPath(),"onehand") then index=9 end
  if w~=nil and string.find(SceneObject(w):getTemplateObjectPath(),"twohand") then index=9 end
  if mode=="basic" then AiAgent(m):selectDefaultAttack() elseif mode=="special" then AiAgent(m):selectSpecialAttack(index) else AiAgent(m):selectSpecialAttack(index+1) end
  AiAgent(m):enqueueAttack()
  return tostring(SceneObject(m):getObjectID())
 elseif mode=="retreat" then
  SceneObject(p):teleport(5820,getTerrainHeight(p,5820,-4804),-4804,0)
 elseif mode=="return" then
  SceneObject(p):teleport(5800,getTerrainHeight(p,5800,-4804),-4804,0)
 elseif mode=="leash" and m~=nil then
  AiAgent(m):stopWaiting() AiAgent(m):setHomeLocation(5600,getTerrainHeight(p,5600,-4804),-4804,nil)
 elseif mode=="state" and m~=nil then return tostring(CreatureObject(m):isInCombat())..","..tostring(AiAgent(m):getMovementState()) end
 return tostring(SceneObject(p):getWorldPositionX())..","..tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(p):getWorldPositionY())
end
'''
  script.write_text(original+added);console('reloadscreenplays');time.sleep(.2)
  position=[float(n) for n in lua('place').split(',')]
  started=call('/combat/session/start',position=position);session=started['session_id']
  ready=call('/combat/session/update',session_id=session,position=position,ready=True)
  check(ready.get('snapshot',{}).get('ready'),'Native fixture enters world outside Mos Eisley test boundary')
  catalog=json.loads((ROOT/'runtime/assets/combat_actions/catalog.json').read_text())
  negotiated=call('/combat/session/action_combat',session_id=session,action_combat={'action':'negotiate','protocol':2,'catalog_revision':catalog['revision']})['mutation']
  check(negotiated.get('success') and negotiated.get('scope')=='global','Exact global catalog negotiated')
  mob=lua('basic');rows=collect(mob,3,True)
  check(any(r['command']=='defaultattack' and r['shape']=='cone' for r in rows),'Original worrt produces native basic telegraph outside old boundary')
  # Force a fresh original knight to select its first native Force command.
  mob=lua('special');rows=collect(mob,5,True)
  check(any(r['special'] and r['target_required'] and r['shape']=='targeted' and r['eligible_victim_ids']==[str(f['id'])] for r in rows),'Native Force special identifies only the selected victim')
  check(any(r['animation'].startswith('action_ground_special_') for r in rows),'Native special selects its original rig-bound animation')
  mob=lua('cone');rows=collect(mob,5,True)
  check(any(r['special'] and r['shape']=='cone' and not r['target_required'] for r in rows),'Native Force cone publishes its own area and timing')
  lua('leash');rows=collect(mob,5)
  state=lua('state');check(state.startswith('false,'),'Native home leash ends combat after sustained excess distance')
  # Cancellation timing has deterministic policy tests; this deliberately places
  # the fixture beyond reach during preparation to exercise the native hook.
  lua('return');mob=lua('basic');first=collect(mob,.15);lua('retreat');rows=collect(mob,1)
  check(any(r.get('cancel_reason')=='targets_out_of_reach' for r in rows),'Native unreachable preparation cancels before aim lock')
  report['passed']=True
 finally:
  try:
   lua('cleanup')
   if session:call('/combat/session/stop',session_id=session)
  finally:script.write_text(original);console('reloadscreenplays')
  report.update(checks=checks,events=events,requests=requests)
  (ROOT/'runtime/evidence/global-ground-native-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
