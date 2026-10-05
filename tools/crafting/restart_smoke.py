#!/usr/bin/env python3
"""Prepare/verify native escrow and output persistence across graceful Core3 restart."""
import json,secrets,sys,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
f=json.loads((ROOT/'runtime/server/artisan-fixture.json').read_text());assert f['account'].startswith('invtestcraft')
base={'account':f['account'],'character_id':f['id'],'position':[3600,5,-4780]};q='?account='+f['account']+'&character_id='+f['id'];saved=ROOT/'runtime/server/artisan-restart.json'
def act(verb,**kw):
 try:return request('/crafting/'+verb,dict(base,request_id=secrets.token_hex(12),**kw))
 except urllib.error.HTTPError as e:print(e.read().decode(),flush=True);raise

def assemble(tool):
 r=act('open',tool_id=tool['id']);sid=r['state']['session_id'];d=next(x for x in r['state']['schematics'] if x['template'].endswith('pistol_cdef.iff'))
 s=act('select',tool_id=tool['id'],session_id=sid,index=d['index'])['state'];allocations=[[next(i['id'] for i in s['inventory'] if slot['index'] in i['slots'] and i['quantity']>=slot['quantity'])] for slot in s['schematic']['slots']]
 r=act('assemble',tool_id=tool['id'],session_id=sid,allocations=allocations);assert r['state']['stage']==3;return sid

def identities(s):return {i['id']:[i['quantity'],i['customization'],i['container_id']] for i in s['items']}
if sys.argv[1]=='prepare':
 inv=request('/inventory'+q);tools=[i for i in inv['items'] if i['template'].endswith('weapon_tool.iff')]
 sid=assemble(tools[0]);r=act('finish',tool_id=tools[0]['id'],session_id=sid,points=[],colors=[]);job=r['state']['jobs'][0]
 before=identities(r['inventory']);sid=assemble(tools[1]);saved.write_text(json.dumps({'before':before,'job':job,'draft':sid},indent=2));print('Native job running and refundable draft escrow prepared',flush=True)
else:
 state=request('/crafting'+q)['state'];assert not state['session_id'],'Lost native draft was not cancelled'
 inv=request('/inventory'+q);s=json.loads(saved.read_text());after=identities(inv);assert all(after.get(i)==v for i,v in s['before'].items()),'Original draft ingredient conservation failed after restart'
 assert s['job']['prototype_id'] in after,'Persistent reserved output was not delivered'
 report={'passed':True,'live_core3':True,'draft_refunded_after_restart':True,'crafted_output_persisted':True,'output_id':s['job']['prototype_id']};(ROOT/'runtime/evidence/artisan-restart-core3.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
