#!/usr/bin/env python3
"""Exercise native flight against an original asteroid on an isolated crafted hull.
No live XR client or ordinary-player mutation."""
import argparse,json,math,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18088);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--ship-report',type=Path,required=True);a=p.parse_args()
 os.umask(0o077);f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and str(f['id']).isdigit()
 checks=[];samples=[];latencies=[];sid='';player={};original=None
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True);assert ok,label
 def call(path,data=None,required=True):
  nonlocal player
  body=None if data is None else {'account':f['account'],'character_id':f['id'],'session_id':sid,**data}
  req=urllib.request.Request('http://127.0.0.1:'+str(a.port)+path,None if body is None else json.dumps(body).encode(),{'Content-Type':'application/json'})
  started=time.monotonic()
  try:
   with urllib.request.urlopen(req,timeout=90) as r:value=json.load(r)
   latencies.append({'path':path.split('?')[0],'seconds':time.monotonic()-started})
  except urllib.error.HTTPError as e:value={'http_error':e.code,**json.load(e)}
  samples.append({'response':value})
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
 ship_report=json.loads(a.ship_report.read_text());assert ship_report['passed'] and ship_report['fixture_id']==f['id'];ship_id=ship_report['crafted_ship_id']
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'

 lua='''
function Tests:swgxrFlightCollision(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY()+1;local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y,cell);return "ready,"..SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif mode=="position" then
  return SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif string.sub(mode,1,5)=="rock," then
  local coords={};for v in string.gmatch(string.sub(mode,6),"[^,]+") do table.insert(coords,tonumber(v)) end
  local rock=spawnSceneObject(SceneObject(s):getZoneName(),"object/static/space/asteroid/asteroid_iron_small_01.iff",coords[1],coords[2],coords[3],0,1,0,0,0)
  if rock==nil then return "spawn_failed" end
  writeData("swgxrFlightRock",SceneObject(rock):getObjectID());return string.format("%.0f",SceneObject(rock):getObjectID())
 elseif mode=="cleanup" then
  local rock=getSceneObject(readData("swgxrFlightRock"));if rock~=nil then SceneObject(rock):destroyObjectFromWorld();SceneObject(rock):destroyObjectFromDatabase() end
  deleteData("swgxrFlightRock");CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'native_corecu':True,'client_launched':False,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'fixture_controls':'Previously natively crafted Z95; original asteroid placed 120m ahead. Native collision and flight retained.'}
 registration=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/space/swgxr_pilot/registration.lua';original_registration=registration.read_text()
 launched=False;sequence=0
 try:
  sid=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]})['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays')
  call('/combat/session/stop',{});sid=''
  placed=console('runLuaFunction Tests:swgxrFlightCollision:terminal').split(',')
  check(placed[0]=='ready','Crafted fixture ship at original launch terminal')
  time.sleep(1.5)
  position=console('runLuaFunction Tests:swgxrFlightCollision:position').split(',')
  pose={'zone':'tatooine','position':[float(v) for v in position],'building_id':'1106368','cell_index':4}
  sid=call('/combat/session/start',pose)['session_id'];call('/session/update',{**pose,'ready':True})
  stage=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage']
  state=act('launch',terminal_id='1279066',launch_id=stage['id'])['state'];launched=True;sequence=state['ship']['control_sequence']
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Crafted and outfitted Z-95 launches')
  start=state['ship']['position'];qx,qy,qz,qw=state['ship']['quaternion']
  forward=[2*(qx*qz+qw*qy),2*(qy*qz-qw*qx),1-2*(qx*qx+qy*qy)]
  obstacle=[p+v*120 for p,v in zip(start,forward)]
  rock=console('runLuaFunction Tests:swgxrFlightCollision:rock,'+','.join(map(str,obstacle)))
  check(rock.isdigit(),'Original native asteroid created ahead of crafted ship')
  deadline=time.monotonic()+20;first=state['ship'].get('collision_sequence',0)
  while time.monotonic()<deadline:
   sequence+=1;state=act('control',sequence=sequence,throttle=1,pitch=0,yaw=0,roll=0,primary_fire=False,targeting_active=False)['state']
   if state['ship'].get('collision_sequence',0)>first:break
   time.sleep(.12)
  ship=state['ship'];report['collision_ship']=ship;report['obstacle']=obstacle
  check(ship.get('collision_sequence',0)>first,'Native flight emits an authoritative collision receipt')
  check(ship.get('collision_object')==rock,'Collision identifies the original spawned scenery object')
  check(ship['speed_mps']==0 and math.dist(ship['velocity'],[0,0,0])<.001,'Collision stops native translation and extrapolation velocity')
  travelled=sum((p-v)*d for p,v,d in zip(ship['position'],start,forward))
  check(0<travelled<120,'Crafted ship advances but cannot pass through asteroid')
  hold=ship['position']
  for i in range(8):
   sequence+=1;state=act('control',sequence=sequence,throttle=1,pitch=0,yaw=0,roll=0,primary_fire=False,targeting_active=False)['state'];time.sleep(.1)
  check(math.dist(hold,state['ship']['position'])<1,'Held throttle cannot creep through the obstacle')
  deadline=time.monotonic()+22
  while time.monotonic()<deadline:
   sequence+=1;state=act('control',sequence=sequence,throttle=1,pitch=0,yaw=1,roll=0,primary_fire=False,targeting_active=False)['state']
   if not state['ship'].get('collision_blocked') and math.dist(hold,state['ship']['position'])>5:break
   time.sleep(.12)
  check(not state['ship'].get('collision_blocked') and math.dist(hold,state['ship']['position'])>5,'Pilot turns away and resumes native flight without being trapped')
  report['passed']=True
 except Exception as error:report['error']=str(error);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrFlightCollision:cleanup')
    if launched:act('land',required=False)
   finally:registration.write_text(original_registration);script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
