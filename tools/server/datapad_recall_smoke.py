#!/usr/bin/env python3
"""Exercise existing owned vehicle/helper devices, restoring fixture world state."""
import json,time
from pathlib import Path
from delivery_mission_smoke import Probe,pose
from services_smoke import ROOT
p=Probe('datapad_recall',ROOT/'runtime/evidence/core2/datapad-recall-native.json')
original={};device='';pet=''
def wait_spawn(key,kind):
 deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  state=p.call('/vehicles/status')['state']
  row=next((r for r in state[kind] if r['device_id']==key),None)
  if row:return row
  time.sleep(.5)
 raise AssertionError('Original native call did not complete')
def wait_stored(key,kind):
 deadline=time.monotonic()+8
 while time.monotonic()<deadline:
  state=p.call('/vehicles/status')['state']
  if not next(r for r in state[kind] if r['id']==key)['spawned']:return state
  time.sleep(.25)
 raise AssertionError('Original native store did not complete')
def approach(row):
 loc=list(row['position']);loc[0]+=.6
 p.call('/session/update',position=loc,building_id='0',cell_index=0,ready=True)
def operation(action,**values):
 result=p.call('/vehicles/'+action,**values)
 p.check(result.get('mutation',{}).get('success'), 'Native '+action+' accepted')
 return result
try:
 p.fixture=json.loads((ROOT/'runtime/server/vehicles-fixture.json').read_text())[0]
 assert p.fixture['account'].startswith('invtestvehicle')
 entered=p.call('/enter');p.initial_pose=entered['source_location'];p.start(p.initial_pose)
 state=p.call('/vehicles/status')['state'];original={'datapad':state['datapad'],'pet_datapad':state['pet_datapad']};p.report['original_devices']=original
 p.check(bool(state['pet_datapad']),'Existing original follower droid device present without grants')
 d=state['pet_datapad'][0];pet=d['id']
 if not d['spawned']:operation('pet_call',device_id=pet)
 row=wait_spawn(pet,'pets');approach(row);time.sleep(1.05)
 # Wrong kind and external IDs must not alias a valid controlled object.
 p.check(p.call('/vehicles/pet_recall',device_id=row['id']).get('http_error')==400,'Creature ID is not accepted as an owned pet control device')
 bad=list(row['position']);bad[0]+=10
 p.check(p.call('/vehicles/pet_store',device_id=pet,left=bad,right=bad).get('http_error')==400,'Remote fake hand contact rejected by native droid geometry')
 p.call('/session/update',position=[row['position'][0]+15,row['position'][1],row['position'][2]],building_id='0',cell_index=0,ready=True)
 p.check(p.call('/vehicles/pet_recall',device_id=pet).get('http_error')==400,'Out-of-reach datapad droid recall rejected')
 row=wait_spawn(pet,'pets');approach(row)
 recalled=operation('pet_recall',device_id=pet)
 p.check(not next(x for x in wait_stored(pet,'pet_datapad')['pet_datapad'] if x['id']==pet)['spawned'],'Native droid recall removes world object and retains device')
 time.sleep(1.05);operation('pet_call',device_id=pet);row=wait_spawn(pet,'pets');approach(row);time.sleep(1.05)
 hand=list(row['position']);hand[1]+=min(.5,row['height']*.5)
 stored=operation('pet_store',device_id=pet,left=hand,right=hand)
 p.check(not next(x for x in wait_stored(pet,'pet_datapad')['pet_datapad'] if x['id']==pet)['spawned'],'Both native hand contacts store original follower droid')
 v=next(x for x in original['datapad'] if not x['spawned']);device=v['id'];operation('call',device_id=device);row=wait_spawn(device,'vehicles');approach(row)
 badid=operation('recall',device_id=device)
 p.check(not next(x for x in badid['state']['datapad'] if x['id']==device)['spawned'],'Datapad vehicle recall succeeds without invented hand positions')
 p.report['passed']=True
finally:
 try:
  if original:
   state=p.call('/vehicles/status')['state']
   for kind,key,call,store in [('datapad','vehicles','call','recall'),('pet_datapad','pets','pet_call','pet_recall')]:
    for old in original[kind]:
     now=next(r for r in state[kind] if r['id']==old['id'])
     if now['spawned'] and not old['spawned']:
      row=wait_spawn(old['id'],key);approach(row);time.sleep(1.05);operation(store,device_id=old['id']);wait_stored(old['id'],kind)
     elif old['spawned'] and not now['spawned']:
      p.call('/session/update',**pose(p.initial_pose),ready=True);time.sleep(1.05);operation(call,device_id=old['id']);wait_spawn(old['id'],key)
   final=p.call('/vehicles/status')['state']
   p.check(all([(r['id'],r['spawned']) for r in final[k]]==[(r['id'],r['spawned']) for r in original[k]] for k in original),'Original fixture device identities and spawned states restored')
 except Exception as error:p.report['device_cleanup_error']=str(error);p.report['passed']=False
 p.cleanup()
 if not p.report.get('cleanup_errors'):
  try:
   fresh=p.call('/enter')['source_location']
   p.check(all(abs(a-b)<.02 for a,b in zip(fresh['position'],p.initial_pose['position'])) and str(fresh.get('building_id','0'))==str(p.initial_pose.get('building_id','0')) and int(fresh.get('cell_index',0))==int(p.initial_pose.get('cell_index',0)) and abs(float(fresh.get('heading_radians',0))-float(p.initial_pose.get('heading_radians',0)))<.0001, 'Fresh native login verifies restored source position, cell and heading')
   state=p.call('/vehicles/status')['state']
   p.check(all({r['id'] for r in state[k]}=={r['id'] for r in original[k]} for k in original), 'Original persistent control devices survive fresh native login')
  except Exception as error:p.report['readback_error']=str(error);p.report['passed']=False
 if p.report.get('cleanup_errors'):p.report['passed']=False
 p.output.write_text(json.dumps(p.report,indent=2)+'\n');print(json.dumps({'passed':p.report['passed'],'checks':len(p.report['checks']),'cleanup_errors':p.report.get('cleanup_errors'),'device_cleanup_error':p.report.get('device_cleanup_error')}))
