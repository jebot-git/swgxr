#!/usr/bin/env python3
"""Disposable actual-Core3 Smuggler combat test; never grants production players skills."""
import json,math,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console
from live_combat_smoke import Test

def main():
 f={'account':'invtestsmuggler'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8))}
 created=req('/characters',dict(f,species='human',profession='combat_marksman'));assert 'character'in created,created
 f['id']=created['character']['id'];f['position']=[5010,0,-5500]
 (ROOT/'runtime/server/smuggler-fixture.json').write_text(json.dumps(f))
 checks=[];records=[];report={'passed':False,'native_execution':True,'headset_tested':False,'fixture':f,'checks':checks,'records':records};t=None
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 begin='\n-- BEGIN SWGXR SMUGGLER COMBAT TEST ONLY\n';end='-- END SWGXR SMUGGLER COMBAT TEST ONLY\n';key='swgxrSmuggler:'+f['id']
 source=(ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/trainers/trainerData.lua').read_text()
 skills=re.findall(r'"([a-z0-9_]+)"',re.search(r'trainer_smuggler\s*=\s*\{([^}]+)',source).group(1))
 grants='\n'.join('awardSkill(p,"'+skill+'")'for skill in skills)
 code=f'''function Tests:swgxrSmugglerSetup()
 local p=getSceneObject({f['id']}) if p==nil then return end
 awardSkill(p,"combat_marksman_master") {grants}
 giveItem(SceneObject(p):getSlottedObject("inventory"),"object/weapon/ranged/pistol/pistol_fwg5.iff",-1)
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0)
end
function Tests:swgxrSmugglerReloadScene()
 local p=getSceneObject({f['id']}) if p==nil then return end
 SceneObject(p):switchZone("tatooine",5010,getTerrainHeight(p,5010,-5500),-5500,0)
end
function Tests:swgxrSmugglerRestore()
 local p=getSceneObject({f['id']}) if p==nil then return end
 CreatureObject(p):clearCombatState(true)
 for i=0,8 do CreatureObject(p):setWounds(i,0);CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
end
function Tests:swgxrSmugglerLowPools()
 local p=getSceneObject({f['id']}) if p==nil then return end
 CreatureObject(p):setHAM(0,math.floor(CreatureObject(p):getMaxHAM(0)*.3))
 CreatureObject(p):setHAM(3,math.floor(CreatureObject(p):getMaxHAM(3)*.1))
 CreatureObject(p):setHAM(6,math.floor(CreatureObject(p):getMaxHAM(6)*.03))
end
function Tests:swgxrSmugglerSpawn(kind)
 local p=getSceneObject({f['id']}) if p==nil then return end
 local old=getSceneObject(readData("{key}")) if old~=nil then SceneObject(old):destroyObjectFromWorld() end
 local m=spawnMobile("tatooine",kind or "worrt",0,5013,getTerrainHeight(p,5013,-5500),-5500,0,0)
 if m==nil then return end
 AiAgent(m):setHamRegenDisabled(true)
 for _,pool in ipairs({{0,3,6}}) do CreatureObject(m):setMaxHAM(pool,100000);CreatureObject(m):setBaseHAM(pool,100000);CreatureObject(m):setHAM(pool,100000) end
 SceneObject(m):setCustomObjectName("SWGXR Smuggler fixture")
 writeData("{key}",SceneObject(m):getObjectID())
end
function Tests:swgxrSmugglerAttack()
 local p=getSceneObject({f['id']}) local m=getSceneObject(readData("{key}"))
 if p~=nil and m~=nil then AiAgent(m):setDefender(p) end
end
function Tests:swgxrSmugglerKiller() self:swgxrSmugglerSpawn("death_kreetle") end
function Tests:swgxrSmugglerInspect()
 local m=getSceneObject(readData("{key}")) if m==nil then return end
 SceneObject(m):setCustomObjectName("SWGXR Smuggler fixture snare="..CreatureObject(m):getSkillMod("private_swgxr_snare").." root="..CreatureObject(m):getSkillMod("private_swgxr_concussion_root").." daze="..CreatureObject(m):getSkillMod("private_swgxr_concussion_daze").." frozen="..CreatureObject(m):hasState(131072).." dizzy="..CreatureObject(m):hasState(16384))
end
function Tests:swgxrSmugglerBreakConcussion()
 local m=getSceneObject(readData("{key}")) if m~=nil then CreatureObject(m):inflictDamage(m,0,1,1) end
end
function Tests:swgxrSmugglerCooldowns()
 local p=getSceneObject({f['id']}) if p==nil then return end
 for _,ability in ipairs({{"restraining_shot","concussion_shot_improved"}}) do CreatureObject(p):addCooldown("swgxr_smuggler_"..ability,0) end
end
function Tests:swgxrSmugglerCleanup()
 local m=getSceneObject(readData("{key}")) if m~=nil then SceneObject(m):destroyObjectFromWorld() end deleteData("{key}")
end
'''
 def inventory():
  for attempt in range(6):
   result=req('/inventory?account='+f['account']+'&character_id='+f['id'])
   if 'items' in result:return result
   time.sleep(1)
  raise AssertionError(result)
 def fixture(name):console('runLuaFunction Tests:'+name);time.sleep(.3)
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def pose(feign=False,upright=False,position=None):
  return t.request('update',{'position':position or t.last['snapshot']['player']['position'],'smuggler_pose':{'tracked':True,'feign':feign,'upright':upright}})
 try:
  inventory()
  s=script.read_text();script.write_text(s+begin+code+end);console('reloadscreenplays');time.sleep(.4);fixture('swgxrSmugglerSetup')
  inv=inventory();gun=next(x for x in inv['items']if x['template'].endswith('/pistol_fwg5.iff'))
  equip=req('/inventory/equip',dict(account=f['account'],character_id=f['id'],item_id=gun['id'],arrangement=0));check(equip.get('mutation',{}).get('success'),'Real fixture equips certified source pistol')
  state=req('/services/status',dict(account=f['account'],character_id=f['id']));f['position']=state['state']['player']['position'];t=Test(f,'http://127.0.0.1:18080');t.request('start',{'position':f['position']});t.request('update',{'position':f['position'],'ready':True})
  fixture('swgxrSmugglerReloadScene');reloaded=t.poll()['snapshot'];records.append({'native_scene_reload':reloaded['player']})
  check(reloaded['ready'] and reloaded['player']['on_load_screen'],'Actual native zone transfer restores load protection in an already-ready session')
  unchanged=t.request('update',{'position':reloaded['player']['position'],'ready':False})['snapshot'];check(unchanged['player']['on_load_screen'],'Unready update does not clear native scene-loading protection')
  acknowledged=t.request('update',{'position':reloaded['player']['position'],'ready':True})['snapshot'];check(acknowledged['ready'] and not acknowledged['player']['on_load_screen'],'Explicit ready update reconciles native load state without restarting session')
  available={a['id']for a in t.last['snapshot']['weapon']['ability_catalog']};check({'lethal_shot','last_ditch','low_blow','restraining_shot','concussion_shot_improved'}<=available,'Learned native skill boxes expose all five ranged abilities')
  loadout=dict(t.last['snapshot']['weapon']['ability_loadout'],slots=['lethal_shot','low_blow','restraining_shot','concussion_shot_improved'],ultimate='last_ditch')
  equipped=t.request('loadout',{'item_id':gun['id'],'loadout':loadout});check(equipped.get('mutation',{}).get('success'),'Fixture explicitly equips four combat abilities and Last Ditch')
  check(t.last['snapshot']['player']['feign_death_available'],'Native Smuggler has Feign Death ability')
  fixture('swgxrSmugglerSpawn');t.poll();target=next(a for a in t.last['snapshot']['actors']if a['name'].startswith('SWGXR Smuggler fixture'))
  fixture('swgxrSmugglerLowPools');t.poll();p=t.last['snapshot']['player'];expected=2+sum(1-v/m for v,m in zip(p['ham'],p['max_ham']));origin=p['position'].copy();origin[1]+=1;hit=target['position'].copy();hit[1]+=.2;delta=[hit[i]-origin[i]for i in range(3)];length=math.sqrt(sum(v*v for v in delta));direction=[v/length for v in delta]
  launched=t.request('fire',{'shot_id':'smuggler_lastditch_01','item_id':gun['id'],'origin':origin,'direction':direction,'ability_id':'last_ditch'});records.append(launched)
  check(launched.get('mutation',{}).get('success'),'Last Ditch accepted through actual projectile launch')
  got=launched['snapshot']['player'];check(got['ham'][1:]==[1,1],'Last Ditch consumes real remaining action and mind to one')
  check(abs(launched['mutation']['damage_multiplier']-expected)<.1,'Last Ditch multiplier uses inverse current health/action/mind at launch')
  replay=t.request('fire',{'shot_id':'smuggler_lastditch_01','item_id':gun['id'],'origin':origin,'direction':direction,'ability_id':'last_ditch'});check(replay.get('error_code')=='duplicate_shot','Native shot receipt prevents duplicate consumption')
  time.sleep(.2);impact=t.request('impact',{'shot_id':'smuggler_lastditch_01','target_id':target['id'],'hit_position':hit,'projectile_age_seconds':1.0});records.append(impact)
  check(impact.get('mutation',{}).get('success'),'Last Ditch projectile applies native configured combat command after prepaid launch')
  fixture('swgxrSmugglerRestore');fixture('swgxrSmugglerCleanup');t.poll();start=pose(feign=True);records.append(start);check(start['snapshot']['player']['feigning_death'] and not start['snapshot']['player']['incapacitated'],'Tracked posture starts feign without creating real incapacitation')
  before=start['snapshot']['player']['position'];moved=pose(feign=True,position=[before[0]+3,before[1],before[2]]);check(moved['mutation'].get('movement_accepted')is False and moved['snapshot']['player']['position']==before,'Pending extra-hit feign is already immobilized')
  blocked=t.request('fire',{'shot_id':'smuggler_feign_denied','item_id':gun['id'],'origin':origin,'direction':[1,0,0]});check(not blocked.get('mutation',{}).get('success'),'Feigning cannot fire')
  fixture('swgxrSmugglerSpawn');fixture('swgxrSmugglerAttack');deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   t.poll();player=t.last['snapshot']['player']
   if player['posture']==13:break
   time.sleep(.5)
  check(player['posture']==13 and player['feigning_death'] and not player['incapacitated'],'One real MOB attack enters native feigned incap posture')
  lowest=player['ham'].copy();time.sleep(4);t.poll();after=t.last['snapshot']['player'];check(all(a>=b for a,b in zip(after['ham'],lowest)),'Nonkiller MOB stops inflicting damage after the extra blow')
  upright=pose(upright=True);check(not upright['snapshot']['player']['feigning_death'] and upright['snapshot']['player']['posture']==0,'Tracked upright posture exits native feign')
  after=pose(position=[before[0]+1,before[1],before[2]]);check(after['mutation'].get('movement_accepted'),'Normal native movement resumes after standing')
  fixture('swgxrSmugglerRestore');fixture('swgxrSmugglerSpawn');t.poll()
  for ability,effect in (('restraining_shot','snare=25'),('concussion_shot_improved','root=1.0 daze=1.0')):
   observed=False
   for attempt in range(4):
    fixture('swgxrSmugglerCooldowns');time.sleep(max(2,t.last['snapshot']['weapon']['fire_interval_seconds']+.1));t.poll();target=next(a for a in t.last['snapshot']['actors']if a['name'].startswith('SWGXR Smuggler fixture'));origin=t.last['snapshot']['player']['position'].copy();origin[1]+=1;hit=target['position'].copy();hit[1]+=.2;delta=[hit[i]-origin[i]for i in range(3)];length=math.sqrt(sum(v*v for v in delta));direction=[v/length for v in delta];shot='smuggler_'+ability+'_'+str(attempt)
    fired=t.request('fire',{'shot_id':shot,'item_id':gun['id'],'origin':origin,'direction':direction,'ability_id':ability});check(fired.get('mutation',{}).get('success'),'Actual native '+ability+' launch');time.sleep(.2)
    impacted=t.request('impact',{'shot_id':shot,'target_id':target['id'],'hit_position':hit,'projectile_age_seconds':1.0});records.append(impacted);check(impacted.get('mutation',{}).get('success'),'Actual native '+ability+' impact')
    fixture('swgxrSmugglerInspect');t.poll();target=next(a for a in t.last['snapshot']['actors']if a['id']==target['id'])
    if (effect=='snare=25' and float(re.search(r'snare=([0-9.]+)',target['name']).group(1))==25) or (effect!='snare=25' and all(float(v)==1 for v in re.search(r'root=([0-9.]+) daze=([0-9.]+)',target['name']).groups())):observed=True;break
   check(observed,'Successful native '+ability+' applies '+effect)
  fixture('swgxrSmugglerBreakConcussion');fixture('swgxrSmugglerInspect');t.poll();target=next(a for a in t.last['snapshot']['actors']if a['id']==target['id']);records.append({'concussion_after_damage':target});check(all(float(v)==0 for v in re.search(r'root=([0-9.]+) daze=([0-9.]+) frozen=([0-9.]+) dizzy=([0-9.]+)',target['name']).groups()),'Further actual damage clears native concussion root and daze')
  fixture('swgxrSmugglerRestore');fixture('swgxrSmugglerCleanup');t.poll();pose(feign=True);fixture('swgxrSmugglerKiller');fixture('swgxrSmugglerAttack');deadline=time.monotonic()+30;feigned=False
  while time.monotonic()<deadline:
   t.poll();player=t.last['snapshot']['player'];feigned=feigned or player['feigning_death']
   if player['dead']:break
   time.sleep(.5)
  check(feigned and player['dead'],'Original killer MOB deathblows a feigning player')
  report['passed']=True
 finally:
  if t and t.session:
   try:pose(upright=True);t.request('stop')
   except Exception:pass
  fixture('swgxrSmugglerCleanup');s=script.read_text()
  if begin in s:script.write_text(s[:s.index(begin)]+s[s.index(end)+len(end):]);console('reloadscreenplays')
  if t:report['session_checks']=t.checks
  (ROOT/'runtime/evidence/smuggler-native-combat.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}),flush=True)
if __name__=='__main__':main()
