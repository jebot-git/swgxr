#!/usr/bin/env python3
"""Native recipe retirement checks on the dedicated CU wound fixture."""
import sys,json,secrets,time
from pathlib import Path
sys.path.insert(0,'tools/server')
from services_smoke import req,ROOT
from equipment_smoke import console
r=json.loads((ROOT/'runtime/evidence/cu-wounds-native.json').read_text());o=r['fixtures'][0];session='';draft='';loc={};checks=[];helper='';script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
def call(path,**kw):
 out=req(path,dict(account=o['account'],character_id=o['id'],**kw))
 if out.get('error'):print(path,out,flush=True)
 return out
def check(ok,label):checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True);assert ok,label
try:
 entered=call('/enter')
 helper='\nfunction Tests:swgxrCuRecipeStation(mode) local p=getSceneObject('+o['id']+');if mode=="cleanup" then local station=getSceneObject(readData("swgxrCuRecipeStation"));if station~=nil then SceneObject(station):destroyObjectFromWorld();SceneObject(station):destroyObjectFromDatabase()end;return "clean" end;local h=getTerrainHeight(p,5010,-5500);SceneObject(p):teleport(5010,h,-5500,0);local station=spawnSceneObject("tatooine","object/tangible/crafting/station/food_station.iff",5011,h,-5500,0,0);writeData("swgxrCuRecipeStation",SceneObject(station):getObjectID());giveItem(SceneObject(p):getSlottedObject("inventory"),"object/tangible/crafting/station/food_tool.iff",-1);return "ready" end\n'
 script.write_text(script.read_text()+helper);console('reloadscreenplays');time.sleep(.3);console('runLuaFunction Tests:swgxrCuRecipeStation');time.sleep(.7)
 native=call('/services/status')['state']['player'];loc={k:native[k] for k in ('position','building_id','cell_index')}
 session=call('/combat/session/start',**loc)['session_id'];call('/combat/session/update',session_id=session,ready=True,**loc)
 inv=call('/inventory/status',live_session_id=session);tool=next(i for i in inv['items'] if i['template'].endswith('/food_tool.iff'))
 draft='curec_'+secrets.token_hex(8);out=call('/crafting/open',live_session_id=session,request_id=draft,tool_id=tool['id'],**loc)
 if 'state' not in out:raise RuntimeError(out)
 check(out['state'].get('station_id') not in (None,'0',0),'Appropriate food/chemical tool is connected to a native food station')
 rows=out['state']['schematics'];names=[i['template'].rsplit('/',1)[-1] for i in rows];(ROOT/'runtime/evidence/cu-items-recipes-offered.json').write_text(json.dumps(names,indent=2)+'\n')
 check(any(x.startswith('medpack_wound_health') for x in names),'Native crafting tool offers Health Wound Medpack recipe')
 check(not any(x.startswith('medpack_wound_') and not x.startswith('medpack_wound_health') for x in names),'Native crafting tool omits obsolete wound recipes')
 check(not any(x.startswith('medpack_poison_') and 'health' not in x for x in names),'Native crafting tool omits obsolete poison recipes')
 check(any(x.startswith('crafted_stimpack_') for x in names),'Native crafting retains usable stim recipe')
 check(any(x.startswith('medpack_enhance_health_') for x in names),'Native crafting retains functional Health enhancement recipe')
 check(any(x.startswith('medpack_cure_poison_') for x in names),'Native crafting retains antidote recipe')
 check('medpack_revive.iff' in names,'Native crafting retains resuscitation kit recipe')
 check(not any(x.startswith('med_stimpack_state_') and x.endswith('_b.iff') for x in names),'Native crafting omits empty State Stim B placeholders')
 check(not any(x.startswith('medpack_disease_') and 'action' not in x for x in names),'Native crafting tool omits obsolete disease recipes')
finally:
 if draft:call('/crafting/cancel',session_id=draft,live_session_id=session,request_id='curec_'+secrets.token_hex(8))
 if session:call('/combat/session/stop',session_id=session)
 if loc:call('/session/logout',**loc)
 if helper:
  console('runLuaFunction Tests:swgxrCuRecipeStation:cleanup');time.sleep(.3)
  script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays')
 (ROOT/'runtime/evidence/cu-recipes-native.json').write_text(json.dumps({'checks':checks,'passed':bool(checks) and all(x['passed'] for x in checks)},indent=2)+'\n')
