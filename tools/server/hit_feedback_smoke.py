#!/usr/bin/env python3
"""Native unarmed hit feedback and Warcry, isolated fixture; no XR launch."""
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
function Tests:swgxrFeedbackFixture(mode)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "guard_failed" end
 local m=getSceneObject(readData("feedbackFixtureMob"))
 if mode=="cleanup" then
  if m then CreatureObject(m):clearCombatState(true);SceneObject(m):destroyObjectFromWorld() end
  deleteData("feedbackFixtureMob");CreatureObject(p):forcePeace();SceneObject(p):teleport({original[0]},{original[1]},{original[2]},0);return "clean"
 end
 if mode=="place" then
  CreatureObject(p):forcePeace();SceneObject(p):teleport(5800,getTerrainHeight(p,5800,-4804),-4804,0)
  m=spawnMobile("tatooine","smuggler",0,5801.5,getTerrainHeight(p,5801.5,-4804),-4804,0,0)
  AiAgent(m):setWait(60000);writeData("feedbackFixtureMob",SceneObject(m):getObjectID())
  return tostring(SceneObject(p):getWorldPositionX())..","..tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(p):getWorldPositionY())
 end
 return "unknown"
end
'''
 try:
  with native.screenplay('swgxrFeedbackFixture',source):
   try:
    pos=[float(v) for v in native.call('swgxrFeedbackFixture:place').split(',')]
    r=call('/combat/session/start',position=pos);sid=r['session_id'];r=call('/combat/session/update',session_id=sid,position=pos,ready=True)
    weapon=r['snapshot']['weapon']
    if not weapon['unarmed']:
     call('/inventory/unequip',live_session_id=sid,item_id=weapon['item_id'])
     r=call('/combat/session/update',session_id=sid,position=pos,ready=True);weapon=r['snapshot']['weapon']
    check(weapon['unarmed'],'Native equipped weapon is unarmed')
    origin=[pos[0],pos[1]+1.2,pos[2]]
    fields=dict(session_id=sid,shot_id='feedback_'+secrets.token_hex(8),item_id=weapon['item_id'],origin=origin,direction=[1,0,0])
    result=call('/combat/session/melee',**fields)['mutation']
    check(result.get('success') and bool(result.get('target_id')),'Real unarmed strike resolves against native NPC')
    check(result.get('resolution') in ('hit','miss','blocked','dodged','countered','deflected'),'Native attack exposes its actual defense result')
    check('before' in result and 'after' in result and 'damage' in result,'Confirmed hit includes authoritative HAM damage evidence')
    rows=result.get('combat_results',[])
    check(len(rows)==1 and rows[0]['target_id']==result['target_id'] and rows[0]['resolution']==result['resolution'] and rows[0]['damage']==sum(max(0,b-a) for b,a in zip(result['before']['ham'],result['after']['ham'])),'Per-target feedback matches actual native HAM loss')
    r=call('/combat/session/update',session_id=sid,position=pos,ready=True)
    check(r['snapshot']['player']['warcry']['learned'] and r['snapshot']['player']['warcry']['conditions_met'],'Native novice Brawler can use Warcry unarmed')
    time.sleep(2)
    result=call('/combat/session/warcry',**dict(fields,shot_id='warcry_'+secrets.token_hex(8)))['mutation']
    check(result.get('success') and result.get('attempted',0)>0,'Unarmed Warcry reaches native resistance resolution')
    check(len(result.get('combat_results',[]))==result['attempted'] and all(row['resolution'] in ('resisted','applied','ineffective') for row in result['combat_results']),'Every Warcry target emits its real effect or resistance result')
    report['passed']=True
   finally:
    if sid:call('/combat/session/stop',session_id=sid);sid=''
    native.call('swgxrFeedbackFixture:cleanup')
 finally:(ROOT/'runtime/evidence/rec-review/hit-feedback-native.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
