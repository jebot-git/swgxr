#!/usr/bin/env python3
"""Native deployed-tool recovery with concurrent nonblocking inventory refresh."""
import json,time,secrets,threading
from services_smoke import req,redact,ROOT
checks=[];records=[]
def check(ok,label):
 checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
 if not ok:raise AssertionError(label)
def main():
 f=json.loads((ROOT/'runtime/server/gathering-fixture.json').read_text());assert f['account'].startswith('invtest');base=dict(account=f['account'],character_id=f['id']);sid='';report=dict(passed=False,checks=checks,responses=records)
 def call(path,**kw):
  stamp=time.monotonic();r=req(path,dict(base,**kw));records.append(dict(path=path,seconds=time.monotonic()-stamp,response=redact(r)));return r
 def key():return 'recovery_'+secrets.token_hex(8)
 try:
  start=call('/session/start',position=[3600,5,-4780],building_id='0',cell_index=0);sid=start['session_id']
  inv=call('/inventory/status');tool=next(i for i in inv['items']if i['template'].endswith('survey_tool_mineral.iff'))
  state=call('/gathering/status',tool_id=tool['id']);best=None
  for resource in state['resources']:
   survey=call('/gathering/survey',tool_id=tool['id'],resource_id=resource['id'],position=[3600,5,-4780],request_id=key());point=survey['mutation']['survey']['highest']
   if point['density']>=.4:best=(resource,point);break
  check(best is not None,'Original productive resource location available')
  resource,point=best;pos=point['position'];pos[1]=5
  deployed=call('/gathering/deploy',tool_id=tool['id'],resource_id=resource['id'],position=pos,request_id=key());dep=deployed['state']['deployments'][0]
  time.sleep(3.2);state=call('/gathering/status');dep=next(d for d in state['deployments']if d['id']==dep['id']);check(dep['quantity']>0,'Actual persistent-session native samples accumulate')
  payload=dict(request_id=key(),deployment_id=dep['id'],position=pos);answer={}
  def pickup():answer.update(call('/gathering/collect',**payload))
  thread=threading.Thread(target=pickup);thread.start();time.sleep(.03)
  stamp=time.monotonic();during=call('/inventory/status');elapsed=time.monotonic()-stamp;thread.join(20)
  check(not thread.is_alive()and answer.get('mutation',{}).get('success'),'Recovery completes with authoritative mutation acknowledgement')
  check(elapsed<.5 and (during.get('source_kind')=='core3_inventory'or during.get('error_code')=='backend_busy'),'Inventory readout refresh never blocks on ongoing recovery')
  check(tool['id']in {i['id']for i in answer['inventory']['items']},'Committed pickup response restores tool in original inventory')
  replay=call('/gathering/collect',**payload);check(replay.get('mutation',{}).get('replayed'),'Ambiguous pickup retry remains idempotent on retained connection')
  fresh=call('/inventory/status');check(tool['id']in {i['id']for i in fresh['items']},'Next independent read observes committed recovered tool')
  report['passed']=True
 finally:
  if sid:call('/session/logout',position=[3600,5,-4780],building_id='0',cell_index=0,heading_radians=0,live_session_id=sid,request_id=key())
  (ROOT/'runtime/evidence/session-20261005/native-recovery.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
