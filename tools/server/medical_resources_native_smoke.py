#!/usr/bin/env python3
"""Local native CU medical/resource checks on two dedicated disposable characters."""
import json,re,secrets,time
from pathlib import Path
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 report={'passed':False,'native_execution':True,'remote_changed':False,'vr_launched':False,'checks':[],'fixtures':[]}
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';helper='';sessions={};positions={}
 def save(): (ROOT/'runtime/evidence/medical-resources-native.json').write_text(json.dumps(redact(report),indent=2)+'\n')
 def check(ok,label):
  report['checks'].append({'passed':bool(ok),'label':label});save();print(label,bool(ok),flush=True);assert ok,label
 def call(o,path,**kw):
  result=req(path,dict(account=o['account'],character_id=o.get('id',''),**kw))
  if result.get('error'):print('Native response',path,result,flush=True)
  return result
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrCuMedicine:'+mode)
  for _ in range(120):
   with log.open() as f:f.seek(offset);found=re.search(r'runLuaFunction Tests:swgxrCuMedicine: result=([^\n]+)',f.read())
   if found:return found.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Native fixture timeout '+mode)
 def state(o):return call(o,'/combat/session/update',session_id=sessions[o['id']],ready=True,**positions[o['id']])['snapshot']['player']
 def med(o,action,**kw):return call(o,'/medic/'+action,session_id=sessions[o['id']],request_id='cum_'+secrets.token_hex(8),**kw)
 try:
  for _ in range(2):
   o={'account':'invtestcumed'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(9))};report['fixtures'].append(o)
   for attempt in range(3):
    made=call(o,'/characters',name=o['name'],species='human',profession='science_medic')
    if made.get('error')!='Invalid galaxy - missing IP address':break
    time.sleep(.5)
   check('character'in made,'Create dedicated native medical fixture');o['id']=made['character']['id'];entered=call(o,'/enter');check(entered.get('core3_zone_verified'),'Enter native fixture')
   positions[o['id']]={k:entered['source_location'][k]for k in('position','building_id','cell_index')}
  a,b=report['fixtures'];catalog=json.loads((ROOT/'runtime/assets/professions/catalog.json').read_text())
  skills=[n['id']for p in catalog['professions']if p['id']in('science_medic','science_doctor')for n in p['nodes']]
  grants='\n'.join('awardSkill(p,"'+skill+'")'for skill in skills)
  helper='''\n-- BEGIN SWGXR CU MEDICAL TEST\nfunction Tests:swgxrCuMedicine(mode)
 local p=getSceneObject(ACTOR);local q=getSceneObject(PATIENT);
 if mode=="setup" then
 GRANTS
 for i,v in ipairs({p,q})do SceneObject(v):teleport(5010+i,getTerrainHeight(v,5010+i,-5500),-5500,0)end
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/tangible/medicine/medikit_tool_basic.iff",-1);giveItem(inv,"object/tangible/medicine/stimpack_sm_s1.iff",-1);giveItem(inv,"object/tangible/food/spice/spice_crash_n_burn.iff",-1)
 return tostring(CreatureObject(p):getBaseHAM(0))..":"..tostring(CreatureObject(p):getBaseHAM(3))..":"..tostring(CreatureObject(p):getBaseHAM(6))
 elseif mode=="base" then return tostring(CreatureObject(p):getBaseHAM(0))..":"..tostring(CreatureObject(p):getBaseHAM(3))..":"..tostring(CreatureObject(p):getBaseHAM(6))
 elseif mode=="reset" then
 for _,v in ipairs({p,q})do local x=CreatureObject(v);x:forcePeace();x:setPosture(0);x:clearState(16777216);for i=0,8 do x:setWounds(i,0);x:setHAM(i,x:getMaxHAM(i))end end
 return "ready"
 elseif mode=="resources" then
 local h=CreatureObject(q):getHAM(0);CreatureObject(q):setHAM(3,5);CreatureObject(q):setHAM(6,5);CreatureObject(q):inflictDamage(p,3,5000,1);CreatureObject(q):inflictDamage(p,6,5000,1)
 return tostring(CreatureObject(q):getHAM(0)==h)..":"..tostring(CreatureObject(q):getHAM(3))..":"..tostring(CreatureObject(q):getHAM(6))..":"..tostring(CreatureObject(q):getPosture())
 elseif mode=="hurt" then CreatureObject(q):setHAM(0,100);CreatureObject(q):setHAM(3,100);return "hurt"
 elseif mode=="bleed" then CreatureObject(q):addDotState(p,16777216,20,0,60,-1,987611,0);return tostring(CreatureObject(q):hasState(16777216))
 elseif mode=="expire_up" or mode=="expire_down" then
 return tostring(CreatureObject(p):setBuffDuration(getHashCode("spice.crash_n_burn."..(mode=="expire_up" and "up" or "down")),1))
 elseif mode=="firstaid" then return tostring(CreatureObject(p):executeCommand("firstaid",PATIENT,""))
 elseif mode=="tenddamage" or mode=="quickheal" then
 local h=CreatureObject(q):getHAM(0);local act=CreatureObject(q):getHAM(3);local a=CreatureObject(p):getHAM(3);local m=CreatureObject(p):getHAM(6);local f=CreatureObject(p):getWounds(7);local w=CreatureObject(p):getWounds(8)
 local code=CreatureObject(p):executeCommand(mode,PATIENT,"")
 return tostring(code)..":"..tostring(CreatureObject(q):getHAM(0)-h)..":"..tostring(CreatureObject(q):getHAM(3)-act)..":"..tostring(a-CreatureObject(p):getHAM(3))..":"..tostring(m-CreatureObject(p):getHAM(6))..":"..tostring(CreatureObject(p):getWounds(7)-f)..":"..tostring(CreatureObject(p):getWounds(8)-w)
 elseif mode=="cleanup" then
 self:swgxrCuMedicine("reset");return "clean"
 end return "unknown"
end
-- END SWGXR CU MEDICAL TEST\n'''.replace('ACTOR',a['id']).replace('PATIENT',b['id']).replace('GRANTS',grants)
  script.write_text(script.read_text()+helper);console('reloadscreenplays');time.sleep(.3)
  lua('setup')
  for o in (a,b):
   loc=call(o,'/services/status')['state']['player'];positions[o['id']]={k:loc[k]for k in('position','building_id','cell_index')}
   started=call(o,'/combat/session/start',**positions[o['id']]);check('session_id'in started,'Start native fixture session');sessions[o['id']]=started['session_id'];state(o)
  check([float(v)for v in lua('base').split(':')]==[3000,1000,1000],'Native session normalizes Health/Action/Mind baseline')
  check(lua('resources')=='true:0.0:0.0:0.0','Exhausted Action and Mind do not damage Health or incapacitate')
  lua('reset');lua('hurt');values=[int(float(v))for v in lua('tenddamage').split(':')]
  check(values[0]==0 and 120<=values[1]<=210,'Native Tend Damage uses bounded percentage Health healing')
  check(values[2]==0 and values[3:5]==[40,60],'Tend pays Action/Mind and does not replenish patient Action')
  check(values[5:]==[0,0],'Tend no longer inflicts healer Focus/Willpower wounds')
  values=[int(float(v))for v in lua('quickheal').split(':')];check(values[0]!=0 and values[1:5]==[0,0,0,0],'Shared injury recovery rejects alternate heal without spending resources')
  s=med(a,'status')['state'];tool=next(x for x in s['inventory']['items']if x.get('tool_kind')=='medical')
  check(s['medical_item_cooldowns']['healdamage']>0,'Shared recovery is visible through native medical UI state')
  time.sleep(8.2);lua('reset');lua('hurt')
  values=[int(float(v))for v in lua('quickheal').split(':')]
  check(values[0]==0 and 900<=values[1]<=1200 and values[2:]==[0,100,150,0,0],'Native Quick Heal is predictable Health burst with bounded costs and no self wounds')
  time.sleep(6.2);lua('reset');lua('hurt')
  before=med(a,'status')['state'];pack=next(x for x in before['inventory']['items']if x.get('medical_command')=='healdamage')
  check(bool(pack.get('medical_item')),'Native stim is exposed as a held medical item')
  p=positions[b['id']]['position'];pose=dict(tracked=True,crossed=False,grips=False,left=[p[0]-.1,p[1]+1,p[2]],right=[p[0]+.1,p[1]+1,p[2]])
  healed=med(a,'medical_item',item_id=pack['id'],target_id=b['id'],pose=pose);check(healed.get('mutation',{}).get('success'),'Native supply-backed Heal Damage succeeds')
  after=next(x for x in healed['state']['inventory']['items']if x['id']==pack['id']);check(after['use_count']==pack['use_count']-1,'Exactly one native stim charge consumed')
  check(state(b)['ham'][0]>100,'Native stim restores patient Health')
  lua('reset');check(lua('bleed') in ('true','1.0'),'Native bleeding fixture applied')
  p=positions[b['id']]['position'];pose=dict(tracked=True,crossed=False,grips=False,left=[p[0]-.1,p[1]+1,p[2]],right=[p[0]+.1,p[1]+1,p[2]])
  result=med(a,'bandage',target_id=b['id'],pose=pose);check(result.get('mutation',{}).get('success'),'Bandaging invokes native First Aid without a focus or selected ability')
  check(not next(x for x in result['state']['players']if x['id']==b['id'])['needs']['firstaid'],'Bandaging removes the native bleed')
  check(next(x for x in result['state']['abilities']if x['id']=='firstaid')['cooldown_seconds']>0,'Bandaging shares native First Aid recovery')
  pose['tracked']=False;check(med(a,'bandage',target_id=b['id'],pose=pose).get('http_error')==400,'Untracked bandaging rejected')
  time.sleep(8.2);lua('reset');lua('hurt')
  inv=call(a,'/inventory/status',live_session_id=sessions[a['id']]);spice=next(i for i in inv['items']if i['template'].endswith('/spice_crash_n_burn.iff'))
  check(call(a,'/inventory/consume',item_id=spice['id'],live_session_id=sessions[a['id']]).get('mutation',{}).get('success'),'Native Crash and Burn consumption succeeds')
  check(state(a)['max_ham']==[3000,950,1100],'Spice HAM scales source penalties and bonuses to new base pools')
  values=[int(float(v))for v in lua('tenddamage').split(':')];check(values[0]==0 and values[1]==315,'Crash and Burn grants 1.5x actual native healing')
  lua('expire_up');time.sleep(8.2);lua('reset');lua('hurt')
  values=[int(float(v))for v in lua('tenddamage').split(':')];check(values[0]==0 and values[1]<0 and values[2]==0,'Crash withdrawal damages Health without draining patient Action')
  lua('expire_down');time.sleep(1.5)
  report['passed']=True
 finally:
  if helper:
   try:
    lua('expire_up');time.sleep(1.2);lua('expire_down');time.sleep(1.2);lua('cleanup')
   except Exception as e:report['cleanup_error']=str(e)
  for o in report['fixtures']:
   if o.get('id')in sessions:
    try:call(o,'/combat/session/stop',session_id=sessions[o['id']])
    except Exception:pass
   if o.get('id') in positions:
    try:call(o,'/session/logout',**positions[o['id']])
    except Exception:pass
  if helper:script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays')
  save()
if __name__=='__main__':main()
