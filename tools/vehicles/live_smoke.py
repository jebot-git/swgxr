#!/usr/bin/env python3
"""Exercise real persistent Core3 vehicle ownership, two seats, motion and storage."""
import json,sys,time,math,urllib.error,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
fixtures=json.loads((ROOT/'runtime/server/vehicles-fixture.json').read_text());assert all(f['account'].startswith('invtestvehicle') for f in fixtures)
bases=[];checks=[];passed=False;telemetry=[]
def check(v,label):
 assert v,label
 checks.append(label);print(label,flush=True)
def act(i,action,**kw):return request('/vehicles/'+action,dict(bases[i],**kw))
def denied(i,action,**kw):
 try:act(i,action,**kw)
 except urllib.error.HTTPError as e:
  error=json.loads(e.read());print(error.get('error','rejected'),flush=True);return e.code==400
 return False
def update(i,throttle=0,steer=0,held=False,position=None):
 r=request('/combat/session/update',dict(bases[i],position=position or bases[i]['position'],ready=True,vehicle_controls={'held':held,'throttle':throttle,'steer':steer}))
 if r.get('error_code'):raise AssertionError(r['error_code'])
 return r['snapshot']['player']['vehicles']
def local(v,p):
 a=v['heading_radians'];x,y,z=v['position'];return [x+p[0]*math.cos(a)-p[2]*math.sin(a),y+p[1],z-p[0]*math.sin(a)-p[2]*math.cos(a)]
def board(i,v,seat):
 s=next(s for s in v['seats'] if s['id']==seat);p=local(v,s['position']);update(i,position=[p[0],v['position'][1],p[2]])
 return act(i,'board',vehicle_id=v['id'],seat=seat,hand=p)['state']
def called(device):
 act(0,'call',device_id=device['id']);deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  s=act(0,'status')['state'];v=next((v for v in s['vehicles'] if v['device_id']==device['id']),None)
  if v:return v
  time.sleep(.3)
 raise AssertionError('Native call did not finish')
def run():
 global passed
 try:
  for f in fixtures:
   # Native read gives the source ground height after the isolated fixture setup.
   native=request('/medic/status',{'account':f['account'],'character_id':f['id']})['state']['position']
   b={'account':f['account'],'character_id':f['id'],'position':native}
   start=request('/combat/session/start',b);b['session_id']=start['session_id'];bases.append(b);update(len(bases)-1)
  state=act(0,'status')['state'];check(len(state['datapad'])==2,'Native persistent vehicle control devices appear in datapad')
  car=next(d for d in state['datapad'] if 'landspeeder_x34' in d['template']);bike=next(d for d in state['datapad'] if d!=car)
  check(denied(1,'call',device_id=car['id']),'Another player cannot call owned vehicle')
  v=called(car);check(v['max_speed']==13 and v['acceleration']==8,'Landspeeder uses native Core3 movement statistics')
  check(len(v['seats'])==2,'Landspeeder exposes distinct driver and passenger seats')
  check(denied(0,'board',vehicle_id=v['id'],seat='driver',hand=[5000,0,-5400]),'Boarding requires hand contact with chosen seat')
  check(denied(1,'board',vehicle_id=v['id'],seat='driver',hand=local(v,v['seats'][0]['position'])),'Only owner can occupy driver seat')
  s=board(0,v,'driver');check(s['seat']['id']=='driver','Touching driver seat reserves native seat')
  s=board(1,v,'passenger');check(s['seat']['id']=='passenger','Second player can board passenger seat')
  check(denied(0,'store',device_id=car['id'],left=v['position'],right=v['position']),'Occupied vehicle cannot return to datapad')
  s=update(0,position=[6000,0,-6000]);check(s['seat']['id']=='driver' and abs(s['position'][0]-5000)<5,'Foot locomotion packets cannot move seated driver')
  initial=next(x for x in s['vehicles'] if x['id']==v['id']);before=initial['position'];initial_heading=initial['heading_radians']
  for i in range(8):
   s=update(0,1,0,True);update(1,1,1,True)
   current=next(x for x in s['vehicles'] if x['id']==v['id']);telemetry.append({'time':time.monotonic(),'position':current['position'],'speed':current['speed']})
  current=next(x for x in s['vehicles'] if x['id']==v['id'])
  check(math.dist(before,current['position'])>2 and 0<current['speed']<=13,'Throttle moves actual native vehicle with source acceleration and speed cap')
  check(abs(math.remainder(current['heading_radians']-initial_heading,2*math.pi))<.001,'Passenger controls cannot steer the vehicle')
  passenger=update(1);pv=next(x for x in passenger['vehicles'] if x['id']==v['id']);expected=local(pv,pv['seats'][1]['position']);check(math.dist(passenger['position'],expected)<.01,'Passenger is carried by native vehicle movement')
  for i in range(4):s=update(0,1,.6,True);update(1)
  current=next(x for x in s['vehicles'] if x['id']==v['id']);check(abs(math.remainder(current['heading_radians']-initial_heading,2*math.pi))>.1,'Driver steering turns actual native vehicle')
  for i in range(12):s=update(0,-1,0,True);update(1)
  current=next(x for x in s['vehicles'] if x['id']==v['id']);check(current['speed']<0,'Braking through zero produces native reverse movement')
  for i in range(8):s=update(0);update(1)
  current=next(x for x in s['vehicles'] if x['id']==v['id']);check(abs(current['speed'])<.01,'Released controls bring vehicle to a stop')
  r=act(1,'dismount');check(not r['state']['seat'] and 'position' in r['mutation'],'Passenger dismount finds supported exit')
  r=act(0,'dismount');check(not r['state']['seat'],'Driver dismount releases seat')
  v=next(x for x in r['state']['vehicles'] if x['id']==v['id']);touch=local(v,[0,.7,0]);update(0,position=[touch[0],v['position'][1],touch[2]])
  check(denied(1,'store',device_id=car['id'],left=touch,right=touch),'Another player cannot store the vehicle')
  check(denied(0,'store',device_id=car['id'],left=[0,0,0],right=touch),'Both hands must touch to store')
  r=act(0,'store',device_id=car['id'],left=touch,right=touch);check(not next(d for d in r['state']['datapad'] if d['id']==car['id'])['spawned'],'Two-hand owner grab stores original vehicle in native datapad')
  v=called(bike);check(len(v['seats'])==1 and v['kind']=='bike' and v['max_speed']==15,'Single-seat bike uses original class and native speed')
  board(0,v,'driver');s=update(0,1,0,True);time.sleep(1.1);s=act(0,'status')['state'];current=next(x for x in s['vehicles'] if x['id']==v['id']);check(current['speed']<3,'Stale driving input fails closed and brakes')
  act(0,'dismount');passed=True
 finally:
  for b in bases:
   try:request('/combat/session/stop',b)
   except Exception:pass
  (ROOT/'runtime/evidence/vehicles-core3.json').write_text(json.dumps({'passed':passed,'checks':checks,'telemetry':telemetry,'scope':'Actual loopback Core3 objects and two authenticated players; no VR render claim'},indent=2))

if __name__=="__main__":run()
