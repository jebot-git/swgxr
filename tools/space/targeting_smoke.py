#!/usr/bin/env python3
"""Native ship/subsystem selection and missile acquisition on an explicitly named isolated invtest fixture.

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
 def service(action,required=True,**extra):
  return call('/services/'+action,{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'terminal_id':'1279066','ship_id':ship_id,'request_id':uuid.uuid4().hex,**extra},required)
 def act(action,required=True,**extra):return call('/jtl/'+action,{'request_id':uuid.uuid4().hex,**extra},required)
 ship_report=json.loads(a.ship_report.read_text());assert ship_report['passed'] and ship_report['fixture_id']==f['id'];ship_id=ship_report['crafted_ship_id']
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 lua='''
function Tests:swgxrTargetingFixture(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066);local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y+1,cell);return "ready"
 elseif mode=="equipment" then
  local inv=SceneObject(p):getSlottedObject("inventory")
  local launcher=giveItem(inv,"object/tangible/ship/crafted/weapon/missile/wpn_launcher_proton_mk1.iff",-1)
  local ammo=giveItem(inv,"object/tangible/ship/crafted/weapon/missile/wpn_proton_missile_mk1.iff",-1)
  if launcher==nil or ammo==nil then return "create_failed" end
  writeData("swgxrTargetingLauncher",SceneObject(launcher):getObjectID())
  return tostring(SceneObject(launcher):getObjectID())..":"..tostring(SceneObject(ammo):getObjectID())
 elseif mode=="spawn" then
  if not ShipObject(s):isShipLaunched() then return "ship_not_launched" end
  local point=ShipObject(s):getSpawnPointInFrontOfShip(90,90)
  local npc=spawnShipAgent("hutt_quest_hortrix_steelarm_tier3","space_tatooine",point[1],point[2],point[3])
  if npc==nil then return "spawn_failed" end
  writeData("swgxrTargetingNpc",SceneObject(npc):getObjectID());return tostring(readData("swgxrTargetingNpc"))
 elseif mode=="away" then
  local npc=getSceneObject(readData("swgxrTargetingNpc"))
  if npc==nil then return "gone" end
  local point=ShipObject(s):getSpawnPointBehindShip(3000,3000)
  SceneObject(npc):teleport(point[1],point[2],point[3],0);return "away"
 elseif mode=="behind" then
  local npc=getSceneObject(readData("swgxrTargetingNpc"))
  if npc==nil then return "gone" end
  local point=ShipObject(s):getSpawnPointBehindShip(90,90)
  SceneObject(npc):teleport(point[1],point[2],point[3],0);return "behind"
 elseif mode=="align" then
  local npc=getSceneObject(readData("swgxrTargetingNpc"))
  if npc==nil then return "gone" end
  if ShipObject(npc):isShipDestroyed() then return "destroyed" end
  local point=ShipObject(s):getSpawnPointInFrontOfShip(90,90)
  SceneObject(npc):teleport(point[1],point[2],point[3],0)
  ShipObject(s):repairShip(p,1,0,false)
  return "aligned"
 elseif mode=="cleanup" then
  local npc=getSceneObject(readData("swgxrTargetingNpc"));if npc~=nil then SceneObject(npc):destroyObjectFromWorld();SceneObject(npc):destroyObjectFromDatabase() end
  deleteData("swgxrTargetingNpc");CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'npc_template':'hutt_quest_hortrix_steelarm_tier3','fixture_controls':'NPC repositioned to exercise acquisition boundaries; original launcher/ammo provisioned to isolated invtest inventory; native commands, acquisition, consumption and guided missile simulation unchanged'}
 launched=False;events={};sequence=0;launcher='';weapon_slot=-1
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');check(console('runLuaFunction Tests:swgxrTargetingFixture:terminal')=='ready','Crafted ship fixture at original terminal')
  act('status');call('/session/update',{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  launcher,ammo=console('runLuaFunction Tests:swgxrTargetingFixture:equipment').split(':')
  options=service('ship_manage')['state']['terminal']['options']
  option=next(o for o in options if o['operation']=='ship_component_install' and o['component_id']==launcher)
  weapon_slot=option['slot']
  service('ship_component_install',component_id=launcher,slot=weapon_slot)
  loaded=service('ship_ammo_load',component_id=ammo,slot=weapon_slot,request_id='targeting_ammo_'+ammo)
  replay=service('ship_ammo_load',component_id=ammo,slot=weapon_slot,request_id='targeting_ammo_'+ammo)
  check(replay['mutation'].get('replayed') is True,'Native ammunition loading retry is idempotent')
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Actually crafted and outfitted Z-95 launches with combat enabled')
  samples.append({'launch':state});sequence=state['ship']['control_sequence']
  def tick(count=1):
   nonlocal sequence,state
   for _ in range(count):
    sequence+=1;state=act('control',sequence=sequence,throttle=0,pitch=0,yaw=0,roll=0,primary_fire=False,targeting_active=True)['state']
    samples.append(state['ship']['targeting'])
    for e in state.get('combat_events',[]):events[e['id']]=e
    time.sleep(.1)
   return state['ship']['targeting']
  npc=console('runLuaFunction Tests:swgxrTargetingFixture:spawn');check(npc.isdigit(),'Original hostile NPC created beside native crafted ship')
  report['npc_id']=npc
  check(act('target',False,target_id=ship_id).get('ok') is False,'Self selection rejected')
  target=act('target',target_id=npc)['state']['ship']['targeting']
  check(target['target_id']==npc and target['component_slot']==-1,'Explicit target defaults to whole ship, not reactor')
  components=target['target']['components'];slot=next(c['slot'] for c in components if c['available'])
  target=act('subsystem',target_id=npc,component_slot=slot)['state']['ship']['targeting']
  check(target['component_slot']==slot,'Native targetable subsystem is explicitly selectable')
  bad=act('subsystem',False,target_id=ship_id,component_slot=slot)
  check(bad.get('ok') is False,'Stale subsystem command rejected')
  bad=act('subsystem',False,target_id=npc,component_slot=111)
  check(bad.get('ok') is False,'Uninstalled subsystem rejected')
  act('subsystem',target_id=npc,component_slot=-1)
  console('runLuaFunction Tests:swgxrTargetingFixture:align')
  check(act('inspect',target_id=npc).get('ok') is True,'Selected ship dispatches native inspection command')
  target=act('missile_select',weapon_slot=weapon_slot)['state']['ship']['targeting']
  before=next(w['ammo'] for w in target['weapons'] if w['slot']==weapon_slot)
  check(before>0,'Native original missile ammunition loaded')
  check(act('missile_fire',False,target_id=npc,component_slot=-1,weapon_slot=weapon_slot).get('ok') is False,'Missile launch without acquisition rejected')
  def acquire():
   for _ in range(100):
    console('runLuaFunction Tests:swgxrTargetingFixture:align')
    target=tick(2)
    if target['lock_acquired']:return target
   raise AssertionError('No missile lock: '+json.dumps(target))
  target=acquire();check(target['lock_acquired'],'Native cone and timer acquire missile lock')
  console('runLuaFunction Tests:swgxrTargetingFixture:behind');target=tick(2)
  check(not target['lock_acquired'],'Leaving forward cone clears acquired lock')
  acquire()
  key=uuid.uuid4().hex
  fired=act('missile_fire',target_id=npc,component_slot=-1,weapon_slot=weapon_slot,request_id=key)
  replay=act('missile_fire',target_id=npc,component_slot=-1,weapon_slot=weapon_slot,request_id=key)
  after=next(w['ammo'] for w in replay['state']['ship']['targeting']['weapons'] if w['slot']==weapon_slot)
  check(after==before-1 and replay.get('replayed',replay.get('mutation',{}).get('replayed',False)),'Missile request/retry consumes exactly one native round')
  tick(20)
  check(any(e.get('kind')=='missile' and e.get('ship_id')==ship_id for e in events.values()),'Native guided missile publishes presentation receipts')
  console('runLuaFunction Tests:swgxrTargetingFixture:away');target=tick(2)
  check(target['target_id']=='0' and not target['lock_acquired'],'Out-of-range selection and lock clear')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrTargetingFixture:cleanup')
    if launched:act('land',required=False)
    if launcher and weapon_slot>=0:service('ship_component_remove',required=False,component_id=launcher,slot=weapon_slot)
   finally:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['events']=list(events.values());report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
