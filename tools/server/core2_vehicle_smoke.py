#!/usr/bin/env python3
"""Call/store an existing owned fixture vehicle; no grants or movement benchmark."""
import json,time,math
from pathlib import Path
from delivery_mission_smoke import Probe,pose,key
from services_smoke import ROOT
p=Probe('core2_vehicle',ROOT/'runtime/evidence/core2/native-vehicle.json')
created_device=''
try:
 p.fixture=json.loads((ROOT/'runtime/server/vehicles-fixture.json').read_text())[0]
 assert p.fixture['account'].startswith('invtestvehicle')
 entered=p.call('/enter');p.initial_pose=entered['source_location'];p.start(p.initial_pose)
 state=p.call('/vehicles/status')['state']
 p.check(bool(state['datapad']),'Existing native vehicle control devices available')
 device=next(d for d in state['datapad'] if not d['spawned'])
 created_device=device['id']
 called=p.call('/vehicles/call',device_id=device['id'])
 p.check(called.get('mutation',{}).get('success'),'Native vehicle call resolves installed original descriptor')
 deadline=time.monotonic()+25;vehicle=None
 while time.monotonic()<deadline:
  state=p.call('/vehicles/status')['state'];vehicle=next((v for v in state['vehicles'] if v['device_id']==device['id']),None)
  if vehicle:break
  time.sleep(.4)
 p.check(vehicle is not None and bool(vehicle['seats']) and vehicle['max_speed']>0,'Actual original vehicle spawns with native seats and movement statistics')
 p.call('/session/update',position=vehicle['position'],building_id='0',cell_index=0,ready=True)
 touch=list(vehicle['position']);touch[1]+=.7
 stored=p.call('/vehicles/store',device_id=device['id'],left=touch,right=touch)
 p.check(stored.get('mutation',{}).get('success') and not next(d for d in stored['state']['datapad'] if d['id']==device['id'])['spawned'],'Original owned vehicle returns to persistent datapad')
 created_device='';p.report['vehicle_template']=vehicle['template'];p.report['passed']=True
finally:
 if created_device:
  try:
   state=p.call('/vehicles/status')['state'];v=next(v for v in state['vehicles'] if v['device_id']==created_device)
   p.call('/session/update',position=v['position'],building_id='0',cell_index=0,ready=True)
   touch=list(v['position']);touch[1]+=.7
   result=p.call('/vehicles/store',device_id=created_device,left=touch,right=touch)
   if not result.get('mutation',{}).get('success'):p.report['vehicle_cleanup_error']=result.get('error','store failed')
  except Exception as error:p.report['vehicle_cleanup_error']=str(error)
 p.cleanup()
 if p.report.get('cleanup_errors') or p.report.get('vehicle_cleanup_error'):p.report['passed']=False
 p.output.write_text(json.dumps(p.report,indent=2)+'\n');print(json.dumps({'passed':p.report['passed'],'checks':len(p.report['checks']),'cleanup_errors':p.report.get('cleanup_errors'),'vehicle_cleanup_error':p.report.get('vehicle_cleanup_error')}))
