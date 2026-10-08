#!/usr/bin/env python3
"""Local Core3 companion balance: labelled admin fixtures, ordinary treatment APIs."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 report=dict(passed=False,native_execution=True,vr_launched=False,remote_changed=False,checks=[],fixture={},fixture_setup='Disposable character; admin grants, genuine creature pet and original droid deed, supplies and controlled HAM. Treatments run normal native commands / held-item API.')
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';helper='';sid=None
 def save():(ROOT/'runtime/evidence/cu-companions-native.json').write_text(json.dumps(redact(report),indent=2)+'\n')
 def check(ok,label):
  report['checks'].append(dict(passed=bool(ok),label=label));save();print(label,bool(ok),flush=True);assert ok,label
 def call(path,**kw):return req(path,dict(account=o['account'],character_id=o.get('id',''),**kw))
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrCompanions:'+mode)
  for _ in range(150):
   with log.open()as f:f.seek(offset);text=f.read()
   m=re.search(r'runLuaFunction Tests:swgxrCompanions: result=([^\n]+)',text)
   if m:return m.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Fixture timeout '+mode+': '+text[-1500:])
 def med(action='status',**kw):return call('/medic/'+action,session_id=sid,request_id='cp_'+secrets.token_hex(8),**kw)
 def vehicle(action,**kw):return call('/vehicles/'+action,live_session_id=sid,request_id='cp_'+secrets.token_hex(8),zone='tatooine',**kw)
 def state(oid):return [float(v)for v in lua('stats_'+oid).split(':')]
 try:
  o=dict(account='invtestcompanion'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8)));report['fixture']=o
  for _ in range(6):
   made=call('/characters',name=o['name'],species='human',profession='science_medic')
   if 'character'in made:break
   if 'name_declined'in made.get('error',''):o['name']='Ivtest'+''.join(secrets.choice('aeilo')for _ in range(8))
   time.sleep(.5)
  if 'character'not in made:print(made,flush=True)
  check('character'in made,'Create isolated native companion owner');o['id']=made['character']['id'];check(call('/enter').get('core3_zone_verified'),'Enter native world')
  helper='''
function Tests:swgxrCompanions(mode)
 local p=getSceneObject(OWNER)
 local op,id=string.match(mode,"([^_]+)_(%d+)");local pet=nil;if id~=nil then pet=getSceneObject(tonumber(id))end
 if mode=="setup" then
 awardSkill(p,"outdoors_creaturehandler_master");awardSkill(p,"crafting_droidengineer_novice")
 SceneObject(p):teleport(3527,getTerrainHeight(p,3527,-4810),-4810,0)
 local inv=SceneObject(p):getSlottedObject("inventory")
 local baby=spawnBabyMobile("tatooine","bantha",0,3528,getTerrainHeight(p,3528,-4810),-4810,0,0)
 if not grantCreaturePet(p,baby) then return "pet_failed"end
 local deed=giveItem(inv,"object/tangible/deed/pet_deed/deed_r3_basic.iff",-1)
 if not activateOwnedDroidDeed(p,deed)then return "droid_failed"end
 local bag=giveItem(inv,"object/tangible/wearables/backpack/backpack_s01.iff",-1)
 for _,name in ipairs({"pet_stimpack_a","droid_damage_kit_a","droid_wound_kit_a"})do local item=giveItem(bag,"object/tangible/medicine/pet/"..name..".iff",-1);TangibleObject(item):setUseCount(8)end
 local food=giveItem(inv,"object/tangible/food/crafted/dessert_felbar.iff",-1);TangibleObject(food):setUseCount(8);writeData("swgxr_companion_food",SceneObject(food):getObjectID())
 local stim=giveItem(inv,"object/tangible/medicine/crafted/crafted_stimpack_sm_s1_a.iff",-1);TangibleObject(stim):setUseCount(8)
 return tostring(SceneObject(baby):getObjectID())
 elseif op=="stats" then
 local v={};for _,i in ipairs({0,3,6})do table.insert(v,CreatureObject(pet):getHAM(i))end
 table.insert(v,CreatureObject(pet):getPosture());for i=0,8 do table.insert(v,CreatureObject(pet):getWounds(i))end
 for _,i in ipairs({0,3,6})do table.insert(v,CreatureObject(pet):getMaxHAM(i))end
 return table.concat(v,":")
 elseif op=="prepare" then
 CreatureObject(pet):forcePeace();CreatureObject(pet):setPosture(0)
 for i=0,8 do local base=300;if i==0 then base=3000 elseif i==3 or i==6 then base=1000 end;CreatureObject(pet):setBaseHAM(i,base);CreatureObject(pet):setMaxHAM(i,base);CreatureObject(pet):setWounds(i,0);CreatureObject(pet):setHAM(i,base)end
 CreatureObject(pet):setState(2);CreatureObject(pet):setHAM(0,500);CreatureObject(pet):setHAM(3,100);CreatureObject(pet):setHAM(6,100)
 SceneObject(pet):teleport(3527.5,getTerrainHeight(p,3527,-4810),-4810,0)
 CreatureObject(p):forcePeace();CreatureObject(p):setPosture(0);for _,i in ipairs({0,3,6})do CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i))end
 return "ready"
 elseif op=="wounds" then
 for i=0,8 do CreatureObject(pet):setWounds(i,200)end;return "set"
 elseif op=="rest" then CreatureObject(pet):forcePeace();return "resting"
 elseif op=="resources" then
 for _,i in ipairs({3,6})do CreatureObject(pet):inflictDamage(p,i,99999,1)end;return "drained"
 elseif op=="health" then CreatureObject(pet):inflictDamage(p,0,99999,1);return "hit"
 elseif op=="disease" then CreatureObject(pet):addDotState(p,33554432,9999,6,12,-1,987750,0);return "dot"
 elseif op=="food" then
 CreatureObject(pet):forcePeace();CreatureObject(pet):setHAM(0,500);CreatureObject(pet):setHAM(6,100)
 return tostring(CreatureObject(p):executeCommand("giveitem",readData("swgxr_companion_food"),id))
 elseif op=="trick" then
 CreatureObject(pet):forcePeace();CreatureObject(pet):setHAM(6,1);return "ready"
 elseif op=="trickready" then return tostring(CreatureObject(pet):checkCooldownRecovery("trickCooldown"))
 elseif op=="hospital" then
 CreatureObject(pet):forcePeace();CreatureObject(p):forcePeace();local cell=BuildingObject(getSceneObject(4005381)):getCell(2);local cellId=SceneObject(cell):getObjectID()
 SceneObject(p):teleport(1,0,0,cellId);SceneObject(pet):teleport(2,0,0,cellId);return "clinic"
 elseif mode=="cleanup" then CreatureObject(p):forcePeace();CreatureObject(p):storePets();deleteData("swgxr_companion_food");return "clean"
 end return "unknown"
end
'''.replace('OWNER',o['id'])
  script.write_text(script.read_text()+helper);console('reloadscreenplays');time.sleep(.3);pet=lua('setup');check(pet.isdigit(),'Admin fixture produces genuine creature pet and activated droid deed')
  loc=call('/services/status')['state']['player'];context={k:loc[k]for k in('position','building_id','cell_index')};start=call('/combat/session/start',**context);sid=start['session_id'];call('/combat/session/update',session_id=sid,ready=True,**context)
  v=vehicle('status');drow=next(p for p in v['state']['pet_datapad'] if p['template']=='object/mobile/r3_crafted.iff');droid=drow['pet_id']
  for helper_pet in v['state']['pet_datapad']:
   if helper_pet['template']=='object/mobile/nhelper_droid.iff' and helper_pet['spawned']:vehicle('pet_recall',device_id=helper_pet['id'])
  for oid in (pet,droid):
   prow=next(p for p in v['state']['pet_datapad'] if p['pet_id']==oid)
   if not prow['spawned']:
    for attempt in range(65):
     out=vehicle('pet_call',device_id=prow['id']);report['last_call']=out;save()
     if out.get('mutation',{}).get('success'):break
     time.sleep(1)
    for _ in range(25):
     time.sleep(1);v=vehicle('status');prow=next(p for p in v['state']['pet_datapad'] if p['pet_id']==oid)
     if prow['spawned']:break
   check(prow['spawned'],'Original companion call succeeds: '+prow['pet_kind'])
  report.update(pet=pet,droid=droid)
  for oid,command in [(pet,'healpet'),(droid,'healdroiddamage')]:
   lua('prepare_'+oid);lua('wounds_'+oid);st=state(oid)
   check(st[4]==200 and all(w==0 for w in st[5:13]),command+': Health-only wound setters')
   lua('resources_'+oid);st=state(oid);check(st[0]>0 and st[3]not in(13,14) and st[1]>=0 and st[2]>=0,command+': exhausting resources cannot incapacitate')
   lua('prepare_'+oid);snapshot=med()['state'];report['debug_snapshot']=snapshot;report['debug_vehicle']=vehicle('status');save();person=next(p for p in snapshot['companions'] if p['id']==oid);check(person['companion'] and person['droid']==(oid==droid),command+': native recipient kind published')
   pack=next(i for i in snapshot['inventory']['items']if i.get('medical_command')==command);check(pack['consume_available'],command+': held supply in nested backpack available')
   pos=person['position'];pose=dict(tracked=True,crossed=False,grips=False,left=[pos[0],pos[1]+1,pos[2]],right=[pos[0]+.1,pos[1]+1,pos[2]])
   time.sleep(snapshot['medical_item_cooldowns'][command]+.2);lua('prepare_'+oid)
   key='cp_'+secrets.token_hex(8);out=call('/medic/medical_item',session_id=sid,request_id=key,item_id=pack['id'],target_id=oid,pose=pose)
   if out.get('error'):print(out,flush=True)
   check(out.get('mutation',{}).get('success'),command+': normal item API succeeds');st=state(oid)
   check(500<st[0]<=500+825,command+': Health healing bounded by patient maximum');check(st[1]<=220 and st[2]<=220,command+': treatment does not refill resources')
   after=next(i for i in out['state']['inventory']['items'] if i['id']==pack['id']);check(after['use_count']==pack['use_count']-1,command+': exactly one chosen charge consumed')
   repeat=call('/medic/medical_item',session_id=sid,request_id=key,item_id=pack['id'],target_id=oid,pose=pose);check(repeat.get('mutation',{}).get('replayed'),command+': retry idempotent')
   check(bool(med('medical_item',item_id=pack['id'],target_id=oid,pose=pose).get('error')),command+': shared recovery enforced')
   check(bool(med('medical_item',item_id=pack['id'],target_id=o['id'],pose=pose).get('error')),command+': companion supply rejects player')
  lua('prepare_'+pet);lua('rest_'+pet);before=state(pet);time.sleep(4);after=state(pet);check(after[0]-before[0]>=120 and after[1]-before[1]>=80,'Pet AI uses percentage Health/resource regeneration')
  lua('prepare_'+pet);lua('disease_'+pet);time.sleep(7);st=state(pet);check(st[1]>=1 and all(w==0 for w in st[5:13])and st[3]not in(13,14),'Pet disease drains Action without wounds or incap')
  time.sleep(6);lua('prepare_'+pet);before=state(pet);lua('food_'+pet);time.sleep(.5);after=state(pet);check(1000<after[15]<=1100,'Pet food buff capped at ten percent');check(after[2]<300,'Pet food max-Mind increase does not refill Mind')
  lua('trick_'+pet);prow=next(p for p in vehicle('status')['state']['pet_datapad'] if p['pet_id']==pet)
  for _ in range(20):
   trained=vehicle('ch_train_command',device_id=prow['id'],command_id=8)
   row=next(p for p in trained.get('state',{}).get('pet_datapad',[]) if p['pet_id']==pet)
   if any(c['command_id']==8 for c in row['commands']):break
   time.sleep(.1)
  check(any(c['command_id']==8 for c in row['commands']),'Native Trick 2 training completes')
  lua('trick_'+pet);vehicle('pet_command',device_id=prow['id'],command_id=8);time.sleep(.5);restored=state(pet)[2];check(1<restored<=300,'Pet trick restores bounded Mind')
  check(lua('trickready_'+pet)in('false','0'),'Native trick recovery is active');lua('trick_'+pet);vehicle('pet_command',device_id=prow['id'],command_id=8);time.sleep(.5);check(state(pet)[2]<150,'Repeated trick blocked by shared recovery')
  lua('prepare_'+droid);lua('wounds_'+droid);lua('hospital_'+droid)
  snapshot=med()['state'];person=next(p for p in snapshot['companions'] if p['id']==droid);pack=next(i for i in snapshot['inventory']['items']if i.get('medical_command')=='healdroidwound');pos=person['position'];pose.update(left=[pos[0],pos[1]+1,pos[2]],right=[pos[0]+.1,pos[1]+1,pos[2]])
  out=med('medical_item',item_id=pack['id'],target_id=droid,pose=pose)
  if out.get('error'):print(out,flush=True)
  check(out.get('mutation',{}).get('success'),'Droid reconstruction kit treats Health wounds in hospital');check(0<=state(droid)[4]<200,'Reconstruction changes real Health wounds')
  for oid in (pet,droid):
   lua('health_'+oid);time.sleep(.2);check(state(oid)[3]in(13,14),'Health depletion incapacitates companion '+oid)
  report.pop('debug_snapshot',None);report.pop('debug_vehicle',None);report.pop('last_call',None)
  report['passed']=True;save()
 finally:
  if helper:
   try:lua('cleanup')
   finally:script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays')
  if sid:
   try:
    loc=call('/services/status')['state']['player'];call('/session/logout',session_id=sid,**{k:loc[k]for k in('position','building_id','cell_index')})
   except Exception:pass
  save()
if __name__=='__main__':main()
