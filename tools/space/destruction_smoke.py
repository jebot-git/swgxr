#!/usr/bin/env python3
"""Exercise native destruction recovery and communications on an isolated crafted hull.
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
function Tests:swgxrDestruction(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY()+1;local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y,cell);return "ready,"..SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif mode=="position" then
  return SceneObject(p):getWorldPositionX()..","..SceneObject(p):getWorldPositionZ()..","..SceneObject(p):getWorldPositionY()
 elseif string.sub(mode,1,6)=="taunt," then
  local npc=getSceneObject(tonumber(string.sub(mode,7)))
  if npc==nil then return "missing" end
  ShipAiAgent(npc):tauntPlayer(p,"@space/quest:escort_too_far1")
  return "sent"
 elseif mode=="destroy" then
  if not ShipObject(s):isShipLaunched() then return "not_launched" end
  SpaceHelpers:sendQuestAlert(p,"Recovery fixture incoming transmission")
  CreatureObject(p):playMusicMessage("sound/mus_quest_theme_opening.snd")
  ShipObject(s):scheduleDestroyShipTask(0)
  return "scheduled"
 elseif mode=="cleanup" then
  CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'native_corecu':True,'client_launched':False,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'fixture_controls':'Previously natively crafted Z95. Schedule original DestroyShipTask directly; tests recovery, not lethal damage delivery.'}
 registration=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/space/swgxr_pilot/registration.lua';original_registration=registration.read_text()
 launched=False;sequence=0
 try:
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays')
  placed=console('runLuaFunction Tests:swgxrDestruction:terminal').split(',')
  check(placed[0]=='ready','Crafted fixture ship at original launch terminal')
  time.sleep(1.5)
  position=console('runLuaFunction Tests:swgxrDestruction:position').split(',')
  pose={'zone':'tatooine','position':[float(v) for v in position],'building_id':'1106368','cell_index':4}
  sid=call('/combat/session/start',pose)['session_id'];call('/session/update',{**pose,'ready':True})
  stage=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage']
  state=act('launch',terminal_id='1279066',launch_id=stage['id'])['state'];launched=True;sequence=state['ship']['control_sequence']
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Crafted and outfitted Z-95 launches')
  npc=next(row for row in state['nearby_ships'] if row.get('station_comms'))
  check(console('runLuaFunction Tests:swgxrDestruction:taunt,'+npc['id'])=='sent','Native NPC transmission invoked')
  check(console('runLuaFunction Tests:swgxrDestruction:destroy')=='scheduled','Original native destruction task scheduled on isolated crafted hull')
  deadline=time.monotonic()+25;started=time.monotonic();message_seen=False;taunt_seen=False
  while time.monotonic()<deadline:
   state=act('status')['state']
   message_seen=message_seen or any('Recovery fixture incoming transmission' in row.get('text','') for row in state.get('communications',[]))
   taunt_seen=taunt_seen or any(row.get('sender') and row.get('text') for row in state.get('communications',[]))
   if not state.get('space_active',False):break
   time.sleep(.25)
  report['final_player']=player
  report['recovery_seconds']=time.monotonic()-started
  report['final_state']=state
  check(taunt_seen,'Native NPC dialogue reaches owner communications with sender')
  check(message_seen,'Native space system message reaches normalized owner communications')
  check(not state.get('space_active',False),'Native destruction returns pilot to ground without a manual land request')
  check(player.get('zone')=='tatooine','Pilot returns to the launch planet')
  check(any(row['id']==ship_id for row in state.get('ships',[])),'Native crafted hull remains owned after destruction task')
  launched=False
  report['passed']=True
 except Exception as error:report['error']=str(error);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrDestruction:cleanup')
    if launched:act('land',required=False)
   finally:registration.write_text(original_registration);script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
