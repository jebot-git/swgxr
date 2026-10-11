#!/usr/bin/env python3
"""Exercise the converted two-stop delivery through real native docking.
Original quest relocated near a crafted fixture ship; hostile waves disabled.
Does not claim original-route travel, combat balance, or XR validation."""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]

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
function Tests:swgxrPilotDelivery(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 local q=PilotQuests.instances["delivery:corellia_rebel_tier3_3"]
 if mode=="terminal" then
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY()+1;local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y,cell);return "ready,"..SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif mode=="position" then
  return SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif mode=="mission" then
  if PlayerObject(CreatureObject(p):getPlayerObject()):hasGodMode() then return "admin_forbidden" end
  PilotQuests.clear(p,"delivery","corellia_rebel_tier3_3")
  q.questZone="space_tatooine";q.sideQuest=false;q.attackShips={}
  local x=SceneObject(s):getPositionX();local z=SceneObject(s):getPositionZ()+80;local y=SceneObject(s):getPositionY()
  q.objectivePoints={{x=x,z=z,y=y},{x=x,z=z+150,y=y}}
  PilotQuests.grant(p,nil,"delivery","corellia_rebel_tier3_3")
  return "mission"
 elseif mode=="progress" then
  return tostring(q:get(p,"stage"))..":"..tostring(q:get(p,"target"))..":"..tostring(SpaceHelpers:isSpaceQuestActive(p,q.questType,q.questName))..":"..tostring(SpaceHelpers:isSpaceQuestComplete(p,q.questType,q.questName))
 elseif mode=="cleanup" then
  PilotQuests.clear(p,"delivery","corellia_rebel_tier3_3");CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'native_corecu':True,'client_launched':False,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'fixture_controls':'Original delivery corellia_rebel_tier3_3 relocated to two nearby rendezvous in Tatooine, waves and follow-on quest disabled; original target templates, native docking, journal tasks and completion observer retained.'}
 registration=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/space/swgxr_pilot/registration.lua';original_registration=registration.read_text()
 launched=False;sequence=0
 try:
  sid=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]})['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays')
  call('/combat/session/stop',{});sid=''
  placed=console('runLuaFunction Tests:swgxrPilotDelivery:terminal').split(',')
  check(placed[0]=='ready','Crafted fixture ship at original launch terminal')
  time.sleep(1.5)
  position=console('runLuaFunction Tests:swgxrPilotDelivery:position').split(',')
  pose={'zone':'tatooine','position':[float(v) for v in position],'building_id':'1106368','cell_index':4}
  sid=call('/combat/session/start',pose)['session_id'];call('/session/update',{**pose,'ready':True})
  stage=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage']
  state=act('launch',terminal_id='1279066',launch_id=stage['id'])['state'];launched=True;sequence=state['ship']['control_sequence']
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Crafted and outfitted Z-95 launches')
  # Reload the same fixture override in each native Lua worker, not only the console worker.
  x,z,y=state['ship']['position'];z+=80
  registration.write_text(original_registration+'\nlocal q=PilotQuests.instances["delivery:corellia_rebel_tier3_3"]\nq.questZone="space_tatooine";q.sideQuest=false;q.attackShips={}\nq.objectivePoints={{x='+str(x)+',z='+str(z)+',y='+str(y)+'},{x='+str(x)+',z='+str(z+150)+',y='+str(y)+'}}\n')
  console('reloadscreenplays')
  check(console('runLuaFunction Tests:swgxrPilotDelivery:mission')=='mission','Original converted delivery activated on non-admin fixture')
  def tick():
   nonlocal sequence,state
   sequence+=1;state=act('control',sequence=sequence,throttle=0,pitch=0,yaw=0,roll=0,primary_fire=False,targeting_active=True)['state']
  def progress():return console('runLuaFunction Tests:swgxrPilotDelivery:progress').split(':')
  targets=[]
  for phase in (1,2):
   deadline=time.monotonic()+15
   while time.monotonic()<deadline:
    current=progress()
    if int(float(current[0]))==phase and int(float(current[1])):break
    tick();time.sleep(.25)
   npc=str(int(float(current[1])));check(npc!='0','Delivery phase '+str(phase)+' spawns its target')
   targets.append(npc);act('target',target_id=npc);tick()
   check(state['ship']['targeting']['target'].get('dock_permitted'),'Native journal grants phase '+str(phase)+' docking permission')
   state=act('dock',target_id=npc)['state'];check(state['ship']['docking'],'Native docking starts for phase '+str(phase))
   deadline=time.monotonic()+65
   while time.monotonic()<deadline:
    tick();time.sleep(.2)
    if not state['ship']['docking']:break
   # Native docking clears its flag before dispatching SHIPDOCKED asynchronously.
   time.sleep(.5)
   current=progress()
   if phase==1:
    check(current[0]=='2' and current[3]=='false','Pickup advances to delivery without completing the mission')
    check(act('dock',False,target_id=npc).get('ok') is False,'Pickup permission cannot be reused for delivery')
   else:check(current[3]=='true','Native SHIPDOCKED observer completes the delivery')
  check(targets[0]!=targets[1],'Pickup and delivery use distinct native ship IDs')
  report['passed']=True
 except Exception as error:report['error']=str(error);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrPilotDelivery:cleanup')
    if launched:act('land',required=False)
   finally:registration.write_text(original_registration);script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
