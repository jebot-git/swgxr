#!/usr/bin/env python3
"""Explicitly mutating native bounds regression for only the dedicated Varek fixture.

Requires exclusive fixture ownership. Restores its test HAM/posture, spawns and
removes an ephemeral native lair/children, and briefly installs strict-ID console
fixtures. Does not restart Core3 or alter unrelated saved characters.
"""
import json,math,sys,time,urllib.request
from pathlib import Path
import argparse,os
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--mutate-dedicated-fixture',action='store_true',required=True);parser.parse_args()
os.chdir(ROOT);sys.path.insert(0,str(ROOT/'tools/server'))
from live_impact_bounds_check import run
run()
from live_combat_smoke import Test
from equipment_smoke import console
f=json.load(open('runtime/server/ranged-test-fixture.json'));assert f['id']=='281474993659303' and f['account']=='rangetest1a142'
def get(path):
 with urllib.request.urlopen('http://127.0.0.1:18080'+path,timeout=60) as r:return json.load(r)
for _ in range(40):
 if get('/health')['core3']['ready']:break
 time.sleep(1)
else:raise RuntimeError('native readiness')
get('/weapons?character_id='+f['id']+'&account='+f['account'])
p=Path('vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua');original=p.read_text()
restore='''\nfunction Tests:swgxrRestoreBoundFixture()\n local p=getSceneObject(281474993659303) if p==nil then return end\n CreatureObject(p):clearCombatState(true) SceneObject(p):teleport(3790,5,-4780,0)\n for i=0,8 do CreatureObject(p):setWounds(i,0) CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end\n CreatureObject(p):setShockWounds(0) CreatureObject(p):setPosture(0)\nend\n'''
def install(extra=''):
 p.write_text(original+restore+extra);console('reloadscreenplays');time.sleep(.5)
install();console('runLuaFunction Tests:swgxrRestoreBoundFixture');time.sleep(.5)
t=Test(f,'http://127.0.0.1:18080');report={'passed':False,'server_mocked':False,'native_execution':True};lair_id='';children=[]
try:
 s=t.request('start',{'position':f['position'],'heading_radians':0,'spawn_test_lair':True});lair_id=s['snapshot']['test_lair_id'];lair=t.actor(lair_id)
 t.request('update',{'position':f['position'],'ready':True});edge=json.load(open('runtime/evidence/live-impact-source-bounds.json'))['above_ground_edge_source_local'];hit=[lair['position'][i]+edge[i] for i in range(3)];assert math.dist(hit,lair['position'])>3
 launch,result=t.shot(lair,hit=hit);assert result['mutation']['success'] and result['mutation']['native_result']==0,result
 b=result['mutation']['impact_bounds'];assert b['source']=='original_appearance_sphere' and abs(b['radius']-4.51905775)<.0001
 report['unrotated_edge']={'hit_position':hit,'mutation':result['mutation']};t.next_fire=time.monotonic()+2.2
 install(f'\nfunction Tests:swgxrRotateBoundLair() local p=getSceneObject({lair_id}) if p~=nil then SceneObject(p):setDirectionalHeading(1.5707963267948966) end end\n');console('runLuaFunction Tests:swgxrRotateBoundLair');time.sleep(.3);t.poll();lair=t.actor(lair_id);assert abs(lair['heading_radians']-math.pi/2)<.001
 rotated=[edge[2],edge[1],-edge[0]];hit=[lair['position'][i]+rotated[i] for i in range(3)];launch,result=t.shot(lair,hit=hit);assert result['mutation']['success'] and result['mutation']['native_result']==0,result
 report['rotated_edge']={'hit_position':hit,'mutation':result['mutation']};t.next_fire=time.monotonic()+2.2
 # Far enough outside authored sphere+margin while still within native weapon range and ray checks.
 bad=[lair['position'][0],lair['position'][1]+12,lair['position'][2]];launch,result=t.shot(lair,hit=bad);assert result['error_code']=='impact_outside_target',result
 report['outside_rejected']=True
 started=time.monotonic()
 for i in range(5):
  t.next_fire=time.monotonic()+2.2
  for _ in range(3):t.request('update',{'position':f['position'],'ready':True})
  launch,result=t.shot(lair,hit=bad);assert result['error_code']=='impact_outside_target'
 report['mixed_request_seconds']=time.monotonic()-started;assert report['mixed_request_seconds']>10
 report['mixed_request_timeouts']=0;report['passed']=True
finally:
 if t.session:
  try:
   t.poll();children=[a['id'] for a in t.last['snapshot']['actors'] if a.get('lair_id')==lair_id];t.request('stop')
  except Exception as e:report['stop_error']=str(e)
 # Remove only the explicitly-created ephemeral test lair and its native children.
 ids=sorted(set(children+[lair_id])-{''});cleanup='\nfunction Tests:swgxrCleanupBoundLair()\n'+''.join(f' local p=getSceneObject({i}) if p~=nil then SceneObject(p):destroyObjectFromWorld() end\n' for i in ids)+'end\n'
 install(cleanup);console('runLuaFunction Tests:swgxrCleanupBoundLair');console('runLuaFunction Tests:swgxrRestoreBoundFixture');time.sleep(.5);p.write_text(original);console('reloadscreenplays')
 report['checks']=t.checks;report['cleaned_ephemeral_ids']=ids;Path('runtime/evidence/live-impact-native-bounds.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ['checks','unrotated_edge','rotated_edge']}))
