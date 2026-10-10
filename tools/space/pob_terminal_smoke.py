#!/usr/bin/env python3
"""Native POB terminal furniture recovery on an explicitly named isolated invtest fixture.

Run on the test server as its maintenance user. Test ingredients/skills are
provisioned only to that fixture; recovery must move the existing native object through permission checks.
"""
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
 lua='''
function Tests:swgxrPobFixture(mode)
 local p=getSceneObject(__ID__)
 if p==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if mode=="terminal" then
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",x,z,y+1,cell);return "ready"
 elseif mode=="inspect" then
  local t=getSceneObject(1279066)
  return "range="..tostring(SceneObject(p):isInRangeWithObject(t,8)).." cell="..SceneObject(p):getParentID().." target_cell="..SceneObject(t):getParentID().." combat="..tostring(CreatureObject(p):isInCombat()).." mount="..tostring(CreatureObject(p):isRidingMount()).." zone="..SceneObject(p):getZoneName()
 elseif mode=="cleanup" then
  local i=getSceneObject(readData("swgxrPobFixtureItem"));if i~=nil then SceneObject(i):destroyObjectFromWorld();SceneObject(i):destroyObjectFromDatabase() end
  deleteData("swgxrPobFixtureItem");return "clean"
 else
  local target,side=string.match(mode,"^(%d+)%-(%d+)$");local t=getSceneObject(tonumber(target));if t==nil then return "missing_terminal" end
  local s=SceneObject(t):getRootParent();if s==nil or ShipObject(s):getOwnerID()~=__ID__ then return "owner_failed" end
  local cell=SceneObject(t):getParentID()
  local zone=SceneObject(s):getZoneName();local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY()
  local n=tonumber(side);local dx=({1,-1,0,0,6})[n];local dy=({0,0,1,-1,0})[n]
  SceneObject(p):switchZone(zone,x+dx,z,y+dy,cell)
  local i=getSceneObject(readData("swgxrPobFixtureItem"))
  if i==nil then i=giveItem(getSceneObject(cell),"object/tangible/furniture/all/frn_all_chair_kitchen_s1.iff",-1) end
  if i==nil then return "item_failed" end
  SceneObject(i):setPosition(x+2,z,y)
  writeData("swgxrPobFixtureItem",SceneObject(i):getObjectID())
  local pr=SceneObject(p):getRootParent();local tr=SceneObject(t):getRootParent()
  return tostring(SceneObject(i):getObjectID()).." range="..tostring(SceneObject(p):isInRangeWithObject(t,4)).." player_cell="..SceneObject(p):getParentID().." terminal_cell="..SceneObject(t):getParentID().." player_root="..SceneObject(pr):getObjectID().." terminal_root="..SceneObject(tr):getObjectID()

 end
end
'''.replace('__ID__',str(f['id'])).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'fixture_id':f['id'],'checks':checks,'fixture_controls':'Original furniture placed in yacht cell by fixture; recovery and replay are native'}
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');check(console('runLuaFunction Tests:swgxrPobFixture:terminal')=='ready','Fixture at original launch terminal')
  state=act('status')['state'];yacht=next(s for s in state['ships'] if s['template'].endswith('/player_sorosuub_space_yacht.iff'))
  report['yacht_before']=yacht
  call('/session/update',{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  report['at_terminal']=console('runLuaFunction Tests:swgxrPobFixture:inspect');print(report['at_terminal'],flush=True);report['player_before']=player
  staged=act('crew_prepare',terminal_id='1279066',ship_id=yacht['id'])['state']['launch_stage'];state=act('launch',terminal_id='1279066',launch_id=staged['id'])['state']
  terminal=next(t for t in state['ship']['interactions'] if t['command_id']=='pob_terminal')
  act('leave');opened=None
  for side in range(1,5):
   info=console('runLuaFunction Tests:swgxrPobFixture:'+terminal['id']+'-'+str(side));print(info,flush=True);item=info.split(' ')[0];check(item.isdigit(),'Original floor furniture fixture in owned yacht')
   result=act('terminal',required=False,terminal_id=terminal['id']);report.setdefault('attempts',[]).append({'info':info,'result':result,'terminal':terminal})
   if result.get('ok'):opened=result;break
  check(opened is not None,'Original POB terminal reachable from an unobstructed side')
  check(any(x['id']==item for x in opened['state']['ship']['decorations']),'POB terminal lists actual placed item')
  invalid=act('terminal_recover',required=False,terminal_id=terminal['id'],item_id=terminal['id']);check(invalid.get('ok') is False or invalid.get('http_error'),'Fixed POB terminal cannot be recovered')
  key=uuid.uuid4().hex;payload={'request_id':key,'terminal_id':terminal['id'],'item_id':item}
  recovered=call('/jtl/terminal_recover',payload)
  check(sum(x['id']==item for x in recovered['inventory']['items'])==1 and not any(x['id']==item for x in recovered['state']['ship']['decorations']),'POB terminal transfers exactly one original item to inventory')
  repeated=call('/jtl/terminal_recover',payload);check(repeated['mutation'].get('replayed') and sum(x['id']==item for x in repeated['inventory']['items'])==1,'POB terminal recovery replay does not duplicate furniture')
  console('runLuaFunction Tests:swgxrPobFixture:'+terminal['id']+'-5')
  distant=act('terminal',required=False,terminal_id=terminal['id']);check(distant.get('error_code')=='jtl_pob_terminal_out_of_reach','POB terminal remains unavailable beyond native reach')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:console('runLuaFunction Tests:swgxrPobFixture:cleanup')
   finally:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  report['latencies']=latencies;a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
