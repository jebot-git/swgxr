#!/usr/bin/env python3
"""Isolated native GCW rules; administrator setup is explicit, no remote changes."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 checks=[];records=[];fixtures=[];sessions={};contexts={};marker='gcw_'+secrets.token_hex(5);added=''
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 report=dict(passed=False,native_execution=True,headset_tested=False,remote_server_changed=False,checks=checks,responses=records,fixtures=fixtures,fixture_setup='Fresh novice artisan accounts; administrator spawns original recruiters/scanner in a city outdoor area (opposing recruiter fixture awareness is disabled to isolate its UI; scanner AI remains original), grants test credits/standing/spice (rank is earned by the native promotion operation). Trusted screenplay enforced=true bypasses only scan selection chance; original task sequence, detection/fines/receipts remain native. During the long pending-duty wait, only the isolated combatant fixture is held at source altitude1000m and heartbeated to exclude unrelated NPC combat; it returns to source ground before NPC/recruiter checks. This is not a proof of random autonomous wild-scan selection.')
 def check(v,label):
  checks.append(dict(passed=bool(v),label=label));print(label,bool(v),flush=True)
  if not v:
   for fixture in fixtures:
    if fixture['id']in sessions:
     try:update(fixture)
     except Exception:pass
   raise AssertionError(label)
 def call(o,path,**kw):
  for _ in range(10):
   out=req(path,dict(account=o['account'],character_id=o['id'],**kw));records.append(dict(path=path,owner=o['id'],response=redact(out)))
   if out.get('error_code')!='backend_busy' or out.get('mutation_started')is not False:return out
   time.sleep(1)
  return out
 def service(o,action='status',**kw):
  if action not in ('status','open'):kw.setdefault('request_id','gcw_'+secrets.token_hex(10))
  return call(o,'/services/'+action,live_session_id=sessions[o['id']],**(contexts[o['id']]|kw))
 def update(o):return call(o,'/session/update',session_id=sessions[o['id']],ready=True,**contexts[o['id']])
 def enter(o):
  entry=call(o,'/enter');loc={k:entry['source_location'][k]for k in ('position','zone','building_id','cell_index')};r=call(o,'/combat/session/start',**loc);sessions[o['id']]=r['session_id'];return r
 def okay(out):return out.get('mutation',{}).get('success')is True
 def denied(out):return out.get('http_error')==400 or out.get('mutation',{}).get('success')is False
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(120):
   with log.open()as f:f.seek(offset);s=f.read()
   match=re.search('runLuaFunction Tests:'+name+r': result=([^\n]+)',s)
   if match:
    result=match.group(1).strip().strip('[]');records.append(dict(native_screenplay=name,result=result));return result
   if 'Failed to runLuaFunction'in s:raise RuntimeError(s[-1500:])
   time.sleep(.1)
  raise RuntimeError('Native screenplay timeout '+name)
 try:
  for i in range(2):
   o=dict(account='invtestgcw'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8)));created=req('/characters',dict(o,species='human',profession='crafting_artisan'))
   for attempt in range(5):
    if 'character'in created or 'name_declined_'not in created.get('error',''):break
    report.setdefault('name_rejections',[]).append(created['error']);o['name']='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8));created=req('/characters',dict(o,species='human',profession='crafting_artisan'))
   assert 'character'in created,created;o['id']=created['character']['id'];fixtures.append(o);enter(o);contexts[o['id']]=dict(position=[3527+i*50,5,-4810],zone='tatooine',building_id='0',cell_index=0);update(o)
  a,b=fixtures;(ROOT/'runtime/server/gcw-fixtures.json').write_text(json.dumps(fixtures))
  added=f'''
-- BEGIN {marker}
function Tests:swgxrGcwSetup()
 local p=getSceneObject({a['id']});local y=getTerrainHeight(p,3527,-4810);writeData("{marker}:height",y)
 for i,id in ipairs({{{a['id']},{b['id']}}}) do SceneObject(getSceneObject(id)):teleport(3477+i*50,y,-4810,0) end
 for _,row in ipairs({{{{"recruiter","rebel_recruiter",3529}},{{"imperial","imperial_recruiter",3525}},{{"scanner","stormtrooper",3579}}}}) do local n=spawnMobile("tatooine",row[2],0,row[3],y,-4810,0,0);if n then if row[1]=="imperial" then AiAgent(n):setAITemplate("none") end;AiAgent(n):setHomeLocation(row[3],y,-4810,nil);writeData("{marker}:"..row[1],SceneObject(n):getObjectID()) end end
 local terminal=spawnSceneObject("tatooine","object/tangible/terminal/terminal_mission_rebel.iff",3527,y,-4808,0,0);writeData("{marker}:mission",SceneObject(terminal):getObjectID())
 return tostring(y)..","..tostring(readData("{marker}:recruiter"))..","..tostring(readData("{marker}:imperial"))..","..tostring(readData("{marker}:scanner"))..","..tostring(readData("{marker}:mission"))
end
function Tests:swgxrGcwLambdaType() local n=spawnSceneObject("tatooine","object/creature/npc/theme_park/lambda_shuttle.iff",3600,5,-4900,0,0);if n==nil then return "missing" end;local value=tostring(SceneObject(n):getGameObjectType())..","..tostring(SceneObject(n):isAiAgent())..","..tostring(SceneObject(n):isCreatureObject());SceneObject(n):destroyObjectFromWorld();return value end
function Tests:swgxrGcwFunds() local p=getSceneObject({a['id']});PlayerObject(CreatureObject(p):getPlayerObject()):setFactionStanding("rebel",5000);CreatureObject(getSceneObject({b['id']})):addCashCredits(10000,true) end
function Tests:swgxrGcwPvp() local a=getSceneObject({a['id']});local b=getSceneObject({b['id']});CreatureObject(b):setFaction(3679112276);CreatureObject(a):setFactionStatus(2);CreatureObject(b):setFactionStatus(2);local ret=CreatureObject(a):isAttackableBy(b) or CreatureObject(b):isAttackableBy(a);CreatureObject(a):setFactionStatus(1);CreatureObject(b):setFaction(0);CreatureObject(b):setFactionStatus(0);return ret and "1" or "0" end
function Tests:swgxrGcwNpcCombat() local a=getSceneObject({a['id']});local n=getSceneObject(readData("{marker}:scanner"));return (CreatureObject(a):isAttackableBy(n) and CreatureObject(n):isAttackableBy(a)) and "1" or "0" end
function Tests:swgxrGcwSpice() local p=getSceneObject({b['id']});local inv=SceneObject(p):getSlottedObject("inventory");local bag=giveItem(inv,"object/tangible/container/general/satchel.iff",-1);local spice=giveItem(bag,"object/tangible/food/spice/spice_booster_blue.iff",-1);return spice and tostring(SceneObject(spice):getObjectID()) or "0" end
function Tests:swgxrGcwScan() local n=getSceneObject(readData("{marker}:scanner"));return AiAgent(n):startContrabandScan(getSceneObject({b['id']}),true) and "1" or "0" end
function Tests:swgxrGcwCleanup() for _,key in ipairs({{"recruiter","imperial","scanner","mission"}}) do local n=getSceneObject(readData("{marker}:"..key));if n then SceneObject(n):destroyObjectFromWorld() end;deleteData("{marker}:"..key) end end
-- END {marker}
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');raw=lua('swgxrGcwSetup').split(',');height=float(raw[0]);recruiter,imperial,scanner,mission_terminal=raw[1:];report['lambda_native_type']=lua('swgxrGcwLambdaType')
  for o in fixtures:contexts[o['id']]['position'][1]=height;update(o)
  opened=service(a,'open',terminal_id=recruiter);check(okay(opened)and opened['state']['terminal']['kind']=='recruiter','Actual original recruiter opens native terminal interface')
  check(opened['state']['terminal']['can_join']and len(opened['state']['terminal']['rewards'])>8,'Neutral character sees simple join and complete scrollable source rewards')
  check(any(t['id']==recruiter for t in opened['state']['terminals']),'Original recruiter is present in terminal targeting collection')
  key='gcw_join_'+secrets.token_hex(8);joined=service(a,'recruiter_join',terminal_id=recruiter,request_id=key);check(okay(joined)and joined['state']['gcw']['status']==1 and joined['state']['gcw']['faction']=='rebel','Simple neutral join applies original Rebel combatant status without standing grant')
  replay=service(a,'recruiter_join',terminal_id=recruiter,request_id=key);check(replay.get('mutation',{}).get('replayed'),'Stable join retry is idempotent')
  check(denied(service(a,'recruiter_join',terminal_id=imperial)),'Already affiliated player cannot join opposing faction')
  reward=next(row for row in service(a,'open',terminal_id=recruiter)['state']['terminal']['rewards']if row['key']=='frn_cabinet')
  check(denied(service(a,'recruiter_purchase',terminal_id=recruiter,reward_id=reward['id'])),'Native reward purchase requires original faction standing reserve')
  lua('swgxrGcwFunds');check(sum(service(b)['state']['wallet'].values())>=2000,'Administrator credit prerequisite is verified before original scan');view=service(a,'open',terminal_id=recruiter)['state']['terminal'];key='gcw_promote_'+secrets.token_hex(8);before_promotion=service(a)['state']['gcw']['standings']['rebel'];promoted=service(a,'recruiter_promote',terminal_id=recruiter,expected_rank=0,request_id=key)
  check(okay(promoted)and promoted['mutation']['rank']==1 and before_promotion-promoted['state']['gcw']['standings']['rebel']==view['promotion_cost_faction_points'],'Original rank0 to rank1 promotion charges native cost and advances rank')
  check(service(a,'recruiter_promote',terminal_id=recruiter,expected_rank=0,request_id=key).get('mutation',{}).get('replayed'),'Promotion replay is idempotent')
  check(denied(service(a,'recruiter_promote',terminal_id=recruiter,expected_rank=0)),'Stale expected rank cannot promote again')
  lua('swgxrGcwFunds');reward=next(row for row in service(a,'open',terminal_id=recruiter)['state']['terminal']['rewards']if row['id']==reward['id']);before=service(a)['state']['gcw']['standings']['rebel'];key='gcw_buy_'+secrets.token_hex(8)
  bought=service(a,'recruiter_purchase',terminal_id=recruiter,reward_id=reward['id'],request_id=key);check(okay(bought)and bought['mutation']['faction_points_paid']==reward['cost_faction_points']and bought['state']['gcw']['standings']['rebel']==before-reward['cost_faction_points'],'Original awardItem charges actual native discounted price')
  check(any(i.get('template')==reward['template']for i in bought['state']['inventory']['items']),'Purchased original reward enters real inventory')
  replay=service(a,'recruiter_purchase',terminal_id=recruiter,reward_id=reward['id'],request_id=key);check(replay.get('mutation',{}).get('replayed')and replay['state']['gcw']['standings']==bought['state']['gcw']['standings'],'Purchase replay never charges twice')
  offers=service(a,'mission_refresh',terminal_id=mission_terminal);rows=offers.get('state',{}).get('terminal',{}).get('missions',[]);check(okay(offers)and any(row.get('faction')=='rebel'and row.get('faction_points',{}).get('rebel',0)>0 for row in rows),'Original faction terminal generates source missions with native faction rewards')
  offer=next(row for row in rows if row['supported']);accepted=service(a,'mission_accept',terminal_id=mission_terminal,mission_id=offer['id']);check(okay(accepted)and any(row['id']==offer['id']for row in accepted['state']['missions']),'Original faction PvE mission accepts through shared authoritative mission flow')
  check(okay(service(a,'mission_abort',mission_id=offer['id'])),'Faction mission cancellation uses original objective cleanup')
  check(lua('swgxrGcwPvp')=='0','Opposed original OVERT players remain mutually nonattackable in PvE scope')
  check(lua('swgxrGcwNpcCombat')=='1','Original enemy faction NPC combat is mutually available to combatant')
  check(denied(service(a,'recruiter_status_toggle',terminal_id=recruiter,expected_status=0)),'Stale salute status is rejected')
  left=service(a,'recruiter_status_toggle',terminal_id=recruiter,expected_status=1);check(okay(left)and left['mutation']['delay_ms']==300000 and left['state']['gcw']['pending_status']==0,'Salute queues original five-minute on-leave transition')
  check(denied(service(a,'recruiter_status_toggle',terminal_id=recruiter,expected_status=1)),'Repeated salute cannot restart pending native transition')
  contexts[a['id']]['position'][1]=1000;update(a)
  spice=lua('swgxrGcwSpice');check(spice!='0'and service(b)['state']['gcw']['scan']['contraband_count']==1,'Original contraband detection includes a single nested item')
  check(lua('swgxrGcwScan')=='1','Administrator-selected original enforced scan schedules native task')
  phases=set();speech=False
  for _ in range(90):
   update(a);state=service(b);scan=state['state']['gcw']['scan'];phases.add(scan['phase']);native=update(b);speech=speech or any(e['actor_id']==scanner for e in native['snapshot']['player']['npc_speech']['events'])
   if scan['answer_pending']:break
   time.sleep(1)
  check(scan['answer_pending']and scan['fine']==2000 and len(phases)>=3,'Actual native scan task progresses through source phases and issues original fine')
  check(speech,'Actual scanner emits source speech through native chatter replication')
  check(denied(service(b,'contraband_answer',scan_id='1',accept=True)),'Old or foreign scan identity cannot answer current fine')
  before=state['state']['wallet'];key='gcw_fine_'+secrets.token_hex(8);paid=service(b,'contraband_answer',scan_id=scan['id'],accept=True,request_id=key);check(okay(paid)and paid['mutation']['pending_native_scan'],'Fine answer is queued on original scan session')
  for _ in range(10):
   final=service(b)
   if not final['state']['gcw']['scan']['active']:break
   time.sleep(1)
  check(not final['state']['gcw']['scan']['active']and sum(before.values())-sum(final['state']['wallet'].values())==2000,'Original scan task charges exactly the accepted fine and finishes')
  replay=service(b,'contraband_answer',scan_id=scan['id'],accept=True,request_id=key);check(replay.get('mutation',{}).get('replayed')and replay['state']['wallet']==final['state']['wallet'],'Fine response replay never charges again')
  check(final['state']['gcw']['scan']['contraband_count']==1,'Original contraband fine preserves the item; no invented confiscation')
  check(lua('swgxrGcwScan')=='1','Second explicitly administered native scan starts for refusal regression')
  for _ in range(90):
   update(a);refused_state=service(b);scan2=refused_state['state']['gcw']['scan']
   if scan2['answer_pending']:break
   time.sleep(1)
  check(scan2['answer_pending']and scan2['id']!=scan['id'],'New native scan has a distinct fine identity')
  wallet=refused_state['state']['wallet'];standing=refused_state['state']['gcw']['standings']['imperial'];refused=service(b,'contraband_answer',scan_id=scan2['id'],accept=False);check(okay(refused),'Original fine may be refused explicitly')
  for _ in range(10):
   finished=service(b)
   if not finished['state']['gcw']['scan']['active']:break
   time.sleep(1)
  check(not finished['state']['gcw']['scan']['active']and finished['state']['wallet']==wallet and finished['state']['gcw']['standings']['imperial']==standing-100,'Original refusal deducts100 faction points and leaves credits unchanged')
  call(a,'/combat/session/stop',session_id=sessions.pop(a['id']));enter(a);update(a);persist=service(a);check(persist['state']['gcw']['faction']=='rebel'and persist['state']['gcw']['standings']==bought['state']['gcw']['standings'],'Faction and purchased reward standing persist through real logout/login')
  for _ in range(155):
   update(a);out=service(a)
   if out['state']['gcw']['status']==0 and not out['state']['gcw']['changing']:break
   time.sleep(2)
  check(out['state']['gcw']['status']==0 and not out['state']['gcw']['changing'],'Original on-leave callback completes after full source delay across logout')
  contexts[a['id']]['position'][1]=height;update(a)
  check(lua('swgxrGcwNpcCombat')=='0','On-leave status blocks normal faction NPC combat')
  resume=service(a,'recruiter_status_toggle',terminal_id=recruiter,expected_status=0);check(okay(resume)and resume['mutation']['delay_ms']==30000,'Salute resumes combatant duty using original30second delay')
  for _ in range(40):
   update(a);out=service(a)
   if out['state']['gcw']['status']==1 and not out['state']['gcw']['changing']:break
   time.sleep(1)
  check(out['state']['gcw']['status']==1 and not out['state']['gcw']['changing'],'Original resume-duty task completes naturally')
  report['passed']=True
 finally:
  try:
   if added:lua('swgxrGcwCleanup')
  except Exception as exc:report['cleanup_error']=str(exc)
  if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  for o in fixtures:
   if o['id']in sessions:
    try:
     contexts[o['id']]['position'][1]=5;update(o)
    except Exception:pass
    try:call(o,'/combat/session/stop',session_id=sessions[o['id']])
    except Exception as exc:report.setdefault('logout_errors',[]).append(str(exc))
  path=ROOT/'runtime/evidence/gcw-native.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2));print(path,flush=True)
if __name__=='__main__':main()
