#!/usr/bin/env python3
"""Native junk sales on an isolated invtest fixture; supplied test items are disposable."""
import argparse,json,re,secrets,time,urllib.parse
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18088);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 fixture=ROOT/'runtime/server/junk-fixture.json'
 if fixture.exists():f=json.loads(fixture.read_text())
 else:
  f=dict(account='invtestjunk'+secrets.token_hex(4),name='Jktest'+''.join(secrets.choice('aeilnorstu') for _ in range(9)))
  response=shared.req('/characters',dict(f,species='human',profession='crafting_artisan'));assert 'character' in response,response
  f['id']=response['character']['id'];fixture.write_text(json.dumps(f))
 assert f['account'].startswith('invtestjunk') and str(f['id']).isdigit()
 base=dict(account=f['account'],character_id=f['id']);checks=[];completed=False;session='';responses=[]
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 def check(value,label):
  checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True);assert value,label
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:corecuJunkFixture:'+mode)
  for _ in range(200):
   with log.open() as stream:stream.seek(offset);text=stream.read()
   match=re.search(r'runLuaFunction Tests:corecuJunkFixture: result=\[(.*?)\]',text)
   if match:return match[1]
   time.sleep(.05)
  raise AssertionError('Fixture timeout '+mode)
 def call(path,**kw):return shared.req(path,dict(base,**kw))
 def service(action,**kw):
  kw.setdefault('request_id','junk_'+secrets.token_hex(12))
  result=call('/services/'+action,session_id=session,**kw);responses.append(shared.redact(result))
  if not result.get('ok'):print(action,result.get('error'),flush=True)
  return result
 added=f'''
function Tests:corecuJunkFixture(mode)
 local p=getSceneObject({f['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{f['name']}" then return "bad_owner" end
 local key="swgxr_junk_fixture"
 local function obj(k) return getSceneObject(tonumber(readScreenPlayData(p,key,k)) or 0) end
 local function save(k,o) if o~=nil then writeScreenPlayData(p,key,k,tostring(SceneObject(o):getObjectID())) end return o end
 if mode=="setup" then
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",5900,getTerrainHeight(p,5900,-4804),-4804,0)
  local npc=save("npc",spawnMobile("tatooine","junk_dealer",0,5901,getTerrainHeight(p,5901,-4804),-4804,0,0))
  AiAgent(npc):addObjectFlag(AI_STATIC)
  local inv=SceneObject(p):getSlottedObject("inventory")
  for _,k in ipairs({{"a","b","c"}}) do save(k,giveItem(inv,"object/tangible/loot/collectible/collectible_rewards/orange_rug.iff",-1)) end
  local bag=save("bag",giveItem(inv,"object/tangible/container/drum/tatt_drum_1.iff",-1))
  save("nested",giveItem(bag,"object/tangible/loot/collectible/collectible_rewards/orange_rug.iff",-1))
  return tostring(SceneObject(npc):getObjectID())
 elseif mode=="finery" then AiAgent(obj("npc")):setConvoTemplate("junkDealerFineryConvoTemplate");return "ok"
 elseif mode=="generic" then AiAgent(obj("npc")):setConvoTemplate("junkDealerGenericConvoTemplate");return "ok"
 elseif mode=="cleanup" then
  for _,k in ipairs({{"a","b","c","nested","bag","npc"}}) do local o=obj(k);if o~=nil then SceneObject(o):destroyObjectFromWorld();SceneObject(o):destroyObjectFromDatabase() end end
  return "ok"
 end
 return "unknown"
end
'''
 try:
  entered=call('/enter');loc=entered['source_location']
  start=call('/combat/session/start',**loc);session=start['session_id']
  script.write_text(original+added);console('reloadscreenplays');time.sleep(.3)
  npc=lua('setup');check(npc.isdigit(),'Disposable original junk dealer and loot provisioned')
  opened=service('open',terminal_id=npc);check(opened.get('ok'),'Native dealer opens')
  options=opened['state']['terminal']['options'];singles=[x for x in options if not x.get('all')]
  check(len(singles)==3 and all(x['price']==1000 for x in singles),'Original prices quoted; nested backpack item excluded')
  before=opened['state']['wallet']['cash'];quote=singles[0]['items'];bad=[dict(quote[0],price=1)]
  check(not service('junk_sell',terminal_id=npc,items=bad).get('ok'),'Forged price rejected')
  lua('finery');check(not service('open',terminal_id=npc)['state']['terminal']['options'],'Per-NPC finery override excludes generic junk')
  check(not service('junk_sell',terminal_id=npc,items=quote).get('ok'),'Changed dealer category invalidates old quote')
  lua('generic');key='junk_retry_'+secrets.token_hex(10)
  sold=service('junk_sell',terminal_id=npc,items=quote,request_id=key)
  check(sold.get('ok') and sold['state']['wallet']['cash']==before+1000 and sold['mutation']['sold_count']==1,'Native single sale removes item and credits cash')
  replay=service('junk_sell',terminal_id=npc,items=quote,request_id=key)
  check(replay.get('ok') and replay['mutation'].get('replayed') and replay['state']['wallet']['cash']==before+1000,'Repeated receipt cannot duplicate payment')
  check(not service('junk_sell',terminal_id=npc,items=quote).get('ok'),'New request cannot sell deleted item twice')
  opened=service('open',terminal_id=npc);bulk=next(x for x in opened['state']['terminal']['options'] if x.get('all'))
  sold=service('junk_sell',terminal_id=npc,items=bulk['items'])
  check(sold.get('ok') and sold['state']['wallet']['cash']==before+3000 and not sold['state']['terminal']['options'],'Sell all removes exactly reviewed eligible loot')
  completed=True
 finally:
  try:
   if script.read_text()!=original:lua('cleanup')
  finally:
   script.write_text(original);console('reloadscreenplays')
   if session:call('/combat/session/stop',session_id=session)
   (ROOT/'runtime/evidence/junk-dealer-native.json').write_text(json.dumps({'passed':completed,'checks':checks,'responses':responses,'fixture':f,'live_core3':True,'headset_tested':False},indent=2))
if __name__=='__main__':main()
