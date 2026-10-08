#!/usr/bin/env python3
"""Real local medical-item and food checks. Privileged fixtures, normal treatment APIs."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 report=dict(passed=False,native_execution=True,vr_launched=False,remote_changed=False,fixtures=[],checks=[])
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';helper='';sessions={};locations={}
 def save():(ROOT/'runtime/evidence/medical-items-native.json').write_text(json.dumps(redact(report),indent=2)+'\n')
 def check(ok,label):
  report['checks'].append(dict(passed=bool(ok),label=label));save();print(label,bool(ok),flush=True);assert ok,label
 def call(o,path,**kw):return req(path,dict(account=o['account'],character_id=o.get('id',''),**kw))
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrMedicalItems:'+mode)
  for _ in range(150):
   with log.open() as f:f.seek(offset);m=re.search(r'runLuaFunction Tests:swgxrMedicalItems: result=([^\n]+)',f.read())
   if m:return m.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Fixture timeout: '+mode)
 def medical(action='status',**kw):return call(a,'/medic/'+action,session_id=sessions[a['id']],request_id='mi_'+secrets.token_hex(8),**kw)
 try:
  for _ in range(2):
   o=dict(account='invtestmeditems'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(9)));report['fixtures'].append(o)
   for attempt in range(6):
    made=call(o,'/characters',name=o['name'],species='human',profession='science_medic')
    if made.get('error')!='Invalid galaxy - missing IP address':break
    time.sleep(.5)
   if 'character' not in made:print(made,flush=True)
   check('character'in made,'Create native medical-item fixture');o['id']=made['character']['id'];check(call(o,'/enter').get('core3_zone_verified'),'Enter persistent fixture')
  a,b=report['fixtures'];catalog=json.loads((ROOT/'runtime/assets/professions/catalog.json').read_text())
  grants='\n'.join('awardSkill(p,"'+n['id']+'")' for p in catalog['professions'] if p['id']in('science_medic','science_doctor','science_combatmedic')for n in p['nodes'])
  paths=['medicine/crafted/'+n for n in ['crafted_stimpack_sm_s1_a','medpack_stunned_a','medpack_cure_poison_a','medpack_cure_disease_a','medic_fire_blanket','medpack_enhance_health_a','medpack_revive','medpack_grenade_damage_a','medpack_grenade_area_a']]+['food/crafted/'+n for n in ['dessert_felbar','dessert_vagnerian_canape','drink_spiced_tea','drink_blue_milk','drink_ruby_bliel']]
  give='\n'.join('local item=giveItem(inv,"object/tangible/'+p+'.iff",-1);TangibleObject(item):setUseCount(8)'for p in paths)
  helper='''\nfunction Tests:swgxrMedicalItems(mode)
 local p=getSceneObject(ACTOR);local q=getSceneObject(PATIENT)
 if mode=="setup" then
 GRANTS
 local cell=BuildingObject(getSceneObject(4005381)):getCell(2);local cellId=SceneObject(cell):getObjectID()
 for i,v in ipairs({p,q})do SceneObject(v):teleport(i,0,0,cellId)end
 local inv=SceneObject(p):getSlottedObject("inventory")
 GIVE
 local bag=giveItem(inv,"object/tangible/wearables/backpack/backpack_s01.iff",-1)
 local stim=giveItem(bag,"object/tangible/medicine/crafted/crafted_stimpack_sm_s1_a.iff",-1);TangibleObject(stim):setUseCount(8)
 return tostring(SceneObject(stim):getObjectID())
 elseif mode=="reset" then
 for _,v in ipairs({p,q})do CreatureObject(v):forcePeace();CreatureObject(v):setPosture(0);for i=0,8 do CreatureObject(v):setWounds(i,0);CreatureObject(v):setHAM(i,CreatureObject(v):getMaxHAM(i))end end
 return "ready"
 elseif mode=="outside" then
 for i,v in ipairs({p,q})do SceneObject(v):teleport(5010+i*10,getTerrainHeight(v,5010+i*10,-5500),-5500,0)end;return "outside"
 elseif mode=="hospital" then
 local cell=BuildingObject(getSceneObject(4005381)):getCell(2);local cellId=SceneObject(cell):getObjectID()
 for i,v in ipairs({p,q})do SceneObject(v):teleport(i,0,0,cellId)end;return "hospital"
 elseif mode=="area_hurt" then CreatureObject(p):setHAM(0,100);CreatureObject(q):setHAM(0,100);return "hurt"
 elseif mode=="actor_health" then return tostring(CreatureObject(p):getHAM(0))
 elseif mode=="hurt" then CreatureObject(q):setHAM(0,100);return "hurt"
 elseif mode=="stun" then CreatureObject(q):setState(4096);return "stun"
 elseif mode=="poison" then CreatureObject(q):addDotState(p,8388608,10,0,120,-1,987720,0);return "poison"
 elseif mode=="disease" then CreatureObject(q):addDotState(p,33554432,10,3,120,-1,987721,0);return "disease"
 elseif mode=="fire" then CreatureObject(q):addDotState(p,67108864,10,0,120,-1,987722,0);return "fire"
 elseif mode=="dead" then CreatureObject(q):executeCommand("consent",ACTOR,"ACTORNAME");CreatureObject(q):setHAM(0,0);CreatureObject(q):setPosture(14);return "dead"
 elseif mode=="state" then return tostring(CreatureObject(q):getHAM(0))..":"..tostring(CreatureObject(q):getMaxHAM(0))..":"..tostring(CreatureObject(q):getPosture())
 elseif mode=="food_hurt" then CreatureObject(p):setState(2);CreatureObject(p):setHAM(6,100);return tostring(CreatureObject(p):getMaxHAM(6))
 elseif mode=="food_state" then return tostring(CreatureObject(p):getHAM(6))..":"..tostring(CreatureObject(p):getMaxHAM(6))..":"..tostring(CreatureObject(p):getMaxHAM(7))
 end return "unknown"
end\n'''.replace('ACTORNAME',a['name'].lower()).replace('ACTOR',a['id']).replace('PATIENT',b['id']).replace('GRANTS',grants).replace('GIVE',give)
  script.write_text(script.read_text()+helper);console('reloadscreenplays');time.sleep(.3);nested=lua('setup');lua('reset')
  for o in (a,b):
   loc=call(o,'/services/status')['state']['player'];locations[o['id']]={k:loc[k]for k in('position','building_id','cell_index')}
   started=call(o,'/combat/session/start',**locations[o['id']]);sessions[o['id']]=started['session_id'];call(o,'/combat/session/update',session_id=sessions[o['id']],ready=True,**locations[o['id']])
  p=locations[b['id']]['position'];pose=dict(tracked=True,crossed=False,grips=False,left=[p[0],p[1]+1,p[2]],right=[p[0]+.1,p[1]+1,p[2]])
  def item(command):return next(i for i in medical()['state']['inventory']['items'] if i.get('medical_command')==command)
  def use(pack,key=None,**extra):return call(a,'/medic/medical_item',session_id=sessions[a['id']],request_id=key or 'mi_'+secrets.token_hex(8),item_id=pack['id'],target_id=b['id'],pose=pose,**extra)
  def wait(command):time.sleep(medical()['state']['medical_item_cooldowns'][command]+.25)
  state=medical()['state'];check({v['id']for v in state['abilities']}=={'tenddamage','firstaid','quickheal'},'Only supply-free treatments remain in focus wheel')
  check({i.get('medical_command')for i in state['inventory']['items']if i.get('medical_item')} >= {'healdamage','healstate','curepoison','curedisease','extinguishfire','healenhance','reviveplayer'},'Native item metadata exposes all reusable medicine families')
  pack=next(i for i in state['inventory']['items']if i['id']==nested);lua('hurt');key='mi_'+secrets.token_hex(8);out=use(pack,key)
  check(out.get('mutation',{}).get('success'),'Stim in nested backpack heals exact patient');check(float(lua('state').split(':')[0])>100,'Stim changes real Health')
  after=next(i for i in out['state']['inventory']['items']if i['id']==nested);check(after['use_count']==pack['use_count']-1,'Only chosen nested stim loses one charge')
  check(use(pack,key).get('mutation',{}).get('replayed'),'Idempotent retry does not spend another charge')
  check(bool(use(pack).get('error')),'Shared injury timer rejects immediate item repeat')
  check(bool(use({'id':'1'}).get('error')),'Unowned medicine rejected')
  pose['tracked']=False;check(bool(use(pack).get('error')),'Untracked medical item use rejected');pose['tracked']=True
  def move(mode):
   lua(mode)
   for o in(a,b):
    loc=call(o,'/services/status')['state']['player'];locations[o['id']]={k:loc[k]for k in('position','building_id','cell_index')}
   source=locations[a['id']]['position'];pose.update(left=[source[0],source[1]+1,source[2]],right=[source[0]+.1,source[1]+1,source[2]])
  wait('healdamage');move('outside');lua('hurt');inventory=medical()['state']['inventory']['items'];pack=next(i for i in inventory if i.get('medical_ranged') and i['medical_area_m']==0)
  out=use(pack)
  if out.get('error'):print(out,flush=True)
  check(out.get('mutation',{}).get('success'),'Held ranged stim heals at ten metres using native range')
  wait('healdamage');lua('area_hurt');pack=next(i for i in medical()['state']['inventory']['items']if i.get('medical_ranged') and i['medical_area_m']>0);out=use(pack)
  check(out.get('mutation',{}).get('success') and float(lua('state').split(':')[0])>100,'Held area stim treats primary recipient')
  check(float(lua('actor_health'))>100,'Same area stim also heals nearby eligible caster')
  move('hospital')
  for mode,command,statebit in [('stun','healstate',4096),('poison','curepoison',8388608),('disease','curedisease',33554432),('fire','extinguishfire',67108864)]:
   wait(command);lua(mode);pack=item(command);out=use(pack)
   if out.get('error'):print(out,flush=True)
   check(out.get('mutation',{}).get('success'),'Held '+mode+' treatment succeeds')
   check(next(i for i in out['state']['inventory']['items']if i['id']==pack['id'])['use_count']==pack['use_count']-1,mode+' treatment consumes one charge')
   patient=next(i for i in out['state']['players']if i['id']==b['id']);check(not (int(patient['states'])&statebit),mode+' condition removed by native treatment')
  wait('healstate');pack=item('healstate');check(bool(use(pack).get('error')),'No-condition treatment rejected without consuming')
  lua('reset');pack=item('healenhance');out=use(pack)
  if out.get('error'):print(out,flush=True)
  check(out.get('mutation',{}).get('success'),'Held Doctor enhancement works in native hospital')
  check(3000<float(lua('state').split(':')[1])<=3450,'Doctor enhancement remains within 15 percent Health cap')
  pack=item('reviveplayer');check(bool(use(pack).get('error')),'Resuscitation refuses living patient')
  lua('dead');out=use(pack)
  if out.get('error'):print(out,flush=True)
  check(out.get('mutation',{}).get('success'),'Held resuscitation kit revives consenting patient')
  vals=[float(x)for x in lua('state').split(':')];check(vals[2]==0 and vals[0]>0,'Resuscitated player is upright with real Health')
  lua('reset')
  def food(suffix):return next(i for i in medical()['state']['inventory']['items']if i['template'].endswith('/'+suffix+'.iff'))
  def eat(pack):return call(a,'/inventory/consume',live_session_id=sessions[a['id']],item_id=pack['id'])
  check(not eat(food('dessert_felbar')).get('mutation',{}).get('success'),'Pet-only food remains unavailable to players')
  pack=food('dessert_vagnerian_canape');lua('food_hurt');out=eat(pack)
  if out.get('error'):print(out,flush=True)
  check(out.get('mutation',{}).get('success'),'Player food is consumed through native inventory')
  vals=[float(x)for x in lua('food_state').split(':')];check(vals[2]==317,'Food rebases 550 legacy Focus bonus to 17 on base 300')
  check(eat(pack).get('mutation',{}).get('success'),'Native attribute-food stacking remains available')
  check(float(lua('food_state').split(':')[2])==334,'Two servings stack their bounded bonuses')
  pack=food('drink_spiced_tea');out=eat(pack);change=out.get('mutation',{})
  check(change.get('success') and change['after_stats']['max_ham'][6]-change['before_stats']['max_ham'][6]==7 and change['after_stats']['ham'][6]==change['before_stats']['ham'][6],'Mind capacity drink does not heal or refill resources')
  pack=food('drink_blue_milk');before=float(lua('food_state').split(':')[0]);out=eat(pack);after=float(lua('food_state').split(':')[0])
  check(out.get('mutation',{}).get('success') and 0<after-before<=190,'Drink restores bounded resource amount')
  check(not eat(pack).get('mutation',{}).get('success'),'Shared food/drink restore cooldown prevents spam')
  report['passed']=True
 finally:
  if helper:
   try:lua('reset')
   except Exception:pass
  for o in report['fixtures']:
   if o.get('id')in sessions:
    try:call(o,'/combat/session/stop',session_id=sessions[o['id']])
    except Exception:pass
   if o.get('id')in locations:
    try:call(o,'/session/logout',**locations[o['id']])
    except Exception:pass
  if helper:script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays')
  save()
if __name__=='__main__':main()
