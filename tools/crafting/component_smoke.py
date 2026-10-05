#!/usr/bin/env python3
"""Verify exact native component refund on the isolated artisan fixture."""
import json,secrets,sys,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
f=json.loads((ROOT/'runtime/server/artisan-fixture.json').read_text());assert f['account'].startswith('invtestcraft');q='?account='+f['account']+'&character_id='+f['id'];base={'account':f['account'],'character_id':f['id'],'position':[3600,5,-4780]}
def act(action,**kw):
 try:return request('/crafting/'+action,dict(base,request_id=secrets.token_hex(12),**kw))
 except urllib.error.HTTPError as e: print(e.read().decode());raise
before=request('/inventory'+q);tool=next(i for i in before['items'] if i['template'].endswith('weapon_tool.iff'));base['tool_id']=tool['id'];r=act('open');base['session_id']=r['state']['session_id'];choice=next(s for s in r['state']['schematics'] if s['template'].endswith('craftable_bug_habitat.iff'));r=act('select',index=choice['index']);s=r['state'];a=[[next(i['id'] for i in s['inventory'] if slot['index'] in i['slots'] and i['quantity']>=slot['quantity'])] for slot in s['schematic']['slots']]
r=act('assemble',allocations=a);assert r['state']['stage']==3
r=act('cancel');after=r['inventory'];byid=lambda x:{i['id']:(i['quantity'],i['customization'],i['container_id']) for i in x['items']};assert byid(before)==byid(after)
report={'passed':True,'component_id':a[-1][0],'refunded_exact_identity':True,'live_core3':True};(ROOT/'runtime/evidence/artisan-component-refund.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
