#!/usr/bin/env python3
"""Native Shipwright transactions on an explicitly named isolated invtest fixture.

Run on the test server as its maintenance user. Test ingredients/skills are
provisioned only to that fixture; outputs must come from CraftingSession.
"""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--assemble-only',action='store_true');a=p.parse_args()
 os.umask(0o077);f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and str(f['id']).isdigit()
 checks=[];samples=[];sid='';craft_sid='';tool='';player={};original=None
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True);assert ok,label
 def call(path,data=None,required=True):
  nonlocal player
  body=None if data is None else {'account':f['account'],'character_id':f['id'],'session_id':sid,**data}
  req=urllib.request.Request('http://127.0.0.1:18080'+path,None if body is None else json.dumps(body).encode(),{'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=90) as r:value=json.load(r)
  except urllib.error.HTTPError as e:value={'http_error':e.code,**json.load(e)}
  player=value.get('live_response',value).get('snapshot',{}).get('player',player)
  if required and (value.get('http_error') or value.get('ok') is False):raise AssertionError((path,value.get('error'),value.get('error_code')))
  return value
 def craft(action,required=True,**extra):
  data={'request_id':uuid.uuid4().hex,'tool_id':tool,'session_id':craft_sid,'live_session_id':sid,'zone':'tatooine','position':player.get('position',[3600,5,-4780]),'building_id':player.get('building_id','0'),'cell_index':player.get('cell_index',0),**extra}
  return call('/crafting/'+action,data,required)
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
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 lua='''
function Tests:swgxrShipwrightFixture(mode)
 local p=getSceneObject(__ID__)
 if p==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 local inv=SceneObject(p):getSlottedObject("inventory")
 if mode=="setup" then
  SceneObject(p):switchZone("tatooine",3600,5,-4780,0)
  for _,skill in ipairs({"crafting_artisan_novice","crafting_artisan_engineering_01","crafting_artisan_engineering_02","crafting_artisan_engineering_03","crafting_artisan_engineering_04","crafting_shipwright_novice"}) do awardSkill(p,skill) end
  for _,branch in ipairs({"engineering","propulsion","systems","defense"}) do for level=1,4 do awardSkill(p,"crafting_shipwright_"..branch.."_0"..level) end end
  awardSkill(p,"crafting_shipwright_master")
  local haveTool=false;local resources=0
  local count=SceneObject(inv):getContainerObjectsSize()
  for i=0,count-1 do
   local item=SceneObject(inv):getContainerObject(i)
   local template=SceneObject(item):getTemplateObjectPath()
   if template=="object/tangible/crafting/station/space_tool.iff" then haveTool=true end
   if string.find(template,"object/resource_container/",1,true) then resources=resources+1 end
  end
  if not haveTool then giveItem(inv,"object/tangible/crafting/station/space_tool.iff",-1) end
  if resources<30 then
   for i=1,30 do givePlayerResource(p,"mineral",10000) end
   for i=1,8 do givePlayerResource(p,"chemical",10000) end
  end
  local station=spawnSceneObject("tatooine","object/tangible/crafting/station/space_station.iff",3601,5,-4780,0,0,0,0,1)
  if station==nil then return "station_failed" end
  writeData("swgxrShipwrightStation",SceneObject(station):getObjectID())
  return "ready"
 elseif mode=="cleanup" then
  local station=getSceneObject(readData("swgxrShipwrightStation"));if station~=nil then SceneObject(station):destroyObjectFromWorld();SceneObject(station):destroyObjectFromDatabase() end
  deleteData("swgxrShipwrightStation");return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__NAME__',f['name'].split()[0].lower())
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'checks':checks,'samples':samples}
 try:
  r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays');check(console('runLuaFunction Tests:swgxrShipwrightFixture:setup')=='ready','Isolated native Shipwright fixture provisioned')
  inventory=call('/inventory?account='+f['account']+'&character_id='+f['id']);tool=next(x['id'] for x in inventory['items'] if x['template'].endswith('/space_tool.iff'))
  state=craft('open')['state'];craft_sid=state['session_id'];samples.append({'schematics':state['schematics']})
  choice=next(x for x in state['schematics'] if x['template'].endswith('/z95_chassis_token.iff'))
  check(bool(state.get('station_id')),'Native space station enables Shipwright experimentation')
  state=craft('select',index=choice['index'])['state'];samples.append({'selected':state})
  reserved={};allocations=[]
  for slot in state['schematic']['slots']:
   item=next(x for x in state['inventory'] if slot['index'] in x['slots'] and x['quantity']-reserved.get(x['id'],0)>=slot['quantity']);allocations.append([item['id']]);reserved[item['id']]=reserved.get(item['id'],0)+slot['quantity']
  assembled=craft('assemble',allocations=allocations);state=assembled['state'];samples.append({'assembled':state})
  check(state['stage']==3 and state['points']>0 and bool(state['rows']),'Native chassis assembly exposes experimentation points and attributes')
  if a.assemble_only:
   craft('cancel');report['passed']=True;return
  for attempt in range(2):
   allocation=[0]*len(state['rows']);index=next(i for i,r in enumerate(state['rows']) if r['point_limit']>0);allocation[index]=1
   key=uuid.uuid4().hex;before=state['points'];result=craft('experiment',points=allocation,request_id=key);state=result['state'];samples.append({'round':attempt,'state':state,'mutation':result['mutation']})
   check(state['stage']==3 and state['points']==before-1,'Experimentation round consumes one native point without finalizing')
   replay=craft('experiment',points=allocation,request_id=key)
   check(replay['state']['points']==state['points'] and replay['state']['statistics']==state['statistics'],'Experimentation retry does not reroll or consume twice')
  bad=craft('experiment',required=False,points=[10]*len(state['rows']));check(bad.get('http_error') or bad.get('ok') is False,'Overspent native experimentation is rejected')
  result=craft('finish',points=[],colors=[]);job=next(j for j in result['state']['jobs'] if j['tool_id']==tool);samples.append({'job':job})
  deadline=time.monotonic()+job['duration']+30
  while time.monotonic()<deadline:
   state=craft('status')['state']
   if not any(j['prototype_id']==job['prototype_id'] for j in state['jobs']):break
   time.sleep(2)
  inventory=call('/inventory?account='+f['account']+'&character_id='+f['id']);product=next(x for x in inventory['items'] if x['id']==job['prototype_id']);samples.append({'product':product})
  check(product['template'].endswith('/z95_chassis_token.iff'),'Native crafting timer delivers the original Z-95 chassis token')
  check(bool(product.get('attributes')),'Crafted chassis exposes its native mass, hitpoints and crafting identity')
  report['crafted_chassis_id']=product['id'];report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:
    if craft_sid:craft('cancel',required=False)
    console('runLuaFunction Tests:swgxrShipwrightFixture:cleanup')
   finally:
    script.write_text(original);console('reloadscreenplays')
    if sid:call('/combat/session/stop',{},False)
  a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
