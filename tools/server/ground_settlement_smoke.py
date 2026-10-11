#!/usr/bin/env python3
"""Two isolated native peers; synthetic stationary contact receipts, no XR or balance test."""
import argparse,json,time
from pathlib import Path
import services_smoke as shared
from seed_bazaar import Native
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18088);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 fixtures=[json.loads((ROOT/'runtime/server'/file).read_text()) for file in ('heralds-fixture.json','hit-feedback-fixture.json')]
 assert all(f['account'].startswith('invtest') and f['name'].startswith(('Hrtest','Fbtest')) for f in fixtures)
 peers=[dict(account=f['account'],character_id=f['id']) for f in fixtures];native=Native('swgxr-core3-build');checks=[];evidence=[];trace=[];sessions=[]
 def call(i,path,**kw):
  r=shared.req(path,dict(peers[i],**kw));assert not r.get('http_error'),r;return r
 def batch(i,rows=None):return call(i,'/combat/session/action_combat',session_id=sessions[i],action_combat=dict(action='batch',receipts=rows or []))['mutation']
 def check(ok,label):checks.append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 original=[call(i,'/enter')['source_location']['position'] for i in range(2)]
 source=f'''
function Tests:swgxrSettlementFixture(mode)
 local p=getSceneObject({fixtures[0]['id']}) local q=getSceneObject({fixtures[1]['id']})
 if p==nil or q==nil or CreatureObject(p):getFirstName()~="{fixtures[0]['name']}" or CreatureObject(q):getFirstName()~="{fixtures[1]['name']}" then return "guard_failed" end
 local m=getSceneObject(readData("settlementFixtureMob"))
 if m then CreatureObject(m):clearCombatState(true);SceneObject(m):destroyObjectFromWorld();deleteData("settlementFixtureMob") end
 CreatureObject(p):forcePeace();CreatureObject(q):forcePeace()
 if mode=="cleanup" then
  SceneObject(p):teleport({original[0][0]},{original[0][1]},{original[0][2]},0)
  SceneObject(q):teleport({original[1][0]},{original[1][1]},{original[1][2]},0)
  return "clean"
 end
 if mode=="place" or mode=="laneplace" then
  local px=5800.95 local qx=5800.5 if mode=="laneplace" then px=5812 qx=5808 end
  for _,c in ipairs({{p,q}}) do for i=0,8 do CreatureObject(c):setWounds(i,0);CreatureObject(c):setHAM(i,CreatureObject(c):getMaxHAM(i)) end;CreatureObject(c):setPosture(0) end
  SceneObject(p):teleport(px,getTerrainHeight(p,px,-4804),-4804,0)
  SceneObject(q):teleport(qx,getTerrainHeight(q,qx,-4804),-4804,0)
  return tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(q):getWorldPositionZ())
 end
 local template="worrt" if mode=="lane" then template="sulfur_lake_pirate_lieutenant" end
 m=spawnMobile("tatooine",template,0,5800,getTerrainHeight(p,5800,-4804),-4804,0,0)
 AiAgent(m):setAITemplate("none");AiAgent(m):clearCurrentPath();AiAgent(m):setCurrentSpeed(0);AiAgent(m):setWait(60000);AiAgent(m):setDefender(p);AiAgent(m):setFollowObject(p);CreatureObject(m):engageCombat(p)
 writeData("settlementFixtureMob",SceneObject(m):getObjectID());AiAgent(m):selectDefaultAttack();AiAgent(m):enqueueAttack()
 return tostring(SceneObject(m):getObjectID())
end
'''
 passed=False
 try:
  with native.screenplay('swgxrSettlementFixture',source):
   try:
    heights=[float(x) for x in native.call('swgxrSettlementFixture:place').split(',')];positions=[[5800.95,heights[0],-4804],[5800.5,heights[1],-4804]]
    revision=json.loads((ROOT/'runtime/assets/combat_actions/catalog.json').read_text())['revision']
    for i in range(2):
     sessions.append(call(i,'/combat/session/start',position=positions[i])['session_id'])
     call(i,'/combat/session/update',session_id=sessions[i],position=positions[i],ready=True)
     call(i,'/combat/session/action_combat',session_id=sessions[i],action_combat=dict(action='negotiate',protocol=2,catalog_revision=revision))
    for scenario in ('cleave','lane'):
     if scenario=='lane':
      heights=[float(x) for x in native.call('swgxrSettlementFixture:laneplace').split(',')];positions=[[5812,heights[0],-4804],[5808,heights[1],-4804]]
      for i in range(2):call(i,'/combat/session/update',session_id=sessions[i],position=positions[i],ready=True)
     mob=native.call('swgxrSettlementFixture:'+scenario);tracks=[dict(warned=False,acked=False,sent=False),dict(warned=False,acked=False,sent=False)];pending=[[],[]];attack=None;out=[[],[]];early=False;until=time.monotonic()+15
     while time.monotonic()<until:
      for i in range(2):
       r=batch(i,pending[i]);trace.append(dict(peer=i,reply=r));pending[i]=[];stamp=r['server_sent'];t=tracks[i]
       for receipt in r['receipts']:
        if receipt['kind']=='contact':
         check(receipt['accepted'],scenario+' peer '+str(i)+' contact accepted');t['received_at']=r['server_received']
       events=[e for e in r['action_events'] if e['id']==mob and (attack is None or e['attack_id']==attack)]
       for e in events:
        if attack is None:attack=e['attack_id'];check(e['hit_policy']==('cleave' if scenario=='cleave' else 'first_contact'),scenario+' native profile selected')
        common=dict(actor_id=mob,attack_id=attack,aim_revision=e['aim_revision'])
        if not t['warned'] and e['phase']=='windup':pending[i].append(dict(common,kind='warning',presented_at=stamp));t['warned']=True
        if not t['acked'] and e['aim_locked'] and e['phase']=='windup':pending[i].append(dict(common,kind='lock',presented_at=stamp));t['acked']=True
        delay=.025 if i==0 else .22
        if t['acked'] and not t['sent'] and stamp>=e['end_at']+delay and e['phase']=='active':
         pending[i].append(dict(common,kind='contact',contact=True,sample_position=positions[i],coverage_start=e['active_at']+.01,coverage_end=stamp,contact_at=e['active_at']+.01));t['sent']=True
       out[i]=[o for o in r['outcomes'] if o['actor_id']==mob and o['attack_id']==attack]
       if i==0 and tracks[0]['sent'] and not tracks[1]['sent']:
        if scenario=='cleave' and out[0]:early=True
        if scenario=='lane':check(not out[0],'Lane holds arbitration while another participant can still report')
      if out[0] and out[1]:break
      time.sleep(.015)
     check(bool(out[0] and out[1]),scenario+' both peers settle')
     if scenario=='cleave':check(out[0][0]['settled_at']<tracks[1]['received_at'] and all(o[0]['delivered'] for o in out),'Cleave resolves ready peer before slower peer without losing either result')
     else:check(not out[0][0]['delivered'] and out[1][0]['delivered'],'Near interceptor wins despite far peer reporting first')
     evidence.append(dict(scenario=scenario,outcomes=out))
    passed=True
   finally:
    native.call('swgxrSettlementFixture:cleanup')
    for i,s in enumerate(sessions):call(i,'/combat/session/stop',session_id=s)
 finally:
  (ROOT/'runtime/evidence/ground-stability-review/settlement-native.json').write_text(json.dumps(dict(passed=passed,checks=checks,evidence=evidence,trace=trace,native=True,synthetic_receipts=True,xr=False),indent=2)+'\n')
if __name__=='__main__':main()
