#!/usr/bin/env python3
"""Original native Ranger regression; all administrator prerequisites are isolated."""
import json,re,secrets,time,sys
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 checks=[];records=[];fixtures=[];sessions={};contexts={};added='';marker='ranger_'+secrets.token_hex(5)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 report=dict(passed=False,native_execution=True,remote_server_changed=False,headset_tested=False,checks=checks,responses=records,fixtures=fixtures,ai_target_prospect_setup='Original setWatchObject selects the isolated fixture as the native awareness prospect; original range/LOS/camouflage/aggro behavior still decides attack. This is a controlled awareness test, not autonomous random target selection.',fixture_setup='Fresh novice artisan accounts. Trusted administrator screenplay gives original camouflage kits, Ranger prerequisites to only one fixture, and original isolated animal/humanoid/droid spawns. Powerful active buff expiry is accelerated through original setBuffDuration for cache regression. Actual kit consumption, command eligibility, AI detection, rescue threat, tracking delay/results and receipts remain native; not earned advanced progression.')
 def check(v,label):
  checks.append(dict(passed=bool(v),label=label));print(label,bool(v),flush=True)
  if not v:raise AssertionError(label)
 def call(o,path,**kw):
  for _ in range(12):
   out=req(path,dict(account=o['account'],character_id=o['id'],**kw));records.append(dict(path=path,owner=o['id'],response=redact(out)))
   if out.get('error_code')!='backend_busy' or out.get('mutation_started')is not False:return out
   time.sleep(1)
  return out
 def ranger(o,action='ranger_status',**kw):
  if action!='ranger_status':kw.setdefault('request_id','ranger_'+secrets.token_hex(10))
  return call(o,'/scout/'+action,live_session_id=sessions[o['id']],**(contexts[o['id']]|kw))
 def ent(o,action,**kw):return call(o,'/entertainer/'+action,live_session_id=sessions[o['id']],request_id='ranger_group_'+secrets.token_hex(8),**(contexts[o['id']]|kw))
 def denied(out):return out.get('http_error')==400 or out.get('mutation',{}).get('success')is False
 def okay(out):return out.get('mutation',{}).get('success')is True
 def lua(fn):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+fn)
  for _ in range(100):
   with log.open()as f:f.seek(offset);s=f.read()
   m=re.search(r'runLuaFunction Tests:'+fn+r': result=([^\n]+)',s)
   if m:
    records.append(dict(native_screenplay=fn,result=m.group(1)));return m.group(1).strip().strip('[]')
   if 'Failed to runLuaFunction'in s or 'Exception in runLuaFunction'in s:raise RuntimeError(s[-2000:])
   time.sleep(.1)
  raise RuntimeError('Native screenplay timed out '+fn)
 def kit(o,zone='tatooine'):
  return next(k for k in ranger(o)['state']['ranger']['kits']if k['effective_zone']==zone and k['charges']>0)
 def wait_track(o):
  for _ in range(12):
   out=ranger(o)
   if out['state']['ranger']['tracking'].get('state')!='pending':return out
   time.sleep(1)
  return out
 try:
  previous=json.loads((ROOT/'runtime/server/ranger-fixtures.json').read_text()) if '--reuse' in sys.argv else []
  for i in range(3):
   o=dict(account='invtestranger'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8)));o=previous[i] if previous else o;assert o['account'].startswith('invtestranger');r={'character':{'id':o['id']}} if previous else req('/characters',dict(o,species='human',profession='crafting_artisan'));assert 'character'in r,r;o['id']=r['character']['id'];fixtures.append(o)
   entry=call(o,'/enter');ctx={k:entry['source_location'][k]for k in ('position','zone','building_id','cell_index')};opened=call(o,'/combat/session/start',**ctx);sessions[o['id']]=opened['session_id'];contexts[o['id']]=dict(position=[3527+i*2,5,-4810],zone='tatooine',building_id='0',cell_index=0);call(o,'/session/update',session_id=opened['session_id'],ready=True,**contexts[o['id']])
  (ROOT/'runtime/server/ranger-fixtures.json').write_text(json.dumps(fixtures))
  report['reused_isolated_fixtures']=bool(previous)
  novice,advanced,recipient=fixtures
  added=f'''
-- BEGIN {marker}
function Tests:swgxrRangerSetup()
 for _,id in ipairs({{{','.join(o['id']for o in fixtures)}}}) do local p=getSceneObject(id);CreatureObject(p):setBuffDuration(getHashCode("skill_buff_mask_scent"),1);local inv=SceneObject(p):getSlottedObject("inventory");for n=1,4 do local k=giveItem(inv,"object/tangible/scout/camokit/camokit_tatooine.iff",-1);TangibleObject(k):setUseCount(5) end;local k=giveItem(inv,"object/tangible/scout/camokit/camokit_naboo.iff",-1);TangibleObject(k):setUseCount(5) end
 local ranger=getSceneObject({advanced['id']});for _,skill in ipairs({{{','.join('"'+x+'"'for x in reversed(json.loads((ROOT/'runtime/assets/services/trainers.json').read_text())['trainers']['trainer_ranger']['skill_ids']))}}}) do CreatureObject(ranger):removeSkill(skill) end
 local z=getTerrainHeight(getSceneObject({novice['id']}),3527,-4810)
 for key,template in pairs({{animal="bantha",npc="highwayman",droid="mouse_droid"}}) do local m=spawnMobile("tatooine",template,0,(key=="npc" and 3900 or key=="animal" and 4200 or 4500),z,-4810,0,0);if m~=nil then SceneObject(m):setCustomObjectName("SWGXR Ranger "..key);AiAgent(m):setLevel(key=="npc" and 90 or 1);writeData("{marker}:"..key,SceneObject(m):getObjectID()) end end
end
function Tests:swgxrRangerNovice() awardSkill(getSceneObject({advanced['id']}),"outdoors_ranger_novice") end
function Tests:swgxrRangerMaster() awardSkill(getSceneObject({advanced['id']}),"outdoors_ranger_master") end
function Tests:swgxrRangerDetect()
 local m=getSceneObject(readData("{marker}:npc"));local p=getSceneObject({advanced['id']});return AiAgent(m):isCamouflaged(p) and "1" or "0"
end
function Tests:swgxrRangerDetectNovice()
 local m=getSceneObject(readData("{marker}:animal"));local p=getSceneObject({novice['id']});return AiAgent(m):isCamouflaged(p) and "1" or "0"
end
function Tests:swgxrRangerDetectDroid()
 local m=getSceneObject(readData("{marker}:droid"));local p=getSceneObject({advanced['id']});return AiAgent(m):isCamouflaged(p) and "1" or "0"
end
function Tests:swgxrRangerExpire() CreatureObject(getSceneObject({advanced['id']})):setBuffDuration(getHashCode("skill_buff_mask_scent"),2) end
function Tests:swgxrRangerMoveAnimal()
 local m=getSceneObject(readData("{marker}:animal"));local p=getSceneObject({advanced['id']});SceneObject(m):teleport(3535,5,-4810,0);AiAgent(m):setHomeLocation(3535,5,-4810,nil);AiAgent(m):executeBehavior()
end
function Tests:swgxrRangerFight()
 local m=getSceneObject(readData("{marker}:npc"));local p=getSceneObject({novice['id']});SceneObject(m):teleport(3528,5,-4810,0);AiAgent(m):setHomeLocation(3528,5,-4810,nil);AiAgent(m):executeBehavior();AiAgent(m):setDefender(p)
end
function Tests:swgxrRangerApproach()
 local m=getSceneObject(readData("{marker}:npc"));CreatureObject(m):clearCombatState(true);AiAgent(m):setOblivious();AiAgent(m):clearCurrentPath();AiAgent(m):setWatchObject(getSceneObject({advanced['id']}));SceneObject(m):teleport(3531,5,-4810,0);AiAgent(m):setHomeLocation(3531,5,-4810,nil);AiAgent(m):executeBehavior()
end
function Tests:swgxrRangerHideEnemy()
 local m=getSceneObject(readData("{marker}:npc"));CreatureObject(m):clearCombatState(true);AiAgent(m):setOblivious();SceneObject(m):teleport(3900,5,-4810,0);AiAgent(m):setHomeLocation(3900,5,-4810,nil);AiAgent(m):executeBehavior()
 for _,id in ipairs({{{','.join(o['id']for o in fixtures)}}}) do CreatureObject(getSceneObject(id)):clearCombatState(true) end
end
function Tests:swgxrRangerWrongPlanet()
 local m=getSceneObject(readData("{marker}:npc"));SceneObject(m):switchZone("naboo",3900,0,-4810,0);return AiAgent(m):isCamouflaged(getSceneObject({advanced['id']})) and "1" or "0"
end
function Tests:swgxrRangerReturnPlanet()
 local m=getSceneObject(readData("{marker}:npc"));SceneObject(m):switchZone("tatooine",3900,5,-4810,0)
end
function Tests:swgxrRangerDebug()
 local m=getSceneObject(readData("{marker}:npc"));local p=getSceneObject({advanced['id']});local d=TangibleObject(m):getMainDefender();local f=AiAgent(m):getFollowObject()
 return "aggro="..tostring(AiAgent(m):isAggressiveTo(p))..",attackable="..tostring(CreatureObject(p):isAttackableBy(m))..",los="..tostring(AiAgent(m):checkLineOfSight(p))..",distance="..tostring(SceneObject(m):getDistanceTo(p))..",state="..tostring(AiAgent(m):getMovementState())..",combat="..tostring(AiAgent(m):isInCombat())..",defender="..tostring(d and SceneObject(d):getObjectID() or 0)..",follow="..tostring(f and SceneObject(f):getObjectID() or 0)..",invisible="..tostring(CreatureObject(p):isInvisible())..",players="..tostring(AiAgent(m):getNumberOfPlayersInRange())
end
function Tests:swgxrRangerEnemy()
 local m=getSceneObject(readData("{marker}:npc"));local d=TangibleObject(m):getMainDefender();return d~=nil and SceneObject(d):getObjectID()=={advanced['id']} and "1" or "0"
end
function Tests:swgxrRangerCleanup()
 for _,id in ipairs({{{','.join(o['id']for o in fixtures)}}}) do local p=getSceneObject(id);if p then CreatureObject(p):clearCombatState(true) end end
 for _,key in ipairs({{"npc","animal","droid"}}) do local m=getSceneObject(readData("{marker}:"..key));if m then CreatureObject(m):clearCombatState(true);SceneObject(m):destroyObjectFromWorld() end;deleteData("{marker}:"..key) end
end
-- END {marker}
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');lua('swgxrRangerSetup');time.sleep(2)
  for index,o in enumerate((novice,recipient)):
   contexts[o['id']]['position']=[3400+index*2,5,-4810];ranger(o)
  lua('swgxrRangerApproach')
  for _ in range(60):
   if lua('swgxrRangerEnemy')=='1':break
   time.sleep(.25)
  print(lua('swgxrRangerDebug'),flush=True)
  check(lua('swgxrRangerEnemy')=='1','Controlled original humanoid awareness acquires unprotected player before conceal')
  lua('swgxrRangerHideEnemy')
  for index,o in enumerate((novice,recipient)):
   contexts[o['id']]['position']=[3527+index*4,5,-4810];ranger(o)
  base=ranger(novice);check(okay(base)and base['state']['ranger']['camouflage']==0,'Untouched novice artisan can inspect native Ranger/kit state')
  check(denied(ranger(novice,'area_track',track_type='animal')),'Unlearned tracking rejected')
  first=kit(novice);foreign=kit(recipient);check(denied(ranger(novice,'conceal',item_id=foreign['id'])),'Kit ownership is native')
  wrong=kit(novice,'naboo');check(denied(ranger(novice,'conceal',item_id=wrong['id']))and next(k['charges']for k in ranger(novice)['state']['ranger']['kits']if k['id']==wrong['id'])==wrong['charges'],'Wrong-planet kit rejected without consuming it')
  key='ranger_conceal_'+secrets.token_hex(10);start=time.monotonic();applied=ranger(novice,'conceal',item_id=first['id'],request_id=key)
  check(okay(applied)and applied['mutation']['conceal']['power']==5 and 195<=applied['mutation']['conceal']['remaining_seconds']<=200,'Zero-skill artisan consumes kit and gets explicit200second baseline')
  check(applied['mutation']['charges_remaining']==first['charges']-1,'Exactly selected original kit charge consumed')
  replay=ranger(novice,'conceal',item_id=first['id'],request_id=key,position=[3527.05,5,-4810]);check(replay['mutation'].get('replayed'),'Changed tracked pose does not consume charge twice')
  held=kit(novice);check(denied(ranger(novice,'conceal',item_id=held['id']))and next(k['charges']for k in ranger(novice)['state']['ranger']['kits']if k['id']==held['id'])==held['charges'],'Already concealed self does not toggle buff or waste another kit')
  check(lua('swgxrRangerDetectNovice')=='1','Actual animal detection gate recognizes untrained kit concealment')
  lua('swgxrRangerNovice');state=ranger(advanced);check(state['state']['ranger']['track_types']==['animal'],'Original novice Ranger unlocks animal tracking only')
  check(denied(ranger(advanced,'area_track',track_type='npc')),'Unlearned humanoid tracking denied')
  lua('swgxrRangerMoveAnimal');scan=ranger(advanced,'area_track',track_type='animal');check(okay(scan)and scan['mutation']['pending'],'Original6second tracking task starts')
  duplicate=ranger(advanced,'area_track',track_type='animal',request_id=scan['mutation']['request_id']);check(duplicate['mutation'].get('replayed'),'Tracking retry keeps one original task')
  results=wait_track(advanced);tracking=results['state']['ranger']['tracking'];check(tracking['state']=='succeeded'and any(r['name']=='SWGXR Ranger animal'for r in tracking['results']),'Original source tracking task finds actual nearby animal')
  check(all(not {'id','position','direction','distance'}&r.keys()for r in tracking['results']),'Novice tracks expose names only, not unlearned direction/distance or exact positions')
  lua('swgxrRangerMaster');master=ranger(advanced);check(master['state']['ranger']['track_types']==['animal','npc','player']and master['state']['ranger']['camouflage']>5,'Original master Ranger skill grants and tracking filters refreshed')
  advancedkit=kit(advanced);selfbuff=ranger(advanced,'conceal',item_id=advancedkit['id']);check(okay(selfbuff)and selfbuff['mutation']['conceal']['power']==master['state']['ranger']['camouflage']//2,'Original Ranger power scaling retained')
  # Original level-90 humanoid detection remains probabilistic; retry only through native cooldown.
  detected=lua('swgxrRangerDetect')
  for _ in range(3):
   if detected=='1':break
   for _ in range(15):
    for o in fixtures:ranger(o)
    time.sleep(5)
   again=ranger(advanced,'conceal',item_id=kit(advanced)['id']);check(okay(again),'Retry original failed detection after native cooldown');detected=lua('swgxrRangerDetect')
  check(detected=='1','Actual level90 aggressive humanoid NPC detection honors Ranger concealment')
  check(lua('swgxrRangerDetect')=='1','Same buff application reuses native cached success')
  check(lua('swgxrRangerDetectDroid')=='0','Original droid exception remains detectable')
  rkit=kit(advanced);target=contexts[recipient['id']]['position'];hand=[target[0],target[1]+1.5,target[2]]
  check(denied(ranger(advanced,'conceal',item_id=rkit['id'],target_id=recipient['id'],hand_position=[3529,7.5,-4810])),'Other-player camouflage requires hand touching actual source body')
  other=ranger(advanced,'conceal',item_id=rkit['id'],target_id=recipient['id'],hand_position=hand);check(okay(other)and other['mutation']['target_id']==recipient['id'],'Original kit applies native conceal to touched other player')
  check(other['mutation']['conceal']['power']==selfbuff['mutation']['conceal']['power']and ranger(recipient)['state']['ranger']['camouflage']==0,'Untrained recipient receives casterhalf; source AI has no recipient bonus')
  for index,o in enumerate((novice,recipient)):
   contexts[o['id']]['position']=[3400+index*2,5,-4810];ranger(o)
  lua('swgxrRangerApproach');time.sleep(3);check(lua('swgxrRangerEnemy')=='0','Controlled original awareness does not attack concealed Ranger nearby')
  lua('swgxrRangerExpire');time.sleep(3);check(not ranger(advanced)['state']['ranger']['conceal']['active'],'Original duration event expires accelerated diagnostic buff')
  check(lua('swgxrRangerDetect')=='0','Humanoid NPC cannot reuse cached conceal success after expiry')
  for _ in range(20):
   if lua('swgxrRangerEnemy')=='1':break
   time.sleep(.25)
  check(lua('swgxrRangerEnemy')=='1','Controlled original awareness attacks Ranger after buff expiry')
  lua('swgxrRangerHideEnemy')
  renewed=ranger(advanced,'conceal',item_id=kit(advanced)['id']);check(okay(renewed),'New original kit application restores native buff')
  detected=lua('swgxrRangerDetect')
  for _ in range(3):
   if detected=='1':break
   for _ in range(15):
    for o in fixtures:ranger(o)
    time.sleep(5)
   again=ranger(advanced,'conceal',item_id=kit(advanced)['id']);check(okay(again),'Reapplication retry respects native detection-failure cooldown');detected=lua('swgxrRangerDetect')
  check(detected=='1','New original kit application re-establishes valid humanoid concealment')
  check(lua('swgxrRangerWrongPlanet')=='0','Cached humanoid success cannot bypass original kit planet binding');lua('swgxrRangerReturnPlanet')
  for index,o in enumerate((novice,recipient)):
   contexts[o['id']]['position']=[3527+index*4,5,-4810];ranger(o)
  track=ranger(advanced,'area_track',track_type='npc');check(okay(track),'Master accepts original humanoid filter');tracked=wait_track(advanced)['state']['ranger']['tracking'];check(tracked['state']=='succeeded'and all('direction'in r and 'distance'in r and 'position'not in r for r in tracked['results']),'Master receives source direction and integer distance only')
  interrupted=ranger(advanced,'area_track',track_type='animal');check(okay(interrupted),'Second native tracking task starts after recovery');contexts[advanced['id']]['position']=[3533,5,-4810];ranger(advanced);broken=wait_track(advanced);check(broken['state']['ranger']['tracking']['state']=='failed','Movement beyond1m interrupts original tracking')
  # Leave the original minimum-duration kit to expire naturally; no synthetic time.
  while time.monotonic()-start<203:
   for o in fixtures:ranger(o)
   time.sleep(max(.05,min(5,203-(time.monotonic()-start))))
  expired=ranger(novice);check(not expired['state']['ranger']['conceal']['active'],'Untrained baseline kit expires through original native duration event')
  check(ent(advanced,'group_invite',target_id=novice['id']).get('ok')and ent(novice,'group_join').get('ok'),'Original native group prerequisite established')
  lua('swgxrRangerFight');time.sleep(.4);state=ranger(advanced);targetrow=next(t for t in state['state']['ranger']['targets']if t['kind']=='rescue');check(denied(ranger(recipient,'rescue',target_id=targetrow['id'])),'Unlearned or ungrouped rescue rejected')
  check(denied(ranger(advanced,'rescue',target_id=novice['id'])),'Rescue targets enemy NPC, not friendly player')
  saved=ranger(advanced,'rescue',target_id=targetrow['id']);check(okay(saved)and saved['mutation']['rescued'],'Original rescue taunt moves native highest threat to Ranger')
  for _ in range(20):
   if lua('swgxrRangerEnemy')=='1':break
   time.sleep(.1)
  check(lua('swgxrRangerEnemy')=='1','Actual NPC AI target switches to rescuing Ranger')
  lua('swgxrRangerCleanup')
  report['passed']=True
 finally:
  if added:lua('swgxrRangerCleanup')
  for o in fixtures:
   if o['id']in sessions:call(o,'/combat/session/stop',session_id=sessions[o['id']])
  if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/ranger-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(checks))),flush=True)
if __name__=='__main__':main()
