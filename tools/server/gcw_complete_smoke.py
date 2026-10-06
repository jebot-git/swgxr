#!/usr/bin/env python3
"""Continue completed native GCW transactions after the isolated fixture died while idle."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 path=ROOT/'runtime/evidence/gcw-native.json';report=json.loads(path.read_text());assert len(report['checks'])>=35 and all(c['passed']for c in report['checks'])
 path.with_name('gcw-native-before-timer-continuation.json').write_text(json.dumps(report,indent=2))
 a=report['fixtures'][0];assert a['account'].startswith('invtestgcw');session=None;script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';marker='gcw_complete_'+secrets.token_hex(5);added='';context=dict(position=[3527,5,-4810],zone='tatooine',building_id='0',cell_index=0)
 report['continuation_setup']='The previous original combatant fixture was killed by native NPCs while idle and its retained session expired. Its earlier35successful checks are preserved. Administrator repair restores only this isolated test character HAM/posture/defenders, not faction, rank, standing or duty. Verify the original300s callback completed naturally while logged out, then continuously heartbeat during original30s resume.'
 prior=next(e['response']for e in reversed(report['responses'])if e.get('owner')==a['id']and e.get('path')=='/services/recruiter_purchase'and e['response'].get('mutation',{}).get('success'))
 expected=prior['state']['gcw']['standings'];reward=prior['mutation']['reward_id'];catalog=json.loads((ROOT/'runtime/assets/gcw/catalog.json').read_text());template=next(r['template']for r in catalog['rewards']if r['id']==reward)
 def call(route,**kw):
  out=req(route,dict(account=a['account'],character_id=a['id'],**kw));report['responses'].append(dict(path=route,owner=a['id'],response=redact(out)));return out
 def service(action='status',**kw):
  if action not in ('status','open'):kw.setdefault('request_id','gcw_continue_'+secrets.token_hex(8))
  return call('/services/'+action,live_session_id=session,**(context|kw))
 def check(v,label):
  report['checks'].append(dict(passed=bool(v),label=label));print(label,bool(v),flush=True)
  if not v:raise AssertionError(label)
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(100):
   with log.open()as f:f.seek(offset);s=f.read()
   match=re.search('runLuaFunction Tests:'+name+r': result=([^\n]+)',s)
   if match:
    value=match.group(1).strip().strip('[]');report['responses'].append(dict(native_screenplay=name,result=value));return value
   time.sleep(.1)
  raise RuntimeError('Native screenplay timeout '+name)
 try:
  enter=call('/enter');location={k:enter['source_location'][k]for k in ('position','zone','building_id','cell_index')};start=call('/combat/session/start',**location);session=start['session_id']
  added=f'''
-- BEGIN {marker}
function Tests:swgxrGcwContinueSetup()
 local p=getSceneObject({a['id']});CreatureObject(p):clearCombatState(true);for i=0,8 do CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end;CreatureObject(p):setPosture(0);SceneObject(p):teleport(3527,5,-4810,0)
 local n=spawnMobile("tatooine","rebel_recruiter",0,3529,5,-4810,0,0);writeData("{marker}:recruiter",SceneObject(n):getObjectID());local enemy=spawnMobile("tatooine","stormtrooper",0,3650,5,-4810,0,0);writeData("{marker}:enemy",SceneObject(enemy):getObjectID());return tostring(SceneObject(n):getObjectID())
end
function Tests:swgxrGcwContinueNpcCombat() local a=getSceneObject({a['id']});local n=getSceneObject(readData("{marker}:enemy"));return (CreatureObject(a):isAttackableBy(n) or CreatureObject(n):isAttackableBy(a)) and "1" or "0" end
function Tests:swgxrGcwContinueCleanup() for _,k in ipairs({{"recruiter","enemy"}}) do local n=getSceneObject(readData("{marker}:"..k));if n then SceneObject(n):destroyObjectFromWorld() end;deleteData("{marker}:"..k) end end
-- END {marker}
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');recruiter=lua('swgxrGcwContinueSetup');ready=call('/session/update',session_id=session,ready=True,**context);check(not ready['snapshot']['player']['dead']and ready['snapshot']['player']['ham'][0]>0,'Isolated fixture HAM/posture repair verified without altering faction data')
  state=service()['state'];check(state['gcw']['faction']=='rebel'and state['gcw']['standings']==expected,'Faction and original purchase standing persist through native logout/login')
  # Inventory is requested through the existing owned inventory bridge, not fabricated from a reward row.
  inventory=call('/inventory/status',live_session_id=session,**context);items=inventory.get('state',inventory).get('items',[])
  if not items:items=inventory.get('inventory',{}).get('items',[])
  check(any(item.get('template')==template for item in items),'Original purchased faction reward persists in native inventory')
  check(state['gcw']['status']==0 and not state['gcw']['changing'],'Original300second on-leave callback completed naturally while logged out')
  check(lua('swgxrGcwContinueNpcCombat')=='0','Living on-leave player and enemy faction NPC are mutually nonattackable')
  resumed=service('recruiter_status_toggle',terminal_id=recruiter,expected_status=0);check(resumed.get('mutation',{}).get('success')and resumed['mutation']['delay_ms']==30000,'Salute queues original30second return to combatant duty')
  for _ in range(40):
   call('/session/update',session_id=session,ready=True,**context);final=service()['state']
   if final['gcw']['status']==1 and not final['gcw']['changing']:break
   time.sleep(1)
  check(final['gcw']['status']==1 and not final['gcw']['changing'],'Original resume-duty task completes naturally with continuous native presence')
  report['passed']=True
 finally:
  if added:
   try:lua('swgxrGcwContinueCleanup')
   except Exception as exc:report['continuation_cleanup_error']=str(exc)
   script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  if session:call('/combat/session/stop',session_id=session)
  path.write_text(json.dumps(report,indent=2));print(path,flush=True)
if __name__=='__main__':main()
