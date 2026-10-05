#!/usr/bin/env python3
"""Prepare isolated real Medic test characters; restores only its own Lua block."""
import json,secrets,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
path=ROOT/'runtime/server/medic-fixture.json';target=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
start='\n-- BEGIN SWGXR MEDIC TEST\n';end='-- END SWGXR MEDIC TEST\n'
if '--restore' in sys.argv:
 s=target.read_text()
 if start in s:s=s[:s.index(start)]+s[s.index(end)+len(end):];target.write_text(s);console('reloadscreenplays')
 raise SystemExit()
if not path.exists():
 records=[]
 for _ in range(2):
  account='invtestmedic'+secrets.token_hex(3);name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))
  created=request('/characters',{'account':account,'name':name,'species':'human','profession':'science_medic'})['character'];records.append({'account':account,'id':created['id'],'name':name})
 path.write_text(json.dumps(records))
f=json.loads(path.read_text());assert all(p['account'].startswith('invtestmedic') for p in f)
for p in f:request('/inventory?account='+p['account']+'&character_id='+p['id'])
code='''
function Tests:swgxrMedicFixture(oid)
 if tonumber(oid)~=__DOC__ and tonumber(oid)~=__PATIENT__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):setPosture(0)
 CreatureObject(p):clearCombatState(true)
 awardSkill(p,"science_medic_novice")
 for _,branch in ipairs({"injury","injury_speed","ability","crafting"}) do for level=1,4 do awardSkill(p,"science_medic_"..branch.."_0"..level) end end
 awardSkill(p,"science_medic_master")
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/tangible/medicine/medikit_tool_basic.iff",-1)
 giveItem(inv,"object/tangible/medicine/stimpack_sm_s1.iff",-1)
 CreatureObject(p):setHAM(0,100)
 CreatureObject(p):setHAM(3,100)
 CreatureObject(p):setHAM(6,1000)
 SceneObject(p):teleport(5000,getTerrainHeight(p,5000,-5400),-5400,0)
end
function Tests:swgxrMedicIncap(oid)
 if tonumber(oid)~=__PATIENT__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):inflictDamage(p,0,CreatureObject(p):getHAM(0)+30,1)
end
function Tests:swgxrMedicDamage(oid)
 if tonumber(oid)~=__PATIENT__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):inflictDamage(p,0,20,1)
end
function Tests:swgxrMedicArea(oid)
 if tonumber(oid)~=__DOC__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 awardSkill(p,"science_combatmedic_novice")
 for level=1,3 do awardSkill(p,"science_combatmedic_support_0"..level) end
 local inv=SceneObject(p):getSlottedObject("inventory")
 for i=SceneObject(inv):getContainerObjectsSize()-1,0,-1 do
  local item=SceneObject(inv):getContainerObject(i)
  if string.find(SceneObject(item):getTemplateObjectPath(),"stimpack_sm_s1.iff",1,true) or string.find(SceneObject(item):getTemplateObjectPath(),"medpack_grenade_area",1,true) then SceneObject(item):destroyObjectFromWorld();SceneObject(item):destroyObjectFromDatabase() end
 end
 giveItem(inv,"object/tangible/medicine/crafted/medpack_grenade_area_a.iff",-1)
 CreatureObject(p):setHAM(0,100)
 CreatureObject(p):setHAM(3,100)
end
'''.replace('__DOC__',f[0]['id']).replace('__PATIENT__',f[1]['id'])
s=target.read_text()
if start in s:s=s[:s.index(start)]+s[s.index(end)+len(end):]
target.write_text(s+start+code+end);console('reloadscreenplays');time.sleep(.5)
for p in f:console('runLuaFunction Tests:swgxrMedicFixture:'+p['id'])
print(json.dumps(f))
