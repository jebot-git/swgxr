#!/usr/bin/env python3
"""Local-only native prototype test using the disposable ranged character.

The C++ native client owns a real Core3 session. This driver controls its movement
and action receipts, and samples the independent event stream. No health model is
substituted for Core3. Godot presentation/coverage has a separate headless test.
"""
import argparse,json,math,sys,time,urllib.request,urllib.parse,urllib.error,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/server'))
from equipment_smoke import console

def main():
 p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:18081');p.add_argument('--out',type=Path,default=ROOT/'runtime/action-prototype/native-test.json');p.add_argument('--seconds',type=float,default=28);p.add_argument('--godot',action='store_true');p.add_argument('--latency-ms',type=int,default=0);args=p.parse_args()
 assert urllib.parse.urlparse(args.url).hostname in ('127.0.0.1','localhost'), 'Isolated local backend only'
 f=json.loads((ROOT/'runtime/server/ranged-test-fixture.json').read_text());assert f['account'].startswith('rangetest') and f['id']=='281474993659303'
 identity=dict(account=f['account'],character_id=f['id']);sequence=0;session='';traces=[];checks=[];events={};started=time.monotonic();position=f['position'][:]
 report=dict(server_mocked=False,headset_tested=False,gpu_tested=False,driver='Python AI through real native Core3 client',passed=False)
 def request(path,data):
  stamp=time.monotonic();req=urllib.request.Request(args.url+path,json.dumps(dict(identity,**data)).encode(),{'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=30) as r:out=json.load(r)
  except urllib.error.HTTPError as error:
   raise RuntimeError(path+": "+error.read().decode()) from error
  traces.append(dict(path=path,detail=data.get('action_combat',{}).get('action'),ms=round((time.monotonic()-stamp)*1000,3),error=out.get('error_code')));return out
 def action(op,**kw):return request('/combat/session/action_combat',dict(action_combat=dict(action=op,**kw)))
 def check(value,label):
  checks.append(dict(passed=bool(value),description=label))
  if not value:raise AssertionError(label)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 def install(extra=''):
  script.write_text(original+f'''\nfunction Tests:swgxrActionFixtureRestore()
 local p=getSceneObject({f['id']}) if p==nil or CreatureObject(p):getFirstName()~="Varek" then return end
 CreatureObject(p):clearCombatState(true) SceneObject(p):teleport(3790,5,-4780,0)
 for i=0,8 do CreatureObject(p):setWounds(i,0) CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
 CreatureObject(p):setShockWounds(0) CreatureObject(p):setPosture(0)
 writeScreenPlayData(p,"swgxr_livecombat","test_authorized","1")
end
'''+extra);console('reloadscreenplays');time.sleep(.2)
 try:
  initial=request('/combat/session/start',dict(position=position,heading_radians=0,spawn_test_lair=False));session=initial['session_id'];identity['session_id']=session
  install();console('runLuaFunction Tests:swgxrActionFixtureRestore');time.sleep(.3)
  ready=request('/combat/session/update',dict(position=position,heading_radians=0,ready=True));check(ready.get('snapshot',{}).get('ready'),'Native session ready')
  initial_health=ready['snapshot']['player']['ham'][0]
  encounter=action('start');check(encounter.get('mutation',{}).get('success'), 'Opt-in three-mob encounter starts')
  native=encounter['mutation'];check(len(native['mobs'])==3,'Three original native mob instances')
  ids={m['role']:m['id'] for m in native['mobs']};check(encounter.get('compact') and 'snapshot' not in encounter,'Compact reply contains no fake RPG snapshot')
  # Damage one native ally so the support has real health to restore.
  install(f'''\nfunction Tests:swgxrActionFixtureWound()
 local owner=getSceneObject({f['id']}) local mob=getSceneObject({ids['melee']})
 if owner==nil or mob==nil or CreatureObject(owner):getFirstName()~="Varek" then return end
 CreatureObject(mob):inflictDamage(owner,0,math.floor(CreatureObject(mob):getMaxHAM(0)*0.3),0)
end
''');console('runLuaFunction Tests:swgxrActionFixtureWound')
  if args.godot:
   config=dict(identity,url=args.url,position=position,seconds=args.seconds,latency_ms=args.latency_ms,output=str(args.out.with_suffix('.godot.json').resolve()))
   config_path=args.out.with_suffix('.config.json');config_path.write_text(json.dumps(config));config_path.chmod(0o600)
   with args.out.with_suffix('.godot.log').open('w') as log:
    process=subprocess.run(['godot','--headless','--xr-mode','off','--max-fps','90','--path',str(ROOT/'client'),'--script','res://tests/action_combat_live_smoke.gd','--',str(config_path.resolve())],stdout=log,stderr=subprocess.STDOUT,timeout=args.seconds+30)
   check(process.returncode==0,'Live Godot AI driver completed without movement errors')
   client=json.loads(args.out.with_suffix('.godot.json').read_text());status=action('status')['mutation']
   check(client['accepted']>0,'Godot coverage receipts accepted by native timeline')
   check(status['misses']>0,'Godot sidesteps avoided committed native attacks')
   check(status['damage']>0,'Stationary phase received native damage')
   check(status['healing']>0,'Support restored native ally health')
   check(action('stop').get('mutation',{}).get('success'),'Native encounter stopped after Godot run')
   position_last=position
   # Snapshot does not move the body back after the AI driver has sidestepped.
   remaining=request('/combat/session/update',dict(position=client.get('position',position_last),heading_radians=0,ready=True))
   present={a['id'] for a in remaining['snapshot']['actors']};check(not present.intersection(ids.values()),'Fixture actors removed after live Godot run')
   report.update(passed=True,status=status,client=client,native_mobs=ids,driver='Godot AI diagnostic body through real native Core3 client')
   return
  until=time.monotonic()+args.seconds;last_update=0;duplicates=0;foreign=False;received=0;accepted=0;last_receipt=None
  while time.monotonic()<until:
   stamp=time.monotonic()
   if stamp-last_update>.3:
    update=request('/combat/session/update',dict(position=position,heading_radians=0,ready=True));last_update=time.monotonic()
    check(not update.get('error_code'),'Movement heartbeat accepted')
   sequence+=1
   reply=request('/session/sync',dict(sequence=sequence,world_revision=0,event_sequence=0,position=position,heading_radians=0,zone='tatooine',building_id='0',cell_index=0,tracking={}))
   for row in reply.get('motion',{}).get('action_events',[]):
    key=(row['encounter_id'],row['attack_id']);entry=events.get(key)
    server_now=row['server_now']+row['age_ms']/1000
    if entry is None:
     entry=dict(row=row,anchor=time.monotonic(),server=server_now,coverage=server_now,hit=False,sent=False,seen=[]);events[key]=entry
    entry['row']=row;entry['seen'].append(row['phase']);received+=1
   for entry in events.values():
    row=entry['row'];now=entry['server']+time.monotonic()-entry['anchor']
    if row['role']=='support' or row['phase'] in ('cancelled','recovery'):continue
    # This integration phase holds the body stationary for the entire attack.
    # Continuous client coverage and moving avoidance are tested in Godot.
    if now>=row['active_at'] and not entry['sent']:
     dx=position[0]-row['origin'][0];dz=position[2]-row['origin'][2];d=math.hypot(dx,dz);along=dx*row['direction'][0]+dz*row['direction'][2]
     hit=(along>=-.35 and abs(dx*row['direction'][2]-dz*row['direction'][0])<=row['radius']+.35) if row['role']=='ranged' else (d<=.35 or along>=row['cosine']*max(0,d-.35))
     entry['hit']|=hit and d<=row['range']+.35
    if now>=row['end_at']+.05 and not entry['sent'] and entry['coverage']<=row['active_at']:
     entry['sent']=True
     # Every third attack deliberately drops its receipt to exercise fallback.
     if int(row['attack_id'])%3==0:continue
     fields=dict(aim_revision=row['aim_revision'],encounter_id=row['encounter_id'],attack_id=row['attack_id'],actor_id=row['id'],contact=entry['hit'],coverage_start=entry['coverage'],coverage_end=now)
     result=action('contact',**fields);last_receipt=fields
     if result.get('mutation',{}).get('accepted'):accepted+=1
     if duplicates==0 and result.get('mutation',{}).get('accepted'):
      duplicate=action('contact',**fields);check(not duplicate.get('mutation',{}).get('success'),'Duplicate contact rejected');duplicates+=1
     if not foreign:
      bad=action('contact',**dict(fields,encounter_id='1'));check(not bad.get('mutation',{}).get('success'),'Foreign encounter receipt rejected');foreign=True
   time.sleep(.06)
  status=action('status')['mutation'];check(bool(events),'Native attack feed reached adapter independently of full snapshots')
  check(accepted>0,'Client contact receipt accepted by native timeline');check(status['damage']>0,'Core3 applied actual health damage');check(status['healing']>0,'Support restored actual ally health');check(status['fallbacks']>0,'Dropped report uses native active-window sample')
  check(any('windup' in e['seen'] for e in events.values()),'Wind-up arrives before resolution')
  stopped=action('stop');check(stopped.get('mutation',{}).get('success'),'Encounter stopped')
  if last_receipt:check(not action('contact',**last_receipt).get('mutation',{}).get('success'),'Stopped encounter rejects stale receipt')
  remaining=request('/combat/session/update',dict(position=position,heading_radians=0,ready=True));present={a['id'] for a in remaining['snapshot']['actors']};check(not present.intersection(ids.values()),'All fixture actors removed from native world')
  report.update(passed=True,status=status,initial_health=initial_health,final_health=remaining['snapshot']['player']['ham'][0],accepted_receipts=accepted,attack_count=len(events),native_mobs=ids)
 except Exception as error:report['error']=str(error)
 finally:
  if session:
   try:action('stop');console('runLuaFunction Tests:swgxrActionFixtureRestore');time.sleep(.2);request('/combat/session/stop',{})
   except Exception as error:report['cleanup_error']=str(error)
  script.write_text(original);console('reloadscreenplays')
  report.update(checks=checks,requests=traces,events=list(events.values()),elapsed_seconds=time.monotonic()-started)
  args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ('events','requests','checks','client')},indent=2))
 if not report['passed']:raise SystemExit(1)
if __name__=='__main__':main()
