#!/usr/bin/env python3
"""Targeted native Sweetblossom damage versus HAM-bookkeeping regression checks.
Admin fixture grants items/skills, resets test HAM and shortens real buff timers;
negative fixture potency bypasses only the random application roll; subsequent
ticks and all outcomes run native consumable, buff, damage, AI and combat code.
"""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 owner={'account':'invtestspice'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorst')for _ in range(9))}
 created=req('/characters',dict(owner,species='human',profession='combat_brawler'));assert 'character'in created,created;owner['id']=created['character']['id'];base={'account':owner['account'],'character_id':owner['id']}
 report={'passed':False,'native_execution':True,'headset_tested':False,'privileged_fixture':True,'shortened_native_timers':True,'fixture':owner,'checks':[],'responses':[]};session='';script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';added='';loc={}
 def check(value,label):
  report['checks'].append({'passed':bool(value),'label':label});print(label,bool(value),flush=True);assert value,label
 def call(path,**kw):
  result=req(path,dict(base,**kw));report['responses'].append({'path':path,'response':redact(result)});return result
 def lua(name):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
  for _ in range(80):
   with log.open()as f:f.seek(offset);match=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',f.read())
   if match:return match.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Lua timeout '+name)
 def live():
  out=call('/combat/session/update',session_id=session,ready=True,**{k:loc[k]for k in('position','building_id','cell_index')});return out['snapshot']
 def inventory():return call('/services/slicing_status',session_id=session,zone='tatooine')['state']['inventory']['items']
 def phase(name,wanted):
  for _ in range(55):
   s=live();effects=s['player']['spice']['effects']
   if (not wanted and not effects)or any(e['spice_id']==name and e['phase']==wanted for e in effects):return s
   time.sleep(.1)
  raise AssertionError(('phase',name,wanted,effects))
 def consume(name):
  lua('swgxrSpiceEdgeRestore');item=next(i for i in inventory()if i['template'].endswith('/spice_'+name+'.iff'));r=call('/inventory/consume',item_id=item['id'],live_session_id=session);check(r.get('mutation',{}).get('success'),'Native consumption '+name);return phase(name,'active')
 def expire(name,which='up'):
  check(lua('swgxrSpiceEdgeExpire:'+name+','+which)=='true','Shorten real native '+name+' '+which+' timer');return phase(name,'withdrawal'if which=='up'else'')
 try:
  call('/enter')
  added=f'''
-- BEGIN SWGXR SPICE DAMAGE EDGE FIXTURE
function Tests:swgxrSpiceEdgeSetup()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);awardSkill(p,"combat_brawler_master");awardSkill(p,"combat_marksman_master")
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/weapon/melee/knife/knife_survival.iff",-1)
 for _,name in ipairs({{"sweetblossom"}})do giveItem(inv,"object/tangible/food/spice/spice_"..name..".iff",-1)end
 for i=0,8 do local n=(i%3==0)and10000 or2100;c:setBaseHAM(i,n);c:setMaxHAM(i,n);c:setWounds(i,0);c:setHAM(i,n)end
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0);SceneObject(p):setDirectionalHeading(0)
 return "ready"
end
function Tests:swgxrSpiceEdgeRestore()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:forcePeace();c:setPosture(0)
 for i=0,8 do c:setWounds(i,0);c:setHAM(i,c:getMaxHAM(i))end return "restored"
end
function Tests:swgxrSpiceEdgeExpire(arg)local name,phase=string.match(arg,"([^,]+),([^,]+)");return tostring(CreatureObject(getSceneObject({owner['id']})):setBuffDuration(getHashCode("spice."..name.."."..phase),1))end
function Tests:swgxrSpiceEdgeCost(name)
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);for _,i in ipairs({{1,4,7}})do c:setHAM(i,300)end
 local before=c:getHAM(0)+c:getHAM(3)+c:getHAM(6);local target=readData("swgxrSpiceEdge:{owner['id']}:1");local code=c:executeCommand(name,target,"");c:forcePeace();local after=c:getHAM(0)+c:getHAM(3)+c:getHAM(6);local posture=c:getPosture();local m=getSceneObject(target);if m~=nil then CreatureObject(m):forcePeace()end
 return tostring(code)..":"..tostring(before)..":"..tostring(after)..":"..tostring(posture)
end
function Tests:swgxrSpiceEdgeDotStatus()
 local c=CreatureObject(getSceneObject({owner['id']}));return tostring(c:hasState(8388608))..":"..tostring(c:hasState(16777216))..":"..tostring(c:getPosture())..":"..tostring(c:getHAM(0))
end
function Tests:swgxrSpiceEdgeDot(kind)
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:clearState(8388608);c:clearState(16777216);c:setPosture(0);for _,i in ipairs({{0,3,6}})do c:setHAM(i,c:getMaxHAM(i))end
 c:addDotState(p,tonumber(kind),1,0,35,-1,1711+tonumber(kind),0);return tostring(c:hasState(tonumber(kind)))..":"..tostring(c:getSkillMod("absorption_bleeding"))..":"..tostring(c:getSkillMod("absorption_poison"))
end
function Tests:swgxrSpiceEdgeCleanup()
 local p=getSceneObject({owner['id']});if p~=nil then CreatureObject(p):clearState(8388608);CreatureObject(p):clearState(16777216)end
 for i=1,8 do local key="swgxrSpiceEdge:{owner['id']}:"..i;local m=getSceneObject(readData(key));if m~=nil then SceneObject(m):destroyObjectFromWorld()end;deleteData(key)end return "clean"
end
function Tests:swgxrSpiceEdgeSpawn(kind)
 self:swgxrSpiceEdgeCleanup();local p=getSceneObject({owner['id']})
 local coords={{{{5010,-5498}},{{5011,-5498}},{{5010,-5502}},{{5010,-5480}}}}
 for i,v in ipairs(coords)do local m=spawnMobile("tatooine",kind or"worrt",0,v[1],getTerrainHeight(p,v[1],v[2]),v[2],0,0);AiAgent(m):setHamRegenDisabled(true);CreatureObject(m):setState(131072)
 for _,pool in ipairs({{0,3,6}})do CreatureObject(m):setBaseHAM(pool,100000);CreatureObject(m):setMaxHAM(pool,100000);CreatureObject(m):setHAM(pool,100000)end
 SceneObject(m):setCustomObjectName("SWGXR spice cone "..i);writeData("swgxrSpiceEdge:{owner['id']}:"..i,SceneObject(m):getObjectID())end return "spawned"
end
-- END SWGXR SPICE DAMAGE EDGE FIXTURE
'''.replace('and10000 or2100','and 10000 or 2100')
  script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.2);check(lua('swgxrSpiceEdgeSetup')=='ready','Disposable original native spice items and combat fixture created')
  loc=call('/services/status')['state']['player'];session=call('/session/start',**{k:loc[k]for k in('position','building_id','cell_index')})['session_id'];live()
  knife=next(i for i in inventory()if i['template'].endswith('/knife_survival.iff'));check(call('/inventory/equip',item_id=knife['id'],arrangement=0,live_session_id=session)['mutation']['success'],'Equip native melee fixture weapon')
  consume('sweetblossom');s=expire('sweetblossom');check(not s['player']['incapacitated'],'Sweet withdrawal starts without unrelated HAM bookkeeping incapacitation')
  check(lua('swgxrSpiceEdgeSpawn:worrt')=='spawned','Prepare native stationary attack target')
  cost=[float(v)for v in lua('swgxrSpiceEdgeCost:melee1hhit1').split(':')]
  check(cost[0]==0 and cost[2]<cost[1]and cost[3]!=13,'Actual native weapon HAM cost is consumed without triggering Sweet withdrawal incap')
  cost=[float(v)for v in lua('swgxrSpiceEdgeCost:tumbletoprone').split(':')]
  check(cost[0]==0 and cost[2]<cost[1]and cost[3]!=13,'Native Tumble ability action cost is consumed without withdrawal incap')
  lua('swgxrSpiceEdgeCleanup')
  # Test the longer tick first: native clearState leaves its DOT list entry;
  # a cleared earlier tick can prune the list before a later fixture tick.
  for name,state in [('bleeding',16777216),('poison',8388608)]:
   diagnostic=lua('swgxrSpiceEdgeDot:'+str(state));report.setdefault('dot_fixtures',[]).append({'kind':name,'installed_state_bleed_absorption_poison_absorption':diagnostic});check(float(diagnostic.split(':')[0])!=0,'Apply original self-attributed '+name+' DOT fixture')
   end=time.monotonic()+23;observed=time.monotonic()-4
   while time.monotonic()<end:
    s=live()
    if time.monotonic()-observed>=4:
     observed=time.monotonic();report.setdefault('dot_states',[]).append({'kind':name,'remaining':end-observed,'native':lua('swgxrSpiceEdgeDotStatus')})
    if s['player']['incapacitated']:break
    time.sleep(.25)
   check(s['player']['incapacitated'],'Actual native ordinarily nonlethal '+name+' tick causes Sweet withdrawal incap')
  expire('sweetblossom','down')
  report['passed']=True
 finally:
  if added:
   try:lua('swgxrSpiceEdgeCleanup')
   except Exception:pass
  if session:
   try:call('/session/logout',live_session_id=session,zone='tatooine',**{k:loc[k]for k in('position','building_id','cell_index')})
   except Exception:pass
  if added and added in script.read_text():script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  path=ROOT/'runtime/evidence/spice-damage-native-smoke.json';path.write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(path)}),flush=True)
if __name__=='__main__':main()
