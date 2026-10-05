#!/usr/bin/env python3
"""Native life-state regression, explicitly scoped to the disposable Varek fixture.

Uses native inflictDamage to enter real incapacitation. Actual cloning applies
original wounds/decay. No runtime health substitution; only fixture setup/cleanup
uses strict-ID admin commands. Requires exclusive ownership and ready patch0026.
"""
import argparse,json,math,sys,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from live_combat_smoke import Test
from equipment_smoke import console

def main():
 p=argparse.ArgumentParser();p.add_argument('--mutate-dedicated-fixture',action='store_true',required=True);p.parse_args()
 fixture=json.loads((ROOT/'runtime/server/ranged-test-fixture.json').read_text());assert fixture['id']=='281474993659303' and fixture['account']=='rangetest1a142'
 # Zone the owned fixture into memory before strict-ID native setup; no live session exists yet.
 with urllib.request.urlopen('http://127.0.0.1:18080/weapons?account='+fixture['account']+'&character_id='+fixture['id'],timeout=60) as r:json.load(r)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 lua='''
function Tests:swgxrLifeRestore()
 local p=getSceneObject(281474993659303) if p==nil then return end
 CreatureObject(p):clearCombatState(true) SceneObject(p):teleport(3790,5,-4780,0)
 for i=0,8 do CreatureObject(p):setWounds(i,0) CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
 CreatureObject(p):setShockWounds(0) CreatureObject(p):setPosture(0)
end
function Tests:swgxrLifeIncap()
 local p=getSceneObject(281474993659303) if p==nil then return end
 CreatureObject(p):inflictDamage(p,0,CreatureObject(p):getHAM(0)+30,1)
end
function Tests:swgxrLifeDeadSetup()
 local p=getSceneObject(281474993659303) if p==nil then return end
 CreatureObject(p):setPosture(14)
end
'''
 t=Test(fixture,'http://127.0.0.1:18080');report={'passed':False,'server_mocked':False,'native_execution':True,'fixture_setup':'strict-ID admin setup; actual inflictDamage, recovery and suicide/cloning native APIs'}
 def admin(name):console('runLuaFunction Tests:'+name);time.sleep(.4)
 def start():return t.request('start',{'position':fixture['position'],'spawn_test_lair':False})
 def update(**fields):return t.request('update',dict(position=t.last['snapshot']['player']['position'],ready=True,**fields))
 def life(action):return t.request('life',{'action':action})
 try:
  script.write_text(original+lua);console('reloadscreenplays');time.sleep(.4);admin('swgxrLifeRestore')
  start();update()
  t.check(life('recover').get('error_code')=='native_player_not_incapacitated','Upright recovery rejected')
  t.check(life('medical_transport').get('error_code')=='native_player_not_down','Upright suicide/medical transport rejected')
  admin('swgxrLifeIncap');s=t.poll()['snapshot'];t.check(s['player']['posture']==13,'Actual source damage enters incapacitation')
  original_position=s['player']['position'];time.sleep(7);s=t.poll()['snapshot'];t.check(s['player']['posture']==13 and not s['player']['recovery_requested'],'Original automatic recovery held only for active VR session')
  moved=t.request('update',{'position':[0,0,0],'ready':True})
  t.check(moved['snapshot']['player']['position']==original_position and moved['mutation']['movement_accepted'] is False,'Incapacitated movement ignored without disconnect')
  requested=life('recover');s=requested['snapshot'];remaining=s['player']['recovery_remaining_seconds'];t.check(requested['mutation']['success'] and 0<remaining<=6.1,'Hold intent starts exact source six-second recovery interval')
  time.sleep(.5);s=t.poll()['snapshot'];t.check(s['player']['posture']==13,'Recovery is not an instant client heal')
  deadline=time.monotonic()+10
  while time.monotonic()<deadline:
   time.sleep(.4);s=t.poll()['snapshot']
   if s['player']['posture']==0:break
  t.check(s['player']['posture']==0 and s['player']['ham'][0]>0,'Original recovery task restores native posture and survivable HAM')
  report['recovered_player']=s['player']
  admin('swgxrLifeIncap');t.poll();t.check(t.last['snapshot']['player']['posture']==13,'Second native incapacitation available for medical action')
  t.request('stop');t.session='';t.seq=-1;start()
  t.check(t.last['snapshot']['player']['posture']==13,'Reconnect does not revive or reject incapacitated player')
  update();response=life('medical_transport');s=response['snapshot'];transport=s['transport'];dest=transport['destination']
  t.check(response['mutation']['success'] and transport['facility_id']!='0','One medical action invokes native suicide and chosen clone facility')
  t.check(s['player']['dead'] and s['player']['cloning'] and s['player']['on_load_screen'],'Native clone starts dead, with destination loading protection')
  t.check(dest['cell_index']>0 and dest['building_id']!='0' and dest['cell_id']!='0','Core3 medical destination is an actual original interior cell')
  t.check(s['player']['position']==dest['position'],'Snapshot destination uses actual native world position')
  report['transport']=transport
  stale=t.request('update',{'position':fixture['position'],'ready':True});t.check(stale['snapshot']['player']['position']==dest['position'] and stale['snapshot']['transport']==transport,'Stale pre-transport movement cannot overwrite clone position')
  bad=t.request('update',{'position':dest['position'],'transport_ack':'wrong','building_id':dest['building_id'],'cell_index':dest['cell_index']})
  t.check(bad.get('error_code')=='transport_ack_mismatch','Incorrect transport acknowledgment rejected')
  duplicate=life('medical_transport');t.check(duplicate.get('error_code')=='native_clone_pending','Repeated A cannot repeat cloning consequences')
  time.sleep(3.2);s=t.poll()['snapshot'];t.check(s['player']['posture']==0 and not s['player']['cloning'],'Original three-second clone recovery executes without fabricated revival')
  ack=t.request('update',{'position':dest['position'],'transport_ack':transport['id'],'building_id':dest['building_id'],'cell_index':dest['cell_index'],'ready':True})
  t.check(ack['snapshot']['transport']=={} and not ack['snapshot']['player']['on_load_screen'],'Validated client destination acknowledgment releases native loading guard')
  shifted=dest['position'].copy();shifted[0]+=.2
  inside=t.request('update',{'position':shifted,'building_id':dest['building_id'],'cell_index':dest['cell_index'],'ready':True})
  t.check(math.dist(inside['snapshot']['player']['position'],shifted)<.002 and inside['snapshot']['player']['cell_id']==dest['cell_id'],'World-to-cell movement preserves original cell and coordinates')
  outside=t.request('update',{'position':fixture['position'],'building_id':'0','cell_index':0,'ready':True})
  t.check(outside['snapshot']['player']['cell_id']=='0','Explicit outdoor transition exits original medical cell')
  # Already-dead reconnect has the same route; this setup does not represent a combat kill.
  admin('swgxrLifeDeadSetup');t.request('stop');t.session='';t.seq=-1;start();t.check(t.last['snapshot']['player']['dead'],'Already-dead native player can reconnect without implicit revival')
  r=life('medical_transport');t.check(r['mutation']['success'] and bool(r['snapshot']['transport']),'Already-dead A performs native cloning directly');time.sleep(3.2)
  report['passed']=True
 finally:
  if t.session:
   try:t.request('stop')
   except Exception as exc:report['stop_error']=str(exc);report['passed']=False
  admin('swgxrLifeRestore');script.write_text(original);console('reloadscreenplays')
  report['checks']=t.checks;report['responses']=t.responses
  (ROOT/'runtime/evidence/live-life-core3.json').write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps({'passed':report['passed'],'checks':len(t.checks),'transport':report.get('transport'), 'stop_error':report.get('stop_error')}))
 if not report['passed']:raise SystemExit(1)
if __name__=='__main__':main()
