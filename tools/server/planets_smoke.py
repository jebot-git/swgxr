#!/usr/bin/env python3
"""Real Core3 roundtrip tickets and non-Tatooine persistence. No diagnostic grants."""
import argparse, json, secrets, time
from services_smoke import ROOT, req, redact

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--fixture',default='planets-fixture.json');args=parser.parse_args()
 if '/'in args.fixture or not args.fixture.endswith('.json'):raise ValueError('Fixture basename required')
 checks=[];records=[];live='';fixture=ROOT/'runtime/server'/args.fixture
 def check(ok,label):
  checks.append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 if fixture.exists():f=json.loads(fixture.read_text())
 else:
  f={'account':'invtestplanets'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8))}
  out=req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character'in out,out;f['id']=out['character']['id'];fixture.write_text(json.dumps(f))
 assert f['account'].startswith('invtestplanets')
 def call(path,**kw):
  stamp=time.monotonic();out=req(path,dict(account=f['account'],character_id=f['id'],**kw));records.append(dict(path=path,seconds=time.monotonic()-stamp,response=redact(out)));return out
 def service(action,**kw):
  if action not in ('status','open'):kw.setdefault('request_id','planets_'+secrets.token_hex(8))
  if live:kw['live_session_id']=live
  return call('/services/'+action,**kw)
 def update(loc,**kw):return call('/session/update',session_id=live,zone=loc['zone'],position=loc['position'],building_id=loc.get('building_id','0'),cell_index=loc.get('cell_index',0),**kw)
 report=dict(passed=False,native_execution=True,mocked=False,checks=checks,responses=records,fixture=f)
 try:
  entry=call('/enter');location=entry['source_location'];check(location['zone']=='tatooine','Dedicated fixture begins on Tatooine')
  started=call('/combat/session/start',**{k:location[k]for k in ('zone','position','building_id','cell_index')});live=started['session_id'];update(location,ready=True)
  state=service('status',zone='tatooine',position=[3599,5,-4780],building_id='0',cell_index=0)
  terminal=next(t for t in state['state']['terminals']if t['kind']=='travel');at={k:terminal[k]for k in ('position','building_id','cell_index')};at['terminal_id']=terminal['id'];at['zone']='tatooine'
  opened=service('open',**at);destinations=opened['state']['terminal']['destinations'];zones={d['destination_planet']for d in destinations}
  check(set(('naboo','corellia','tatooine')).issubset(zones),'Original permitted routes enumerate loaded other planets')
  destination=next(d for d in destinations if d['destination_planet']=='naboo'and d['available'])
  before=opened['state']['wallet'];key='planets_ticket_'+secrets.token_hex(8)
  bought=service('travel_purchase',**at,destination_id=destination['id'],destination_planet='naboo',round_trip=True,request_id=key)
  check(bought.get('ok'),'Original command purchases interplanetary roundtrip')
  tickets=bought['state']['tickets'];outbound=next(t for t in tickets if t['destination_planet']=='naboo');back=next(t for t in tickets if t['destination_planet']=='tatooine'and t['departure_planet']=='naboo')
  check(bought['state']['wallet']['bank']<before['bank'],'Original fare debited')
  replay=service('travel_purchase',**at,destination_id=destination['id'],destination_planet='naboo',round_trip=True,request_id=key)
  check(replay.get('mutation',{}).get('replayed')and replay['state']['wallet']==bought['state']['wallet'],'Duplicate ticket purchase preserves money and tickets')
  def board(ticket,zone,near):
   deadline=time.monotonic()+260
   while time.monotonic()<deadline:
    state=service('status',zone=zone,position=near,building_id='0',cell_index=0)
    shuttles=state.get('state',{}).get('shuttles',[])
    if shuttles:
     shuttle=shuttles[0];near=shuttle.get('collector_position',shuttle['position'])
     if shuttle.get('doors_open'):break
    time.sleep(3)
   check(bool(shuttles)and shuttle.get('doors_open'),'Original '+zone+' shuttle schedule permits boarding')
   out=service('travel_board',zone=zone,position=near,building_id='0',cell_index=0,ticket_id=ticket['id'])
   check(out.get('ok'),'Original '+zone+' boarding accepts owned ticket')
   transport=out.get('transport')or out.get('live_response',{}).get('snapshot',{}).get('transport',{})
   loc=transport['destination'];check(loc['zone']==ticket['destination_planet'],'Boarding reports authoritative target planet')
   check(not any(t['id']==ticket['id']for t in out['state']['tickets']),'Boarding consumes exact outbound ticket')
   ack=update(loc,transport_ack=transport['id'],ready=True)
   check(ack.get('mutation',{}).get('transport_acknowledged'),'Destination ready ACK retains native session')
   check(ack.get('session_id')==live,'Interplanetary transfer preserves native session identity')
   return loc
  location=board(outbound,'tatooine',bought['state']['shuttles'][0]['position'])
  bad=call('/session/update',session_id=live,zone='tatooine',position=location['position'],building_id='0',cell_index=0)
  check(bad.get('http_error')==400 or bad.get('error_code')=='native_source_zone_mismatch','Stale old-planet movement rejected')
  for path in ('/services/status','/gathering/status','/crafting/status'):
   out=call(path,zone='naboo',live_session_id=live);check(not out.get('http_error'),path+' works in original destination zone')
  inventory=call('/inventory/status',live_session_id=live)
  tool=next(i for i in inventory['items']if i['template'].endswith('/survey_tool_mineral.iff'))
  gathering=call('/gathering/status',zone='naboo',live_session_id=live,tool_id=tool['id'])
  check(gathering.get('planet')=='naboo'and bool(gathering.get('resources')),'Original Naboo resource list resolves owned mineral tool')
  resource=gathering['resources'][0]
  survey=call('/gathering/survey',zone='naboo',live_session_id=live,tool_id=tool['id'],resource_id=resource['id'],position=location['position'],request_id='planets_survey_'+secrets.token_hex(8))
  native_survey=survey.get('survey',survey.get('mutation',{}).get('survey',{}))
  check(survey.get('mutation',{}).get('success')and native_survey.get('planet')=='naboo','Native survey samples destination density and planet')
  check(bool(native_survey.get('spots')),'Original destination survey produces source density spots')
  waypoint=call('/waypoints',name='Planet roundtrip proof',planet='naboo',position=dict(zip(('x','y','z'),location['position'])))
  check(waypoint.get('waypoint',{}).get('planet')=='naboo','Native waypoint belongs to destination planet')
  call('/datapad/delete',entry_id=waypoint['waypoint']['id'])
  saved=call('/session/logout',live_session_id=live,zone='naboo',position=location['position'],building_id=location['building_id'],cell_index=location['cell_index'],heading_radians=location.get('heading_radians',0));live=''
  check(saved.get('saved')and saved['location']['zone']=='naboo','Native logout saves non-Tatooine zone')
  entry=call('/enter');check(entry.get('scene')=='naboo'and entry['source_location']['zone']=='naboo','Fresh authenticated entry restores saved non-Tatooine zone')
  started=call('/combat/session/start',**{k:entry['source_location'][k]for k in ('zone','position','building_id','cell_index')});live=started['session_id'];update(entry['source_location'],ready=True)
  state=service('status',zone='naboo');check(any(t['id']==back['id']for t in state['state']['tickets']),'Return ticket survives logout and new native session')
  location=board(back,'naboo',entry['source_location']['position'])
  check(location['zone']=='tatooine','Original return ticket completes interplanetary roundtrip')
  saved=call('/session/logout',live_session_id=live,**{k:location[k]for k in ('zone','position','building_id','cell_index','heading_radians')});live='';check(saved.get('saved'),'Returned fixture saved through normal logout')
  report['passed']=True
 finally:
  if live:call('/combat/session/stop',session_id=live)
  (ROOT/'runtime/evidence/planets-native-roundtrip.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(checks))),flush=True)
if __name__=='__main__':main()
