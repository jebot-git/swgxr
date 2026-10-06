#!/usr/bin/env python3
"""Append isolated native cross-zone conceal and final-charge regression evidence."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 evidence=ROOT/'runtime/evidence/ranger-native.json';report=json.loads(evidence.read_text());assert report['passed']
 owner=json.loads((ROOT/'runtime/server/ranger-fixtures.json').read_text())[0];assert owner['account'].startswith('invtestranger')
 records=[];checks=[];session='';added='';ctx={};passed=False;script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 def check(value,label):
  checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True)
  if not value:raise AssertionError(label)
 def call(path,**kw):
  result=req(path,dict(account=owner['account'],character_id=owner['id'],**kw));records.append(dict(path=path,owner=owner['id'],response=redact(result)));return result
 def ranger(action='ranger_status',**kw):
  if action!='ranger_status':kw.setdefault('request_id','ranger_zone_'+secrets.token_hex(10))
  return call('/scout/'+action,live_session_id=session,**(ctx|kw))
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(100):
   with log.open()as f:f.seek(offset);text=f.read()
   match=re.search('runLuaFunction Tests:'+name+r': result=([^\n]+)',text)
   if match:
    result=match.group(1).strip().strip('[]');records.append(dict(native_screenplay=name,result=result));return result
   time.sleep(.1)
  raise RuntimeError('Native screenplay timeout '+name)
 def success(r):return r.get('mutation',{}).get('success')is True
 try:
  entered=call('/enter');saved=entered['source_location'];opened=call('/combat/session/start',**{k:saved[k]for k in ('position','zone','building_id','cell_index')});session=opened['session_id'];ctx=dict(position=[3527,5,-4810],zone='tatooine',building_id='0',cell_index=0)
  call('/session/update',session_id=session,ready=True,**ctx)
  state=ranger()['state']['ranger'];tat=next(k for k in state['kits']if k['effective_zone']=='tatooine'and k['charges']>0);nab=next(k for k in state['kits']if k['effective_zone']=='naboo'and k['charges']>0)
  added=f'''\n-- BEGIN ranger-zone-fixture\nfunction Tests:swgxrRangerZonePrepare() local p=getSceneObject({owner['id']});CreatureObject(p):clearCombatState(true);CreatureObject(p):setBuffDuration(getHashCode("skill_buff_mask_scent"),1);TangibleObject(getSceneObject({nab['id']})):setUseCount(1) end
function Tests:swgxrRangerZoneNaboo() local p=getSceneObject({owner['id']});SceneObject(p):switchZone("naboo",-4858,0,4168,0);local y=getTerrainHeight(p,-4858,4168);SceneObject(p):teleport(-4858,y,4168,0);return tostring(y) end
function Tests:swgxrRangerZoneRestore() local p=getSceneObject({owner['id']});CreatureObject(p):clearCombatState(true);SceneObject(p):switchZone("tatooine",3527,5,-4810,0) end
-- END ranger-zone-fixture\n'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');lua('swgxrRangerZonePrepare');time.sleep(2)
  first=ranger('conceal',item_id=tat['id']);check(success(first)and first['mutation']['conceal']['active'],'Zone fixture applies real Tatooine conceal before original zone transition')
  y=float(lua('swgxrRangerZoneNaboo'));ctx=dict(position=[-4858,y,4168],zone='naboo',building_id='0',cell_index=0)
  stale=ranger()['state']['ranger'];check(not stale['conceal']['active']and stale['conceal']['zone']=='tatooine'and stale['conceal']['remaining_seconds']>0,'Foreign-planet retained buff is correctly inactive after original switchZone')
  tat_before=next(k['charges']for k in stale['kits']if k['id']==tat['id']);wrong=ranger('conceal',item_id=tat['id']);after_wrong=ranger()['state']['ranger'];check(not success(wrong)and next(k['charges']for k in after_wrong['kits']if k['id']==tat['id'])==tat_before and after_wrong['conceal']['zone']=='tatooine','Rejected wrong-planet kit preserves both charge and stale buff')
  before={k['id']:k['charges']for k in after_wrong['kits']};key='ranger_zone_final_'+secrets.token_hex(10);replacement=ranger('conceal',item_id=nab['id'],request_id=key)
  check(success(replacement)and replacement['mutation']['conceal']['active']and replacement['mutation']['conceal']['zone']=='naboo','Correct planet kit replaces stale native buff rather than toggling it off')
  check(replacement['mutation']['charges_remaining']==0 and all(k['id']!=nab['id']for k in replacement['state']['ranger']['kits']),'Original final charge destroys the selected kit and removes it from owned inventory projection')
  retry=ranger('conceal',item_id=nab['id'],request_id=key);after_retry={k['id']:k['charges']for k in retry['state']['ranger']['kits']};check(success(retry)and retry['mutation'].get('replayed')and after_retry=={k:v for k,v in before.items()if k!=nab['id']},'Retry after native kit destruction replays receipt without consuming any other kit')
  lua('swgxrRangerZoneRestore');ctx=dict(position=[3527,5,-4810],zone='tatooine',building_id='0',cell_index=0);check(not ranger()['state']['ranger']['conceal']['active'],'Returning to Tatooine invalidates the retained Naboo conceal buff')
  advanced=json.loads((ROOT/'runtime/server/ranger-fixtures.json').read_text())[1];advanced_base=dict(account=advanced['account'],character_id=advanced['id']);advanced_session=''
  def advanced_call(path,**kw):
   r=req(path,advanced_base|kw);records.append(dict(path=path,owner=advanced['id'],response=redact(r)));return r
  try:
   entry=advanced_call('/enter');advanced_ctx={k:entry['source_location'][k]for k in ('position','zone','building_id','cell_index')};opened=advanced_call('/combat/session/start',**advanced_ctx);advanced_session=opened['session_id'];advanced_call('/session/update',session_id=advanced_session,ready=True,**advanced_ctx)
   started=advanced_call('/scout/area_track',live_session_id=advanced_session,request_id='ranger_bounded_'+secrets.token_hex(10),track_type='npc',**advanced_ctx);check(success(started),'Source master tracking starts for bounded-count regression')
   for _ in range(12):
    state=advanced_call('/scout/ranger_status',live_session_id=advanced_session,**advanced_ctx);tracking=state['state']['ranger']['tracking']
    if tracking['state']!='pending':break
    time.sleep(1)
   check(tracking['state']=='succeeded'and tracking['total_results']>=len(tracking['results'])and tracking['truncated']==(tracking['total_results']>len(tracking['results']))and len(tracking['results'])<=256,'Native tracking exposes precise source count and honest truncation without coordinate disclosure')
  finally:
   if advanced_session:advanced_call('/combat/session/stop',session_id=advanced_session)
  passed=True;report['checks'].extend(checks);report['responses'].extend(records);report['zone_regression_setup']='Existing isolated novice fixture only; administrator source switchZone and one-charge kit setup. Native conceal, charge destruction and receipt remain original. No travel-ticket behavior claimed.'
  evidence.write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=True,checks=len(checks),combined_checks=len(report['checks']))),flush=True)
 finally:
  if added:
   lua('swgxrRangerZoneRestore');script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  if session:call('/combat/session/stop',session_id=session)
  (ROOT/'runtime/evidence/ranger-zone-native.json').write_text(json.dumps(redact(dict(passed=passed,checks=checks,responses=records)),indent=2))
if __name__=='__main__':main()
