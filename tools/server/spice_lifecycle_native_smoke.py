#!/usr/bin/env python3
"""Real Core3 spice consumption, HAM, regeneration, incap, cone and owner interest checks.
Admin fixture grants items/skills, resets test HAM and shortens real buff timers;
all outcomes run native consumable, buff, damage, AI and combat code.
"""
import json,math,re,secrets,time
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
  lua('swgxrSpiceLifeRestore');item=next(i for i in inventory()if i['template'].endswith('/spice_'+name+'.iff'));r=call('/inventory/consume',item_id=item['id'],live_session_id=session);check(r.get('mutation',{}).get('success'),'Native consumption '+name);return phase(name,'active')
 def expire(name,which='up'):
  check(lua('swgxrSpiceLifeExpire:'+name+','+which)=='true','Shorten real native '+name+' '+which+' timer');return phase(name,'withdrawal'if which=='up'else'')
 try:
  call('/enter')
  added=f'''
-- BEGIN SWGXR SPICE LIFECYCLE FIXTURE
function Tests:swgxrSpiceLifeSetup()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);awardSkill(p,"combat_brawler_master");awardSkill(p,"combat_marksman_master")
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/weapon/melee/knife/knife_survival.iff",-1)
 for _,name in ipairs({{"scramjet","shadowpaw","thruster_head","sweetblossom","sweetblossom","sedative_h4b","pyrepenol","giggledust"}})do giveItem(inv,"object/tangible/food/spice/spice_"..name..".iff",-1)end
 for i=0,8 do local n=(i%3==0)and10000 or2100;c:setBaseHAM(i,n);c:setMaxHAM(i,n);c:setWounds(i,0);c:setHAM(i,n)end
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0);SceneObject(p):setDirectionalHeading(0)
 return "ready"
end
function Tests:swgxrSpiceLifeRestore()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:forcePeace();c:setPosture(0)
 for i=0,8 do c:setWounds(i,0);c:setHAM(i,c:getMaxHAM(i))end return "restored"
end
function Tests:swgxrSpiceLifeExpire(arg)local name,phase=string.match(arg,"([^,]+),([^,]+)");return tostring(CreatureObject(getSceneObject({owner['id']})):setBuffDuration(getHashCode("spice."..name.."."..phase),1))end
function Tests:swgxrSpiceLifePool(pool)
 local c=CreatureObject(getSceneObject({owner['id']}));c:setHAM(tonumber(pool),1000);return tostring(c:getHAM(tonumber(pool)))
end
function Tests:swgxrSpiceLifeDamage(amount)
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:inflictDamage(p,0,tonumber(amount),1);return tostring(c:getPosture())..":"..tostring(c:getHAM(0))
end
function Tests:swgxrSpiceLifePin()
 local c=CreatureObject(getSceneObject({owner['id']}));for _,i in ipairs({{0,3,6}})do c:setHAM(i,999)end;return tostring(c:getHAM(0))..":"..tostring(c:getHAM(3))..":"..tostring(c:getHAM(6))
end
function Tests:swgxrSpiceLifeCleanup()
 for i=1,8 do local key="swgxrSpiceLife:{owner['id']}:"..i;local m=getSceneObject(readData(key));if m~=nil then SceneObject(m):destroyObjectFromWorld()end;deleteData(key)end return "clean"
end
function Tests:swgxrSpiceLifeSpawn(kind)
 self:swgxrSpiceLifeCleanup();local p=getSceneObject({owner['id']})
 local coords={{{{5010,-5498}},{{5011,-5498}},{{5010,-5502}},{{5010,-5480}}}}
 for i,v in ipairs(coords)do local m=spawnMobile("tatooine",kind or"worrt",0,v[1],getTerrainHeight(p,v[1],v[2]),v[2],0,0);AiAgent(m):setHamRegenDisabled(true);CreatureObject(m):setState(131072)
 for _,pool in ipairs({{0,3,6}})do CreatureObject(m):setBaseHAM(pool,100000);CreatureObject(m):setMaxHAM(pool,100000);CreatureObject(m):setHAM(pool,100000)end
 SceneObject(m):setCustomObjectName("SWGXR spice cone "..i);writeData("swgxrSpiceLife:{owner['id']}:"..i,SceneObject(m):getObjectID())end return "spawned"
end
function Tests:swgxrSpiceLifeIndoor()
 self:swgxrSpiceLifeCleanup();local p=getSceneObject({owner['id']});local b=SceneObject(getSceneObject(1280129));local x=b:getWorldPositionX()+8;local y=b:getWorldPositionY()
 SceneObject(p):teleport(x,getTerrainHeight(p,x,y),y,0)
 local m=spawnMobile("tatooine","death_kreetle",0,0,0,0,0,1280131);CreatureObject(m):setState(131072);writeData("swgxrSpiceLife:{owner['id']}:1",SceneObject(m):getObjectID());return tostring(SceneObject(m):getObjectID())
end
function Tests:swgxrSpiceLifeAttack()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);local target=readData("swgxrSpiceLife:{owner['id']}:1");local code=c:executeCommand("attack",target,"");c:forcePeace();local out=tostring(code)
 for i=1,4 do local m=getSceneObject(readData("swgxrSpiceLife:{owner['id']}:"..i));CreatureObject(m):forcePeace();out=out..":"..tostring(CreatureObject(m):getHAM(0)+CreatureObject(m):getHAM(3)+CreatureObject(m):getHAM(6))end return out
end
-- END SWGXR SPICE LIFECYCLE FIXTURE
'''.replace('and10000 or2100','and 10000 or 2100')
  script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.2);check(lua('swgxrSpiceLifeSetup')=='ready','Disposable original native spice items and combat fixture created')
  loc=call('/services/status')['state']['player'];session=call('/session/start',**{k:loc[k]for k in('position','building_id','cell_index')})['session_id'];live()
  knife=next(i for i in inventory()if i['template'].endswith('/knife_survival.iff'));check(call('/inventory/equip',item_id=knife['id'],arrangement=0,live_session_id=session)['mutation']['success'],'Equip native melee fixture weapon')
  for name,pool,key,duration in [('scramjet',0,'health_regen_scale',700),('shadowpaw',3,'action_regen_scale',600),('thruster_head',6,'mind_regen_scale',400)]:
   s=consume(name);check(s['player']['spice']['effects'][0]['duration_seconds']==duration,'Preserve original active duration '+name)
   for current,multiplier,expected in [('active',1.2,16),('withdrawal',.8,11)]:
    if current=='withdrawal':s=expire(name);check(s['player']['spice']['effects'][0]['duration_seconds']==120,'Native regen withdrawal lasts120seconds')
    check(math.isclose(s['player']['spice']['modifiers'][key],multiplier,abs_tol=1e-6),'Authoritative regen multiplier '+name+' '+current)
    check(float(lua('swgxrSpiceLifePool:'+str(pool)))==1000,'Prepare bounded damaged HAM for actual regen')
    previous=1000;increments=[];deadline=time.monotonic()+3.8
    while time.monotonic()<deadline and len(increments)<2:
     value=live()['player']['ham'][pool//3]
     if value>previous:increments.append(value-previous);previous=value
     time.sleep(.12)
    report.setdefault('regen_ticks',[]).append({'name':name,'phase':current,'increments':increments})
    check(len(increments)>=2 and all(expected<=d<=expected+1 for d in increments),'Actual native periodic regeneration follows '+name+' '+current)
   expire(name,'down')
  consume('sweetblossom');s=expire('sweetblossom');check(s['player']['spice']['effects'][0]['duration_seconds']==180,'Sweetblossom native withdrawal window180seconds')
  check(float(lua('swgxrSpiceLifeDamage:1').split(':')[0])==13,'One actual damage instantly incapacitates during Sweetblossom withdrawal')
  expire('sweetblossom','down');lua('swgxrSpiceLifeRestore')
  consume('sedative_h4b');lua('swgxrSpiceLifeDamage:50000');s=live();check(not s['player']['incapacitated']and not s['player']['dead']and s['player']['ham'][0]==1,'Active Sedative clamps lethal damage at1 without incap')
  s=expire('sedative_h4b');check(s['player']['incapacitated']and s['player']['ham']==[1,1,1],'Sedative expiry immediately causes actual native incap and pinsallHAM1')
  check([float(v)for v in lua('swgxrSpiceLifePin').split(':')]==[1,1,1],'Native primary setters cannot bypass Sedative withdrawal pin')
  expire('sedative_h4b','down');lua('swgxrSpiceLifeRestore');check([float(v)for v in lua('swgxrSpiceLifePin').split(':')]==[999,999,999],'Expired Sedative releases all primary HAM pins')
  consume('pyrepenol');check(lua('swgxrSpiceLifeSpawn:worrt')=='spawned','Spawn real eligible cone targets front, side, behind and outside range')
  attempts=[]
  for _ in range(12):
   result=[int(float(v))for v in lua('swgxrSpiceLifeAttack').split(':')];attempts.append(result)
   if result[1]<300000 and result[2]<300000:break
   time.sleep(.1)
  report['cone_attacks']=attempts
  check(result[1]<300000 and result[2]<300000,'One-target melee command damages additional native front-cone target')
  check(result[3:]==[300000,300000],'Pyrepenol excludes behind-player and out-of-range native targets')
  lua('swgxrSpiceLifeCleanup');expire('pyrepenol');expire('pyrepenol','down')
  consume('giggledust');lua('swgxrSpiceLifeSpawn:death_kreetle');s=live();rows=s['world']['spice_outlines'];check(any(r.get('aggressive')and r.get('outline_only')and not r.get('attackable')for r in rows),'Giggledust exposes actual aggressive actors through separate non-targetable owner interest')
  indoor=str(int(float(lua('swgxrSpiceLifeIndoor'))));loc=call('/services/status')['state']['player'];s=live();rows=s['world']['spice_outlines']
  check(any(r['id']==indoor and r['cell_id']=='1280131'for r in rows),'Giggledust includes actual aggressive target in another original building cell')
  check(not any(r['id']==indoor for r in s['world']['actors']),'Cross-cell outline never enters ordinary actor/target interest')
  (ROOT/'runtime/evidence/spice-giggledust-native-snapshot.json').write_text(json.dumps(s,indent=2))
  lua('swgxrSpiceLifeCleanup');expire('giggledust');check(not live()['world']['spice_outlines'],'Giggledust outline interest disappears during withdrawal');expire('giggledust','down')
  consume('sweetblossom');lua('swgxrSpiceLifeDamage:50000');s=live();check(not s['player']['dead']and not s['player']['incapacitated']and s['player']['ham'][0]>=1,'First actual incapacitating hit under Sweetblossom recovers instantly')
  lua('swgxrSpiceLifeDamage:50000');s=live();check(s['player']['dead'],'Second actual incapacitating hit under Sweetblossom forces native death')
  check(not s['player']['spice']['effects'],'Native death clears spice without creating withdrawal')
  report['passed']=True
 finally:
  if added:
   try:lua('swgxrSpiceLifeCleanup')
   except Exception:pass
  if session:
   try:call('/session/logout',live_session_id=session,zone='tatooine',**{k:loc[k]for k in('position','building_id','cell_index')})
   except Exception:pass
  if added and added in script.read_text():script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  path=ROOT/'runtime/evidence/spice-lifecycle-native-smoke.json';path.write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(path)}),flush=True)
if __name__=='__main__':main()
