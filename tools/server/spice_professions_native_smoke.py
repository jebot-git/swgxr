#!/usr/bin/env python3
"""Exercise native spice healing, performance and crafting on isolated local grants.

Uses original consumables and commands. Only fixture skills/resources/HAM and
buff clock shortening are privileged; no substitute effect implementation.
"""
import argparse,json,math,re,secrets,sys,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console
from delivery_mission_smoke import allocations_for
sys.path.insert(0,str(ROOT))
from server.character_protocol import crc


def main():
 p=argparse.ArgumentParser();p.add_argument('--execute-native',action='store_true',required=True);p.add_argument('--only',choices=['all','medicine','entertainer','crafting'],default='all');args=p.parse_args()
 report=dict(passed=False,native_execution=True,privileged_fixture=True,fixture_note='Original skill/item/resource grants and HAM preparation; native buff durations shortened only to enter and clean withdrawal. All tested treatment, performance and crafting effects execute production native paths.',checks=[],responses=[],fixtures=[])
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';added='';sessions={};drafts={};owners=[];used_spices=[]
 def key():return 'spiceprof_'+secrets.token_hex(10)
 def check(ok,label):report['checks'].append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 def call(f,path,**kw):
  for retry in range(10):
   out=req(path,dict(account=f['account'],character_id=f['id'],**kw));report['responses'].append(dict(path=path,character=f['id'],response=redact(out)))
   if out.get('error_code')!='backend_busy' or out.get('mutation_started') is not False:return out
   time.sleep(.4)
  return out
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(100):
   with log.open() as f:f.seek(offset);m=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',f.read())
   if m:return m.group(1).strip().strip('[]')
   time.sleep(.1)
  raise RuntimeError('Native helper timeout '+name)
 def pose(row):return {k:row[k] for k in ('position','building_id','cell_index')}
 def inventory(f):return call(f,'/inventory/status',live_session_id=sessions[f['id']])
 def status(f):return call(f,'/combat/session/update',session_id=sessions[f['id']],ready=True,**f['pose'])
 def command(f,name,target=0,argument=''):
  return int(lua('swgxrSpiceCommand:'+','.join([f['id'],name,str(target),argument])))
 def expire(f,spice,phase):
  check(lua('swgxrSpiceExpire:'+','.join([f['id'],str(crc('spice.'+spice+'.'+phase))]))=='true','Native '+spice+' '+phase+' clock shortened on fixture only')
  time.sleep(1.4)
 def consume(f,name):
  item=next(i for i in inventory(f)['items'] if i['template'].endswith('/spice_'+name+'.iff'))
  out=call(f,'/inventory/consume',item_id=item['id'],live_session_id=sessions[f['id']]);check(out.get('mutation',{}).get('success'),'Original '+name+' consumable activates through native inventory')
  used_spices.append((f,name))
  return out
 def clear(f,name):expire(f,name,'up');expire(f,name,'down')
 def treat(name,selfheal=False):
  state=call(actor,'/medic/status',live_session_id=sessions[actor['id']])['state']
  remaining=state.get('medical_item_cooldowns',{}).get(name,0) if name in ('healwound','healdamage') else next(a['cooldown_seconds'] for a in state['abilities']if a['id']==name)
  if remaining>0:time.sleep(remaining+.2)
  fields=lua('swgxrSpiceTreat:'+name+(','+'self' if selfheal else ',other')).split(',')
  return [int(float(x)) for x in fields]
 def performance(f,action,**kw):return call(f,'/entertainer/'+action,live_session_id=sessions[f['id']],request_id=key(),zone='tatooine',**kw)
 def patron():return json.loads(lua('swgxrSpicePatron'))
 try:
  for profession in ['science_medic','social_entertainer','crafting_artisan']:
   f=dict(account='invtestspiceprof'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8)))
   for readiness_attempt in range(6):
    made=req('/characters',dict(f,species='human',profession=profession));report['responses'].append(dict(path='/characters',response=redact(made)))
    # Native galaxy registration failed before sending character creation.
    if made.get('error')!='Invalid galaxy - missing IP address':break
    report['creation_readiness_retries']=report.get('creation_readiness_retries',0)+1;time.sleep(1)
   if 'character' not in made:print(made,flush=True)
   check('character' in made,'Create disposable original '+profession+' character');f['id']=made['character']['id'];owners.append(f);report['fixtures'].append(f)
   loc=call(f,'/enter')['source_location'];f['pose']=pose(loc);sessions[f['id']]=call(f,'/session/start',**f['pose'])['session_id'];status(f)
  actor,patient,crafter=owners
  added=f'''
-- BEGIN SWGXR SPICE PROFESSION FIXTURE
function Tests:swgxrSpiceSetup()
 local a=getSceneObject({actor['id']});local b=getSceneObject({patient['id']});local c=getSceneObject({crafter['id']})
 awardSkill(a,"science_medic_master");awardSkill(a,"social_dancer_master");awardSkill(c,"crafting_artisan_master")
 for _,p in ipairs({{a,b,c}}) do CreatureObject(p):forcePeace();for n=0,8 do CreatureObject(p):setBaseHAM(n,10000);CreatureObject(p):setMaxHAM(n,10000);CreatureObject(p):setHAM(n,10000);CreatureObject(p):setWounds(n,0) end end
 local ai=SceneObject(a):getSlottedObject("inventory");local ci=SceneObject(c):getSlottedObject("inventory")
 for _,name in ipairs({{"crash_n_burn","neutron_pixey","grey_gabaki"}}) do giveItem(ai,"object/tangible/food/spice/spice_"..name..".iff",-1) end
 for _,name in ipairs({{"yarrock","muon_gold"}}) do giveItem(ci,"object/tangible/food/spice/spice_"..name..".iff",-1) end
 local pack=giveItem(ai,"object/tangible/medicine/stimpack_sm_s1.iff",-1);TangibleObject(pack):setUseCount(50)
 local wound=giveItem(ai,"object/tangible/medicine/medpack_wound_health.iff",-1);TangibleObject(wound):setUseCount(50)
 writeData("swgxrSpiceWoundPack",SceneObject(wound):getObjectID())
 for i=1,6 do giveItem(ci,"object/tangible/crafting/station/weapon_tool.iff",-1) end
 for i=1,18 do givePlayerResource(c,"mineral",500);givePlayerResource(c,"chemical",500) end
 return "ready"
end
function Tests:swgxrSpiceVenue()
 local a=getSceneObject({actor['id']});local b=getSceneObject({patient['id']})
 SceneObject(a):teleport(10.65,-0.894992,1.91,1082877);SceneObject(b):teleport(11.15,-0.894992,1.91,1082877)
 return "ready"
end
function Tests:swgxrSpiceCommand(arg)
 local id,name,target,arguments=string.match(arg,"([^,]+),([^,]+),([^,]+),(.*)")
 return tostring(CreatureObject(getSceneObject(tonumber(id))):executeCommand(name,tonumber(target),arguments))
end
function Tests:swgxrSpiceExpire(arg)
 local id,hash=string.match(arg,"([^,]+),([^,]+)");return tostring(CreatureObject(getSceneObject(tonumber(id))):setBuffDuration(tonumber(hash),1))
end
function Tests:swgxrSpiceTreat(arg)
 local name,kind=string.match(arg,"([^,]+),([^,]+)");local a=getSceneObject({actor['id']});local p=getSceneObject({patient['id']});if kind=="self" then p=a end
 CreatureObject(a):setPosture(0);CreatureObject(a):forcePeace();CreatureObject(a):setHAM(6,CreatureObject(a):getMaxHAM(6));CreatureObject(a):setWounds(6,0)
 for _,n in ipairs({{0,3}}) do CreatureObject(p):setHAM(n,4000) end
 CreatureObject(p):setWounds(0,name=="healwound" and 500 or 0)
 if name=="healwound" then
 local cell=BuildingObject(getSceneObject(4005381)):getCell(2);local cellId=SceneObject(cell):getObjectID()
 SceneObject(a):teleport(1,0,0,cellId);SceneObject(p):teleport(2,0,0,cellId)
 end
 local h=CreatureObject(p):getHAM(0);local w=CreatureObject(p):getWounds(0)
 local result=CreatureObject(a):executeCommand(name,{patient['id']},"");if kind=="self" then -- the explicit target below is replaced before use
 end
 return tostring(result)..","..tostring(CreatureObject(p):getHAM(0)-h)..","..tostring(w-CreatureObject(p):getWounds(0))
end
function Tests:swgxrSpiceUnavailablePerformance()
 local p=getSceneObject({actor['id']});local values={{}}
 for _,posture in ipairs({{13,14}}) do CreatureObject(p):setPosture(posture);CreatureObject(p):executeCommand("startdance",0,"basic");table.insert(values,tostring(CreatureObject(p):getPosture())) end
 CreatureObject(p):setPosture(0);return table.concat(values,",")
end
function Tests:swgxrSpiceHealingSkill() return tostring(CreatureObject(getSceneObject({actor['id']})):getSkillMod("healing_dance_mind")) end
function Tests:swgxrSpiceWounds()
 local p=getSceneObject({patient['id']});for _,n in ipairs({{0}}) do CreatureObject(p):setWounds(n,1000) end
 return "ready"
end
function Tests:swgxrSpicePatron()
 local a=getSceneObject({actor['id']});local b=getSceneObject({patient['id']});local data=CreatureObject(a):getEntertainerPatronData(b)
 return string.sub(data,1,-2)..',"wounds":'..tostring(CreatureObject(b):getWounds(0))..',"max_mind":'..tostring(CreatureObject(b):getMaxHAM(6))..',"base_mind":'..tostring(CreatureObject(b):getBaseHAM(6))..'}}'
end
-- END SWGXR SPICE PROFESSION FIXTURE
'''
  added=added.replace('local result=CreatureObject(a):executeCommand(name,'+patient['id']+',"");if kind=="self" then -- the explicit target below is replaced before use\n end','local result=CreatureObject(a):executeCommand(name,SceneObject(p):getObjectID(),"")')
  added=added.replace('executeCommand(name,SceneObject(p):getObjectID(),"")','executeCommand(name,SceneObject(p):getObjectID(),name=="healwound" and ("health|"..tostring(readData("swgxrSpiceWoundPack"))) or "")')
  script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.3);check(lua('swgxrSpiceSetup')=='ready','Isolated native fixtures receive documented skill, resource and HAM setup')
  # Use real movement endpoint to put physician and patient within native range.
  loc=actor['pose'];patient['pose']=dict(loc)
  moved=call(patient,'/services/status',session_id=sessions[patient['id']],zone='tatooine',**loc);status(patient)
  if args.only in ('all','medicine'):
   baseline=treat('tenddamage');check(baseline[0]==0 and baseline[1]>0,'Original Tend Damage provides measurable unmodified healing')
   wb=treat('healwound');check(wb[0]==0 and wb[2]>0,'Health Wound Medpack provides measurable unmodified healing')
   ib=treat('healdamage');check(ib[0]==0 and ib[1]>0,'Original stim item provides measurable unmodified healing')
   consume(actor,'crash_n_burn');time.sleep(3.2)
   active=treat('tenddamage');check(active[0]==0 and active[1]==math.floor(1.5*baseline[1]+.5),'Crash active multiplies actual ability restoration by the CU 1.5x multiplier')
   wa=treat('healwound');check(wa[0]==0 and wa[2]==math.floor(1.5*wb[2]+.5),'Crash active multiplies actual wound restoration by the CU 1.5x multiplier')
   ia=treat('healdamage');check(ia[0]==0 and ia[1]==math.floor(1.5*ib[1]+.5),'Crash active multiplies actual stim restoration by the CU 1.5x multiplier')
   expire(actor,'crash_n_burn','up')
   withdrawn=treat('tenddamage');check(withdrawn[0]==0 and withdrawn[1]==-baseline[1],'Crash withdrawal turns actual outgoing ability healing into equal damage')
   ww=treat('healwound');check(ww[0]==0 and ww[1]==-wb[2] and ww[2]==0,'Withdrawal wound treatment damages corresponding HAM and leaves wounds untouched')
   self_heal=treat('tenddamage',True);check(self_heal[0]==0 and self_heal[1]==-baseline[1],'Withdrawal self-healing lowers authoritative own HAM')
   feedback=call(actor,'/medic/status',live_session_id=sessions[actor['id']])['state']['vital_feedback'];check(feedback['heal']>feedback['damage'],'Self-treatment actor illusion is newest native healing feedback event')
   time.sleep(3.2);iw=treat('healdamage');check(iw[0]==0 and iw[1]==-ib[1],'Withdrawal reverses actual healing item output as well')
   recipient_feedback=call(patient,'/medic/status',live_session_id=sessions[patient['id']])['state']['vital_feedback'];check(recipient_feedback['damage']>recipient_feedback['heal'],'Recipient receives newest authoritative damage feedback while actor sees healing')
   expire(actor,'crash_n_burn','down')
   time.sleep(3.2);base_cd=treat('healdamage');m=call(actor,'/medic/status',live_session_id=sessions[actor['id']]);normal=m['state']['medical_item_cooldowns']['healdamage']
   time.sleep(3.2);consume(actor,'grey_gabaki');grey=treat('healdamage');m=call(actor,'/medic/status',live_session_id=sessions[actor['id']]);reduced=m['state']['medical_item_cooldowns']['healdamage']
   report['medical_cooldown_samples']={'baseline_seconds':normal,'grey_seconds':reduced};check(base_cd[0]==0 and grey[0]==0 and 0<reduced<normal and abs(normal-reduced-round(normal)*.1)<.2,'Grey reduces the actual native medical recovery duration by ten percent')
   expire(actor,'grey_gabaki','up')
  if args.only in ('all','entertainer'):
   venue=next(r for r in json.loads((ROOT/'runtime/assets/ambient_npcs/placements.json').read_text())['instances'] if r['source_cell_id']=='1082877')
   inside=dict(position=venue['source_world_xyz'],building_id=venue['building_object_id'],cell_index=int(venue['cell_id'].split(':')[1]))
   check(lua('swgxrSpiceVenue')=='ready','Privileged fixture teleport enters original cantina')
   for f in [actor,patient]:
    f['pose']=pose(call(f,'/services/status')['state']['player']);check(performance(f,'status').get('source_kind')=='core3_entertainer','Fixture enters original native cantina with entertainment healing modifiers');status(f)
   performance(actor,'stop');check(performance(actor,'perform',kind='dance',name='basic').get('mutation',{}).get('success'),'Original dancer starts baseline performance')
   check(command(actor,'setperformancebufftarget',patient['id'])==0 and command(patient,'watch',actor['id'])==0,'Native performer target and patron watch commands establish actual patron')
   lua('swgxrSpiceWounds');before=patron();deadline=time.monotonic()+14
   while time.monotonic()<deadline:
    status(actor);status(patient)
    observed=patron()
    if observed['wounds']<before['wounds']:break
    time.sleep(.3)
   wound_tick=before['wounds']-observed['wounds'];strength_tick=observed['strength']-before['strength'];check(wound_tick>0 and strength_tick>0,'Original performance tick heals real patron and accrues inspiration strength')
   consume(actor,'neutron_pixey');lua('swgxrSpiceWounds');before=patron();deadline=time.monotonic()+14
   while time.monotonic()<deadline:
    status(actor);status(patient)
    observed=patron()
    if observed['wounds']<before['wounds']:break
    time.sleep(.3)
   check(before['wounds']-observed['wounds']==2*wound_tick,'Neutron doubles exact original entertainer wound-healing tick')
   check(observed['strength']-before['strength']==2*strength_tick,'Neutron doubles actual earned inspiration strength')
   # Native Flourish increases strength directly; original session caps benefits
   # at five per tick. Wait across ticks until the real cap is reached.
   expected_cap=2*min(125,int(float(lua('swgxrSpiceHealingSkill'))));deadline=time.monotonic()+110
   while time.monotonic()<deadline:
    for f in owners:status(f)
    for _ in range(5):command(actor,'flourish',0,'1')
    observed=patron()
    if observed['strength']>=expected_cap:break
    time.sleep(2)
   check(observed['strength']==expected_cap,'Neutron reaches exactly twice the original learned inspiration cap')
   check(command(patient,'stopwatching')==0,'Original patron stop-watch applies the earned native inspiration buff')
   applied=patron();check(applied['max_mind']==applied['base_mind']*(1+expected_cap/100),'Actual PerformanceBuff HAM modifier retains doubled inspiration strength')
   expire(actor,'neutron_pixey','up');command(actor,'stand');failed=performance(actor,'perform',kind='dance',name='basic');observed=status(actor)['snapshot']['player']
   check(not failed.get('ok') and observed['posture']==12,'Withdrawal dance attempt produces original knocked-down posture')
   command(actor,'stand');inv=inventory(actor);instrument=next((i for i in inv['items'] if i['template'].endswith('/slitherhorn.iff')),None)
   if instrument is None:
    # The actor started as a medic; the patron's original starter instrument
    # is deliberately not borrowed. Supply one original fixture instrument.
    extra=f'\nfunction Tests:swgxrSpiceInstrument() giveItem(SceneObject(getSceneObject({actor["id"]})):getSlottedObject("inventory"),"object/tangible/instrument/slitherhorn.iff",-1);return "ready" end\n'
    script.write_text(script.read_text()+extra);added+=extra;console('reloadscreenplays');lua('swgxrSpiceInstrument');instrument=next(i for i in inventory(actor)['items'] if i['template'].endswith('/slitherhorn.iff'))
   held=call(actor,'/inventory/equip',item_id=instrument['id'],arrangement=0,live_session_id=sessions[actor['id']]);check(held.get('mutation',{}).get('success'),'Explicitly equip original instrument before withdrawal music attempt')
   failed=performance(actor,'perform',kind='music',name='starwars1',item_id=instrument['id']);observed=status(actor)['snapshot']['player'];check(not failed.get('ok') and observed['posture']==12,'Withdrawal music attempt also produces original knockdown')
   unavailable=[int(float(v)) for v in lua('swgxrSpiceUnavailablePerformance').split(',')];check(unavailable==[13,14],'Withdrawal dance attempt preserves incapacitated and dead fixture postures')
   expire(actor,'neutron_pixey','down');command(actor,'stand')
  if args.only in ('all','crafting'):
   stations=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())['static_terminals'];station=min((s for s in stations if s['template'].endswith('/public_weapon_station.iff')),key=lambda s:math.dist(s['position'],[3500,5,-4800]))
   crafter['pose']=pose(station);tools=[i for i in inventory(crafter)['items'] if i['template'].endswith('/weapon_tool.iff')];index=0
   def craft(label,finish=False):
    nonlocal index
    tool=tools[index];index+=1;base=dict(tool_id=tool['id'],live_session_id=sessions[crafter['id']],**crafter['pose'])
    for attempt in range(4):
     draft=key();drafts[crafter['id']]=draft
     opened=call(crafter,'/crafting/open',request_id=draft,**base);check(bool(opened.get('state',{}).get('station_id')) and opened['state']['station_id']!='0',label+' opens original native crafting station')
     recipe=next(r for r in opened['state']['schematics'] if r['template'].endswith('/pistol_cdef.iff'))
     selected=call(crafter,'/crafting/select',session_id=draft,request_id=key(),index=recipe['index'],**base)
     allocations=allocations_for(selected['state'],{i['id'] for i in selected['state']['inventory']})
     assembled=call(crafter,'/crafting/assemble',session_id=draft,request_id=key(),allocations=allocations,**base)
     if 'Critical assembly failure; original ingredients returned' not in json.dumps(assembled):break
     report.setdefault('native_assembly_retries',[]).append(label)
    check(assembled.get('state',{}).get('stage')==3,label+' reaches actual original experimentation phase')
    points=assembled['state']['points'];check(points>0,label+' native experimentation budget is available')
    if finish:
     rows=assembled['state']['rows'];allocation=[0]*len(rows);choice=next(i for i,r in enumerate(rows) if r['point_limit']>0);allocation[choice]=1
     finished=call(crafter,'/crafting/finish',session_id=draft,request_id=key(),points=allocation,colors=[],**base);check(finished.get('mutation',{}).get('success'),label+' actual experimental craft commits native production');drafts.pop(crafter['id'],None);return points,finished['mutation']['experimentation_result']
    call(crafter,'/crafting/cancel',session_id=draft,request_id=key(),live_session_id=sessions[crafter['id']]);drafts.pop(crafter['id'],None);return points,None
   baseline,_=craft('Baseline');consume(crafter,'yarrock');boosted,_=craft('Yarrock active');check(boosted==baseline+2,'Yarrock adds exactly two experimentation points to each new craft')
   expire(crafter,'yarrock','up');_,result=craft('Yarrock withdrawal',True);check(result==8,'Every Yarrock-withdrawal experiment uses native failure outcome');expire(crafter,'yarrock','down')
   consume(crafter,'muon_gold');_,result=craft('Muon active',True);check(result==0,'Muon forces native Amazing Success result');expire(crafter,'muon_gold','up');_,result=craft('Muon withdrawal',True);check(result==8,'Muon withdrawal forces native Critical Failure result');expire(crafter,'muon_gold','down')
   deadline=time.monotonic()+90
   while time.monotonic()<deadline:
    result=call(crafter,'/crafting/status',live_session_id=sessions[crafter['id']])
    if not result['state']['jobs']:break
    time.sleep(1)
   check(not result['state']['jobs'],'All actual experimental prototype production completes without pending jobs')
  report['passed']=True
 finally:
  if added:
   # Clear only this run's original spice buffs before saving its fixtures.
   try:
    for f,spice in used_spices:
     lua('swgxrSpiceExpire:'+f['id']+','+str(crc('spice.'+spice+'.up')))
    time.sleep(1.3)
    for f,spice in used_spices:
     lua('swgxrSpiceExpire:'+f['id']+','+str(crc('spice.'+spice+'.down')))
    if args.only in ('all','entertainer') and len(owners)>1:
     lua('swgxrSpiceExpire:'+owners[1]['id']+','+str(crc('performance_enhance_dance_mind')))
    time.sleep(1.3)
   except Exception as e:report.setdefault('cleanup_errors',[]).append(str(e))
  for f in owners:
   try:
    if f['id'] in drafts:call(f,'/crafting/cancel',session_id=drafts[f['id']],request_id=key(),live_session_id=sessions[f['id']])
    if f['id'] in sessions:
     performance(f,'stop');loc=call(f,'/services/status',session_id=sessions[f['id']])['state']['player'];call(f,'/session/logout',live_session_id=sessions[f['id']],**pose(loc))
   except Exception as e:report.setdefault('cleanup_errors',[]).append(str(e))
  if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  report['passed']=report['passed'] and not report.get('cleanup_errors');out=ROOT/'runtime/evidence/spice-professions-native-smoke.json';out.write_text(json.dumps(redact(report),indent=2)+'\n');print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']),evidence=str(out))),flush=True)

if __name__=='__main__':main()
