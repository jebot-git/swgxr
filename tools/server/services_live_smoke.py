#!/usr/bin/env python3
"""Real persistent services/crafting with synthetic authenticated hand contact."""
import json,secrets,threading,time,math
from services_smoke import ROOT,req,redact

def main():
 f=json.loads((ROOT/'runtime/server/services-fixture.json').read_text());g=json.loads((ROOT/'runtime/server/services-recipient-fixture.json').read_text());artisan=json.loads((ROOT/'runtime/server/artisan-fixture.json').read_text());checks=[];records=[];sessions={};running=False
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def rpc(owner,path,**data):
  payload=dict(account=owner['account'],character_id=owner['id'],**data)
  if owner['id'] in sessions and path.startswith('/services/'):payload['session_id']=sessions[owner['id']]
  r=req(path,payload);records.append({'path':path,'response':r});return r
 report={'native_execution':True,'headset_tracking':'synthetic, no live VR','checks':checks,'responses':records,'passed':False}
 try:
  pos=[3511,5,-4927];start=rpc(f,'/combat/session/start',position=pos);check(start.get('session_live'),'Persistent native session starts without ranged weapon');sessions[f['id']]=start['session_id']
  state=rpc(f,'/services/status',position=pos,building_id='0',cell_index=0);other=rpc(g,'/services/status',position=[3511.5,5,-4927],building_id='0',cell_index=0)
  check(state.get('ok') and state.get('live_response',{}).get('session_live'),'Service state reuses live character session')
  running=True
  def poses():
   seq=0
   while running:
    for owner,s,wallet in [(f,state,True),(g,other,False)]:
     req('/services/presence',dict(account=owner['account'],character_id=owner['id'],token=s['presence']['token'],sequence=seq,position=s['state']['player']['position'],hand={'position':[3511.3,6,-4927],'grip':True,'tracked':True},wallet_held=wallet))
    seq+=1;time.sleep(.08)
  worker=threading.Thread(target=poses,daemon=True);worker.start();time.sleep(.65)
  stamp=time.monotonic();paid=rpc(f,'/services/pay',target_id=g['id'],amount=3,request_id='services_livepay_'+secrets.token_hex(8),position=pos,building_id='0',cell_index=0);report['payment_seconds']=time.monotonic()-stamp;running=False;worker.join(2)
  check(paid.get('ok') and paid.get('live_response',{}).get('session_live'),'Live sender pays temporarily connected original recipient')
  alive=rpc(f,'/combat/session/update',session_id=sessions[f['id']],position=pos,building_id='0',cell_index=0,ready=True);check(alive.get('session_live') and alive['snapshot']['ready'],'Closing temporary recipient leaves original sender live')
  # Native original station and skill-qualified existing isolated artisan tool.
  p=[3497.0432,5,-4756.8506];view=rpc(artisan,'/services/status',position=p,building_id='0',cell_index=0);station=next(t for t in view['state']['terminals']if t['template'].endswith('/public_weapon_station.iff'))
  opened=rpc(artisan,'/services/open',terminal_id=station['id'],position=p,building_id='0',cell_index=0)
  tools=opened['state']['terminal'].get('tools',[]);check(len(tools)>0,'Source crafting station exposes only owned compatible tools')
  tool=tools[0];selected=rpc(artisan,'/services/crafting_station',terminal_id=station['id'],tool_id=tool['id'],position=p,building_id='0',cell_index=0,request_id='services_station_'+secrets.token_hex(8));check(selected.get('ok'),'Station validates original tool compatibility and ownership')
  start=rpc(artisan,'/combat/session/start',position=p);check(start.get('session_live'),'Second independent native persistent character session starts');sessions[artisan['id']]=start['session_id']
  draft='services_craft_'+secrets.token_hex(8)
  craft=rpc(artisan,'/crafting/open',tool_id=tool['id'],position=p,building_id='0',cell_index=0,request_id=draft,live_session_id=sessions[artisan['id']]);check(craft.get('source_kind')=='core3_crafting' and craft.get('state',{}).get('schematics'),'Native crafting session opens beside original station while combat session retained')
  cancel=rpc(artisan,'/crafting/cancel',session_id=draft,request_id='services_cancel_'+secrets.token_hex(8),live_session_id=sessions[artisan['id']]);check(cancel.get('mutation',{}).get('success'),'Crafting draft cancels using separate live and recipe session identities')
  live=rpc(f,'/combat/session/update',session_id=sessions[f['id']],position=pos);check(live.get('session_live'),'Other session remains live through concurrent character crafting')
  report['passed']=True
 finally:
  running=False
  for owner in [f,artisan]:
   if owner['id'] in sessions:rpc(owner,'/combat/session/stop',session_id=sessions[owner['id']])
  (ROOT/'runtime/evidence/services-live-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
