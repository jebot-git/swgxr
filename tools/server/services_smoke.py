#!/usr/bin/env python3
"""Real native terminal service checks against isolated persistent characters."""
import json,sys,secrets,time,urllib.request,urllib.error,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE='http://127.0.0.1:18080'
def redact(value):
 if isinstance(value,dict):return {k:('[redacted]' if k in ('token','password','presence_token') else redact(v)) for k,v in value.items()}
 if isinstance(value,list):return [redact(v) for v in value]
 return value
def req(path,data=None):
 request=urllib.request.Request(BASE+path,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=70) as r:return json.load(r)
 except urllib.error.HTTPError as e:return {'http_error':e.code,**json.load(e)}
def main():
 path=ROOT/'runtime/server/services-fixture.json'
 if path.exists():f=json.loads(path.read_text())
 else:
  f={'account':'invtestservices'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))}
  r=req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character' in r,r;f['id']=r['character']['id'];path.write_text(json.dumps(f))
 assert f['account'].startswith('invtestservices')
 base={'account':f['account'],'character_id':f['id']};checks=[];responses=[]
 def service(action,**kw):
  data=dict(base,**kw)
  if action not in ('status','open'):data.setdefault('request_id','services_'+secrets.token_hex(10))
  r=req('/services/'+action,data);responses.append({'action':action,'response':r});return r
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label, bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 report={'native_execution':True,'mocked':False,'fixture':f,'checks':checks,'responses':responses,'passed':False}
 try:
  state=service('status',position=[3527,5,-4810],building_id='0',cell_index=0)
  check(state.get('source_kind')=='core3_services','Owned native services state available')
  (ROOT/'runtime/evidence/services-native-initial.json').write_text(json.dumps(redact(state),indent=2))
  print(json.dumps({'wallet':state['state']['wallet'],'terminals':state['state']['terminals']}),flush=True)
  data=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())
  bank=min([t for t in data['static_terminals'] if t['kind']=='bank' and int(t['id'])>0],key=lambda t:math.dist(t['position'],[3527,5,-4810]))
  def at(t):return {'terminal_id':t['id'],'position':t['position'],'building_id':t['building_id'],'cell_index':t['cell_index']}
  opened=service('open',**at(bank));check(opened.get('ok') and opened['state']['terminal']['kind']=='bank','Native bank terminal opens within source range')
  before=opened['state']['wallet'];key='services_bank_'+secrets.token_hex(8)
  deposited=service('bank_transfer',**at(bank),amount=10,direction='deposit',request_id=key)
  check(deposited.get('ok') and deposited['state']['wallet']=={'cash':before['cash']-10,'bank':before['bank']+10},'Native bank transfer conserves total credits')
  replay=service('bank_transfer',**at(bank),amount=10,direction='deposit',request_id=key)
  check(replay.get('ok') and replay['state']['wallet']==deposited['state']['wallet'] and replay['mutation'].get('replayed'),'Native durable receipt prevents duplicate transfer')
  withdrawn=service('bank_transfer',**at(bank),amount=10,direction='withdraw');check(withdrawn.get('ok') and withdrawn['state']['wallet']==before,'Native withdrawal restores exact balances')
  bad=at(bank);bad['position']=[3527,5,-4810]
  check(service('bank_transfer',**bad,amount=10,direction='deposit').get('http_error')==400,'Remote bank mutation rejected')
  check(service('bank_transfer',**at(bank),amount=2000000000,direction='withdraw').get('http_error')==400,'Overspend rejected')
  mission=min([t for t in data['static_terminals'] if t['kind']=='mission' and t['template'].endswith('/terminal_mission.iff') and int(t['id'])>0],key=lambda t:math.dist(t['position'],[3527,5,-4810]))
  opened=service('open',**at(mission));check(opened.get('ok') and len(opened['state']['terminal']['missions'])>0,'Original mission manager generates offers')
  offer=opened['state']['terminal']['missions'][0]
  accepted=service('mission_accept',**at(mission),mission_id=offer['id']);check(accepted.get('ok') and any(m['id']==offer['id'] for m in accepted['state']['missions']),'Original objective accepted into persistent datapad')
  persisted=service('status');check(any(m['id']==offer['id'] for m in persisted['state']['missions']),'Mission survives independent authenticated login')
  aborted=service('mission_abort',mission_id=offer['id']);check(aborted.get('ok') and not any(m['id']==offer['id'] for m in aborted['state']['missions']),'Native mission abort removes active objective')
  bazaar=min([t for t in data['static_terminals'] if t['kind']=='bazaar' and int(t['id'])>0],key=lambda t:math.dist(t['position'],[3527,5,-4810]))
  opened=service('open',**at(bazaar));check(opened.get('ok') and isinstance(opened['state']['terminal']['listings'],list),'Original galactic auction map loads')
  report['passed']=True
 finally:
  (ROOT/'runtime/evidence/services-native-smoke.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
