#!/usr/bin/env python3
"""Disposable Core3 scout fixture; original media and native objects only."""
import json,secrets,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
path=ROOT/'runtime/server/scout-fixture.json';target=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';backup=ROOT/'runtime/server/scout-tests-original.lua'
if '--restore' in sys.argv:
 if backup.exists():target.write_bytes(backup.read_bytes());backup.unlink();console('reloadscreenplays')
 raise SystemExit()
if not path.exists():
 account='invtestscout'+secrets.token_hex(3);name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))
 created=request('/characters',{'account':account,'name':name,'species':'human','profession':'outdoors_scout'})['character']
 path.write_text(json.dumps({'account':account,'id':created['id'],'name':name}))
f=json.loads(path.read_text());assert f['account'].startswith('invtestscout')
request('/inventory?account='+f['account']+'&character_id='+f['id'])
if not backup.exists():backup.write_bytes(target.read_bytes())
code='''
function Tests:swgxrScoutFixture(oid)
 if tonumber(oid)~=__ID__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):setPosture(0)
 CreatureObject(p):clearCombatState(true)
 awardSkill(p,"outdoors_scout_novice")
 for _,branch in ipairs({"movement","tools","harvest","camp"}) do for level=1,4 do awardSkill(p,"outdoors_scout_"..branch.."_0"..level) end end
 awardSkill(p,"outdoors_scout_master")
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/tangible/scout/camp/camp_basic.iff",-1)
 giveItem(inv,"object/tangible/scout/trap/trap_webber.iff",-1)
 giveItem(inv,"object/tangible/scout/trap/trap_noise_maker.iff",-1)
 CreatureObject(p):addCooldown("burstrun",0)
 CreatureObject(p):addCooldown("throwtrap",0)
 CreatureObject(p):addCooldown("skill_buff_mask_scent_self",0)
 local animal=spawnMobile("tatooine","worrt",0,5008,180,-5400,0,0)
 if animal~=nil then writeData("swgxr_scout_fixture_mob",SceneObject(animal):getObjectID()) end
end
'''.replace('__ID__',f['id'])
target.write_text(backup.read_text()+code);console('reloadscreenplays');time.sleep(.5);console('runLuaFunction Tests:swgxrScoutFixture:'+f['id']);print(json.dumps(f))
