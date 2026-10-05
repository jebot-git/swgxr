#!/usr/bin/env python3
"""Real Core3 artisan transactions on the isolated fixture only."""
import json,secrets,sys,time,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
f=json.loads((ROOT/'runtime/server/artisan-fixture.json').read_text());assert f['account'].startswith('invtestcraft')
base={'account':f['account'],'character_id':f['id'],'position':[3600,5,-4780]};query='?account='+f['account']+'&character_id='+f['id'];checks=[]
def check(ok,name):
 if not ok:raise AssertionError(name)
 checks.append(name);print(name,flush=True)
def inv():return request('/inventory'+query)
def status():return request('/crafting'+query)['state']
def action(verb,**kw):
 body=dict(base,request_id=secrets.token_hex(12),**kw)
 try:return request('/crafting/'+verb,body)
 except urllib.error.HTTPError as e:raise RuntimeError(str(e.code)+' '+e.read().decode()) from e

def prepare(tool,position=None):
 pos=position or base['position'];r=action('open',tool_id=tool['id'],position=pos);s=r['state'];sid=s['session_id'];choice=next(c for c in s['schematics'] if c['template'].endswith('pistol_cdef.iff'))
 r=action('select',tool_id=tool['id'],session_id=sid,index=choice['index'],position=pos);s=r['state']
 allocations=[[next(i['id'] for i in s['inventory'] if slot['index'] in i['slots'] and i['quantity']>=slot['quantity'])] for slot in s['schematic']['slots']]
 return sid,allocations,r

def identities(s):return {i['id']:(i['quantity'],i['customization'],i['container_id']) for i in s['items']}
try:
 snapshot=inv();tools=[i for i in snapshot['items'] if i['template'].endswith('weapon_tool.iff')];check(len(tools)>=2,'two owned tools available')
 sid,allocation,_=prepare(tools[0]);before=inv()
 r=action('assemble',tool_id=tools[0]['id'],session_id=sid,allocations=allocation)
 check(r['state']['stage']==3 and r['state']['station_id']!='','native station enables experimentation')
 check(r['inventory']['inventory']['occupied']==before['inventory']['occupied'],'escrow preserves inventory reservations')
 check(len(r['inventory']['items'])<len(before['items']),'original inputs reside outside usable inventory during assembly')
 r=action('cancel',session_id=sid)
 check(identities(before)==identities(r['inventory']),'cancellation restores exact original ingredients')
 sid,allocation,_=prepare(tools[0]);r=action('assemble',tool_id=tools[0]['id'],session_id=sid,allocations=allocation)
 try:action('finish',tool_id=tools[0]['id'],session_id=sid,points=[10,10,10,10])
 except RuntimeError:check(True,'overspent experimentation rejected')
 else:check(False,'overspent experimentation rejected')
 console('runLuaFunction Tests:swgxrArtisanFixture:'+f['id']+':fill');time.sleep(.3)
 try:action('finish',tool_id=tools[0]['id'],session_id=sid,points=[])
 except RuntimeError as e:check('inventory slot' in str(e),'full inventory rejects crafting start')
 else:check(False,'full inventory rejects crafting start')
 r=action('cancel',session_id=sid);after=identities(r['inventory']);check(all(after.get(i)==v for i,v in identities(before).items()),'full-bag cancellation cannot lose escrow ingredients')
 console('runLuaFunction Tests:swgxrArtisanFixture:'+f['id']+':clear');time.sleep(.3)
 before=inv();jobs=[];starts=[]
 for tool in tools[:2]:
  sid,allocation,_=prepare(tool);r=action('assemble',tool_id=tool['id'],session_id=sid,allocations=allocation);s=r['state'];points=[0]*len(s['rows'])
  if points and s['points']>0:points[0]=min(1,s['rows'][0]['point_limit'])
  body=dict(base,tool_id=tool['id'],session_id=sid,request_id=secrets.token_hex(12),points=points,colors=[])
  r=request('/crafting/finish',body);jobs=r['state']['jobs'];starts.append(body)
  check(any(j['tool_id']==tool['id'] for j in jobs),'native crafting timer started '+tool['id'])
  again=request('/crafting/finish',body);check(identities(r['inventory'])==identities(again['inventory']),'replayed start does not consume twice '+tool['id'])
 check(len(jobs)==2,'two tools produce concurrently')
 check(all(j['duration']>0 and j['due']>r['state']['server_time'] for j in jobs),'original complexity controls timers')
 (ROOT/'runtime/server/artisan-running.json').write_text(json.dumps(r,indent=2))
 deadline=time.monotonic()+max(j['duration'] for j in jobs)+30
 while time.monotonic()<deadline:
  if not status()['jobs']:break
  time.sleep(2)
 after=inv();ids={i['id'] for i in after['items']}
 check(all(j['prototype_id'] in ids for j in jobs),'both outputs delivered to reserved inventory slots')
 check(all(next(i for i in after['items'] if i['id']==j['prototype_id'])['template'].endswith('pistol_cdef.iff') for j in jobs),'native crafted outputs use requested original template')
 r=action('open',tool_id=tools[0]['id'],position=[3630,5,-4780]);check(not r['state']['station_id'],'station range gates experimentation');action('cancel',session_id=r['state']['session_id'])
 report={'passed':True,'checks':checks,'fixture':f,'live_core3':True,'gpu_validation':False,'output_ids':[j['prototype_id'] for j in jobs]}
 (ROOT/'runtime/evidence/artisan-crafting-core3.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
except Exception as e:
 (ROOT/'runtime/evidence/artisan-crafting-core3.json').write_text(json.dumps({'passed':False,'checks':checks,'error':str(e)},indent=2));raise
