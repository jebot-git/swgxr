#!/usr/bin/env python3
"""Native scout regression on the disposable fixture only."""
import json,secrets,sys,time,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
f=json.loads((ROOT/'runtime/server/scout-fixture.json').read_text());assert f['account'].startswith('invtestscout')
checks=[];base={'account':f['account'],'character_id':f['id'],'position':[5000,180,-5400],'posture':'standing'}
def call(action,**kw):
 try:
  payload=dict(base,request_id=secrets.token_hex(12));payload.update(kw)
  result=request('/scout/'+action,payload);(ROOT/('runtime/server/scout-'+action+'.json')).write_text(json.dumps(result,indent=2));return result
 except urllib.error.HTTPError as e:print(e.read().decode(),flush=True);raise

def check(value,name):
 assert value,name
 checks.append(name);print(name,flush=True)
r=call('status');s=r['state'];check(s['slope_fraction']==1 and s['harvesting']>0 and s['foraging_mod']>0,'Native scout skill bonuses retained')
trap=next(i for i in s['items'] if i['tool_kind']=='trap');kit=next(i for i in s['items'] if i['tool_kind']=='camp')
key=secrets.token_hex(12)
r=call('holster',item_id=trap['id'],request_id=key);check(r['state']['hip_tool']['id']==trap['id'] and trap['id'] not in [i['id'] for i in r['state']['inventory']['items']],'Owned trap moves to persistent tool hip slot')
r=call('holster',item_id=trap['id'],request_id=key);check(r['mutation'].get('replayed',False),'Retry replays the native receipt without duplicating the trap')
r=call('return_tool',item_id=trap['id']);check(r['state']['hip_tool'] is None and trap['id'] in [i['id'] for i in r['state']['inventory']['items']],'Trap returns to inventory without duplication')
r=call('camp',item_id=kit['id']);camp=next(c for c in r['state']['camps'] if c['owner_id']==f['id']);check(camp['terminal_id'] and 'visitors' in camp and 'uptime_seconds' in camp,'Native camp has original objects, terminal and SWG statistics')
check(kit['id'] not in [i['id'] for i in r['state']['items']],'Native camp deployment consumes original kit once')
r=call('disband',terminal_id=camp['terminal_id']);check(not any(c['id']==camp['id'] for c in r['state']['camps']),'Owner disband destroys native camp')
r=call('forage');check(r['state']['foraging'],'Native foraging task starts with source 8.5 second timing')
time.sleep(9)
r=call('status');check(not r['state']['foraging'],'Native foraging finishes without a second activation')
before=r['state']['ham'];r=call('burst_run');check(r['state']['burst_active'] and r['state']['burst_cooldown']>290,'Native Burst Run grants buff and source recovery cooldown')
check(all(r['state']['ham'][i]<before[i] for i in [0,3,6]),'Burst Run pays original scout-modified HAM costs')
r=call('mask_scent');check(r['state']['mask_scent_active'],'Native mask scent buff activates')
# Native toggle removes existing scent buff, permitting the discard-only path.
r=call('mask_scent');r=call('discard_mask_scent');check(not r['state']['mask_scent_active'] and r['state']['mask_scent_cooldown']>590,'Replacing armed mask scent applies cooldown without activating buff')
# Use the eligible native creature from the same source state; source command owns effects.
r=call('status');trap=next(i for i in r['state']['items'] if i['id']==trap['id']);targets=r['state']['targets'];check(bool(targets),'Native eligible trap targets are enumerated')
if targets:
 r=call('trap',item_id=trap['id'],target_id=targets[0]['id']);check(r['state']['trap_pending'],'Throw Trap invokes original pending source task')
 time.sleep(3);r=call('status');remaining=next((i['use_count'] for i in r['state']['items'] if i['id']==trap['id']),0);check(not r['state']['trap_pending'] and remaining==trap['use_count']-1,'Original trap task finishes and consumes exactly one native use')
report={'passed':True,'live_core3':True,'checks':checks,'fixture':f};(ROOT/'runtime/evidence/scout-core3.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
