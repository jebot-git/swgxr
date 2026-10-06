#!/usr/bin/env python3
"""Local Core3 factory acceptance on an isolated invtest fixture, no headset."""
import json, os, secrets, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/server'))
from equipment_smoke import console
import services_smoke
services_smoke.BASE=os.environ.get("SWGXR_FACTORY_TEST_URL","http://127.0.0.1:18080")
from services_smoke import req, redact
PATH=ROOT/'runtime/server/factories-fixture.json'
TARGET=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
BACKUP=ROOT/'runtime/server/factories-tests-original.lua'
checks=[]; records=[]
def check(ok,label):
 checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
 if not ok:raise AssertionError(label)
def main():
 if '--resume-production' not in sys.argv:
  f={'account':'invtestfactory'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))}
  r=req('/characters',dict(f,species='human',profession='crafting_artisan'));f['id']=r['character']['id'];PATH.write_text(json.dumps(f))
 f=json.loads(PATH.read_text());assert f['account'].startswith('invtestfactory') and f['name'].startswith('Ivtest')
 base={'account':f['account'],'character_id':f['id'],'position':[4800,5,-4780],'building_id':'0','cell_index':0}
 query='?account='+f['account']+'&character_id='+f['id']
 def call(path,**kw):
  body=dict(base,request_id='factory_'+secrets.token_hex(12));body.update(kw)
  for attempt in range(5):
   r=req(path,body)
   if r.get('error')!='native_player_unavailable':break
   time.sleep(1)
  records.append({'path':path,'response':redact(r)})
  if r.get('http_error') or r.get('error'):print(json.dumps({'error':r.get('error'),'http_error':r.get('http_error')}),flush=True)
  else:r.setdefault('ok',True)
  return r
 def service(action,**kw):return call('/services/house_'+action,**kw)
 def inventory():
  for attempt in range(5):
   result=req('/inventory'+query)
   if 'items' in result:return result
   time.sleep(1)
  raise RuntimeError('Native inventory unavailable: '+str(result.get('error',result)))
 report={'passed':False,'native_execution':True,'tracking':'synthetic','gpu_validation':False,'checks':checks,'responses':records}
 code=''
 original=TARGET.read_bytes()
 if BACKUP.exists():raise RuntimeError('Restore unfinished factory fixture screenplay first')
 BACKUP.write_bytes(original)
 try:
  inventory()
  code=r'''
function Tests:swgxrFactoryFixture(oid,phase)
 if tonumber(oid)~=__ID__ then return end
 local player=getSceneObject(tonumber(oid));if player==nil then return end
 CreatureObject(player):setPvpStatusBitmask(0)
 for i=0,8 do CreatureObject(player):setHAM(i,CreatureObject(player):getMaxHAM(i)) end
 CreatureObject(player):setPosture(0);CreatureObject(player):clearCombatState(true)
 local inv=SceneObject(player):getSlottedObject("inventory")
 if phase=="setup" then
  awardSkill(player,"crafting_artisan_novice")
  for i=1,4 do awardSkill(player,"crafting_artisan_engineering_0"..i) end
  giveItem(inv,"object/tangible/crafting/station/weapon_tool.iff",-1)
  giveItem(inv,"object/tangible/deed/factory_deed/factory_item_deed.iff",-1)
  for i=1,12 do givePlayerResource(player,"mineral",2000) end
  givePlayerResource(player,"chemical",2000)
  givePlayerResource(player,"solar",10000)
  giveItem(inv,"object/tangible/food/foraged/foraged_fruit_s1.iff",-1)
  CreatureObject(player):addCashCredits(20000,true)
  local station=spawnSceneObject("tatooine","object/tangible/crafting/station/weapon_station.iff",4800,5,-4779,0,0,0,0,1)
  if station~=nil then writeData("swgxr_factory_station",SceneObject(station):getObjectID()) end
 elseif phase=="fuel" then
  givePlayerResource(player,"solar",10000)
 elseif phase=="cleanup" then
  local station=getSceneObject(readData("swgxr_factory_station"));if station~=nil then SceneObject(station):destroyObjectFromWorld();SceneObject(station):destroyObjectFromDatabase() end
 end
end
'''.replace('__ID__',f['id'])
  TARGET.write_bytes(original+code.encode());console('reloadscreenplays');time.sleep(.5)
  def operation(action,**kw):return service('factory_'+action,structure_id=factory_id,**kw)
  if '--resume-production' in sys.argv:
   previous=json.loads((ROOT/'runtime/evidence/factories-native.json').read_text())
   checks.extend(row for row in previous['checks'] if row['passed']);records.extend(previous['responses'])
   factory_id=previous['factory_id'];report['factory_id']=factory_id
   deed={'id':next(x['response']['mutation']['deed_id'] for x in previous['responses'] if x['path']=='/services/house_preview')}
   factory=next(x for x in service('status')['state']['housing']['structures'] if x['id']==factory_id);base['position']=factory['position']
   console('runLuaFunction Tests:swgxrFactoryFixture:'+f['id']+':fuel');time.sleep(.5)
  else:
   console('runLuaFunction Tests:swgxrFactoryFixture:'+f['id']+':setup');time.sleep(.5)
   inv=inventory();tool=next(i for i in inv['items'] if i['template'].endswith('weapon_tool.iff'))
   r=call('/crafting/open',tool_id=tool['id']);sid=r['state']['session_id'];recipe=next(i for i in r['state']['schematics'] if i['template'].endswith('pistol_cdef.iff'))
   r=call('/crafting/select',tool_id=tool['id'],session_id=sid,index=recipe['index']);s=r['state']
   allocations=[[next(i['id'] for i in s['inventory'] if slot['index'] in i['slots'] and i['quantity']>=slot['quantity'])] for slot in s['schematic']['slots']]
   r=call('/crafting/assemble',tool_id=tool['id'],session_id=sid,allocations=allocations)
   check(r.get('state',{}).get('can_create_blueprint',False),'Native station enables factory blueprint creation')
   r=call('/crafting/finish',tool_id=tool['id'],session_id=sid,output='blueprint',manufacture_limit=2,points=[],colors=[])
   check(r.get('ok') and not r['state']['jobs'],'Native crafting produces blueprint without prototype timer')
   s=service('status')['state']['housing'];blueprint=s['blueprints'][-1];deed=next(i for i in s['deeds'] if i['type']=='factory_deed')
   report['blueprint_id']=blueprint['id']
   point=[4805,5,-4780]
   r=service('preview',deed_id=deed['id'],placement_position=point,rotation=0)
   check(r.get('mutation',{}).get('valid',False),'Original factory deed passes native placement preview')
   r=service('place',deed_id=deed['id'],placement_position=point,rotation=0)
   check(r.get('ok'),'Native factory construction starts')
   deadline=time.monotonic()+90;factory=None
   while time.monotonic()<deadline:
    s=service('status')['state']['housing'];factory=next((i for i in s['structures'] if i.get('factory') and i['owner_id']==f['id']),None)
    if factory:break
    time.sleep(1)
   check(factory is not None,'Native construction completes with owned factory')
   factory_id=factory['id'];report['factory_id']=factory_id;base['position']=factory['position']
   r=operation('blueprint',item_id=blueprint['id'])
   check(r.get('mutation',{}).get('factory',{}).get('blueprint',{}).get('id')==blueprint['id'],'Native source blueprint installs')
   bad=next(i for i in inventory()['items'] if '/foraged/' in i['template'])
   check(operation('input',item_id=bad['id']).get('http_error')==400,'Unrelated item rejected by source blueprint')
   ingredient_ids=list(dict.fromkeys(i for row in allocations for i in row))
   for item_id in ingredient_ids:
    check(operation('input',item_id=item_id).get('ok'),'Owned exact source ingredient enters hopper '+item_id)
   r=operation('withdraw',item_id=ingredient_ids[0]);check(r.get('ok'),'Input resource pulls back into native inventory')
   check(operation('input',item_id=ingredient_ids[0]).get('ok'),'Withdrawn resource reinserts')
   receipt='factory_deposit_'+secrets.token_hex(10)
   r=operation('deposit',amount=10000,request_id=receipt);check(r.get('ok'),'Native maintenance deposit succeeds')
   paid=r['mutation']['factory']['maintenance'];again=operation('deposit',amount=10000,request_id=receipt)
   check(again.get('mutation',{}).get('replayed') and again['mutation']['factory']['maintenance']==paid,'Retry receipt does not charge upkeep twice')
  energy=next(i for i in inventory()['items'] if '/energy_' in i['template'])
  check(operation('power',item_id=energy['id']).get('ok'),'Dragged energy stack fuels native factory')
  check(operation('active',active=True).get('ok'),'Native manufacturing task starts')
  deadline=time.monotonic()+150;out=[]
  while time.monotonic()<deadline:
   r=operation('status');out=r.get('mutation',{}).get('factory',{}).get('output',[])
   if out:break
   time.sleep(2)
  check(bool(out),'Native factory timer produces original output crate')
  operation('active',active=False)
  check(operation('collect',item_id=out[0]['id']).get('ok'),'Output crate pulls into native inventory')
  r=operation('status');detail=r['mutation']['factory']
  for item in detail['input']:check(operation('withdraw',item_id=item['id']).get('ok'),'Remaining input returns to inventory')
  if detail['blueprint']:check(operation('remove_blueprint').get('ok'),'Source blueprint returns to native datapad')
  receipt='factory_recover_'+secrets.token_hex(10)
  r=operation('recover',left_hand=base['position'],right_hand=base['position'],request_id=receipt)
  check(r.get('mutation',{}).get('recovered_deed_id')==deed['id'],'Both-hand recovery returns original deed after emptying factory')
  replay=operation('recover',left_hand=base['position'],right_hand=base['position'],request_id=receipt)
  check(replay.get('mutation',{}).get('replayed') and replay['mutation']['recovered_deed_id']==deed['id'],'Recovery receipt replays after native structure removal')
  check(any(i['id']==deed['id'] for i in inventory()['items']),'Recovered deed persists across a fresh inventory session')
  report['passed']=True
 except Exception as error:
  report['error']=str(error);raise
 finally:
  console('runLuaFunction Tests:swgxrFactoryFixture:'+f['id']+':cleanup')
  current=TARGET.read_bytes()
  if code and code.encode() in current:TARGET.write_bytes(current.replace(code.encode(),b'',1))
  BACKUP.unlink();console('reloadscreenplays')
  evidence=ROOT/'runtime/evidence/factories-native.json'
  if evidence.exists() and checks:evidence.replace(evidence.with_name('factories-native.previous.json'))
  if checks:evidence.write_text(json.dumps(report,indent=2))
  print(json.dumps({'passed':report['passed'],'checks':len(checks)}),flush=True)
if __name__=='__main__':main()
