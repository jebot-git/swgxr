#!/usr/bin/env python3
"""Native pilot conversations, chassis redemption and component transactions on an explicitly named isolated invtest fixture.

Run on the test server as its maintenance user. Test ingredients/skills are
provisioned only to that fixture; hulls and components must use original native ship services.
"""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--crafted',type=Path,required=True);a=p.parse_args()
 os.umask(0o077);f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and str(f['id']).isdigit()
 checks=[];samples=[];sid='';player={};original=None
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
  return call('/services/'+action,{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'request_id':uuid.uuid4().hex,**extra},required)
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 lua='''
function Tests:swgxrShipServices(mode)
 local p=getSceneObject(__ID__)
 if p==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if mode=="setup" then
  SceneObject(p):switchZone("tatooine",3600,5,-4780,0)
  local dealer=spawnMobile("tatooine","chassis_dealer",0,3601,5,-4780,0,0)
  local trainer=spawnMobile("tatooine","dinge",0,3599,5,-4780,0,0)
  if dealer==nil or trainer==nil then return "spawn_failed" end
  writeData("swgxrServiceDealer",SceneObject(dealer):getObjectID())
  writeData("swgxrServiceTrainer",SceneObject(trainer):getObjectID())
  CreatureObject(p):addCashCredits(1000000,true)
  return "dealer:"..readData("swgxrServiceDealer")..":trainer:"..readData("swgxrServiceTrainer")
 elseif mode=="terminal" then
  awardSkill(p,"pilot_rebel_navy_novice")
  local ghost=CreatureObject(p):getPlayerObject();PlayerObject(ghost):addAbility("cert_starships_z95headhunter")
  local t=getSceneObject(1279066)
  local x=SceneObject(t):getPositionX();local z=SceneObject(t):getPositionZ();local y=SceneObject(t):getPositionY();local cell=SceneObject(t):getParentID()
  SceneObject(p):switchZone("tatooine",x,z,y+1,cell)
  return "ready"
 elseif mode=="components" then
  local inv=SceneObject(p):getSlottedObject("inventory");local rows={}
  for _,pair in ipairs({{0,"rct_incom_mark1"},{1,"eng_koensayr_small_ionjet"},{2,"shd_armek_plasma_shell_s1"},{4,"arm_corellian_light_durasteel"},{5,"arm_corellian_light_durasteel"},{6,"cap_novaldex_small_capacitor"},{12,"wpn_incom_light_blaster"}}) do
   local key="swgxrFixtureComponent_"..pair[1];local id=readData(key)
   if id==0 or getSceneObject(id)==nil then id=createLoot(inv,pair[2],1,true);writeData(key,id) end
   table.insert(rows,pair[1]..":"..id)
  end
  return table.concat(rows,",")
 elseif mode=="cleanup" then
  for _,key in ipairs({"swgxrServiceDealer","swgxrServiceTrainer"}) do
   local n=getSceneObject(readData(key));if n~=nil then SceneObject(n):destroyObjectFromWorld();SceneObject(n):destroyObjectFromDatabase() end
   deleteData(key)
  end
  return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__NAME__',f['name'].split()[0].lower())
 previous=json.loads(a.output.read_text()) if a.output.is_file() else {}
 report={'passed':False,'live_core3':True,'fixture_id':f['id'],'checks':checks,'samples':samples}
 try:
  crafted=json.loads(a.crafted.read_text());check(crafted['passed'] and crafted['fixture_id']==f['id'],'Use chassis actually delivered by native crafting')
  chassis=crafted['crafted_chassis_id'];r=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]});sid=r['session_id']
  call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  original=script.read_text();script.write_text(original+lua);console('reloadscreenplays')
  setup=console('runLuaFunction Tests:swgxrShipServices:setup');dealer=re.search(r'dealer:(\d+)',setup)[1];trainer=re.search(r'trainer:(\d+)',setup)[1]
  call('/jtl/status',{})
  started=service('pilot_begin',terminal_id=trainer);view=started['state']['terminal'];samples.append({'pilot_begin':view})
  check(view['kind']=='pilot_trainer','Original pilot trainer conversation opens')
  if view['screen_id']=='recruitment':
   bad=service('pilot_choose',required=False,terminal_id=trainer,screen_token='stale_screen',option=0)
   check(bad.get('http_error') or bad.get('ok') is False,'Stale trainer screen cannot choose or grant skills')
   key=uuid.uuid4().hex;details=dict(terminal_id=trainer,screen_token=view['screen_token'],option=0,request_id=key)
   chosen=service('pilot_choose',**details);view=chosen['state']['terminal'];samples.append({'enlisted':view})
   check(view['screen_id']=='yes_enlist','Original conversation handler enlists the fixture')
   replay=service('pilot_choose',**details);check(replay['mutation'].get('replayed') is True,'Trainer retry returns receipt without repeating side effects')
   for _ in range(5):
    if view['screen_id']=='yes_im_ready':break
    chosen=service('pilot_choose',terminal_id=trainer,screen_token=view['screen_token'],option=0);view=chosen['state']['terminal'];samples.append({'pilot_next':view})
   check(view['screen_id']=='yes_im_ready','Native trainer starts original first patrol mission')
  jtl=call('/jtl/status',{})['state'];check(bool(jtl.get('missions')),'Original space quest appears in native journal snapshot')
  if previous.get('crafted_ship_id') and previous.get('fixture_id')==f['id']:
   ship=next(s for s in jtl['ships'] if s['id']==previous['crafted_ship_id']);report['prior_redemption_checks']=previous['checks']
  else:
   opened=service('open',terminal_id=dealer);option=next(o for o in opened['state']['terminal']['options'] if o['item_id']==chassis)
   samples.append({'dealer':opened['state']})
   before_cash=opened['state']['wallet']['cash'];key=uuid.uuid4().hex
   redeemed=service('ship_chassis_redeem',terminal_id=dealer,item_id=chassis,price=option['price'],request_id=key);samples.append({'redeemed':redeemed['state']})
   check(redeemed['state']['wallet']['cash']==before_cash-option['price'],'Chassis dealer charges exact original native fee')
   replay=service('ship_chassis_redeem',terminal_id=dealer,item_id=chassis,price=option['price'],request_id=key)
   check(replay['state']['wallet']['cash']==redeemed['state']['wallet']['cash'],'Redemption retry does not charge twice')
   deed=next(o for o in redeemed['state']['terminal']['options'] if o['operation']=='ship_register')
   before_ids={s['id'] for s in jtl['ships']}
   registered=service('ship_register',terminal_id=dealer,item_id=deed['item_id']);jtl=call('/jtl/status',{})['state'];ship=next(s for s in jtl['ships'] if s['id'] not in before_ids)
   check(ship['template'].endswith('/player_z95.iff'),'Crafted token becomes native deed and owned Z-95 hull')
  report['crafted_ship_id']=ship['id']
  check(console('runLuaFunction Tests:swgxrShipServices:terminal')=='ready','Fixture moved to original starship terminal')
  call('/jtl/status',{});terminal='1279066'
  call('/session/update',{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
  components=[tuple(map(int,pair.split(':'))) for pair in console('runLuaFunction Tests:swgxrShipServices:components').split(',')]
  report['components_source']='Original Core3 loot item fixtures; this is not a combat loot test'
  for slot,component in components:
   component=str(component)
   outfit=service('ship_manage',terminal_id=terminal,ship_id=ship['id'])['state']['terminal']
   if not any(o['operation']=='ship_component_remove' and o['component_id']==component for o in outfit['options']):
    check(any(o['operation']=='ship_component_install' and o['component_id']==component and o['slot']==slot for o in outfit['options']),'Native compatibility lists fixture component in correct slot')
    installed=service('ship_component_install',terminal_id=terminal,ship_id=ship['id'],component_id=component,slot=slot)
    check(any(o['operation']=='ship_component_remove' and o['component_id']==component for o in installed['state']['terminal']['options']),'Native component installs into crafted hull')
   key=uuid.uuid4().hex;details=dict(terminal_id=terminal,ship_id=ship['id'],component_id=component,slot=slot,request_id=key)
   service('ship_component_remove',**details)
   repeated=service('ship_component_remove',**details);check(repeated['mutation'].get('replayed') is True,'Component removal retry is idempotent')
   installed=service('ship_component_install',terminal_id=terminal,ship_id=ship['id'],component_id=component,slot=slot)
   check(any(o['operation']=='ship_component_remove' and o['component_id']==component for o in installed['state']['terminal']['options']),'Removed component reinstalls through original native command')
  report['passed']=True
 except Exception as e:report['error']=str(e);raise
 finally:
  if original is not None:
   try:console('runLuaFunction Tests:swgxrShipServices:cleanup')
   finally:script.write_text(original);console('reloadscreenplays')
  if sid:call('/combat/session/stop',{},False)
  a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
