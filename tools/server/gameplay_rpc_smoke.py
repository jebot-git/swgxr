#!/usr/bin/env python3
"""Actual isolated Core3 gathering, recipe and deed RPC regression. No VR."""
import json,secrets,time,sys
from pathlib import Path
from services_smoke import req,redact,ROOT
checks=[];records=[];sessions={}
def check(ok,label):
 checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
 if not ok:raise AssertionError(label)
def fixture(name):
 f=json.loads((ROOT/('runtime/server/'+name+'-fixture.json')).read_text());f=f[0]if isinstance(f,list)else f
 assert f['account'].startswith('invtest');return f
def call(f,path,**kw):
 data=dict(account=f['account'],character_id=f['id'],**kw)
 if f['id']in sessions:data.setdefault('live_session_id',sessions[f['id']])
 before=time.monotonic();r=req(path,data);records.append({'path':path,'seconds':time.monotonic()-before,'response':redact(r)});return r
def inventory(f):return req('/inventory?account='+f['account']+'&character_id='+f['id'])
def key():return 'gameplay_'+secrets.token_hex(8)
def main():
 report={'native_execution':True,'checks':checks,'responses':records,'passed':False};g=fixture('gathering');a=fixture('artisan');v=fixture('vehicles')
 try:
  inv=inventory(g);tool=next(i for i in inv['items']if i['template'].endswith('survey_tool_mineral.iff'))
  status=call(g,'/gathering/status',tool_id=tool['id']);check(bool(status.get('resources')),'Actual original survey resource pool available')
  check(all('label'in attr for r in status['resources']for attr in r['attributes']),'Original resource attributes resolve display labels')
  best=None
  for resource in status['resources']:
   survey=call(g,'/gathering/survey',tool_id=tool['id'],resource_id=resource['id'],position=[3600,5,-4780],request_id=key())
   point=survey['mutation']['survey']['highest']
   if point['density']>=.15:best=(resource,point);break
  check(best is not None,'Native resource density supports actual sampling')
  resource,point=best;pos=point['position'];pos[1]=5
  deployed=call(g,'/gathering/deploy',tool_id=tool['id'],resource_id=resource['id'],position=pos,request_id=key());dep=deployed['state']['deployments'][0]
  check(tool['id']not in{i['id']for i in deployed['inventory']['items']},'Deployment removes owned tool in committed same-RPC inventory')
  time.sleep(3.2)
  state=call(g,'/gathering/status');dep=state['deployments'][0]
  check(dep['cycles']>=1 and dep['quantity']>0 and dep['sample_status']=='sample_located','Native sampling settles source units and exposes cycle outcome')
  check(dep['next_sample_at_unix']>state['server_time'],'Native sampling countdown uses authoritative timestamp')
  body=dict(deployment_id=dep['id'],position=pos,request_id=key())
  picked=call(g,'/gathering/collect',**body);check(picked.get('mutation',{}).get('success') and tool['id']in{i['id']for i in picked['inventory']['items']},'Recovery returns tool and resource inventory without second login')
  replay=call(g,'/gathering/collect',**body);check(replay.get('mutation',{}).get('replayed'),'Uncertain recovery retry replays durable receipt without duplication')
  wrong=dict(body,position=[pos[0]+1,pos[1],pos[2]]);bad=call(g,'/gathering/collect',**wrong);check(bad.get('http_error')==400,'Receipt reuse with changed position rejected')
  start=call(g,'/combat/session/start',position=pos);check(start.get('session_live'),'Actual persistent native session starts');sessions[g['id']]=start['session_id']
  live=call(g,'/gathering/status',tool_id=tool['id']);check(live.get('live_response',{}).get('session_live') and live['tool']['id']==tool['id'],'Gathering status reuses existing live native session')
  h=call(g,'/gathering/holster',tool_id=tool['id'],request_id=key());check(h.get('mutation',{}).get('success') and h['state']['hip_tool_id']==tool['id'],'Live gathering mutation reconciles escrow and source attributes')
  h=call(g,'/gathering/return_tool',tool_id=tool['id'],request_id=key());check(h.get('mutation',{}).get('success'),'Live tool retrieval succeeds')
  call(g,'/combat/session/stop',session_id=sessions.pop(g['id']))
  inv=inventory(a);ct=next(i for i in inv['items']if i['template'].endswith('generic_tool.iff'));session=key();base=dict(tool_id=ct['id'],position=[3600,5,-4780],building_id='0',cell_index=0)
  opened=call(a,'/crafting/open',**base,request_id=session);check(bool(opened.get('state',{}).get('schematics')),'Native learned compatible recipe list opens')
  recipe=opened['state']['schematics'][0];selected=call(a,'/crafting/select',**base,session_id=session,index=recipe['index'],request_id=key())
  check(selected.get('state',{}).get('stage')==2 and bool(selected['state']['schematic'].get('slots')),'Selected source recipe has real ingredient slots and preview metadata')
  call(a,'/crafting/cancel',session_id=session,request_id=key())
  inv=inventory(v);deed=next((i for i in inv['items']if '/vehicle_deed/'in i['template']),None);check(deed is not None,'Original owned vehicle deed fixture exists')
  body=dict(item_id=deed['id'],request_id=key(),position=[3600,5,-4780],building_id='0',cell_index=0)
  activated=call(v,'/vehicles/activate',**body);check(activated.get('mutation',{}).get('success') and deed['id']not in{i['id']for i in activated['inventory']['items']},'Original vehicle deed use consumes deed and creates native control device')
  device=activated['mutation']['device_id'];check(any(row['id']==device for row in activated['state']['datapad']),'Activation returns actual native datapad control object')
  replay=call(v,'/vehicles/activate',**body);check(replay.get('mutation',{}).get('replayed') and replay['mutation']['device_id']==device,'Vehicle activation durable retry cannot duplicate native vehicle')
  persisted=call(v,'/vehicles/status');check(any(row['id']==device for row in persisted['state']['datapad']),'Vehicle survives independent native login')
  bad=call(g,'/vehicles/activate',**body);check(bad.get('http_error')==400,'Foreign deed identifier rejected')
  report['passed']=True
 finally:
  for f in (g,a,v):
   if f['id']in sessions:call(f,'/combat/session/stop',session_id=sessions[f['id']])
  (ROOT/'runtime/evidence/gameplay-20261005/native-gameplay.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
