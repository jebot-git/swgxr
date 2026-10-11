#!/usr/bin/env python3
"""Native combat delivery stability: presentation contact, replay and bundles; no sustained combat."""
import argparse,json,secrets,time
from pathlib import Path
import services_smoke as shared
from seed_bazaar import Native
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18088);a=p.parse_args();shared.BASE=f'http://127.0.0.1:{a.port}'
 file=ROOT/'runtime/server/hit-feedback-fixture.json'
 if not file.exists():
  f={'account':'invtestfeedback'+secrets.token_hex(4),'name':'Fbtest'+''.join(secrets.choice('aeilnorst') for _ in range(8))}
  r=shared.req('/characters',dict(f,species='human',profession='combat_brawler'));assert 'character' in r,r;f['id']=r['character']['id'];file.write_text(json.dumps(f))
 f=json.loads(file.read_text());assert f['account'].startswith('invtestfeedback') and f['name'].startswith('Fbtest')
 base=dict(account=f['account'],character_id=f['id']);sid='';checks=[];responses=[];native=Native('swgxr-core3-build')
 def call(path,**fields):
  r=shared.req(path,dict(base,**fields));responses.append({'path':path,'response':shared.redact(r)});assert not r.get('http_error'),r;return r
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True);assert ok,label
 entered=call('/enter');original=entered['source_location']['position'];report={'passed':False,'native':True,'xr':False,'administrative_placement':True,'checks':checks,'responses':responses}
 source=f'''
function Tests:swgxrStabilityFixture(mode)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "guard_failed" end
 local m=getSceneObject(readData("stabilityFixtureMob"))
 if mode=="cleanup" then
  if m then CreatureObject(m):clearCombatState(true);SceneObject(m):destroyObjectFromWorld() end
  deleteData("stabilityFixtureMob");CreatureObject(p):forcePeace();SceneObject(p):teleport({original[0]},{original[1]},{original[2]},0);return "clean"
 end
 if mode=="mob" then return tostring(SceneObject(m):getObjectID()) end
 if mode=="move" then SceneObject(m):teleport(5805.5,getTerrainHeight(p,5805.5,-4804),-4804,0);return "moved" end
 if mode=="place" then
  CreatureObject(p):forcePeace();SceneObject(p):teleport(5800,getTerrainHeight(p,5800,-4804),-4804,0)
  m=spawnMobile("tatooine","smuggler",0,5801.5,getTerrainHeight(p,5801.5,-4804),-4804,0,0)
  AiAgent(m):setWait(60000);writeData("stabilityFixtureMob",SceneObject(m):getObjectID())
  return tostring(SceneObject(p):getWorldPositionX())..","..tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(p):getWorldPositionY())
 end
 return "unknown"
end
'''
 try:
  with native.screenplay('swgxrStabilityFixture',source):
   try:
    pos=[float(v) for v in native.call('swgxrStabilityFixture:place').split(',')]
    r=call('/combat/session/start',position=pos);sid=r['session_id'];r=call('/combat/session/update',session_id=sid,position=pos,ready=True)
    weapon=r['snapshot']['weapon']
    if not weapon['unarmed']:
     call('/inventory/unequip',live_session_id=sid,item_id=weapon['item_id'])
     r=call('/combat/session/update',session_id=sid,position=pos,ready=True);weapon=r['snapshot']['weapon']
    check(weapon['unarmed'],'Native equipped weapon is unarmed')
    origin=[pos[0],pos[1]+1.2,pos[2]]
    fields=dict(session_id=sid,shot_id='feedback_'+secrets.token_hex(8),item_id=weapon['item_id'],origin=origin,direction=[1,0,0])
    check(weapon.get('combat_receipts')=='replay_v1' and weapon.get('melee_contact')=='presented_v1','Native snapshot negotiates result recovery and presented melee')
    mob=native.call('swgxrStabilityFixture:mob')
    row=next(row for row in r['snapshot']['actors'] if row['id']==mob)
    proof=dict(target_id=mob,hit_position=[pos[0]+1,pos[1]+1.2,pos[2]],target_position=row['position'],observation_at=row['observation_at'])
    fields['melee_contact']=proof
    revision=json.loads((ROOT/'runtime/assets/combat_actions/catalog.json').read_text())['revision']
    negotiated=call('/combat/session/action_combat',session_id=sid,action_combat=dict(action='negotiate',protocol=2,catalog_revision=revision))['mutation']
    check(negotiated.get('receipt_bundle')=='ground_v1' and negotiated.get('contact_evidence')=='sample_v1','Native ground evidence and bundle capabilities negotiated')
    fields['ground_receipts']=[]
    native.call('swgxrStabilityFixture:move')
    reply=call('/combat/session/melee',**fields);result=reply['mutation']
    check(result.get('success') and result.get('target_id')==mob and result.get('contact_authority')=='client','Presented melee resolves after native target moves out of old reach')
    check(reply.get('ground_receipts',{}).get('success'),'One native request resolves bundled ground receipt batch')
    original=result.copy();ham=reply['snapshot']['player']['ham'];target_ham=next(row['ham'] for row in reply['snapshot']['actors'] if row['id']==mob)
    replay=call('/combat/session/melee',**dict(fields,receipt_only=True));result=replay['mutation']
    check(result.pop('receipt_replayed',False) and result==original,'Lost-reply query returns exact prior native mutation')
    check(replay['snapshot']['player']['ham'][1:]==ham[1:] and next(row['ham'] for row in replay['snapshot']['actors'] if row['id']==mob)==target_ham,'Receipt replay repeats neither attack costs nor target damage')
    missing=call('/combat/session/melee',**dict(fields,shot_id='missing_'+secrets.token_hex(8),receipt_only=True))['mutation']
    check(not missing['success'] and missing['error_code']=='combat_receipt_missing','Unknown result query never executes an old attack')
    conflict=call('/combat/session/melee',**dict(fields,receipt_only=True,direction=[0,0,1]))['mutation']
    check(not conflict['success'] and conflict['error_code']=='combat_receipt_conflict','Attack identity cannot be rebound to a different intent')
    report['passed']=True
   finally:
    if sid:call('/combat/session/stop',session_id=sid);sid=''
    native.call('swgxrStabilityFixture:cleanup')
 finally:(ROOT/'runtime/evidence/ground-stability-review/native.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
