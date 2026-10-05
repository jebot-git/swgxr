#!/usr/bin/env python3
"""Complete one original destroy mission through native FWG5 impact, Varek only.

No objective-completion shortcut. A strict-ID temporary Lua fixture reduces only
this newly spawned mission lair's max condition. MissionObserver awards/removes
its original objective. Core3 stays running, and unrelated test Lua is preserved.
"""
import argparse,json,math,secrets,sys,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/server'))
from live_combat_smoke import Test
from equipment_smoke import console
from services_smoke import redact


def main():
 p=argparse.ArgumentParser();p.add_argument('--mutate-dedicated-fixture',action='store_true',required=True);p.parse_args()
 fixture=json.loads((ROOT/'runtime/server/ranged-test-fixture.json').read_text())
 assert fixture['account']=='rangetest1a142' and fixture['id']=='281474993659303'
 test=Test(fixture,'http://127.0.0.1:18080');script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 report={'passed':False,'native_execution':True,'server_mocked':False,'headset_tested':False,'fixture':fixture,'responses':[]}
 block='';mission_id='';saved=None
 def service(action,**fields):
  payload={'account':fixture['account'],'character_id':fixture['id'],**fields}
  if test.session:payload['session_id']=test.session
  if action not in ('status','open'):payload.setdefault('request_id','mission_smoke_'+secrets.token_hex(10))
  request=urllib.request.Request(test.url+'/services/'+action,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(request,timeout=70) as response:result=json.load(response)
  except urllib.error.HTTPError as error:raise RuntimeError(json.load(error)) from error
  report['responses'].append({'action':action,'response':redact(result)})
  live=result.get('live_response')
  if live and test.session:test.seq=int(live['sequence']);test.last=live
  return result
 def install(lua):
  nonlocal block
  text=script.read_text()
  if block:text=text.replace(block,'')
  block='\n-- BEGIN SWGXR STRICT VAREK MISSION SMOKE\n'+lua+'\n-- END SWGXR STRICT VAREK MISSION SMOKE\n'
  script.write_text(text+block);console('reloadscreenplays');time.sleep(.5)
 def admin_ground(x,z):
  install(f'''function Tests:swgxrServicesMissionMove()
 local p=getSceneObject(281474993659303) if p==nil then return end
 CreatureObject(p):clearCombatState(true)
 SceneObject(p):teleport({float(x)},getTerrainHeight(p,{float(x)},{float(z)}),{float(z)},0)
end''')
  console('runLuaFunction Tests:swgxrServicesMissionMove');time.sleep(.4)
 def weaken(target):
  # Exact freshly spawned mission identity and original mission location are
  # checked in Python and again against the actual owned datapad in Lua.
  lid=str(target['id']);assert lid.isdigit() and mission_id.isdigit()
  x,y,z=target['position']
  install(f'''function Tests:swgxrServicesMissionWeaken()
 local p=getSceneObject(281474993659303) local m=getSceneObject({mission_id}) local l=getSceneObject({lid})
 if p==nil or m==nil or l==nil then return end
 local bag=SceneObject(p):getSlottedObject("datapad")
 if bag==nil or SceneObject(m):getParentID()~=SceneObject(bag):getObjectID() then return end
 if SceneObject(l):isCreatureObject() or SceneObject(l):getDistanceToPosition({x},{y},{z})>0.01 then return end
 TangibleObject(l):setMaxCondition(1) TangibleObject(l):setConditionDamage(0)
end''')
  console('runLuaFunction Tests:swgxrServicesMissionWeaken');time.sleep(.5)
 def restore():
  point=saved['position'] if saved else fixture['position']
  building=saved.get('building_id','0') if saved else '0';cell=saved.get('cell_index',0) if saved else 0
  # Fixture cleanup heals only Varek and clears combat before native movement.
  install('''function Tests:swgxrServicesMissionRestore()
 local p=getSceneObject(281474993659303) if p==nil then return end
 CreatureObject(p):clearCombatState(true)
 for i=0,8 do CreatureObject(p):setWounds(i,0) CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
 CreatureObject(p):setShockWounds(0) CreatureObject(p):setPosture(0)
end''')
  console('runLuaFunction Tests:swgxrServicesMissionRestore');time.sleep(.4)
  if test.session:test.request('update',{'position':point,'building_id':building,'cell_index':cell,'ready':True})
 try:
  initial=service('status');saved=initial['state']['player'];report['before']=redact(initial)
  test.check(not initial['state']['missions'],'Dedicated fixture has no existing player missions to disturb')
  terminal={'terminal_id':'1316125','position':[3501.7178,5,-4867.427],'building_id':'0','cell_index':0}
  opened=service('open',**terminal)
  offers=[m for m in opened['state']['terminal']['missions'] if m['type']=='destroy' and m.get('supported',False) and not m.get('active',False)]
  test.check(bool(offers),'Original general terminal produces supported destroy mission')
  offer=min(offers,key=lambda m:m['difficulty']);mission_id=offer['id'];report['offer']=offer
  accepted=service('mission_accept',**terminal,mission_id=mission_id)
  test.check(any(m['id']==mission_id for m in accepted['state']['missions']),'Original native destroy objective accepted')
  wallet_before=accepted['state']['wallet'].copy()
  test.request('start',{'position':terminal['position'],'spawn_test_lair':False})
  test.check(test.last['snapshot']['weapon']['item_id']==fixture['weapon_item_id'] and test.last['snapshot']['weapon']['certified'],'Exact original owned certified FWG5 equipped')
  xp_before=test.last['snapshot']['player']['experience'].copy()
  admin_ground(offer['position'][0],offer['position'][2]);test.poll()
  # Native active area selects a fresh valid source lair and updates mission start.
  deadline=time.monotonic()+18;active=None
  while time.monotonic()<deadline:
   state=service('status')['state'];active=next((m for m in state['missions'] if m['id']==mission_id),None)
   if active and math.dist([active['position'][0],active['position'][2]],[offer['position'][0],offer['position'][2]])>.01:break
   time.sleep(.5);test.poll()
  test.check(active is not None and active['position']!=offer['position'],'Native mission active area spawned lair and updated source waypoint')
  report['active_mission']=active
  admin_ground(active['position'][0]-22,active['position'][2]);test.poll()
  candidates=[a for a in test.last['snapshot']['actors'] if a['kind']=='lair' and math.hypot(a['position'][0]-active['position'][0],a['position'][2]-active['position'][2])<.2]
  test.check(len(candidates)==1,'One native mission lair exactly matches updated objective location')
  target=candidates[0];report['lair_before']=target;weaken(target);test.poll()
  target=test.actor(target['id']);test.check(target is not None and target['health']==1,'Strict fixture adjustment only reduces original mission lair condition')
  position=test.last['snapshot']['player']['position'];test.request('update',{'position':position,'building_id':'0','cell_index':0,'ready':True})
  time.sleep(1.1);test.poll()
  impacts=[]
  for _ in range(8):
   target=test.actor(report['lair_before']['id'])
   if target is None or target.get('dead',False):break
   vitals=test.last['snapshot']['player'];test.check(not vitals.get('dead') and not vitals.get('incapacitated') and vitals['ham'][0]>0.5*vitals['max_ham'][0],'Dedicated shooter remains safely above half native health')
   _,impact=test.shot(target,hit=target['position']);impacts.append(impact.get('mutation',{}));time.sleep(.4);test.poll()
  report['impacts']=impacts
  test.check(any(i.get('success') and int(i.get('damage',0))>0 for i in impacts),'Original FWG5 native impact destroys weakened original lair')
  after=service('status');deadline=time.monotonic()+5
  while any(m['id']==mission_id for m in after['state']['missions']) and time.monotonic()<deadline:time.sleep(.4);after=service('status')
  test.check(not any(m['id']==mission_id for m in after['state']['missions']),'Native destruction observer removes completed mission objective')
  wallet_after=after['state']['wallet'];test.check(wallet_after['cash']==wallet_before['cash'] and wallet_after['bank']-wallet_before['bank']==offer['reward'],'Native mission observer deposits exact original reward in bank')
  test.poll();xp_after=test.last['snapshot']['player']['experience'].copy();report.update(wallet_before=wallet_before,wallet_after=wallet_after,experience_before=xp_before,experience_after=xp_after)
  # Original destroy missions award bank credits; lair-only kills may award no
  # weapon XP. Record that original result rather than fabricate a mission XP rule.
  test.check(all(xp_after.get(k,0)>=v for k,v in xp_before.items()),'Native experience remains nondecreasing; original lair-only XP recorded')
  restore();test.request('stop');test.session='';test.seq=-1
  persisted=service('status');test.check(persisted['state']['wallet']==wallet_after and not any(m['id']==mission_id for m in persisted['state']['missions']),'Native reward and mission removal persist across independent login')
  report['persisted']=redact(persisted);report['passed']=True
 except Exception as error:report['error']=str(error)
 finally:
  if test.session:
   try:
    if mission_id:
     current=service('status')
     if any(m['id']==mission_id for m in current['state']['missions']):service('mission_abort',mission_id=mission_id)
    restore();test.request('stop');test.session=''
   except Exception as error:report['cleanup_error']=str(error)
  if block:
   script.write_text(script.read_text().replace(block,''));console('reloadscreenplays')
  report['checks']=test.checks;report['live_requests']=test.responses
  (ROOT/'runtime/evidence/services-mission-native.json').write_text(json.dumps(redact(report),indent=2)+'\n')
  print(json.dumps({'passed':report['passed'],'checks':len(test.checks),'error':report.get('error'),'cleanup_error':report.get('cleanup_error'),'mission':report.get('offer')}),flush=True)
 return 0 if report['passed'] and not report.get('cleanup_error') else 1
if __name__=='__main__':raise SystemExit(main())
