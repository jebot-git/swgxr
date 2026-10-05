#!/usr/bin/env python3
"""Isolated real Core3 vehicle owners/passengers; never grants a human account."""
import json,secrets,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/server'))
from inventory_smoke import request
from equipment_smoke import console
path=ROOT/'runtime/server/vehicles-fixture.json';target=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
start='\n-- BEGIN SWGXR VEHICLES TEST\n';end='-- END SWGXR VEHICLES TEST\n'
if '--restore' in sys.argv:
 s=target.read_text()
 if start in s:s=s[:s.index(start)]+s[s.index(end)+len(end):];target.write_text(s);console('reloadscreenplays')
 raise SystemExit()
if not path.exists():
 records=[]
 for _ in range(2):
  account='invtestvehicle'+secrets.token_hex(3);name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))
  created=request('/characters',{'account':account,'name':name,'species':'human','profession':'science_medic'})['character'];records.append({'account':account,'id':created['id'],'name':name})
 path.write_text(json.dumps(records))
f=json.loads(path.read_text());assert all(p['account'].startswith('invtestvehicle') for p in f)
for p in f:request('/inventory?account='+p['account']+'&character_id='+p['id'])
code='''
function Tests:swgxrVehicleFixture(oid)
 if tonumber(oid)~=__DRIVER__ and tonumber(oid)~=__PASSENGER__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):setPvpStatusBitmask(0)
 for i=0,8 do CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
 CreatureObject(p):setPosture(0);CreatureObject(p):clearCombatState(true)
 local pad=SceneObject(p):getSlottedObject("datapad")
 local hasVehicle=false
 for i=0,SceneObject(pad):getContainerObjectsSize()-1 do
  local item=SceneObject(pad):getContainerObject(i)
  if string.find(SceneObject(item):getTemplateObjectPath(),"intangible/vehicle",1,true) then hasVehicle=true end
 end
 if tonumber(oid)==__DRIVER__ and not hasVehicle then
  giveControlDevice(pad,"object/intangible/vehicle/landspeeder_x34_pcd.iff","object/mobile/vehicle/landspeeder_x34.iff",-1,false)
  giveControlDevice(pad,"object/intangible/vehicle/speederbike_pcd.iff","object/mobile/vehicle/speederbike.iff",-1,false)
 end
 SceneObject(p):teleport(5000,getTerrainHeight(p,5000,-5400),-5400,0)
end
function Tests:swgxrVehicleIncap(oid)
 if tonumber(oid)~=__DRIVER__ and tonumber(oid)~=__PASSENGER__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 -- Controlled native life posture for testing ejection, not a damage test.
 CreatureObject(p):setPosture(13)
end
function Tests:swgxrVehicleDeath(oid)
 if tonumber(oid)~=__DRIVER__ and tonumber(oid)~=__PASSENGER__ then return end
 local p=getSceneObject(tonumber(oid));if p==nil then return end
 CreatureObject(p):setPosture(14)
end
'''.replace('__DRIVER__',f[0]['id']).replace('__PASSENGER__',f[1]['id'])
s=target.read_text()
if start in s:s=s[:s.index(start)]+s[s.index(end)+len(end):]
target.write_text(s+start+code+end);console('reloadscreenplays');time.sleep(.3)
for p in f:console('runLuaFunction Tests:swgxrVehicleFixture:'+p['id'])
print(json.dumps(f))
