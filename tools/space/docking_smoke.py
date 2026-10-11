#!/usr/bin/env python3
"""Original inspection mission docking and completion on an explicitly named isolated invtest fixture.

Run on the test server as its maintenance user. Test ingredients/skills are
provisioned only to that fixture; damage and loot must come from SpaceCombatManager and ShipManager.
"""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
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
function Tests:swgxrDockingFixture(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066);local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y+1,cell);return "ready"
 elseif mode=="spawn" then
  if not ShipObject(s):isShipLaunched() then return "ship_not_launched" end
  local point={SceneObject(s):getPositionX(),SceneObject(s):getPositionZ()+90,SceneObject(s):getPositionY()}
  local npc=spawnShipAgent("nym_cannon_ship_tier2","space_tatooine",point[1],point[2],point[3])
  if npc==nil then return "spawn_failed" end
  ShipAiAgent(npc):removeSpaceFactionEnemy(ShipObject(s):getShipFactionHash())
  ShipAiAgent(npc):addSpaceFactionAlly(ShipObject(s):getShipFactionHash())
  ShipAiAgent(npc):setMinimumGuardPatrol(0);ShipAiAgent(npc):setMaximumGuardPatrol(0);ShipAiAgent(npc):setGuardPatrol()
  ShipObject(npc):setCargoString("shipment_orders")
  writeData("swgxrDockingNpc",SceneObject(npc):getObjectID());return tostring(readData("swgxrDockingNpc"))
 elseif mode=="align" then
  local npc=getSceneObject(readData("swgxrDockingNpc"))
  if npc==nil then return "gone" end
  if ShipObject(npc):isShipDestroyed() then return "destroyed" end
  local point={SceneObject(s):getPositionX(),SceneObject(s):getPositionZ()+90,SceneObject(s):getPositionY()}
  ShipObject(s):repairShip(p,1,0,false)
  return "aligned"
 elseif mode=="mission" then
  local ghost=CreatureObject(p):getPlayerObject()
  if PlayerObject(ghost):hasGodMode() then return "admin_forbidden" end
  SpaceHelpers:clearSpaceQuest(p,"inspect","corellia_privateer_15",false)
  inspect_corellia_privateer_15.questZone="space_tatooine"
  inspect_corellia_privateer_15.targetLocation={x=SceneObject(s):getPositionX(),z=SceneObject(s):getPositionZ(),y=SceneObject(s):getPositionY()}
  inspect_corellia_privateer_15:startQuest(p,"")
  return "mission"
 elseif mode=="progress" then
  local ghost=CreatureObject(p):getPlayerObject()
  return tostring(not not SpaceHelpers:isSpaceQuestTaskActive(p,"inspect","corellia_privateer_15",2))..":"..tostring(not not SpaceHelpers:isSpaceQuestTaskComplete(p,"inspect","corellia_privateer_15",2))..":"..tostring(PlayerObject(ghost):isJournalQuestComplete(getHashCode("spacequest/inspect/corellia_privateer_15")))
 elseif mode=="fail" then
  inspect_corellia_privateer_15:failQuest(p,"false");return "failed"
 elseif mode=="cleanup" then
  if SpaceHelpers:isSpaceQuestActive(p,"inspect","corellia_privateer_15") then inspect_corellia_privateer_15:failQuest(p,"false") end

  local npc=getSceneObject(readData("swgxrDockingNpc"));if npc~=nil then SceneObject(npc):destroyObjectFromWorld();SceneObject(npc):destroyObjectFromDatabase() end
  deleteData("swgxrDockingNpc");CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'npc_template':'nym_cannon_ship_tier2','fixture_controls':'Original CorSec inspection mission relocated to Tatooine for isolated fixture; original target cargo set with a stationary, friendly fixture patrol; native inspect/dock tasks, journal and mission completion observers unchanged'}
 launched=False;events={};sequence=0
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');check(console('runLuaFunction Tests:swgxrDockingFixture:terminal')=='ready','Crafted ship fixture at original terminal')
  act('status');call('/session/update',{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Actually crafted and outfitted Z-95 launches with combat enabled')
  samples.append({'launch':state});sequence=state['ship']['control_sequence']
  npc=console('runLuaFunction Tests:swgxrDockingFixture:spawn');check(npc.isdigit(),'Original CorSec inspection target spawned')
  report['npc_id']=npc
  def tick():
   nonlocal sequence,state
   sequence+=1;state=act('control',sequence=sequence,throttle=0,pitch=0,yaw=0,roll=0,primary_fire=False,targeting_active=True)['state'];samples.append(state['ship'])
   return state
  console('runLuaFunction Tests:swgxrDockingFixture:align')
  act('target',target_id=npc)
  check(act('dock',False,target_id=npc).get('ok') is False,'Non-admin pilot cannot dock without mission permission')
  check(console('runLuaFunction Tests:swgxrDockingFixture:mission')=='mission','Original inspection quest started on non-admin fixture')
  time.sleep(1.5)
  check(act('dock',False,target_id=npc).get('ok') is False,'Quest alone cannot skip required inspection stage')
  def inspect():
   console('runLuaFunction Tests:swgxrDockingFixture:align');act('inspect',target_id=npc)
   for _ in range(40):
    console('runLuaFunction Tests:swgxrDockingFixture:align');tick();time.sleep(.15)
    if state['ship']['targeting']['target'].get('dock_permitted'):return
   raise AssertionError('Native inspection did not grant docking: '+console('runLuaFunction Tests:swgxrDockingFixture:progress'))
  inspect()
  check(state['ship']['targeting']['target']['dock_permitted'],'Native inspect observer grants exact mission target permission')
  key=uuid.uuid4().hex
  first=act('dock',target_id=npc,request_id=key);again=act('dock',target_id=npc,request_id=key)
  check(first['state']['ship']['docking'] and again['mutation'].get('replayed'),'Dock starts and request replay is idempotent')
  samples.append({'before_undock':act('status')})
  act('undock');time.sleep(2.5);tick()
  check(not state['ship']['docking'] and console('runLuaFunction Tests:swgxrDockingFixture:progress').split(':')[1]=='false','Aborting docking does not complete the mission')
  console('runLuaFunction Tests:swgxrDockingFixture:align');act('dock',target_id=npc)
  console('runLuaFunction Tests:swgxrDockingFixture:fail');time.sleep(2.5);tick()
  check(not state['ship']['docking'] and not state['ship']['targeting']['target']['dock_permitted'],'Failed objective revokes in-flight docking permission')
  console('runLuaFunction Tests:swgxrDockingFixture:mission');time.sleep(1.5);inspect()
  console('runLuaFunction Tests:swgxrDockingFixture:align')
  state=act('dock',target_id=npc)['state']
  check(state['ship']['docking'],'Non-admin pilot begins permitted mission docking')
  start=state['ship']['position'];deadline=time.monotonic()+65
  while time.monotonic()<deadline:
   tick();time.sleep(.2)
   if not state['ship']['docking']:break
  time.sleep(1.6);progress=console('runLuaFunction Tests:swgxrDockingFixture:progress')
  report['final_progress']=progress
  check(progress.split(':')[-1]=='true','Actual native SHIPDOCKED observer completes original CorSec mission')
  check(not tick()['ship']['targeting']['target']['dock_permitted'],'Completed quest cannot reuse docking permission')
  check(act('dock',False,target_id=npc).get('ok') is False,'Post-completion dock attempt is rejected')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrDockingFixture:cleanup')
    if launched:act('land',required=False)
   finally:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['events']=list(events.values());report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
