#!/usr/bin/env python3
"""Three independent headless Godot clients against the private remote PvE realm.

Native fixtures must be provisioned separately. No PvP, JtL, latency injection,
privilege grants, health simulation or GPU/headset validation.
"""
import argparse, json, subprocess, time, urllib.error, urllib.request
from pathlib import Path
from tools.server.action_combat_remote_smoke import summary
ROOT=Path(__file__).resolve().parents[2]
URL='http://127.0.0.1:18083'

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixtures',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--seconds',type=float,default=48);a=p.parse_args()
 fixtures=json.loads(a.fixtures.read_text());assert len(fixtures)==3
 for f in fixtures:assert f.get('created_for_remote_combat') and f.get('prepared') and f['account'].startswith('actiontest')
 a.out.mkdir(parents=True,exist_ok=True);sessions=[];processes=[];logs=[];encounter='';report={'passed':False,'scope':'ground PvE only','remote_server':'87.106.27.237','clients':3,'client_processes':3,'server_mocked':False,'injected_latency_ms':0,'renderer':'dummy','gpu_tested':False,'headset_tested':False,'negative_checks':{}}
 def call(i,path,**fields):
  f=fixtures[i];body=dict(account=f['account'],character_id=f['id'],**fields)
  if i<len(sessions) and sessions[i]:body['session_id']=sessions[i]
  req=urllib.request.Request(URL+path,json.dumps(body).encode(),{'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=90) as response:return json.load(response)
  except urllib.error.HTTPError as e:return dict(json.load(e),http_status=e.code)
 def action(i,op,**fields):return call(i,'/combat/session/action_combat',action_combat=dict(action=op,**fields))
 try:
  report['initial_health']=[]
  for i,f in enumerate(fixtures):
   opened=call(i,'/combat/session/start',position=f['position'],heading_radians=0,spawn_test_lair=False);sessions.append(opened['session_id'])
   ready=call(i,'/combat/session/update',position=f['position'],heading_radians=0,ready=True);assert ready['snapshot']['ready'],ready
   report['initial_health'].append(ready['snapshot']['player']['ham'][0])
  started=action(0,'start');assert started.get('mutation',{}).get('success'),started
  encounter=started['mutation']['encounter_id']
  unauthorized=action(1,'status',encounter_id=encounter)
  report['negative_checks']['unjoined_status']=unauthorized
  assert not unauthorized.get('mutation',{}).get('success'),unauthorized
  for i in (1,2):
   joined=action(i,'join',encounter_id=encounter);assert joined.get('mutation',{}).get('success'),joined
  report['encounter_id']=encounter;report['fixtures']=[dict(id=f['id'],behavior=b) for f,b in zip(fixtures,('target','crossing','clear'))]
  start_at=time.time()+2
  for i,(f,behavior) in enumerate(zip(fixtures,('target','crossing','clear'))):
   config=dict(account=f['account'],character_id=f['id'],session_id=sessions[i],url=URL,position=f['position'],seconds=a.seconds,start_at=start_at,behavior=behavior,output=str((a.out/f'client-{i}.json').resolve()))
   path=a.out/f'client-{i}.config.json';path.write_text(json.dumps(config));path.chmod(0o600)
   log=(a.out/f'client-{i}.log').open('w');logs.append(log)
   processes.append(subprocess.Popen(['godot','--headless','--xr-mode','off','--max-fps','90','--path',str(ROOT/'client'),'--script','res://tests/action_combat_multiplayer.gd','--',str(path.resolve())],stdout=log,stderr=subprocess.STDOUT))
  for proc in processes:assert proc.wait(timeout=a.seconds+40)==0,'Godot multiplayer driver failed; see logs'
  clients=[json.loads((a.out/f'client-{i}.json').read_text()) for i in range(3)];report['client_results']=clients
  for c in clients:
   assert c['negative_checks'] and all(not r['reply'].get('mutation',{}).get('accepted') for r in c['negative_checks']),'Duplicate receipt accepted'
  state=action(0,'status')['mutation'];report['status']=state;assert state['participant_count']==3
  rows=state['victim_results'];cross=[r for r in rows if r['victim_id']==fixtures[1]['id'] and r['target_id']==fixtures[0]['id']]
  assert any(r['contact'] and r['damage']>0 and r['reported'] for r in cross),'No confirmed native damage to a crossing non-target'
  assert any(not r['contact'] and r['reported'] for r in cross),'No independently avoided non-target attack'
  assert all(not r['contact'] for r in rows if r['victim_id']==fixtures[2]['id']),'Clear player unexpectedly in contact'
  assert len({(r['actor_id'],r['attack_id'],r['victim_id']) for r in rows})==len(rows),'Duplicate settlement'
  assert all(c['accepted']>0 and not c['movement_errors'] for c in clients)
  # Identity cannot be overridden even with an otherwise plausible receipt.
  forged=action(1,'contact',encounter_id=encounter,actor_id=rows[-1]['actor_id'],attack_id=rows[-1]['attack_id'],contact=True,coverage_start=0,coverage_end=1,aim_revision=1,victim_id=fixtures[0]['id'])
  report['negative_checks']['forged_victim']=forged;assert forged.get('http_status')==400,forged
  replay=action(1,'contact',encounter_id=encounter,actor_id=rows[-1]['actor_id'],attack_id=rows[-1]['attack_id'],contact=True,coverage_start=0,coverage_end=1,aim_revision=1)
  report['negative_checks']['replay']=replay;assert not replay.get('mutation',{}).get('accepted'),replay
  left=action(2,'leave',encounter_id=encounter);assert left.get('mutation',{}).get('success'),left
  rejected=action(2,'status',encounter_id=encounter);report['negative_checks']['left_status']=rejected;assert not rejected.get('mutation',{}).get('success'),rejected
  report['latency_ms']={}
  for i,c in enumerate(clients):
   report['latency_ms'][str(i)]={route:summary([r for r in c['requests'] if r['route']==route],'ms') for route in sorted({r['route'] for r in c['requests']})}
  report['passed']=True
 finally:
  for proc in processes:
   if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
  for log in logs:log.close()
  if encounter:
   try:report['cleanup_encounter']=action(0,'stop')
   except Exception as e:report['cleanup_error']=str(e)
  for i in range(len(sessions)):
   try:call(i,'/combat/session/stop')
   except Exception as e:report['cleanup_error']=str(e)
  (a.out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ('client_results','status')},indent=2))
if __name__=='__main__':main()
