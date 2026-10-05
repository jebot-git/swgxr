#!/usr/bin/env python3
"""Native incapacitated/dead seat ejection. Life states are test fixtures."""
import sys,json,time,math,urllib.parse
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import live_smoke as test
from equipment_smoke import console
checks=[];passed=False
try:
 for f in test.fixtures:
  native=test.request('/medic/status',{'account':f['account'],'character_id':f['id']})['state']['position']
  b={'account':f['account'],'character_id':f['id'],'position':native};s=test.request('/combat/session/start',b);b['session_id']=s['session_id'];test.bases.append(b);test.update(len(test.bases)-1)
 s=test.act(0,'status')['state']
 # Return a prior isolated bike run to its native datapad before calling car.
 for v in s['vehicles']:
  if not v['owned']:continue
  p=test.local(v,[0,.7,0]);test.update(0,position=[p[0],v['position'][1],p[2]])
  test.act(0,'store',device_id=v['device_id'],left=p,right=p)
 car=next(d for d in s['datapad'] if 'landspeeder_x34' in d['template'])
 v=test.called(car)
 for life,posture in [('Incap',13),('Death',14)]:
  for index,seat in [(1,'passenger'),(0,'driver')]:
   for f in test.fixtures:console('runLuaFunction Tests:swgxrVehicleFixture:'+f['id'])
   # Reset test posture through native console, then wait for native acknowledgement.
   for i in range(2):
    deadline=time.monotonic()+5
    while time.monotonic()<deadline:
     p=test.request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in test.bases[i].items() if k!='position'}))['snapshot']['player']
     if p['posture']==0:break
     time.sleep(.1)
    assert p['posture']==0
   # Vehicle may remain farther from reset fixture spawn after the earlier drive.
   s=test.act(0,'status')['state'];v=next(v for v in s['vehicles'] if v['device_id']==car['id'])
   test.board(0,v,'driver');test.board(1,v,'passenger')
   for n in range(3):test.update(0,1,0,True);test.update(1)
   console('runLuaFunction Tests:swgxrVehicle'+life+':'+test.fixtures[index]['id'])
   deadline=time.monotonic()+6
   while time.monotonic()<deadline:
    r=test.request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in test.bases[index].items() if k!='position'}))['snapshot']['player']
    if r['posture']==posture and not r['vehicles']['seat']:break
    time.sleep(.1)
   vs=r['vehicles'];reason='incapacitated' if posture==13 else 'dead'
   assert r['posture']==posture and not vs['seat'] and vs['forced_exit']['reason']==reason,(r['posture'],vs)
   checks.append(f'{reason} {seat} is forcefully ejected without changing native life state');print(checks[-1],flush=True)
   vehicle=next(v for v in vs['vehicles'] if v['device_id']==car['id'])
   assert next(s for s in vehicle['seats'] if s['id']==seat)['occupant_id']==''
   assert abs(vs['position'][1]-vehicle['position'][1])<.6
   checks.append(f'{reason} {seat} releases reservation on supported ground');print(checks[-1],flush=True)
   if index==0:
    assert abs(vehicle['speed'])<.01
    other=test.update(1);assert other['seat']['id']=='passenger'
    checks.append(f'{reason} driver stops vehicle and leaves conscious passenger seated');print(checks[-1],flush=True)
   else:
    other=test.update(0);assert other['seat']['id']=='driver'
    checks.append(f'{reason} passenger leaves conscious driver seated');print(checks[-1],flush=True)
   test.act(1-index,'dismount')
 passed=True
finally:
 for b in test.bases:
  try:test.request('/combat/session/stop',b)
  except Exception:pass
 for f in test.fixtures:console('runLuaFunction Tests:swgxrVehicleFixture:'+f['id'])
 (test.ROOT/'runtime/evidence/vehicles-ejection-core3.json').write_text(json.dumps({'passed':passed,'checks':checks,'scope':'Real native Core3 seats; controlled native life postures, not damage/kill-rule validation'},indent=2))
