#!/usr/bin/env python3
"""Real two-account medical effects, mobile casts, cooldowns and drag cancellation."""
import json,sys,secrets,time,urllib.error,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
fixtures=json.loads((ROOT/'runtime/server/medic-fixture.json').read_text());assert all(f['account'].startswith('invtestmedic') for f in fixtures)
bases=[];checks=[];passed=False
def check(value,label):
 assert value,label
 checks.append(label);print(label,flush=True)
def call(index,action,**kw):
 body=dict(bases[index],request_id='medic-'+secrets.token_hex(10),**kw)
 try:return request('/medic/'+action,body)
 except urllib.error.HTTPError as e:print(e.read().decode(),flush=True);raise
def tracking(p,crossed=False,grips=True):return dict(tracked=True,crossed=crossed,grips=grips,left=[p[0]-.12,p[1]+.3,p[2]],right=[p[0]+.12,p[1]+.3,p[2]])
try:
 for i,f in enumerate(fixtures):
  native=request('/medic/status',{'account':f['account'],'character_id':f['id']})['state']['position']
  base={'account':f['account'],'character_id':f['id'],'position':[native[0]+i,native[1],native[2]]}
  start=request('/combat/session/start',base);base['session_id']=start['session_id'];bases.append(base)
  request('/combat/session/update',dict(base,ready=True,medic_pose=tracking(base['position'])))
 initial=call(0,'status');s=initial['state'];tool=s.get('hip_tool') or next(i for i in s['inventory']['items'] if i.get('tool_kind')=='medical')
 check(len(s['abilities'])==3 and not any(a['id']=='diagnose' for a in s['abilities']),'Native learned basic heals available; Diagnose excluded')
 check(any(p['id']==fixtures[1]['id'] for p in s['players']),'Two authenticated native players share medical targeting')
 r=call(0,'holster',item_id=tool['id']);check(r['state']['hip_tool']['id']==tool['id'],'Medical tool uses persistent hip escrow')
 call(0,'select',item_id=tool['id'],ability='tenddamage')
 before=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[1].items() if k!='position'}))['snapshot']['player']
 doc_before=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[0].items() if k!='position'}))['snapshot']['player']
 pack=next(i for i in s['inventory']['items'] if i.get('medical_command')=='healdamage');used=pack['use_count']
 healed=call(0,'medical_item',item_id=pack['id'],target_id=fixtures[1]['id'],pose=tracking(bases[0]['position']))
 after=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[1].items() if k!='position'}))['snapshot']['player']
 check(after['ham'][0]>before['ham'][0],'Native Heal Damage changes recipient HAM')
 check(after['vital_feedback']['heal']>before['vital_feedback']['heal'],'Only healed recipient receives native healing event')
 doc=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[0].items() if k!='position'}))['snapshot']['player']
 check(doc['vital_feedback']['damage']==doc_before['vital_feedback']['damage'],'Healing mind cost does not create damage flash')
 check(next(i['use_count'] for i in healed['state']['inventory']['items'] if i['id']==pack['id'])==used-1,'Heal consumes exactly one native stim charge')
 check(healed['state']['medical_item_cooldowns']['healdamage']>0,'Source injury recovery reaches independent medical wheel')
 moved=dict(bases[0],position=[5000.2,bases[0]['position'][1],-5400]);r=request('/combat/session/update',moved)
 check(r['mutation']['movement_accepted'] and abs(r['snapshot']['player']['position'][0]-5000.2)<.01,'Player can locomote immediately during healing recovery')
 try:call(0,'medical_item',item_id=pack['id'],target_id=fixtures[1]['id'],pose=tracking(bases[0]['position']))
 except urllib.error.HTTPError as e:check(e.code==400,'Native recovery rejects premature healing')
 else:raise AssertionError('Early heal accepted')
 r=call(0,'return_tool',item_id=tool['id']);check(r['state']['selected']=='tenddamage','Medical selection persists when returned to inventory')
 recovery=next(a['cooldown_seconds']for a in r['state']['abilities']if a['id']=='tenddamage')
 if recovery>0:time.sleep(recovery+.2)
 call(0,'select',item_id=tool['id'],ability='tenddamage');r=call(0,'heal',item_id=tool['id'],ability='tenddamage',target_id=fixtures[1]['id']);check(r['mutation']['success'],'Tend uses its own native command and supplies')
 console('runLuaFunction Tests:swgxrMedicDamage:'+fixtures[1]['id']);time.sleep(.2)
 damage=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[1].items() if k!='position'}))['snapshot']['player'];check(damage['vital_feedback']['damage']>after['vital_feedback']['damage'],'Actual native damage creates recipient screen event')
 console('runLuaFunction Tests:swgxrMedicIncap:'+fixtures[1]['id'])
 deadline=time.monotonic()+8
 while True:
  pstate=request('/combat/session?'+urllib.parse.urlencode({k:v for k,v in bases[1].items() if k!='position'}))['snapshot']['player']
  if pstate['posture']==13:break
  if time.monotonic()>deadline:raise AssertionError('Native fixture did not incapacitate')
  time.sleep(.15)
 call(1,'status',pose=tracking(bases[1]['position'],False))
 result=call(0,'drag',target_id=fixtures[1]['id'],release=False,pose=tracking(bases[1]['position']))
 check(result['mutation']['started'],'Two-hand native drag starts on incapacitated patient')
 p=bases[1]['position'];shifted=[p[0]+.15,p[1],p[2]]
 call(1,'status',pose=tracking(p,False))
 moved_patient=call(0,'drag',target_id=fixtures[1]['id'],release=False,pose=tracking(shifted))
 check(moved_patient['mutation'].get('position',[0])[0]>p[0]+.10,'Physical hand displacement moves native patient across supported ground')
 call(1,'status',pose=tracking(shifted,True))
 try:call(0,'drag',target_id=fixtures[1]['id'],release=False,pose=tracking(bases[1]['position']))
 except urllib.error.HTTPError as e:check(e.code==400,'Patient crossed arms immediately reject drag and re-grab')
 else:raise AssertionError('Crossed arms ignored')
 call(1,'status',pose=tracking(bases[1]['position'],False))
 check(call(0,'drag',target_id=fixtures[1]['id'],release=False,pose=tracking(bases[1]['position']))['mutation']['started'],'Uncrossed fresh tracking permits a new two-hand drag')
 call(0,'drag',target_id=fixtures[1]['id'],release=True)
 check(call(1,'status')['state']['drag']['owner']=='','Releasing grip clears drag owner')
 console('runLuaFunction Tests:swgxrMedicFixture:'+fixtures[1]['id'])
 console('runLuaFunction Tests:swgxrMedicArea:'+fixtures[0]['id']);time.sleep(.3)
 area=call(0,'status')['state'];pack=next(i for i in area['inventory']['items'] if i.get('medical_ranged') and i.get('medical_area_m',0)>0)
 deadline=time.monotonic()+8
 while pack['medical_area_m']!=15 and time.monotonic()<deadline:
  time.sleep(.25);area=call(0,'status')['state'];pack=next(i for i in area['inventory']['items'] if i.get('medical_ranged') and i.get('medical_area_m',0)>0)
 check(pack['medical_area_m']==15,'AoE ring radius is read from original native area stim template')
 remaining=area['medical_item_cooldowns']['healdamage']
 if remaining>0:time.sleep(min(25,remaining+.15))
 before_area=call(1,'status')['state']['vital_feedback']['heal']
 r=call(0,'medical_item',item_id=pack['id'],target_id=fixtures[1]['id'],pose=tracking(bases[0]['position']))
 check(r['state']['vital_feedback']['heal']>0,'Native area healing reaches caster as additional eligible recipient')
 check(call(1,'status')['state']['vital_feedback']['heal']>before_area,'Native area heal also notifies primary recipient')
 passed=True
finally:
 for base in bases:
  try:request('/combat/session/stop',base)
  except Exception:pass
 (ROOT/'runtime/evidence/medic-core3.json').write_text(json.dumps({'checks':checks,'native_core3':True,'passed':passed},indent=2))
