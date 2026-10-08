#!/usr/bin/env python3
"""Actual Core3 movement policy with disposable native character/admin setup only."""
import json, math, re, secrets, time
from services_smoke import ROOT, req, redact
from equipment_smoke import console

def main():
 owner={'account':'invtestmove'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorst')for _ in range(9))}
 made=req('/characters',dict(owner,species='human',profession='combat_brawler'));assert 'character'in made,made;owner['id']=made['character']['id'];base=dict(account=owner['account'],character_id=owner['id'])
 report=dict(passed=False,native_execution=True,privileged_fixture=True,headset_tested=False,fixture=owner,checks=[],responses=[])
 session='';loc={};script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';added=''
 def check(ok,label):
  report['checks'].append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 def call(path,**kw):
  out=req(path,dict(base,**kw));report['responses'].append(dict(path=path,response=redact(out)));return out
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(100):
   with log.open()as f:f.seek(offset);m=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',f.read())
   if m:return m.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Lua timed out '+name)
 def pose(p):return {k:p[k]for k in('position','building_id','cell_index')}
 def snap():return call('/combat/session/snapshot',session_id=session)['snapshot']['player']
 def update(p=None,**kw):return call('/combat/session/update',session_id=session,ready=True,**pose(p or loc),**kw)
 def restart(kind='ground',startpos=None):
  nonlocal session,loc
  if session:call('/combat/session/stop',session_id=session);session=''
  lua('swgxrMovementSetup:'+kind)
  loc=call('/enter')['source_location'];requested=pose(loc)
  if startpos:requested['position']=startpos
  out=call('/combat/session/start',**requested);session=out['session_id'];return out['snapshot']['player']
 try:
  call('/enter')
  added=f'''
-- BEGIN SWGXR MOVEMENT FIXTURE
function Tests:swgxrMovementSetup(kind)
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:forcePeace();c:clearState(131072);c:setPosture(0)
 if kind=="water" then SceneObject(p):teleport(6250,getTerrainHeight(p,6250,-375),-375,0)
 elseif kind=="inside" then SceneObject(p):teleport(-20.133, -0.894992, -11.421,1082877)
 else SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0) end
 return tostring(SceneObject(p):getWorldPositionX())..":"..tostring(SceneObject(p):getWorldPositionZ())..":"..tostring(SceneObject(p):getWorldPositionY())
end
function Tests:swgxrMovementFreeze(on)
 local c=CreatureObject(getSceneObject({owner['id']}));if on=="1"then c:setState(131072)else c:clearState(131072)end;return "done"
end
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.3)
  player=restart(startpos=[0,100,0]);check(math.dist(player['position'],loc['position'])<.01,'Session start preserves saved native position, ignores arbitrary requested teleport')
  native=player['locomotion'];check(all(k in native for k in('run_speed','walk_speed','run_acceleration','walk_acceleration','speed_multiplier_mod','slope_mod_angle_radians','swim_height')),'Native locomotion getter projection available')
  out=update();check(out.get('mutation',{}).get('movement_accepted'),'Stationary ready acknowledgment accepted');loc=out['snapshot']['player']
  check(not loc['on_load_screen'],'Ready movement clears loading protection')
  time.sleep(1.05)
  p=dict(loc,position=list(loc['position']));p['position'][0]+=.8;p['position'][1]+=.1
  out=update(p);check(out.get('mutation',{}).get('movement_accepted'),'Ordinary physical/controller displacement and mesh-floor discrepancy accepted');loc=out['snapshot']['player']
  check(loc['locomotion']['current_speed']>0,'Native currentSpeed and locomotion updated')
  check(not loc['on_load_screen'],'Ordinary movement does not create teleport loading state')
  # The accepted native floor need not echo the submitted visual mesh height.
  check(abs(loc['position'][1]-p['position'][1])>.01,'Outdoor authoritative height resolves original native terrain floor')
  lua('swgxrMovementFreeze:1');p=dict(loc,position=list(loc['position']));p['position'][0]+=.1
  out=update(p);check(out.get('error_code')=='native_movement_player_frozen' and out['mutation']['movement_accepted']is False,'Native frozen state rejects locomotion with authoritative rejection response')
  check(math.dist(out['snapshot']['player']['position'],loc['position'])<.01,'Rejected frozen movement preserves authoritative position')
  lua('swgxrMovementFreeze:0');time.sleep(1.05);out=update();loc=out['snapshot']['player'];time.sleep(1.05)
  p=dict(loc,position=list(loc['position']));p['position'][0]+=100
  out=update(p);check(out.get('error_code')=='native_movement_speed_rejected','Original server speed validation rejects impossible displacement')
  loc=out['snapshot']['player'];check(math.dist(loc['position'],p['position'])>90,'Speed rejection returns restored native validated position')
  time.sleep(1.05);out=update();loc=out['snapshot']['player'];p=dict(loc,position=[8192,loc['position'][1],loc['position'][2]])
  out=update(p);check(out.get('error_code')=='native_movement_terrain_out_of_bounds','Native terrain cache edge is rejected before sampling')
  p=dict(loc,building_id='1082874',cell_index=255);out=update(p);check(out.get('error_code')=='native_movement_invalid_source_cell','Nonexistent building cell rejected')
  player=restart('water');out=update();loc=out['snapshot']['player'];check(loc['locomotion']['swimming'],'Original Tatooine water region sets native swimming state')
  check(abs(loc['position'][1]+loc['locomotion']['swim_height'])<.05,'Native water floor equals source water level minus swim height')
  player=restart('inside');out=update();loc=out['snapshot']['player'];check(loc['cell_index']==3 and loc['building_id']=='1082874','Native indoor parent retained without teleport')
  p=dict(loc,position=list(loc['position']));p['position'][0]+=3000;out=update(p);check(out.get('error_code')=='native_movement_cell_position_out_of_bounds','Interior local-coordinate bounds reject outside position')
  p=dict(loc,cell_index=1);out=update(p);check(out.get('error_code')in('native_movement_unconnected_source_cell','native_movement_cell_floor_mismatch'),'Invalid interior cell transition rejects disconnected portal or wrong original floor')
  report['passed']=True
 finally:
  if session:
   try:loc=snap();call('/session/logout',live_session_id=session,zone='tatooine',**pose(loc))
   except Exception:call('/combat/session/stop',session_id=session)
  if added and added in script.read_text():script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  path=ROOT/'runtime/evidence/movement-native-smoke.json';path.write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']),evidence=str(path))),flush=True)
if __name__=='__main__':main()
