#!/usr/bin/env python3
"""Validate yacht flight, fixed components and original station landing on an isolated invtest owner."""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 os.umask(0o077);f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and str(f['id']).isdigit()
 checks=[];samples=[];latencies=[];sid='';player={};original=None
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True);assert ok,label
 def call(path,data=None,required=True):
  nonlocal player
  body=None if data is None else {'account':f['account'],'character_id':f['id'],'session_id':sid,**data}
  req=urllib.request.Request('http://127.0.0.1:18080'+path,None if body is None else json.dumps(body).encode(),{'Content-Type':'application/json'})
  started=time.monotonic()
  try:
   with urllib.request.urlopen(req,timeout=90) as r:value=json.load(r)
   latencies.append({'path':path.split('?')[0],'seconds':time.monotonic()-started})
  except urllib.error.HTTPError as e:value={'http_error':e.code,**json.load(e)}
  player=value.get('live_response',value).get('snapshot',{}).get('player',player)
  if required and (value.get('http_error') or value.get('ok') is False):raise AssertionError((path,value.get('error'),value.get('error_code')))
  return value
 def console(cmd):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size
  subprocess.run(['podman','exec','swgxr-core3-build','bash','-lc','printf "%s\\n" "$1" > /workspace/runtime/server/core3-console','probe',cmd],check=True)
  if not cmd.startswith('runLuaFunction'):time.sleep(.5);return ''
  marker=':'.join(cmd.split(':')[:2])+': result='
  for _ in range(300):
   with log.open() as stream:stream.seek(offset);lines=stream.read().splitlines()
   row=next((v for v in lines if marker in v),None)
   if row:return row.split(marker,1)[1].strip().removeprefix('[').removesuffix(']')
   time.sleep(.1)
  raise AssertionError('Native fixture console timed out')
 def act(action,required=True,**extra):return call('/jtl/'+action,{'request_id':uuid.uuid4().hex,**extra},required)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'checks':checks,'samples':samples};launched=False
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  state=act('status')['state'];yacht=next(x for x in state['ships'] if 'sorosuub_space_yacht' in x['template']);ship_id=yacht['id']
  lua="""
function Tests:swgxrNavigationFixture(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" or ShipObject(s):getOwnerID()~=__ID__ then return "guard_failed" end
 if mode=="naboo_station" then
  if SceneObject(s):getZoneName()~="space_naboo" then return "wrong_zone" end
  SceneObject(s):teleport(-2291.26,905.49,-6460.67,0)
  return "ready"
 end
 if mode=="terminal" then
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y+1,cell)
  return "ready:"..SceneObject(p):getParentID()

 end
 local t=getSceneObject(1279066)
 return table.concat({SceneObject(p):getParentID(),SceneObject(t):getParentID(),SceneObject(p):getPositionX(),SceneObject(p):getPositionZ(),SceneObject(p):getPositionY()},",")
end
""".replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');relocated=console('runLuaFunction Tests:swgxrNavigationFixture:terminal');print(relocated,flush=True);check(relocated.startswith('ready:'),'Isolated owner at original starship terminal')
  print('Before status',console('runLuaFunction Tests:swgxrNavigationFixture:probe'),flush=True)
  act('status')
  def service(action,required=True,**extra):return call('/services/'+action,{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'request_id':uuid.uuid4().hex,'terminal_id':'1279066','ship_id':ship_id,**extra},required)
  print('Fixture location',json.dumps({k:player.get(k) for k in ['zone','position','building_id','cell_index']}),console('runLuaFunction Tests:swgxrNavigationFixture:probe'),flush=True)
  managed=service('ship_manage');samples.append({'managed':managed})
  blocked=service('ship_component_remove',False,slot=1,component_id='1')
  samples.append({'blocked':{k:blocked.get(k) for k in ['error','error_code','http_error']}})
  check(blocked.get('error_code',blocked.get('error'))=='luxury_yacht_components_fixed','Native yacht component removal rejected before component lookup')
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  sequence=state['ship']['control_sequence'];before=state['ship']['position'];started=time.monotonic()
  for _ in range(24):
   sequence+=1;state=act('control',sequence=sequence,throttle=1,pitch=0,yaw=0,roll=0)['state'];samples.append({'flight':state['ship'],'elapsed':time.monotonic()-started});time.sleep(.15)
  import math
  distance=math.dist(before,state['ship']['position']);report['distance']=distance;report['elapsed']=time.monotonic()-started
  check(state['ship']['max_speed_mps']>20 and state['ship']['speed_mps']>20 and distance>100,'Original yacht accelerates and travels over 100 metres on native tick')
  time.sleep(1.7);state=act('status')['state'];check(state['ship']['speed_mps']==0,'Lost input stops yacht after native lease')
  # Return and relaunch near the original station before communications.
  act('land');launched=False
  check(console('runLuaFunction Tests:swgxrNavigationFixture:terminal').startswith('ready:'),'Return fixture to terminal for station test')
  act('status')
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  stations=[x for x in state['nearby_ships'] if x.get('station_comms') and x.get('comm_in_range')]
  check(bool(stations),'Native original station is reachable from launch point')
  station=stations[0]['id'];state=act('comm_begin',station_id=station)['state'];conversation=state['station_conversation'];samples.append({'conversation':conversation})
  check(bool(conversation.get('options')) and conversation.get('screen_id')!='out_of_range','Original Core3 station greeting opened')
  for _ in range(6):
   options=conversation['options']
   choice=next((x for x in options if any(v in x['name'].lower() for v in ['request landing','land at','land on','landing permission','land.','mos eisley','thank'])),None)
   if choice is None:break
   state=act('comm_choose',station_id=station,screen_token=conversation['screen_token'],option=choice['option'])['state'];conversation=state['station_conversation'];samples.append({'conversation':conversation})
  time.sleep(4)
  state=act('status')['state'];samples.append({'after_landing':state})
  check(not state.get('space_active',True),'Original station landing stores the ship')
  launched=False
  check(player.get('zone')=='tatooine','Station landing returns owner to Tatooine')
  check(console('runLuaFunction Tests:swgxrNavigationFixture:terminal').startswith('ready:'),'Prepare isolated hyperspace test')
  act('status')
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  state=act('hyperspace',destination='space_naboo_0')['state'];phases=set();deadline=time.monotonic()+65
  while time.monotonic()<deadline:
   phase=state.get('ship',{}).get('hyperspace',{}).get('phase','idle');phases.add(phase)
   samples.append({'hyperspace':state.get('ship',{}).get('hyperspace',{}),'zone':state.get('ship',{}).get('zone')})
   if phase=='idle' and 'arrival' in phases:break
   time.sleep(.5);state=act('status')['state']
  check({'countdown','travel','arrival','idle'}<=phases,'Native hyperspace task reports entry and arrival phases')
  check(state.get('ship',{}).get('zone')=='space_naboo','Native hyperspace arrives in original Naboo sector')
  check(console('runLuaFunction Tests:swgxrNavigationFixture:naboo_station')=='ready','Move isolated yacht within original Naboo station range')
  state=act('status')['state']
  stations=[x for x in state['nearby_ships'] if x.get('station_comms') and x.get('comm_in_range')]
  check(bool(stations),'Original Naboo station is in communication range')
  station=stations[0]['id'];state=act('comm_begin',station_id=station)['state'];conversation=state['station_conversation']
  for expected in ['permission to land','theed','(land)']:
   choice=next(x for x in conversation['options'] if expected in x['name'].lower())
   state=act('comm_choose',station_id=station,screen_token=conversation['screen_token'],option=choice['option'])['state'];conversation=state['station_conversation'];samples.append({'naboo_conversation':conversation})
  time.sleep(4);state=act('status')['state'];deadline=time.monotonic()+8
  while state.get('space_active',True) and time.monotonic()<deadline:
   time.sleep(.25);state=act('status')['state']
  samples.append({'naboo_landing':{key:player.get(key) for key in ['zone','position','building_id','cell_index']}})
  check(not state.get('space_active',True) and player.get('zone')=='naboo' and math.dist(player['position'],[-4860,6,4165])<10,'Naboo station lands at selected Theed coordinates, not Tatooine launch port')
  launched=False
  landed=call('/session/update',{'zone':player['zone'],'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  check(landed.get('ok',True) and player.get('zone')=='naboo','Ground movement accepts authoritative Theed arrival after station storage')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if sid and launched:act('land',False)
  if original is not None:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
