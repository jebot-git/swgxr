#!/usr/bin/env python3
"""Actual disposable Core3 gathering persistence, reservation and atomic pickup."""
import argparse,json,sys,uuid,urllib.error,time
from pathlib import Path
from inventory_smoke import request
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);a=p.parse_args();f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest')
 base={'account':f['account'],'character_id':f['id']};query='?account='+f['account']+'&character_id='+f['id'];report={'fixture':f,'checks':{}}
 def call(action,**kw):return request('/gathering/'+action,dict(base,request_id=uuid.uuid4().hex,**kw))
 def reject(action,**kw):
  try:call(action,**kw)
  except urllib.error.HTTPError as e:assert e.code==400;return json.load(e)['error']
  raise AssertionError('Invalid request accepted')
 state=request('/gathering'+query);assert len(state['deployments'])==1;dep=state['deployments'][0];pos=dep['position'];key=dep['tool_id'];report['restart_persisted_deployment']=dep
 assert dep['cycles']>=1 and dep['quantity']>=13
 report['checks']['distant_pickup']=reject('collect',deployment_id=dep['id'],position=[pos[0]+10,pos[1],pos[2]])
 console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':fill');time.sleep(.5)
 full=request('/inventory'+query);assert full['inventory']['occupied']==80
 report['checks']['full_pickup']=reject('collect',deployment_id=dep['id'],position=pos)
 still=request('/gathering'+query);assert still['deployments'][0]['quantity']>=dep['quantity']
 console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':clear_filler');time.sleep(.5)
 body=dict(base,request_id=uuid.uuid4().hex,deployment_id=dep['id'],position=pos)
 collected=request('/gathering/collect',body);replay=request('/gathering/collect',body)
 assert replay['mutation']['replayed'] and replay['mutation']['quantity']==collected['mutation']['quantity']
 assert not replay['state']['deployments'];assert key in {i['id'] for i in replay['inventory']['items']}
 report['collection']=collected['mutation'];report['checks']['idempotent_collect']=True
 report['checks']['stale_deployment']=reject('collect',deployment_id=dep['id'],position=pos)
 h=call('holster',tool_id=key);assert h['state']['hip_tool_id']==key;assert key not in {i['id'] for i in h['inventory']['items']}
 crafting=next(i for i in h['inventory']['items'] if i['tool_kind']=='crafting');h=call('holster',tool_id=crafting['id']);assert h['state']['hip_tool_id']==crafting['id'];assert key in {i['id'] for i in h['inventory']['items']}
 h=call('return_tool',tool_id=crafting['id']);assert not h['state']['hip_tool_id'];report['checks']['any_tool_hip_swap']=True
 report['passed']=True;(ROOT/'runtime/evidence/gathering-core3-smoke.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
