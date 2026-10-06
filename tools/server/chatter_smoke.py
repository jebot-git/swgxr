#!/usr/bin/env python3
"""Actual native spatial delivery and persistent passive comprehension proof."""
import json,re,secrets,time,sys
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 report=dict(passed=False,native_execution=True,remote_server_changed=False,headset_tested=False,fixture_setup='Fresh isolated human artisan listeners and administrator-spawned original NPCs. Explicit trusted screenplay speech invokes real native ChatManager, without skill/progress grants. Natural ambient speech is tested separately through the server timer.',checks=[],responses=[],fixtures=[])
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';added='';sessions={};contexts={};presentation={};marker='speech_'+secrets.token_hex(5)
 def check(value,label):
  report['checks'].append(dict(label=label,passed=bool(value)));print(label,bool(value),flush=True)
  if not value:raise AssertionError(label)
 def call(o,path,**kw):
  result=req(path,dict(account=o['account'],character_id=o['id'],**kw));report['responses'].append(dict(path=path,owner=o['id'],response=redact(result)));return result
 def enter(o):
  entry=call(o,'/enter');loc={k:entry['source_location'][k]for k in ('position','zone','building_id','cell_index')};r=call(o,'/combat/session/start',**loc);sessions[o['id']]=r['session_id'];return r
 def update(o,ready=True):return call(o,'/session/update',session_id=sessions[o['id']],ready=ready,**contexts[o['id']])
 def state(o):return update(o)['snapshot']['player']['npc_speech']
 def sync(o):
  presentation[o['id']]=presentation.get(o['id'],0)+1;time.sleep(.06)
  return call(o,'/session/sync',session_id=sessions[o['id']],sequence=presentation[o['id']],**contexts[o['id']])
 def language(o,identifier=2):return next(row for row in state(o)['languages']if row['id']==identifier)
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(100):
   with log.open()as f:f.seek(offset);s=f.read()
   match=re.search('runLuaFunction Tests:'+name+r': result=([^\n]+)',s)
   if match:
    result=match.group(1).strip().strip('[]');report['responses'].append(dict(native_screenplay=name,result=result));return result
   if 'Failed to runLuaFunction'in s:raise RuntimeError(s[-1500:])
   time.sleep(.1)
  raise RuntimeError('Native screenplay timeout '+name)
 def speak(fn='swgxrSpeechOne'):lua(fn);time.sleep(.4)
 try:
  previous=json.loads((ROOT/'runtime/server/chatter-fixtures.json').read_text())if '--reuse'in sys.argv else []
  for index in range(2):
   o=dict(account='invtestspeech'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8)));o=previous[index]if previous else o;created={'character':{'id':o['id']}}if previous else req('/characters',dict(o,species='human',profession='crafting_artisan'));o['id']=created['character']['id'];report['fixtures'].append(o);enter(o);contexts[o['id']]=dict(position=[6000+index*2,5,-6000],zone='tatooine',building_id='0',cell_index=0);update(o)
  a,b=report['fixtures'];(ROOT/'runtime/server/chatter-fixtures.json').write_text(json.dumps(report['fixtures']))
  added=f'''
-- BEGIN {marker}
function Tests:swgxrSpeechSetup()
 local p=getSceneObject({a['id']});local y=getTerrainHeight(p,6000,-6000);writeData("{marker}:height",y)
 for i,id in ipairs({{{a['id']},{b['id']}}}) do SceneObject(getSceneObject(id)):teleport(5998+i*2,y,-6000,0) end
 for i=1,2 do local n=spawnMobile("tatooine","tough_thug_male_rodian",0,6003+i,y,-6000,0,0);SceneObject(n):setCustomObjectName("SWGXR Native Speaker "..i);AiAgent(n):setHomeLocation(6003+i,y,-6000,nil);writeData("{marker}:npc"..i,SceneObject(n):getObjectID()) end
 return tostring(y)
end
function Tests:swgxrSpeechOne() spatialChat(getSceneObject(readData("{marker}:npc1")),"@npc_reaction/townperson:hi_mid_1",2) end
function Tests:swgxrSpeechPlain() spatialChat(getSceneObject(readData("{marker}:npc1")),"Native speech fixture.",2) end
function Tests:swgxrSpeechLekku() spatialChat(getSceneObject(readData("{marker}:npc1")),"Native gesture fixture.",9) end
function Tests:swgxrSpeechPlayer() spatialChat(getSceneObject({b['id']}),"Player speech must not teach.",2) end
function Tests:swgxrSpeechParams() local text=LuaStringIdChatParameter("@base_player:prose_coin_loot");text:setTT(CreatureObject(getSceneObject({a['id']})):getFirstName());text:setDI(7);spatialChat(getSceneObject(readData("{marker}:npc1")),text:_getObject(),1) end
function Tests:swgxrSpeechDead() CreatureObject(getSceneObject({b['id']})):setPosture(14) end
function Tests:swgxrSpeechAlive() CreatureObject(getSceneObject({b['id']})):setPosture(0) end
function Tests:swgxrSpeechBurst() for i=1,37 do spatialChat(getSceneObject(readData("{marker}:npc"..(i%2+1))),"@npc_reaction/townperson:hi_mid_1",2) end end
function Tests:swgxrSpeechAmbient() local y=readData("{marker}:height");for i=1,2 do local n=spawnMobile("tatooine","commoner",0,6003+i,y,-6000,0,0);SceneObject(n):setCustomObjectName("SWGXR Ambient Speaker "..i);AiAgent(n):setHomeLocation(6003+i,y,-6000,nil);writeData("{marker}:ambient"..i,SceneObject(n):getObjectID()) end end
function Tests:swgxrSpeechCleanup() for _,key in ipairs({{"npc1","npc2","ambient1","ambient2"}}) do local n=getSceneObject(readData("{marker}:"..key));if n then SceneObject(n):destroyObjectFromWorld() end;deleteData("{marker}:"..key) end;CreatureObject(getSceneObject({b['id']})):setPosture(0) end
-- END {marker}
'''
  script.write_text(script.read_text()+added);console('reloadscreenplays');height=float(lua('swgxrSpeechSetup'))
  for o in report['fixtures']:contexts[o['id']]['position'][1]=height;update(o)
  check(language(a)['progress_basis_points']==0 and not language(a)['can_speak'],'Fresh human listener does not know Rodese comprehension or speech')
  speak();sa=state(a);sb=state(b);check(language(a)['progress_basis_points']==250 and language(b)['progress_basis_points']==250,'One actual native NPC event grants exactly2.5percent to both nearby listeners')
  ea=next(e for e in sa['events']if e['language_id']==2);check(ea['text']and not ea['understood']and 'message'not in ea,'Unknown original STF speech is server-scrambled without untranslated payload')
  one=sync(a);two=sync(a);check(one['npc_speech']['events']and one['npc_speech']['events'][0]['id']==two['npc_speech']['events'][0]['id']and language(a)['progress_basis_points']==250,'Authenticated repeated sync replays stable event without another language grant')
  speak('swgxrSpeechPlain');check(language(a)['progress_basis_points']==500,'Plain native spatial overload also produces exactly one learning event')
  speak('swgxrSpeechParams');params=state(a);check(any(a['name'].lower()in e['text'].lower()and '7'in e['text']for e in params['events']),'Original parameterized STF substitutes native listener name and number')
  speak('swgxrSpeechLekku');check(language(a,9)['progress_basis_points']==0 and any(e['language_id']==9 and e['text']=='[Unfamiliar body language]'for e in state(a)['events']),'Inaudible Lekku neither teaches by hearing nor exposes unknown clear text')
  speak('swgxrSpeechPlayer');check(language(a)['progress_basis_points']==500,'Player speech cannot generate NPC passive-learning events')
  contexts[b['id']]['position'][0]=6100;update(b);speak();check(language(a)['progress_basis_points']==750 and language(b)['progress_basis_points']==500,'Listener beyond32m receives no learning while nearby listener advances')
  contexts[b['id']]['position'][0]=6002;call(b,'/combat/session/stop',session_id=sessions.pop(b['id']));enter(b);update(b,ready=False);speak();check(language(b)['progress_basis_points']==500,'Listener on loading screen receives no passive progress');update(b)
  lua('swgxrSpeechDead');speak();lua('swgxrSpeechAlive');check(language(b)['progress_basis_points']==500,'Dead listener receives no passive progress');update(b)
  # Listener A gained two additional test speeches while B was unavailable: 12.5%.
  before_a=language(a)['progress_basis_points'];before_b=language(b)['progress_basis_points'];speak('swgxrSpeechBurst');after_a=language(a);after_b=language(b)
  check(after_a['progress_basis_points']==10000 and after_a['understood']and not after_a['can_speak'],'Native40event threshold awards original comprehension skill only')
  check(after_b['progress_basis_points']==min(10000,before_b+37*250),'Two speakers concurrent native tasks preserve exact second-listener progress without deadlock')
  check(after_b['progress_basis_points']==9750 and not after_b['understood'],'Exactly39native exposures remain below the original comprehension skill threshold')
  call(b,'/combat/session/stop',session_id=sessions.pop(b['id']));enter(b);update(b);partial=language(b);check(partial['progress_basis_points']==9750 and not partial['understood'],'Partial39event comprehension progress survives original logout/login')
  speak();check(language(b)['progress_basis_points']==10000 and language(b)['understood']and not language(b)['can_speak'],'Exactly40thnative event unlocks original comprehension without speech skill')
  check(any(e['language_id']==2 and e['understood']for e in state(a)['events']),'Later native speech becomes clear after original skill grant')
  call(a,'/combat/session/stop',session_id=sessions.pop(a['id']));enter(a);update(a);check(language(a)['understood']and not language(a)['can_speak'],'Comprehension skill persists across real native logout/login')
  call(b,'/combat/session/stop',session_id=sessions.pop(b['id']));enter(b);update(b);check(language(b)['progress_basis_points']==min(10000,before_b+38*250),'Partial or complete learning ledger persists across independent native login')
  time.sleep(6.2);check(not state(a)['events'],'Expired native speech is absent after six seconds')
  lua('swgxrSpeechAmbient');found=False
  for _ in range(25):
   snapshot=update(a);speech=snapshot['snapshot']['player']['npc_speech'];update(b)
   if any(e['name'].startswith('SWGXR Ambient Speaker')for e in speech['events']):found=True;break
   time.sleep(1)
  check(found,'Server-owned presence timer emits a real original commoner greeting')
  sync(a);sync(b);report['passed']=True
 finally:
  if added:
   lua('swgxrSpeechCleanup');script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  for o in report['fixtures']:
   if o['id']in sessions:call(o,'/combat/session/stop',session_id=sessions[o['id']])
  (ROOT/'runtime/evidence/chatter-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']))),flush=True)
if __name__=='__main__':main()
