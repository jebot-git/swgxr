#!/usr/bin/env python3
"""Real Core3 logout, inventory and vehicle lifecycle, no VR or diagnostic grants."""
import json,time,secrets,math
from services_smoke import req,redact,ROOT
checks=[];records=[];sessions={}
def check(v,label):
 checks.append(dict(passed=bool(v),label=label));print(label,bool(v),flush=True)
 if not v:raise AssertionError(label)
def call(f,path,**kw):
 stamp=time.monotonic();out=req(path,dict(account=f['account'],character_id=f['id'],**kw));records.append(dict(path=path,seconds=time.monotonic()-stamp,response=redact(out)));return out
def key():return 'session_'+secrets.token_hex(8)
def main():
 f=json.loads((ROOT/'runtime/server/artisan-fixture.json').read_text());v=json.loads((ROOT/'runtime/server/vehicles-fixture.json').read_text())[1];assert f['account'].startswith('invtest')and v['account'].startswith('invtest')
 report=dict(passed=False,checks=checks,responses=records,native_execution=True)
 try:
  outside=dict(position=[3513.25,5,-4801.75],heading_radians=.75,building_id='0',cell_index=0)
  saved=call(f,'/session/logout',**outside);check(saved.get('saved') and saved.get('session_closed'),'Normal logout confirms native save before close')
  entry=call(f,'/enter');loc=entry.get('source_location',{});check(entry.get('position_space')=='swg_world' and math.dist(loc['position'],outside['position'])<.01 and abs(loc['heading_radians']-.75)<.001,'Independent full entry resumes saved outdoor source position and heading')
  interior=next(t for t in json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())['static_terminals']if t['building_id']!='0'and t['cell_index']>0)
  inside=dict(position=interior['position'],building_id=interior['building_id'],cell_index=interior['cell_index'],heading_radians=1.25)
  duplicate=call(f,'/session/logout',**outside);check(duplicate.get('saved')and duplicate.get('session_closed'),'Duplicate normal logout safely confirms saved position')
  started=call(f,'/combat/session/start',position=outside['position']);sessions[f['id']]=started['session_id']
  liveinv=call(f,'/inventory/status',live_session_id=sessions[f['id']]);check(liveinv.get('source_kind')=='core3_inventory'and liveinv.get('items'),'Inventory reads existing native live session without eviction')
  rejected=call(f,'/session/logout',**dict(inside,building_id='1'),live_session_id=sessions[f['id']]);check(rejected.get('http_error')==400,'Invalid native source cell rejects logout without closing session')
  old_session=sessions[f['id']]
  saved=call(f,'/session/logout',**inside,live_session_id=sessions[f['id']]);check(saved.get('saved')and saved.get('session_closed'),'Live logout saves source interior then closes account session');sessions.pop(f['id'])
  duplicate=call(f,'/session/logout',**inside,live_session_id=old_session);check(duplicate.get('saved')and duplicate.get('session_closed'),'Uncertain live logout retry with closed old session confirms source save')
  entry=call(f,'/enter');loc=entry.get('source_location',{});check(loc['building_id']==inside['building_id']and loc['cell_index']==inside['cell_index']and math.dist(loc['position'],inside['position'])<.02 and abs(loc['heading_radians']-inside['heading_radians'])<.001,'Independent full entry restores original building cell and world heading')
  call(f,'/session/logout',**outside)
  inv=call(f,'/inventory/status');tool=next(i for i in inv['items']if i['template'].endswith('/generic_tool.iff'));draft=key();base=dict(tool_id=tool['id'],**outside)
  opened=call(f,'/crafting/open',**base,request_id=draft);check(bool(opened.get('state',{}).get('schematics')),'Native recipe list opens')
  for path in ('/services/status','/inventory/status','/gathering/status','/crafting/status'):
   middle=call(f,path,**outside);check(not middle.get('http_error'),'Interleaved '+path+' succeeds without draft eviction')
  selected=call(f,'/crafting/select',**base,session_id=draft,request_id=key(),index=opened['state']['schematics'][0]['index']);check(selected.get('state',{}).get('stage')==2 and selected['state']['schematic'].get('slots'),'Recipe selection survives normal polling and inventory reconnects')
  call(f,'/crafting/cancel',session_id=draft,request_id=key())
  started=call(v,'/session/start',**outside);sessions[v['id']]=started['session_id'];check(started.get('source_kind')=='core3_gameplay_session','Normal gameplay session starts without combat projection')
  repeated=call(v,'/session/start',**outside);check(repeated.get('session_id')==sessions[v['id']],'Lost start acknowledgement reuses same native connection')
  state=call(v,'/vehicles/status',**outside);device=state['state']['datapad'][0];called=call(v,'/vehicles/call',device_id=device['id'],**outside);check(called.get('mutation',{}).get('success'),'Normal owned Call Vehicle invokes original control device')
  deadline=time.monotonic()+18
  while time.monotonic()<deadline:
   state=call(v,'/vehicles/status',**outside)
   if any(x['id']==device['vehicle_id']for x in state['state']['vehicles']):break
   time.sleep(1)
  check(any(x['id']==device['vehicle_id']for x in state['state']['vehicles']),'Original vehicle appears at normal player source position')
  state=call(v,'/vehicles/call',device_id=device['id'],live_session_id=sessions[v['id']],**outside);check(state.get('mutation',{}).get('success')and state.get('live_response',{}).get('session_live'),'Live owned Call Vehicle retains source session')
  update=call(v,'/session/update',**outside,session_id=sessions[v['id']],ready=True);check(update.get('session_live') and 'actors'not in update.get('snapshot',{}),'Gameplay heartbeat stays lightweight and authoritative')
  legacy=req('/datapad?account='+v['account']+'&character_id='+v['id']);check(legacy.get('source')=='core3_replication' and legacy.get('physical_entries'),'Legacy datapad decoder refreshes owned baselines through retained session')
  weapons=req('/weapons?account='+v['account']+'&character_id='+v['id']);check(weapons.get('backend')=='core3','Legacy weapons decoder reads retained session')
  current=call(v,'/inventory/status');candidate=next((i for i in current['items']if i.get('equip_available')),None)
  if candidate:
   arrangement=next(a['index']for a in candidate['equip_arrangements']if a['available']);equipped=call(v,'/inventory/equip',item_id=candidate['id'],arrangement=arrangement);check(equipped.get('mutation',{}).get('success')and any(i['id']==candidate['id']for i in equipped['inventory']['equipment']),'Original inventory equip mutation verifies through retained connection')
  else:check(any(i['equipped']for i in current['items']),'Fixture equipment remains authoritative')
  for endpoint in ('/services/status','/gathering/status','/crafting/status'):
   observed=call(v,endpoint,**outside);check(not observed.get('http_error'),'Persistent gameplay '+endpoint+' does not reconnect or evict vehicle')
  waypoint=call(v,'/waypoints',name='Session regression',planet='tatooine',position={'x':3511,'y':5,'z':-4800});check(waypoint.get('waypoint',{}).get('name')=='Session regression','Original waypoint command works on retained session')
  removed=call(v,'/datapad/delete',entry_id=waypoint['waypoint']['id']);check(removed.get('deleted_id')==waypoint['waypoint']['id'],'Owned waypoint deletion confirms refreshed native baselines')
  vehicle=state['state']['vehicles'][0];seat=next(x for x in vehicle['seats']if x['id']=='driver');p=vehicle['position'];a=vehicle['heading_radians'];q=seat['position'];hand=[p[0]+q[0]*math.cos(a)-q[2]*math.sin(a),p[1]+q[1],p[2]-q[0]*math.sin(a)-q[2]*math.cos(a)]
  boarded=call(v,'/vehicles/board',vehicle_id=vehicle['id'],seat='driver',hand=hand,live_session_id=sessions[v['id']],**outside);check(boarded.get('state',{}).get('seat',{}).get('id')=='driver','Actual owned source seat boards before logout test')
  logout=dict(outside,request_id=key(),live_session_id=sessions[v['id']]);saved=call(v,'/session/logout',**logout);check(saved.get('saved')and saved.get('session_closed'),'Seated logout performs native exit and persists actual exit pose');sessions.pop(v['id'])
  replay=call(v,'/session/logout',**logout);check(replay.get('replayed')and replay['location']==saved['location'],'Uncertain seated logout retry preserves original native exit pose')
  entered=call(v,'/enter');check(math.dist(entered['source_location']['position'],saved['location']['position'])<.02,'Fresh entry resumes grounded native vehicle exit pose')
  report['passed']=True
 finally:
  for owner in(f,v):
   if owner['id']in sessions:call(owner,'/combat/session/stop',session_id=sessions[owner['id']])
  (ROOT/'runtime/evidence/session-20261005/native-session.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
