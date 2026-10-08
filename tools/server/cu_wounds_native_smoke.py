#!/usr/bin/env python3
"""Real local CoreCU wound migration, item treatment, and retired-content checks.
Run --prepare with the prior binary, restart onto the new binary, then run normally.
"""
import json,re,secrets,sys,time
from pathlib import Path
from services_smoke import ROOT,req,redact
from equipment_smoke import console
FILE=ROOT/'runtime/evidence/cu-wounds-native.json'
SCRIPT=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
def main():
 prepare='--prepare' in sys.argv
 report={'checks':[],'fixtures':[],'passed':False,'vr_launched':False,'remote_changed':False} if prepare else json.loads(FILE.read_text())
 sessions={};positions={};helper=''
 if not prepare:report['checks']=report['checks'][:3]
 def save():FILE.write_text(json.dumps(redact(report),indent=2)+'\n')
 def check(ok,label):
  report['checks'].append({'passed':bool(ok),'label':label});save();print(label,bool(ok),flush=True);assert ok,label
 def call(o,path,**kw):return req(path,dict(account=o['account'],character_id=o.get('id',''),**kw))
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrCuWounds:'+mode)
  for _ in range(150):
   with log.open() as f:f.seek(offset);m=re.search(r'runLuaFunction Tests:swgxrCuWounds: result=([^\n]+)',f.read())
   if m:return m.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Fixture timeout '+mode)
 try:
  if prepare:
   for _ in range(2):
    o={'account':'invtestcuwound'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(9))};report['fixtures'].append(o)
    for attempt in range(3):
     r=call(o,'/characters',name=o['name'],species='human',profession='science_medic')
     if r.get('error')!='Invalid galaxy - missing IP address':break
     time.sleep(.5)
    check('character' in r,'Create persistent wound fixture');o['id']=r['character']['id'];call(o,'/enter')
  else:
   for o in report['fixtures']:check(call(o,'/enter').get('core3_zone_verified'),'Reload saved fixture with CU cleanup binary')
  a,b=report['fixtures'];catalog=json.loads((ROOT/'runtime/assets/professions/catalog.json').read_text());skills=[n['id'] for p in catalog['professions'] if p['id'] in ('science_medic','science_doctor','science_combatmedic') for n in p['nodes']]
  grants='\n'.join('awardSkill(p,"'+s+'")' for s in skills)
  helper='''\nfunction Tests:swgxrCuWounds(mode)
 local p=getSceneObject(ACTOR);local q=getSceneObject(PATIENT)
 if mode=="prepare" then
 GRANTS
 local inv=SceneObject(p):getSlottedObject("inventory")
 local pack=giveItem(inv,"object/tangible/medicine/medpack_wound_health.iff",-1);TangibleObject(pack):setUseCount(5)
 giveItem(inv,"object/tangible/medicine/medpack_wound_action.iff",-1)
 giveItem(inv,"object/tangible/crafting/station/food_station.iff",-1)
 giveItem(inv,"object/tangible/crafting/station/generic_tool.iff",-1)
 CreatureObject(p):setWounds(0,100);CreatureObject(p):setWounds(3,60);CreatureObject(p):setWounds(7,30)
 return tostring(CreatureObject(p):getWounds(3))..":"..tostring(CreatureObject(p):getWounds(7))
 elseif mode=="wounds" then
 local out={};for i=0,8 do table.insert(out,tostring(CreatureObject(p):getWounds(i)))end;return table.concat(out,":")
 elseif mode=="guard" then
 CreatureObject(p):setWounds(0,100);for i=1,8 do CreatureObject(p):setWounds(i,100)end
 return self:swgxrCuWounds("wounds")
 elseif mode=="reset" then
 for _,v in ipairs({p,q})do CreatureObject(v):forcePeace();CreatureObject(v):setPosture(0);for i=0,8 do CreatureObject(v):setWounds(i,0);CreatureObject(v):setHAM(i,CreatureObject(v):getMaxHAM(i))end end
 CreatureObject(q):setWounds(0,500);return "reset"
 elseif mode=="outside" then
 for i,v in ipairs({p,q})do SceneObject(v):teleport(5010+i,getTerrainHeight(v,5010+i,-5500),-5500,0)end;return "outside"
 elseif mode=="hospital" then
 local building=getSceneObject(4005381);local cell=BuildingObject(building):getCell(2);local cellId=SceneObject(cell):getObjectID()
 for i,v in ipairs({p,q})do SceneObject(v):teleport(i,0,0,cellId)end
 return tostring(CreatureObject(p):getSkillMod("private_medical_rating"))
 elseif mode=="patient" then return tostring(CreatureObject(q):getWounds(0))
 elseif mode=="retired" then
 return tostring(CreatureObject(p):executeCommand("diagnose",PATIENT,""))..":"..tostring(CreatureObject(p):executeCommand("tendwound",PATIENT,""))..":"..tostring(CreatureObject(p):executeCommand("healwound",PATIENT,""))
 elseif mode=="spawn_retired" then return tostring(giveItem(SceneObject(p):getSlottedObject("inventory"),"object/tangible/medicine/medpack_wound_action.iff",-1)==nil)
 elseif mode=="disease" then CreatureObject(q):setState(2);CreatureObject(q):addDotState(p,33554432,100,6,12,-1,987633,0);return "disease"
 elseif mode=="disease_state" then return tostring(CreatureObject(q):getHAM(3))..":"..tostring(CreatureObject(q):getWounds(3))..":"..tostring(CreatureObject(q):getWounds(6))
 elseif mode=="mind" then
 CreatureObject(q):setHAM(6,100);local act=CreatureObject(p):getHAM(3);local m=CreatureObject(p):getHAM(6)
 local code=CreatureObject(p):executeCommand("healmind",PATIENT,"")
 return tostring(code)..":"..tostring(CreatureObject(q):getHAM(6))..":"..tostring(act-CreatureObject(p):getHAM(3))..":"..tostring(m-CreatureObject(p):getHAM(6))..":"..tostring(CreatureObject(p):getWounds(6))
 end return "unknown"
end\n'''.replace('ACTOR',a['id']).replace('PATIENT',b['id']).replace('GRANTS',grants)
  SCRIPT.write_text(SCRIPT.read_text()+helper);console('reloadscreenplays');time.sleep(.4)
  if prepare:
   check([float(x) for x in lua('prepare').split(':')]==[60,30],'Prior binary fixture stores obsolete Action and Focus wounds');report['prepared']=True;return
  values=[float(v) for v in lua('wounds').split(':')];check(values[1:]==[0]*8,'Saved fixture has no obsolete wounds after migration')
  check([float(v) for v in lua('guard').split(':')]==[100]+[0]*8,'Common setter permits Health wounds and prevents eight obsolete attributes')
  lua('outside');lua('reset')
  def refresh():
   for o in (a,b):
    loc=call(o,'/services/status')['state']['player'];positions[o['id']]={k:loc[k] for k in ('position','building_id','cell_index')}
  refresh()
  for o in(a,b):
   started=call(o,'/combat/session/start',**positions[o['id']]);check('session_id'in started,'Start owned native wound session');sessions[o['id']]=started['session_id']
   call(o,'/combat/session/update',session_id=sessions[o['id']],ready=True,**positions[o['id']])
  def med(action,**kw):return call(a,'/medic/'+action,session_id=sessions[a['id']],request_id='cuw_'+secrets.token_hex(8),**kw)
  state=med('status')['state'];pack=next(i for i in state['inventory']['items'] if i.get('wound_medpack'))
  check(not any('/medpack_wound_action' in i['template'] for i in state['inventory']['items']),'Legacy obsolete inventory pack removed on session entry')
  check({i['id'] for i in state['abilities']}=={'tenddamage','firstaid','quickheal'},'Medical ability list excludes Diagnose and wound abilities')
  check(all(float(x)!=0 for x in lua('retired').split(':')),'Native Diagnose/Tend Wound/itemless Heal Wound rejected')
  check(lua('spawn_retired')=='true','New obsolete supply creation rejected')
  def apply(item=pack['id'],target=b['id'],key=None):
   p=positions[b['id']]['position'];pose=dict(tracked=True,crossed=False,grips=False,left=[p[0],p[1]+1,p[2]],right=[p[0]+.1,p[1]+1,p[2]])
   return call(a,'/medic/wound_pack',session_id=sessions[a['id']],request_id=key or 'cuw_'+secrets.token_hex(8),item_id=item,target_id=target,pose=pose)
  result=apply();check(bool(result.get('error')),'Wound pack respects native medical-location requirement')
  rating=lua('hospital');refresh();check(float(rating)>0,'Original hospital supplies native medical environment')
  lua('reset');key='cuw_'+secrets.token_hex(8);result=apply(key=key)
  check(result.get('mutation',{}).get('success'),'Held Health Wound Medpack heals nearby patient in hospital')
  check(0<float(lua('patient'))<500,'Health wounds actually decrease')
  after=next(i for i in result['state']['inventory']['items'] if i['id']==pack['id']);check(after['use_count']==pack['use_count']-1,'Exactly one Health Wound Medpack charge consumed')
  replay=apply(key=key);check(replay.get('mutation',{}).get('replayed'),'Retry uses persisted receipt without consuming again')
  check(bool(apply().get('error')),'Shared wound recovery blocks immediate repeat')
  check(bool(apply(item='1').get('error')),'Unowned or nonexistent medpack rejected')
  lua('reset');vals=[float(v) for v in lua('mind').split(':')];check(vals[0]==0 and 220<=vals[1]<=320 and vals[2:]==[60,100,0],'Heal Mind restores bounded resource, pays both costs, creates no wounds')
  check(float(lua('mind').split(':')[0])!=0,'Heal Mind cannot bypass resource recovery')
  lua('reset');lua('disease');deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   vals=[float(v) for v in lua('disease_state').split(':')]
   if vals[0]<1000:break
   time.sleep(.4)
  check(vals[0]<1000 and vals[1:]==[0,0],'Legacy Mind disease becomes temporary Action drain without wounds')
  lua('reset')
  report['passed']=True
 finally:
  for o in report['fixtures']:
   if o.get('id') in sessions:
    try:call(o,'/combat/session/stop',session_id=sessions[o['id']])
    except Exception:pass
   if o.get('id'):
    try:
     loc=call(o,'/services/status')['state']['player'];call(o,'/session/logout',**{k:loc[k] for k in ('position','building_id','cell_index')})
    except Exception:pass
  if helper:SCRIPT.write_text(SCRIPT.read_text().replace(helper,''));console('reloadscreenplays')
  save()
if __name__=='__main__':main()
