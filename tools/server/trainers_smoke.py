#!/usr/bin/env python3
"""Real six-profession native trainer checks on strict isolated accounts only.
Fixture-only console preparation supplies credits and XP; training itself always
uses original native SkillManager eligibility, XP withdrawal and persistence.
"""
import json,secrets,time,math
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def fixture(filename):
 p=ROOT/'runtime/server'/filename
 if p.exists():return json.loads(p.read_text())
 f={'account':'invtesttrainers'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8))}
 r=req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character'in r,r
 f['id']=r['character']['id'];p.write_text(json.dumps(f));return f

def main():
 f=fixture('trainers-fixture-'+secrets.token_hex(3)+'.json');points=fixture('trainers-points-fixture-'+secrets.token_hex(3)+'.json')
 (ROOT/'runtime/server/trainers-fixture.json').write_text(json.dumps(f));(ROOT/'runtime/server/trainers-points-fixture.json').write_text(json.dumps(points))
 assert all(x['account'].startswith('invtesttrainers')and x['name'].startswith('Ivtest')for x in(f,points))
 checks=[];responses=[];sessions={};added=False;script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 def check(value,label):
  checks.append({'passed':bool(value),'label':label});print(label,bool(value),flush=True)
  if not value:raise AssertionError(label)
 def service(action,owner=f,**kw):
  data=dict(account=owner['account'],character_id=owner['id'],**kw)
  if owner['id']in sessions:data['session_id']=sessions[owner['id']]
  if action not in('status','open'):data.setdefault('request_id','trainer_'+secrets.token_hex(10))
  out=req('/services/'+action,data);responses.append({'action':action,'owner':owner['id'],'response':out});return out
 def at(t):return dict(terminal_id=t['id'],position=t['position'],building_id=t['building_id'],cell_index=t['cell_index'])
 def skill(state,sid):return next(s for s in state['state']['terminal']['skills']if s['id']==sid)
 code='''\n-- BEGIN SWGXR ISOLATED BASIC TRAINER FIXTURE
function Tests:swgxrTrainersFixture(phase)
 local p=getSceneObject(MAIN_ID) if p==nil then return end
 local c=CreatureObject(p)
 if phase=="poor" then c:subtractCashCredits(c:getCashCredits());c:subtractBankCredits(c:getBankCredits())
 elseif phase=="fund" then c:subtractCashCredits(c:getCashCredits());c:subtractBankCredits(c:getBankCredits());c:addCashCredits(40,true);c:addBankCredits(100000,true)
 elseif phase=="xp" then c:awardExperience("crafting_general",10000,false)
 elseif phase=="points" then
  local q=getSceneObject(POINTS_ID) if q==nil then return end
  local d=CreatureObject(q);d:addCashCredits(100000,true)
  awardSkill(q,"crafting_artisan_master");awardSkill(q,"combat_brawler_master");awardSkill(q,"social_entertainer_master");awardSkill(q,"outdoors_scout_novice")
 end
end
-- END SWGXR ISOLATED BASIC TRAINER FIXTURE
'''.replace('MAIN_ID',f['id']).replace('POINTS_ID',points['id'])
 report={'native_execution':True,'headset_tested':False,'fixtures':[f,points],'fixture_setup':'Disposable account credits and crafting XP supplied via original console API; second account original admin skill grants consume skill points to test exhausted eligibility. No production player changes.','checks':checks,'responses':responses,'passed':False}
 try:
  first=service('status',position=[3506,5,-4760],building_id='0',cell_index=0);check(first.get('ok'),'Native trainer service state available')
  trainers={t['profession']:t for t in first['state']['terminals']if t['kind']=='trainer'and t['cell_index']==0}
  check(set(trainers)=={'artisan','brawler','entertainer','marksman','medic','scout'},'All six original spawned basic trainers discovered by native identity')
  for profession,t in trainers.items():
   opened=service('open',**at(t));view=opened.get('state',{}).get('terminal',{})
   check(opened.get('ok')and len(view.get('skills',[]))==18 and bool(view.get('trainer_text'))and not view['trainer_text'].startswith('@'),'Original '+profession+' trainer catalogue and media greeting available')
  artisan=trainers['artisan'];marksman=trainers['marksman'];medic=trainers['medic'];target='crafting_artisan_engineering_01'
  opened=service('open',**at(artisan));row=skill(opened,target)
  check(not row['eligible']and row['xp_available']<row['xp_cost'],'Native XP eligibility blocks unearned skill')
  denied=service('trainer_train',**at(artisan),skill_id=target);check(denied.get('http_error')==400,'Native trainer rejects insufficient XP')
  denied=service('trainer_train',**at(artisan),skill_id='combat_marksman_novice');check(denied.get('error')=='skill_not_taught_by_trainer','Trainer cannot grant foreign profession skill')
  denied=service('trainer_train',**at(artisan),skill_id='crafting_artisan_engineering_02');check(denied.get('http_error')==400,'Native missing prerequisites rejected')
  distant=at(marksman);distant['position']=[marksman['position'][0]+6,marksman['position'][1],marksman['position'][2]]
  check(service('trainer_train',**distant,skill_id='combat_marksman_novice').get('http_error')==400,'Original5m trainer conversation range enforced')
  script.write_text(script.read_text()+code);added=True;console('reloadscreenplays');console('runLuaFunction Tests:swgxrTrainersFixture:poor');time.sleep(.3)
  check(service('trainer_train',**at(marksman),skill_id='combat_marksman_novice').get('http_error')==400,'Native trainer rejects insufficient carried and bank credits')
  console('runLuaFunction Tests:swgxrTrainersFixture:fund');console('runLuaFunction Tests:swgxrTrainersFixture:xp');time.sleep(.3)
  before=service('open',**at(artisan));row=skill(before,target);check(row['eligible']and row['xp_available']>=row['xp_cost'],'Original XP award enables trainer eligibility on isolated fixture')
  key='trainer_native_'+secrets.token_hex(8);trained=service('trainer_train',**at(artisan),skill_id=target,request_id=key)
  check(trained.get('ok')and target in trained['state']['skills'],'Original SkillManager awards actual learned box')
  check(trained['state']['experience'][row['xp_type']]==before['state']['experience'][row['xp_type']]-row['xp_cost'],'Training withdraws exact original XP cost from complete native map')
  check(trained['state']['wallet']['cash']==0 and trained['state']['wallet']['bank']==before['state']['wallet']['bank']-(row['credit_cost']-before['state']['wallet']['cash']),'Original trainer fee consumes carried credits before bank')
  check(trained['state']['terminal']['skill_points']==before['state']['terminal']['skill_points']-row['skill_point_cost'],'Original training consumes exact native skill points')
  repeat=service('trainer_train',**at(artisan),skill_id=target,request_id=key)
  check(repeat.get('ok')and repeat['mutation'].get('replayed')and repeat['state']['wallet']==trained['state']['wallet']and repeat['state']['experience']==trained['state']['experience'],'Durable training receipt prevents duplicate fees and XP withdrawal')
  persisted=service('status');check(target in persisted['state']['skills']and persisted['state']['experience']==trained['state']['experience'],'Learned box and remaining XP persist across independent native login')
  dp=req('/datapad?account='+f['account']+'&character_id='+f['id']);responses.append({'action':'datapad','response':dp})
  check(dp.get('experience_complete')and dp['experience']==persisted['state']['experience'],'Legacy owner PLAY8 XP exactly matches complete native services map')
  for profession in ('marksman','medic','scout','brawler','entertainer'):
   view=service('open',**at(trainers[profession]));novice=next(s for s in view['state']['terminal']['skills']if s['id'].endswith('_novice'))
   got=service('trainer_train',**at(trainers[profession]),skill_id=novice['id']);check(got.get('ok')and novice['id']in got['state']['skills'],'Original '+profession+' novice training persists')
  # Real cell validation against original interior trainer.
  source=json.loads((ROOT/'runtime/assets/services/trainers.json').read_text());interior=next(x for x in source['placements']if 'mos_eisley' in x['id']and x['mobile']=='trainer_marksman'and x['source_cell_id']!='0')
  ci=int(interior['cell_id'].split(':')[1]);inside=service('status',position=interior['source_world_xyz'],building_id=interior['building_object_id'],cell_index=ci)
  indoor=next(t for t in inside['state']['terminals']if t['kind']=='trainer'and t['building_id']==interior['building_object_id']and t['cell_index']==ci)
  check(service('open',**at(indoor)).get('ok'),'Original interior trainer opens in matching authored cell')
  bad=at(indoor);bad['building_id']='0';bad['cell_index']=0
  check(service('open',**bad).get('http_error')==400,'Trainer rejects identical world position in different cell')
  # Complete XP state is available while the real persistent live session owns login.
  live=req('/combat/session/start',dict(account=f['account'],character_id=f['id'],position=artisan['position']));check(live.get('session_live'),'Actual native persistent session opens for trainer regression');sessions[f['id']]=live['session_id']
  state=service('open',**at(artisan));native=state['live_response']['snapshot']['player']
  check(native.get('experience_complete')and native['experience']==state['state']['experience']and 'crafting_general'in native['experience'],'Live session exposes complete noncombat XP without erasing pools')
  next_box='crafting_artisan_domestic_01';before_row=skill(state,next_box)
  if not before_row['eligible']:raise AssertionError('Fixture XP must enable second engineering box')
  trained=service('trainer_train',**at(artisan),skill_id=next_box)
  check(trained.get('ok')and trained['live_response'].get('session_live')and next_box in trained['state']['skills'],'Original training reuses persistent native session')
  check(trained['live_response']['snapshot']['player']['experience']==trained['state']['experience'],'Live response and services XP agree after spending')
  req('/combat/session/stop',dict(account=f['account'],character_id=f['id'],session_id=sessions.pop(f['id'])))
  service('status',owner=points,position=medic['position'],building_id='0',cell_index=0);console('runLuaFunction Tests:swgxrTrainersFixture:points');time.sleep(.3)
  view=service('open',owner=points,**at(medic));novice=skill(view,'science_medic_novice')
  check(not novice['eligible']and 'skill points'in novice['blocked_reason'],'Exhausted native skill points block available novice training')
  check(service('trainer_train',owner=points,**at(medic),skill_id='science_medic_novice').get('http_error')==400,'Original SkillManager rejects training without skill points')
  report['passed']=True
 finally:
  for owner in(f,points):
   if owner['id']in sessions:req('/combat/session/stop',dict(account=owner['account'],character_id=owner['id'],session_id=sessions[owner['id']]))
  if added:script.write_text(script.read_text().replace(code,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/trainers-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}),flush=True)
if __name__=='__main__':main()
