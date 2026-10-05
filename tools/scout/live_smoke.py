#!/usr/bin/env python3
"""Scout operations over the existing authenticated Core3 combat connection."""
import json,secrets,sys,time,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
f=json.loads((ROOT/'runtime/server/scout-fixture.json').read_text());assert f['account'].startswith('invtestscout')
base={'account':f['account'],'character_id':f['id'],'position':[5000,180,-5400],'posture':'standing'};checks=[]
def check(value,text):
 assert value,text
 checks.append(text);print(text,flush=True)
def scout(action,**detail):
 try:return request('/scout/'+action,dict(base,request_id=secrets.token_hex(12),**detail))
 except urllib.error.HTTPError as e:
  print(action,e.read().decode(),flush=True);raise
started=request('/combat/session/start',base);base['session_id']=started['session_id']
request('/combat/session/update',dict(base,ready=True))
try:
 r=scout('status');check(r['state']['character_id']==f['id'],'Scout snapshot uses the owned live combat session')
 trap=next(i for i in r['state']['items'] if i['tool_kind']=='trap' and i['use_count']>1)
 r=scout('holster',item_id=trap['id']);check(r['state']['hip_tool']['id']==trap['id'],'Trap holstering works without a second login')
 targets=sorted(r['state']['targets'],key=lambda t:sum((a-b)**2 for a,b in zip(t['position'],base['position'])));check(bool(targets),'Live scout snapshot exposes native eligible creatures')
 if targets:
  r=scout('trap',item_id=trap['id'],target_id=targets[0]['id']);check(r['state']['trap_pending'],'Hip trap starts native throw task in the live session')
  try:scout('trap',item_id=trap['id'],target_id=targets[0]['id'])
  except urllib.error.HTTPError as e:check(e.code in (400,503),'Pending trap rejects a duplicate throw')
  else:raise AssertionError('Duplicate throw unexpectedly accepted')
  time.sleep(2.2);r=scout('status');check(r['state']['hip_tool']['use_count']==trap['use_count']-1,'Hip trap consumes one use and remains in its persistent slot')
 r=scout('return_tool',item_id=trap['id']);check(r['state']['hip_tool'] is None,'Live trap returns from belt to owned inventory')
 try:request('/scout/status',dict(base,session_id='wrong-session'))
 except urllib.error.HTTPError as e:check(e.code==409,'Wrong live session identity rejected')
 else:raise AssertionError('Wrong session accepted')
finally:request('/combat/session/stop',base)
report={'passed':True,'live_core3':True,'checks':checks};(ROOT/'runtime/evidence/scout-live-session.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
