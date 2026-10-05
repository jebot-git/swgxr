#!/usr/bin/env python3
"""Real two-player native pistol rewards and final-blow corpse-rights test.
Only isolated invtestpve accounts and newly spawned original worrts are changed.
Native HP setup controls the ratio; every credited player hit uses actual combat.
"""
import json,secrets,time,math,sys
from services_smoke import ROOT,req,redact
from equipment_smoke import console
from live_combat_smoke import Test

def main():
 owners=[];tests=[];checks=[];records=[];dynamic='';added=False
 sys.path.insert(0,str(ROOT/'tools/assets'))
 from character_formats import datatable
 from swg_formats import TreSet
 entries=datatable(TreSet(ROOT/'runtime/assets/active_tre').read('datatables/xp/species.iff'))
 bonuses=dict(value.split(':')for row in entries if (value:=row.get('human','')))
 species_multiplier=(100+int(bonuses.get('combat_rangedspecialize_pistol',bonuses.get('all','0'))))/100
 path=ROOT/'runtime/server/pve-fixture.json'
 for n in range(2):
  f={'account':'invtestpve'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8))}
  got=req('/characters',dict(f,species='human',profession='combat_marksman'));assert 'character'in got,got;f['id']=got['character']['id'];f['position']=[5000+n,0,-5400];owners.append(f)
 path.write_text(json.dumps(owners));script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 begin='\n-- BEGIN SWGXR PVE REWARDS TEST ONLY\n';end='-- END SWGXR PVE REWARDS TEST ONLY\n'
 ids=','.join(f['id']for f in owners);key='swgxrPveFixture:'+owners[0]['id']
 base=f'''function Tests:swgxrPveSetup()
 for _,oid in ipairs({{{ids}}}) do
  local p=getSceneObject(oid) if p~=nil then
   CreatureObject(p):clearCombatState(true) CreatureObject(p):setPosture(0)
   for i=0,8 do CreatureObject(p):setWounds(i,0);CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
   awardSkill(p,"combat_marksman_master");awardSkill(p,"outdoors_scout_novice")
   local inv=SceneObject(p):getSlottedObject("inventory")
   giveItem(inv,"object/weapon/ranged/pistol/pistol_fwg5.iff",-1)
   SceneObject(p):teleport(5000,getTerrainHeight(p,5000,-5400),-5400,0)
  end
 end
end
function Tests:swgxrPveSpawn()
 local p=getSceneObject({owners[0]['id']}) if p==nil then return end
 local prior=getSceneObject(readData("{key}"))
 if prior~=nil then SceneObject(prior):destroyObjectFromWorld() end
 local m=spawnMobile("tatooine","worrt",0,5004,getTerrainHeight(p,5004,-5400),-5400,0,0)
 if m==nil then return end
 AiAgent(m):setHamRegenDisabled(true)
 for _,pool in ipairs({{0,3,6}}) do CreatureObject(m):setMaxHAM(pool,100000);CreatureObject(m):setBaseHAM(pool,100000);CreatureObject(m):setHAM(pool,100000) end
 SceneObject(m):setCustomObjectName("SWGXR PvE fixture XP "..AiAgent(m):getBaseXp())
 CreatureObject(m):addCashCredits(25,true)
 giveItem(SceneObject(m):getSlottedObject("inventory"),"object/tangible/food/foraged/foraged_fruit_s1.iff",-1)
 writeData("{key}",SceneObject(m):getObjectID())
end
function Tests:swgxrPveCleanup()
 local m=getSceneObject(readData("{key}")) if m~=nil then SceneObject(m):destroyObjectFromWorld() end
 deleteData("{key}")
 for _,oid in ipairs({{{ids}}}) do local p=getSceneObject(oid) if p~=nil then CreatureObject(p):clearCombatState(true) end end
end
'''
 def install(extra=''):
  nonlocal added
  s=script.read_text()
  if begin in s:s=s[:s.index(begin)]+s[s.index(end)+len(end):]
  script.write_text(s+begin+base+extra+'\n'+end);added=True;console('reloadscreenplays');time.sleep(.3)
 def fixture(command):console('runLuaFunction Tests:'+command);time.sleep(.25)
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def corpse(owner,action,target,**more):
  out=req('/gathering/corpse/'+action,dict(account=owner['account'],character_id=owner['id'],corpse_id=target['id'],position=target['position'],request_id='pvereceipt_'+secrets.token_hex(8),**more));records.append({'action':action,'owner':owner['id'],'response':out});return out
 def xp(t):return t.poll()['snapshot']['player']['experience'].get('combat_rangedspecialize_pistol',0)
 def find_target(t):
  t.poll();return next(a for a in t.last['snapshot']['actors']if a['name'].startswith('SWGXR PvE fixture XP ')and not a['dead'])
 def player_hit(t,target):
  # Real source attack may miss; retry while recording only native health losses.
  for _ in range(8):
   t.poll();actor=t.actor(target['id']);before=actor['health'];before_ham=actor['ham'];_,out=t.shot(actor);after=t.actor(target['id']);damage=sum(max(0,b-max(0,a))for b,a in zip(before_ham,after['ham']))
   records.append({'action':'actual_pistol_impact','owner':t.fixture['id'],'target':target['id'],'health_before':before,'health_after':after['health'],'ham_before':before_ham,'ham_after':after['ham'],'actual_damage':damage,'mutation':out.get('mutation')})
   if damage>0:return damage,after
  raise AssertionError('No successful native pistol damage in eight attempts')
 def adjust(target,remaining,environment=0,kill_environment=False):
  assert target['id'].isdigit()
  extra=f'''function Tests:swgxrPveAdjust()
 local m=getSceneObject({target['id']})
 if m==nil or SceneObject(m):getObjectID()~=readData("{key}") then return end
 CreatureObject(m):clearCombatState(true)
 for _,pool in ipairs({{0,3,6}}) do CreatureObject(m):setHAM(pool,{int(remaining+environment)}) end
 if {int(environment)}>0 then CreatureObject(m):inflictDamage(m,0,{int(environment)},1) end
 if {'true'if kill_environment else'false'} then CreatureObject(m):inflictDamage(m,0,{int(remaining)+100000},1) end
end'''
  install(extra);fixture('swgxrPveAdjust')
 report={'passed':False,'native_execution':True,'diagnostic_native_hook':False,'headset_tested':False,'fixtures':owners,'original_human_xp_multiplier':species_multiplier,'fixture_setup':'Original worrts receive bounded fixture HP, disabled native regeneration and a known loot item/25credits. Strict spawned-ID setup adjusts remaining health after first real pistol hit to approximately70/30; second real native impact supplies final blow. No direct XP or ownership writes.','checks':checks,'records':records}
 try:
  for owner in owners:req('/inventory?account='+owner['account']+'&character_id='+owner['id'])
  install();fixture('swgxrPveSetup')
  for owner in owners:
   inv=req('/inventory?account='+owner['account']+'&character_id='+owner['id']);gun=next(x for x in inv['items']if x['template'].endswith('/pistol_fwg5.iff'))
   equipped=req('/inventory/equip',dict(account=owner['account'],character_id=owner['id'],item_id=gun['id'],arrangement=0))
   check(equipped.get('mutation',{}).get('success'),'Isolated owner equips original certified FWG5')
   status=req('/services/status',dict(account=owner['account'],character_id=owner['id']));owner['position']=status['state']['player']['position'];t=Test(owner,'http://127.0.0.1:18080');t.request('start',{'position':owner['position']});t.request('update',{'position':owner['position'],'ready':True});tests.append(t)
  check(all(t.last['snapshot']['weapon']['certified']for t in tests),'Both real native sessions use equal Master Marksman certification')
  fixture('swgxrPveSpawn');target=find_target(tests[0]);before=[xp(t)for t in tests];base_xp=int(target['name'].rsplit(' ',1)[1]);first,_=player_hit(tests[0],target)
  remaining=max(1,round(first*3/7));adjust(target,remaining);second,dead=player_hit(tests[1],target)
  check(dead['dead']and second==remaining,'Second actual native impact kills with capped remaining health, regardless of raw overkill')
  after=[xp(t)for t in tests];total=first+second;expected=[int(int(base_xp*first/total)*species_multiplier),int(int(base_xp*second/total)*species_multiplier)];earned=[after[i]-before[i]for i in range(2)]
  report['split']={'damage':[first,second],'fractions':[first/total,second/total],'base_xp':base_xp,'expected_pistol_xp':expected,'actual_pistol_xp':earned}
  check(earned==expected,'Two native players receive exact rounded damage-proportional pistol XP')
  check(abs(first/total-.7)<.01,'Controlled original-NPC combat demonstrates approximately70/30 actual damage')
  for t in tests:t.request('stop');t.session=''
  # Clear combat for harvesting using strict player IDs, without changing skills or corpse.
  extra=f'''function Tests:swgxrPvePeace() for _,oid in ipairs({{{ids}}}) do local p=getSceneObject(oid) if p~=nil then CreatureObject(p):clearCombatState(true) end end end'''
  install(extra);fixture('swgxrPvePeace')
  denied=corpse(owners[0],'inspect',target);allowed=corpse(owners[1],'inspect',target)
  check(not denied['corpse']['loot_available']and allowed['corpse']['loot_available'],'Smaller-damage final blower alone owns original corpse loot')
  check(not denied['corpse']['harvest_available']and allowed['corpse']['harvest_available'],'Organic harvest rights belong only to final blower')
  check(corpse(owners[0],'loot',target).get('http_error')is not None,'Higher-damage nonkiller cannot loot credits or items')
  choice=next(x for x in allowed['corpse']['resources']if x['available']);harvested=corpse(owners[1],'harvest',target,kind=choice['kind']);check(harvested.get('mutation',{}).get('success'),'Final blower harvests real organic resource using original yield')
  looted=corpse(owners[1],'loot',target);check(looted.get('mutation',{}).get('credits')==25 and len(looted['mutation'].get('item_ids',[]))>=1,'Final blower receives corpse credits and actual item')
  for i,owner in enumerate(owners):
   state=req('/services/status',dict(account=owner['account'],character_id=owner['id']));check(state['state']['experience'].get('combat_rangedspecialize_pistol',0)==after[i],'Proportional XP persists across independent login')
  # A second independent kill includes NPC/environment damage; a bystander earns none.
  for t in tests:
   t.seq=-1;t.request('start',{'position':t.fixture['position']});t.request('update',{'position':t.fixture['position'],'ready':True})
  fixture('swgxrPveSpawn');target=find_target(tests[0]);before=[xp(t)for t in tests];first,_=player_hit(tests[0],target);adjust(target,first,kill_environment=True);time.sleep(.3)
  after=[xp(t)for t in tests];earned=[after[i]-before[i]for i in range(2)];check(earned==[int(int(base_xp*.5)*species_multiplier),0],'Environment final blow retains its damage denominator; nearby non-damager earns zero')
  for t in tests:t.request('stop');t.session=''
  install(extra);fixture('swgxrPvePeace')
  for owner in owners:
   inspected=corpse(owner,'inspect',target);check(not inspected['corpse']['loot_available']and not inspected['corpse']['harvest_available'],'NPC/environment final blow creates no public or group-zero loot/harvest rights')
  report['passed']=True
 finally:
  for t in tests:
   if t.session:
    try:t.request('stop')
    except Exception:pass
  if added:
   fixture('swgxrPveCleanup');s=script.read_text()
   if begin in s:s=s[:s.index(begin)]+s[s.index(end)+len(end):];script.write_text(s);console('reloadscreenplays')
  report['session_checks']=sum(len(t.checks)for t in tests)
  (ROOT/'runtime/evidence/pve-rewards-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks),'session_checks':report['session_checks']}),flush=True)
if __name__=='__main__':main()
