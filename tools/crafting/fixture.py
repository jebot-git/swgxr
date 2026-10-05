#!/usr/bin/env python3
"""Isolated native artisan fixture; never edits normal player possessions."""
import json,secrets,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
PATH=ROOT/'runtime/server/artisan-fixture.json'
TARGET=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
BACKUP=ROOT/'runtime/server/artisan-tests-original.lua'
if '--restore' in sys.argv:
 if BACKUP.exists():TARGET.write_bytes(BACKUP.read_bytes());BACKUP.unlink();console('reloadscreenplays')
 raise SystemExit()
if not PATH.exists():
 account='invtestcraft'+secrets.token_hex(3);name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))
 created=request('/characters',{'account':account,'name':name,'species':'human','profession':'crafting_artisan'})['character'];PATH.write_text(json.dumps({'account':account,'id':created['id'],'name':name}))
f=json.loads(PATH.read_text());assert f['account'].startswith('invtestcraft') and f['name'].startswith('Ivtest')
request('/inventory?account='+f['account']+'&character_id='+f['id'])
if not BACKUP.exists():BACKUP.write_bytes(TARGET.read_bytes())
code='''
function Tests:swgxrArtisanFixture(oid,phase)
 if tonumber(oid)~=__ID__ then return end
 local player=getSceneObject(tonumber(oid));if player==nil then return end
 local inv=SceneObject(player):getSlottedObject("inventory")
 if phase=="setup" then
  awardSkill(player,"crafting_artisan_novice")
  awardSkill(player,"crafting_artisan_engineering_01")
  awardSkill(player,"crafting_artisan_engineering_02")
  awardSkill(player,"crafting_artisan_engineering_03")
  awardSkill(player,"crafting_artisan_engineering_04")
  for i=1,2 do giveItem(inv,"object/tangible/crafting/station/weapon_tool.iff",-1) end
  for i=1,25 do givePlayerResource(player,"mineral",500) end
  givePlayerResource(player,"chemical",500)
  local station=spawnSceneObject("tatooine","object/tangible/crafting/station/weapon_station.iff",3600,5,-4779,0,0,0,0,1)
  if station~=nil then writeData("swgxr_artisan_station",SceneObject(station):getObjectID()) end
 elseif phase=="component" then
  giveItem(inv,"object/tangible/bug_jar/sample_bugs.iff",-1)
 elseif phase=="station" then
  local station=spawnSceneObject("tatooine","object/tangible/crafting/station/weapon_station.iff",3600,5,-4779,0,0,0,0,1)
  if station~=nil then writeData("swgxr_artisan_station",SceneObject(station):getObjectID()) end
 elseif phase=="fill" then
  for i=1,80 do if SceneObject(inv):getContainerObjectsSize()>=80 then break end;giveItem(inv,"object/tangible/food/foraged/foraged_fruit_s3.iff",-1) end
 elseif phase=="clear" then
  for i=SceneObject(inv):getContainerObjectsSize()-1,0,-1 do
   local item=SceneObject(inv):getContainerObject(i)
   if SceneObject(item):getTemplateObjectPath()=="object/tangible/food/foraged/foraged_fruit_s3.iff" then SceneObject(item):destroyObjectFromWorld();SceneObject(item):destroyObjectFromDatabase() end
  end
 elseif phase=="cleanup" then
  local station=getSceneObject(readData("swgxr_artisan_station"));if station~=nil then SceneObject(station):destroyObjectFromWorld();SceneObject(station):destroyObjectFromDatabase() end
 end
end
'''.replace('__ID__',f['id'])
TARGET.write_text(BACKUP.read_text()+code);console('reloadscreenplays');time.sleep(.5)
phase=sys.argv[1] if len(sys.argv)>1 else 'setup';console('runLuaFunction Tests:swgxrArtisanFixture:'+f['id']+':'+phase);print(json.dumps(f))
