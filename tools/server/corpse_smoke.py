#!/usr/bin/env python3
"""Actual dead Core3 animal: rights/proximity/capacity, native yield and atomic loot."""
import argparse,json,sys,uuid,time,urllib.error
from pathlib import Path
from inventory_smoke import request
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--corpse-id');a=p.parse_args();f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest')
 base={'account':f['account'],'character_id':f['id'],'position':[3600,5,-4780]};q='?account='+f['account']+'&character_id='+f['id'];report={'fixture':f,'fixture_kind':'controlled_native_dead_source_creature_not_combat_bridge','checks':{}}
 def call(action,**kw):return request('/gathering/corpse/'+action,dict(base,request_id=uuid.uuid4().hex,**kw))
 def reject(action,**kw):
  try:call(action,**kw)
  except urllib.error.HTTPError as e:assert e.code==400;return json.load(e)['error']
  raise AssertionError('Invalid corpse interaction accepted')
 if not a.corpse_id:
  request('/inventory'+q);console('reloadscreenplays');time.sleep(.3);console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':clear_organic');time.sleep(.2);console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':clear_filler');time.sleep(.2);console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':corpse');time.sleep(.3)
 nearby=request('/gathering/corpses'+q+'&position=3600,5,-4780');corpse=next(c for c in nearby['corpses'] if c['id']==a.corpse_id) if a.corpse_id else max(nearby['corpses'],key=lambda c:int(c['id']));cid=corpse['id'];assert corpse['dead'] and corpse['harvest_available'] and corpse['loot_available'];assert corpse['scale']==corpse['height'];report['initial_corpse']=corpse
 (ROOT/'runtime/evidence/corpse-native-list.json').write_text(json.dumps(nearby,indent=2)+'\n')
 report['checks']['synthetic_id']=reject('inspect',corpse_id='1')
 report['checks']['distance']=reject('harvest',corpse_id=cid,kind='meat',position=[3620,5,-4780])
 console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':fill');time.sleep(.2)
 report['checks']['full_harvest']=reject('harvest',corpse_id=cid,kind='meat');report['checks']['full_loot']=reject('loot',corpse_id=cid)
 c=call('inspect',corpse_id=cid)['corpse'];assert c['loot']==corpse['loot'];assert next(x for x in c['resources'] if x['kind']=='meat')['block_reason']=='insufficient_inventory_capacity'
 console('runLuaFunction Tests:swgxrGatheringFixture:'+f['id']+':clear_filler');time.sleep(.2)
 (ROOT/'runtime/evidence/corpse-test-progress.json').write_text(json.dumps(report,indent=2));body=dict(base,corpse_id=cid,kind='meat',request_id=uuid.uuid4().hex);harvest=request('/gathering/corpse/harvest',body);repeat=request('/gathering/corpse/harvest',body);assert repeat['mutation']['replayed'];assert harvest['mutation']['quantity']==next(v for v in corpse['resources'] if v['kind']=='meat')['quantity'];assert not harvest['corpse']['harvest_available'];report['harvest']=harvest['mutation'];(ROOT/'runtime/evidence/corpse-test-harvest.json').write_text(json.dumps(harvest,indent=2))
 report['checks']['second_harvest']=reject('harvest',corpse_id=cid,kind='hide')
 body=dict(base,corpse_id=cid,request_id=uuid.uuid4().hex);loot=request('/gathering/corpse/loot',body);repeat=request('/gathering/corpse/loot',body);assert repeat['mutation']['replayed'];assert loot['mutation']['credits']==123;assert len(loot['mutation']['item_ids'])==1;report['loot']=loot['mutation'];report['checks']['receipt_replay_no_duplicate']=True
 report['passed']=True;(ROOT/'runtime/evidence/corpse-core3-smoke.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':
 try:main()
 except urllib.error.HTTPError as e:print(e.code,e.read().decode());raise
