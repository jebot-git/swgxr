#!/usr/bin/env python3
"""Live creature riding regression; only an explicit isolated invtest receives a pet fixture."""
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
 def act(action,required=True,**extra):return call('/vehicles/'+action,{'request_id':uuid.uuid4().hex,**extra},required)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 lua='''
function Tests:swgxrMountFixture(mode)
 local p=getSceneObject(__ID__)
 if p==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if mode=="setup" then
  awardSkill(p,"outdoors_creaturehandler_master")
  local z=getTerrainHeight(p,3527,-4810)
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",3527,z,-4810,0)
  local m=spawnBabyMobile("tatooine","dewback",0,3528,z,-4810,0,0)
  if m==nil then return "spawn_failed" end
  writeData("swgxrMountFixture",SceneObject(m):getObjectID())
  if not grantCreaturePet(p,m) then return "grant_failed" end
  growCreaturePet(p,m)
  return tostring(SceneObject(m):getObjectID())
 elseif mode=="near" then
  local m=getSceneObject(readData("swgxrMountFixture"));if m==nil then return "missing" end
  local x=SceneObject(m):getPositionX();local z=SceneObject(m):getPositionZ();local y=SceneObject(m):getPositionY()
  SceneObject(p):teleport(x-.7,z,y,0);return "ready"
 elseif mode=="cleanup" then
  local m=getSceneObject(readData("swgxrMountFixture"))
  if m~=nil then SceneObject(m):destroyObjectFromWorld() end
  deleteData("swgxrMountFixture");return "clean"
 end
end
'''.replace('__ID__',str(f['id'])).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'checks':checks,'native_execution':True,'fixture_id':f['id'],'fixture_controls':'Administrator grants and matures an original dewback only to invtest. Mount training, seating and movement use native routes.'}
 def status():return act('status')['state']
 def refresh():
  return call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True},False)
 def world(v,p):
  import math
  x,y,z=v['position'];a=v['heading_radians'];return [x+p[0]*math.cos(a)-p[2]*math.sin(a),y+p[1],z-p[0]*math.sin(a)-p[2]*math.cos(a)]
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id'];refresh()
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays')
  petid=console('runLuaFunction Tests:swgxrMountFixture:setup');check(petid.isdigit(),'Isolated original owned dewback fixture created')
  refresh();s=status();pet=next(p for p in s['pets'] if p['id']==petid)
  check(not any(v['id']==petid for v in s['vehicles']),'Untrained pet has no mount seat')
  console('runLuaFunction Tests:swgxrMountFixture:near');refresh();s=status();pet=next(p for p in s['pets'] if p['id']==petid)
  check(pet['creature_handler']['train_mount'],'Native creature mount training eligibility retained')
  hand=list(pet['position']);hand[1]+=.5
  s=act('ch_train_mount',device_id=pet['device_id'],hand=hand)['state']
  ride=next(v for v in s['vehicles'] if v['id']==petid)
  check(ride['kind']=='creature_mount' and len(ride['seats'])==1,'Training exposes original saddle as a native rideable')
  invalid=act('board',required=False,vehicle_id=petid,seat='driver',hand=[0,0,0]);check(invalid.get('http_error') or invalid.get('ok') is False,'Mount boarding rejects remote hand contact')
  seat=world(ride,ride['seats'][0]['position']);s=act('board',vehicle_id=petid,seat='driver',hand=seat)['state']
  check(s['seat'].get('vehicle_id')==petid,'Touching owned saddle reserves mount seat')
  start=next(v for v in s['vehicles'] if v['id']==petid)
  import math
  p=list(start['position']);heading=start['heading_radians']+.08
  p[0]+=.1*math.sin(heading);p[2]+=.1*math.cos(heading)
  result=call('/session/update',{'zone':'tatooine','position':s['position'],'building_id':'0','cell_index':0,'ready':True,'vehicle_controls':{'mode':'client_pose','vehicle_id':petid,'position':p,'heading_radians':heading,'speed':1.0,'held':True,'throttle':1.0,'steer':.5}})
  s=status();moved=next(v for v in s['vehicles'] if v['id']==petid)
  check(math.dist(moved['position'],p)<.02 and abs(moved['heading_radians']-heading)<.01,'Native trained mount accepts rider forward motion and steering')
  s=act('dismount')['state'];check(not s['seat'],'Jump-route dismount releases native mount seat')
  report['mount']=moved;report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if sid:
   try:act('dismount',required=False)
   except Exception:pass
   try:console('runLuaFunction Tests:swgxrMountFixture:cleanup')
   except Exception:pass
   try:call('/combat/session/stop',{},False)
   except Exception:pass
  if original is not None:script.write_text(original);console('reloadscreenplays')
  a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
