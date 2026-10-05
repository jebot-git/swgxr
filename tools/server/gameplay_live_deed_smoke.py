from pathlib import Path
import json,sys,secrets
sys.path.insert(0,'tools/server');from services_smoke import req,redact
f=json.loads(Path('runtime/server/vehicles-fixture.json').read_text())[1];base=dict(account=f['account'],character_id=f['id']);checks=[];records=[]
def call(path,**kw):
 r=req(path,dict(base,**kw));records.append({'path':path,'response':redact(r)});return r
report={'passed':False,'checks':checks,'responses':records}
def check(test,label):
 checks.append({'label':label,'passed':bool(test)});assert test,records[-1]
try:
 r=call('/vehicles/activate',item_id='1',request_id='preflight_'+secrets.token_hex(8),position=[3600,5,-4780],building_id='0',cell_index=0);check(r.get('confirmed_rejection') is True and r.get('mutation_started') is False,'Proven preflight rejection resolves uncertainty')
 inv=req('/inventory?account='+f['account']+'&character_id='+f['id']);deed=next(i for i in inv['items']if'/vehicle_deed/'in i['template'])
 start=call('/combat/session/start',position=[3600,5,-4780]);sid=start['session_id']
 try:
  payload=dict(item_id=deed['id'],request_id='live_deed_'+secrets.token_hex(8),live_session_id=sid,position=[3600,5,-4780],building_id='0',cell_index=0)
  r=call('/vehicles/activate',**payload);check(r.get('mutation',{}).get('success') is True and r.get('live_response',{}).get('session_live') is True,'Actual vehicle deed activation inside retained native session')
  replay=call('/vehicles/activate',**payload);check(replay.get('mutation',{}).get('replayed') is True and replay['mutation']['device_id']==r['mutation']['device_id'],'Live activation durable replay preserves control device')
 finally:call('/combat/session/stop',session_id=sid)
 report['passed']=True
finally:
 Path('runtime/evidence/gameplay-20261005/native-final.json').write_text(json.dumps(report,indent=2));print(json.dumps(checks))
