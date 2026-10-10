#!/usr/bin/env python3
"""Native crafted-ship combat and original encounter loot on an explicitly named isolated invtest fixture.

Run on the test server as its maintenance user. Test ingredients/skills are
provisioned only to that fixture; damage and loot must come from SpaceCombatManager and ShipManager.
"""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--ship-report',type=Path,required=True);a=p.parse_args()
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
 ship_report=json.loads(a.ship_report.read_text());assert ship_report['passed'] and ship_report['fixture_id']==f['id'];ship_id=ship_report['crafted_ship_id']
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 lua='''
function Tests:swgxrCombatFixture(mode)
 local p=getSceneObject(__ID__);local s=getSceneObject(__SHIP__)
 if p==nil or s==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066);local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y+1,cell);return "ready"
 elseif mode=="spawn" then
  if not ShipObject(s):isShipLaunched() then return "ship_not_launched" end
  local point=ShipObject(s):getSpawnPointInFrontOfShip(90,90)
  local npc=spawnShipAgent("hutt_quest_hortrix_steelarm_tier3","space_tatooine",point[1],point[2],point[3])
  if npc==nil then return "spawn_failed" end
  writeData("swgxrCombatNpc",SceneObject(npc):getObjectID());return tostring(readData("swgxrCombatNpc"))
 elseif mode=="align" then
  local npc=getSceneObject(readData("swgxrCombatNpc"))
  if npc==nil then return "gone" end
  if ShipObject(npc):isShipDestroyed() then return "destroyed" end
  local point=ShipObject(s):getSpawnPointInFrontOfShip(90,90)
  SceneObject(npc):teleport(point[1],point[2],point[3],0)
  ShipObject(s):repairShip(p,1,0,false)
  return "aligned"
 elseif mode=="cleanup" then
  local npc=getSceneObject(readData("swgxrCombatNpc"));if npc~=nil then SceneObject(npc):destroyObjectFromWorld();SceneObject(npc):destroyObjectFromDatabase() end
  deleteData("swgxrCombatNpc");CreatureObject(p):forcePeace();return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__SHIP__',ship_id).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'crafted_ship_id':ship_id,'checks':checks,'samples':samples,'npc_template':'hutt_quest_hortrix_steelarm_tier3','fixture_controls':'Original NPC repositioned ahead of crafted hull; fixture hull repaired; native projectile collision, damage, threat, destruction and loot unchanged'}
 launched=False;events={};sequence=0
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');check(console('runLuaFunction Tests:swgxrCombatFixture:terminal')=='ready','Crafted ship fixture at original terminal')
  act('status');call('/session/update',{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  staged=act('crew_prepare',terminal_id='1279066',ship_id=ship_id)['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state'];launched=True
  check(state['ship']['id']==ship_id and not state['ship']['combat_excluded'],'Actually crafted and outfitted Z-95 launches with combat enabled')
  samples.append({'launch':state});sequence=state['ship']['control_sequence'];before=state['ship']['position']
  for _ in range(12):
   sequence+=1;state=act('control',sequence=sequence,throttle=1,pitch=.2,yaw=.1,roll=0,primary_fire=False)['state'];samples.append({'flight':state['ship']});time.sleep(.25)
  import math
  check(math.dist(before,state['ship']['position'])>40,'Crafted ship moves continuously in original 3D dynamics')
  time.sleep(1.8);state=act('status')['state'];check(state['ship']['speed_mps']==0,'Expired control lease stops an actual crafted combat ship')
  inventory=call('/inventory?account='+f['account']+'&character_id='+f['id']);before_items={x['id'] for x in inventory['items']};before_credits=sum(x.get('use_count',0) for x in inventory['items'] if 'credit_chip' in x.get('template',''))
  npc=console('runLuaFunction Tests:swgxrCombatFixture:spawn');check(npc.isdigit(),'Original hostile NPC encounter template spawned for isolated combat')
  report['npc_id']=npc;target_seen=False;minimum=None;deadline=time.monotonic()+180
  while time.monotonic()<deadline:
   aligned=console('runLuaFunction Tests:swgxrCombatFixture:align')
   if aligned in ('destroyed','gone'):break
   for _ in range(3):
    sequence+=1;state=act('control',sequence=sequence,throttle=0,pitch=0,yaw=0,roll=0,primary_fire=True)['state']
    for e in state.get('combat_events',[]):events[e['id']]=e
    target=next((s for s in state['nearby_ships'] if s['id']==npc),None)
    if target:
     target_seen=True;minimum=target['hull']['current'] if minimum is None else min(minimum,target['hull']['current'])
    samples.append({'ship':state['ship'],'target':target,'nearby_ships':state['nearby_ships'],'events':state.get('combat_events',[])})
    time.sleep(.2)
   if len(samples)%12==0:print('combat',len(events),'events','target_hull',minimum,flush=True)
  sequence+=1;act('control',sequence=sequence,throttle=0,pitch=0,yaw=0,roll=0,primary_fire=False)
  check(any(e.get('kind')=='projectile' and e.get('ship_id')==ship_id for e in events.values()),'Fixed primary weapons produce actual Core3 projectile events')
  check(target_seen and (aligned in ('destroyed','gone') or minimum==0),'Native projectile damage destroys the original NPC hull')
  inventory=call('/inventory?account='+f['account']+'&character_id='+f['id']);loot=[x for x in inventory['items'] if x['id'] not in before_items];report['loot']=loot
  check(any('palace_access_doc' in x.get('template','') for x in loot),'Guaranteed original Hortrix quest loot reaches pilot inventory through native kill attribution')
  after_credits=sum(x.get('use_count',0) for x in inventory['items'] if 'credit_chip' in x.get('template',''));report['credit_chip_delta']=after_credits-before_credits
  check(120<=after_credits-before_credits<=294,'Original encounter adds native payout to credit-chip balance')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:
    console('runLuaFunction Tests:swgxrCombatFixture:cleanup')
    if launched:act('land',required=False)
   finally:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['events']=list(events.values());report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
