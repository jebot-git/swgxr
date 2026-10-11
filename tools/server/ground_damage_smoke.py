#!/usr/bin/env python3
"""Local native ordinary-NPC damage regression. Uses disposable fixture only."""
import argparse,json,re,time
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 f=json.loads((ROOT/'runtime/server/heralds-fixture.json').read_text());assert f['account'].startswith('invtestherald') and re.fullmatch('Hrtest[a-z]+',f['name'])
 identity=dict(account=f['account'],character_id=f['id']);session='';checks=[];outcomes=[];receipts=[]
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 def call(path,**kw):
  r=shared.req(path,dict(identity,**kw));assert not r.get('http_error'),r;return r
 def check(ok,label):
  checks.append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:corecuDamageFixture:'+mode)
  for _ in range(100):
   with log.open() as h:h.seek(offset);text=h.read()
   match=re.search(r'runLuaFunction Tests:corecuDamageFixture: result=\[(.*?)\]',text)
   if match:return match[1]
   time.sleep(.05)
  raise AssertionError(text[-1000:])
 def batch(rows=[]):
  r=call('/combat/session/action_combat',session_id=session,action_combat=dict(action='batch',receipts=rows))['mutation'];receipts.extend(r.get('receipts',[]));return r
 passed=False
 try:
  entry=call('/enter');x,y,z=entry['source_location']['position']
  script.write_text(original+f'''
function Tests:corecuDamageFixture(mode)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "bad_owner" end
 local key="corecu_damage_fixture" local m=getSceneObject(tonumber(readScreenPlayData(p,key,"mob")) or 0)
 if mode=="cleanup" or mode=="attack" or mode=="outside" then
  if m~=nil then CreatureObject(m):clearCombatState(true) SceneObject(m):destroyObjectFromWorld() end
  CreatureObject(p):clearCombatState(true) writeScreenPlayData(p,key,"mob","0")
 end
 if mode=="place" then
  SceneObject(p):teleport(5800,getTerrainHeight(p,5800,-4804),-4804,0)
  for i=0,8 do CreatureObject(p):setWounds(i,0) CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
  CreatureObject(p):setPosture(0)
 elseif mode=="cleanup" then SceneObject(p):teleport({x},{y},{z},0)
 elseif mode=="attack" or mode=="outside" then
  local name="smuggler" local mx=5801
  if mode=="outside" then name="worrt" mx=5808 end
  m=spawnMobile("tatooine",name,0,mx,getTerrainHeight(p,mx,-4804),-4804,0,0)
  if m==nil then return "spawn_failed" end
  writeScreenPlayData(p,key,"mob",tostring(SceneObject(m):getObjectID()))
  AiAgent(m):setWait(60000) AiAgent(m):setDefender(p) AiAgent(m):setFollowObject(p) CreatureObject(m):engageCombat(p)
  AiAgent(m):selectDefaultAttack() AiAgent(m):enqueueAttack()
  return tostring(SceneObject(m):getObjectID())
 end
 return tostring(SceneObject(p):getWorldPositionX())..","..tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(p):getWorldPositionY())
end
''');console('reloadscreenplays');time.sleep(.2)
  pos=[float(n) for n in lua('place').split(',')]
  session=call('/combat/session/start',position=pos)['session_id'];call('/combat/session/update',session_id=session,position=pos,ready=True)
  revision=json.loads((ROOT/'runtime/assets/combat_actions/catalog.json').read_text())['revision']
  check(call('/combat/session/action_combat',session_id=session,action_combat=dict(action='negotiate',protocol=2,catalog_revision=revision))['mutation']['success'],'Native global combat negotiated')
  far=lua('outside');far_events=[];until=time.monotonic()+.8
  while time.monotonic()<until:
   far_events.extend(e for e in batch().get('action_events',[]) if e['id']==far);time.sleep(.05)
  check(not far_events,'Out-of-reach ordinary melee NPC does not start an ineffective telegraph')
  mob=lua('attack');until=time.monotonic()+12;pending=[];tracks={};bad_rejected=False;contact_accepted=False
  while time.monotonic()<until:
   r=batch(pending);pending=[]
   for row in r.get('action_events',[]):
    if row['id']!=mob:continue
    track=tracks.setdefault(row['attack_id'],dict(warned=False,acked=False,sent=False))
    now=r['server_sent'];common=dict(actor_id=mob,attack_id=row['attack_id'],aim_revision=row['aim_revision'])
    if not track['warned'] and row['phase']=='windup':pending.append(dict(common,kind='warning'));track['warned']=True
    if row['aim_locked'] and not track['acked'] and row['phase']=='windup':pending.append(dict(common,kind='lock'));track['acked']=True
    if track['acked'] and not track['sent'] and now>=row['end_at']+.025 and row['phase']=='active':
     # Reproduce a fast client's pre-start coverage, then correct that exact report.
     contact=dict(common,kind='contact',contact=True,sample_position=pos,coverage_start=row['start']-.1,coverage_end=now)
     bad=batch([contact]);bad_rejected=not bad['receipts'][0]['accepted']
     contact['coverage_start']=row['start'];good=batch([contact]);contact_accepted=good['receipts'][0]['accepted'];track['sent']=True
   found=[o for o in r.get('outcomes',[]) if o['actor_id']==mob]
   if found:outcomes=found
   if any(o.get('delivered') and o.get('native_result',0)>0 for o in found):break
   time.sleep(.025)
  check(bad_rejected,'Pre-start coverage reproduces rejected contact')
  check(contact_accepted,'Clipped coverage is accepted for same ordinary smuggler attack')
  check(any(o.get('delivered') and o.get('native_result',0)>0 for o in outcomes),'Native CombatManager applies actual NPC damage')
  check(any(o.get('damage',0)>0 for o in outcomes),'Native player HAM decreases')
  passed=True
 finally:
  try:
   lua('cleanup')
   if session:call('/combat/session/stop',session_id=session)
  finally:script.write_text(original);console('reloadscreenplays')
  (ROOT/'runtime/evidence/ground-damage-native.json').write_text(json.dumps(dict(passed=passed,checks=checks,outcomes=outcomes,receipts=receipts,native_execution=True,administrative_fixture=True,headset_tested=False,remote_changed=False),indent=2))
if __name__=='__main__':main()
