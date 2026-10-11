#!/usr/bin/env python3
"""Measure the real remote native fixture through an authenticated SSH tunnel.

Provisioning is a separate admin operation. This driver never grants privileges,
changes realm configuration or adds artificial latency. Godot uses dummy rendering.
"""
import argparse,json,math,subprocess,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def summary(rows,key):
 values=sorted(float(r[key]) for r in rows if key in r)
 if not values:return {}
 return {'count':len(values),'p50':values[(len(values)-1)//2], 'p95':values[min(len(values)-1,math.ceil(len(values)*.95)-1)],'max':values[-1]}

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--seconds',type=float,default=36);a=p.parse_args()
 f=json.loads(a.fixture.read_text());assert f.get('created_for_remote_combat') and f.get('prepared') and f['account'].startswith('actiontest')
 a.out.parent.mkdir(parents=True,exist_ok=True)
 base={'account':f['account'],'character_id':f['id']};url='http://127.0.0.1:18083';session='';report={'passed':False,'remote_server':'87.106.27.237','transport':'SSH tunnel to remote loopback adapter','injected_latency_ms':0,'headset_tested':False,'gpu_tested':False};requests=[]
 def call(path,**fields):
  body=dict(base,**fields)
  if session:body['session_id']=session
  start=time.monotonic()
  req=urllib.request.Request(url+path,json.dumps(body).encode(),{'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=90) as response:value=json.load(response)
  requests.append({'route':path,'ms':(time.monotonic()-start)*1000})
  return value
 def action(op):return call('/combat/session/action_combat',action_combat={'action':op})
 try:
  opened=call('/combat/session/start',position=f['position'],heading_radians=0,spawn_test_lair=False);session=opened['session_id']
  ready=call('/combat/session/update',position=f['position'],heading_radians=0,ready=True);assert ready['snapshot']['ready']
  report['initial_health']=ready['snapshot']['player']['ham'][0]
  encounter=action('start');assert encounter.get('mutation',{}).get('success'),encounter
  config=dict(base,session_id=session,url=url,position=f['position'],seconds=a.seconds,latency_ms=0,output=str(a.out.with_suffix('.godot.json').resolve()))
  path=a.out.with_suffix('.config.json');path.write_text(json.dumps(config));path.chmod(0o600)
  with a.out.with_suffix('.godot.log').open('w') as log:
   run=subprocess.run(['godot','--headless','--xr-mode','off','--max-fps','90','--path',str(ROOT/'client'),'--script','res://tests/action_combat_live_smoke.gd','--',str(path.resolve())],stdout=log,stderr=subprocess.STDOUT,timeout=a.seconds+40)
  assert run.returncode==0,'Remote Godot driver failed; see log'
  client=json.loads(a.out.with_suffix('.godot.json').read_text());report['client']=client;report['status']=action('status')['mutation']
  assert client['accepted']>0 and client['rejected']==0 and not client['movement_errors'] and client['aim_updates']>0
  assert report['status']['misses']>0
  report['latency_ms']={}
  for route in sorted({r['route'] for r in client['requests']}):
   rows=[r for r in client['requests'] if r['route']==route]
   report['latency_ms'][route]={k:summary(rows,k) for k in ('ms','adapter_queue_ms','adapter_rate_wait_ms','native_bridge_roundtrip_ms','native_action_ms') if any(k in r for r in rows)}
  report['passed']=True
 finally:
  if session:
   try:action('stop');call('/combat/session/stop')
   except Exception as error:report['cleanup_error']=type(error).__name__
  report['setup_requests']=requests;a.out.write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps({k:v for k,v in report.items() if k not in ('client','setup_requests')},indent=2))
if __name__=='__main__':main()
