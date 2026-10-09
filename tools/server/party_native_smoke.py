#!/usr/bin/env python3
"""Native party gestures and original group leadership, disposable local players only."""
import json,math,re,secrets,time
from urllib.parse import urlencode
from services_smoke import ROOT,req,redact
from equipment_smoke import console
OUT=ROOT/'runtime/evidence/party/native.json'

def main():
 report={'passed':False,'native_execution':True,'remote_changed':False,'vr_launched':False,'fixtures':[],'checks':[],'responses':[],'limitations':['Bulk surrender callback is source/build verified; runtime tests exercise individual surrender and the shared native election/modifier path. No new production Lua API was added for testing.']}
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';helper='';sessions={};locations={};tokens={};seq={}
 def write():
  OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(redact(report),indent=2)+'\n')
 def check(ok,label):
  report['checks'].append({'passed':bool(ok),'label':label});write();print(label,bool(ok),flush=True);assert ok,label
 def call(o,path,**kw):
  for attempt in range(4):
   out=req(path,dict(account=o['account'],character_id=o.get('id',''),**kw));report['responses'].append({'owner':o.get('id',''),'path':path,'response':redact(out)});write()
   if path not in ('/characters','/enter') or out.get('http_error')!=503:return out
   if path=='/characters':
    # Creation may have committed before its client result was lost. Reconcile
    # this exact dedicated account before any repeat creation request.
    roster=None
    for _ in range(4):
     time.sleep(1)
     found=req('/characters?'+urlencode({'account':o['account']}));report['responses'].append({'owner':o.get('id',''),'path':'/characters (reconcile)','response':redact(found)});write()
     if isinstance(found.get('characters'),list):roster=found['characters'];break
    if roster is None:return out
    if roster:
     match=next((r for r in roster if r.get('name','').lower()==o['name'].lower()),None)
     if match:return {'character':match,'fixture_creation_reconciled':True}
     raise AssertionError('Dedicated fixture roster contains an unexpected character; no duplicate creation attempted')
   time.sleep(1)
  return out
 def refresh(o):
  out=req('/combat/session?'+urlencode(dict(account=o['account'],character_id=o['id'],session_id=sessions[o['id']])));locations[o['id']]=out['snapshot']['player'];return locations[o['id']]
 def pose(o):return {k:locations[o['id']][k] for k in ('position','zone','building_id','cell_index')}
 def ent(o,action,**kw):
  kw.setdefault('request_id','party_'+secrets.token_hex(8));return call(o,'/entertainer/'+action,live_session_id=sessions[o['id']],**pose(o),**kw)
 def state(o):return ent(o,'status')['state']['group']
 def lua(arg):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrPartyFixture:'+arg)
  for _ in range(150):
   with log.open() as stream:
    stream.seek(offset);match=re.search(r'runLuaFunction Tests:swgxrPartyFixture: result=([^\n]+)',stream.read())
   if match:return match.group(1).strip().strip('[]')
   time.sleep(.1)
  raise AssertionError('Party fixture timed out')
 def presence(o,x=0,fist=True,free=True,tracked=True):
  oid=o['id'];seq[oid]=seq.get(oid,0)+1;p=locations[oid]['position'];h=[5010+x,p[1]+1.2,-5500]
  return call(o,'/services/presence',token=tokens[oid],sequence=seq[oid],**pose(o),wallet_held=False,
   hand={'position':h,'tracked':False,'grip':False},hands={'left':{'position':h,'tracked':tracked,'free':free,'fist':fist}})
 def proof(a,b):
  for o in (a,b):
   refresh(o);out=call(o,'/services/status',live_session_id=sessions[o['id']],**pose(o));tokens[o['id']]=out['presence']['token'];seq[o['id']]=max(seq.get(o['id'],0),out['presence']['sequence_floor'])
  presence(a,-.5);presence(b,.5);presence(a);presence(b);time.sleep(.15);out=presence(a)
  peer=next((r for r in out.get('peers',[]) if r['id']==b['id']),{})
  check(peer.get('group_bump_ready'),'Mutual offhand-only separated-then-contact proof issued')
  return {'target_id':b['id'],'group_bump_id':peer['group_bump_id'],'request_id':'bump_'+peer['group_bump_id']}
 def bump(a,b):
  data=proof(a,b);out=ent(a,'group_bump',**data);presence(a,fist=False);presence(b,fist=False);return out,data
 try:
  for index in range(6):
   o={'account':'invtestparty'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))};report['fixtures'].append(o)
   made=call(o,'/characters',name=o['name'],species='human',profession='crafting_artisan');check('character' in made,'Create disposable party player '+str(index+1));o['id']=made['character']['id']
   locations[o['id']]=call(o,'/enter')['source_location'];out=call(o,'/session/start',**pose(o));sessions[o['id']]=out['session_id'];locations[o['id']]=out['snapshot']['player'];call(o,'/session/update',session_id=out['session_id'],ready=True,**pose(o))
  a,b,c,d,e,f=report['fixtures'];allowed=','.join(o['id'] for o in report['fixtures'])
  helper=f'''\n-- BEGIN SWGXR PARTY FIXTURE
function Tests:swgxrPartyFixture(arg)
 local id,op=string.match(arg,"([^,]+),(.+)");local allowed={{{allowed}}};local found=false
 for _,v in ipairs(allowed) do if tostring(v)==id then found=true end end
 if not found then return "fixture_only" end
 local p=getSceneObject(tonumber(id));if p==nil then return "missing_player" end
 if op=="move" then CreatureObject(p):forcePeace();CreatureObject(p):setPosture(0);SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0);return "done" end
 if op=="squad" then return tostring(CreatureObject(p):hasSkill("outdoors_squadleader_novice")) end
 if op=="surrender" then CreatureObject(p):surrenderSkill("outdoors_squadleader_novice");return tostring(CreatureObject(p):hasSkill("outdoors_squadleader_novice")) end
 if op=="mods" then local c=CreatureObject(p);return tostring(c:getSkillMod("private_group_ranged_defense"))..","..tostring(c:getSkillMod("private_group_melee_defense")) end
 if op=="leader_mods" then local c=CreatureObject(p);return tostring(c:getSkillMod("group_ranged_defense"))..","..tostring(c:getSkillMod("group_melee_defense")) end
 if op~="level" then awardSkill(p,op) end
 return tostring(CreatureObject(p):getLevel())
end
-- END SWGXR PARTY FIXTURE
'''
  script.write_text(script.read_text()+helper);console('reloadscreenplays')
  for o in report['fixtures']:
   check(lua(o['id']+',move')=='done','Position disposable player through native teleport');refresh(o);call(o,'/session/update',session_id=sessions[o['id']],ready=True,**pose(o))
  lua(b['id']+',combat_brawler_unarmed_04');lua(c['id']+',combat_brawler_master');lua(d['id']+',outdoors_squadleader_defense_03');lua(f['id']+',outdoors_squadleader_novice')
  check(lua(d['id']+',squad')=='true' and lua(f['id']+',squad')=='true','Original Squad Leader novice skills actually granted')
  report['levels']={o['id']:int(float(lua(o['id']+',level'))) for o in report['fixtures']};check(report['levels'][a['id']]<report['levels'][b['id']]<report['levels'][c['id']],'Original skill awards provide unequal initial and later ordinary combat levels')
  denied=ent(a,'group_bump',target_id=b['id'],group_bump_id='a'*24);check(denied.get('http_error')==400 and state(a)['id']=='0','Public group action without mutual gesture is refused')
  out,first=bump(a,b);check(out.get('ok') and out['state']['group']['leader_id']==b['id'],'Higher combat level of initial two becomes native leader')
  group_id=state(a)['id'];check(group_id!='0' and state(b)['id']==group_id,'Both players share actual native group')
  out,_=bump(a,c);check(out.get('ok') and state(c)['id']==group_id,'Bumping an ordinary nonleader member joins their native group')
  check(state(c)['leader_id']==b['id'],'Later higher-level ordinary member does not replace existing leader')
  out,d_receipt=bump(a,d);check(out.get('ok') and state(a)['leader_id']==d['id'],'Joining Squad Leader automatically leads despite higher-level ordinary member')
  # Exercise original non-gesture routes: their native leadership policy is shared.
  check(ent(e,'group_invite',target_id=f['id']).get('ok'),'Original invite command remains available')
  check(ent(f,'group_join').get('ok'),'Original join command remains available')
  for _ in range(30):
   other=state(e)
   if other['id']!='0':break
   time.sleep(.1)
  check(other['leader_id']==f['id'],'Original invite/join cannot bypass Squad Leader promotion')
  before_a=state(a)['id'];before_e=state(e)['id'];out,_=bump(a,e)
  check(out.get('http_error')==400 and out.get('error')=='cannot_merge_existing_parties','Bumping two different parties is rejected')
  check(state(a)['id']==before_a and state(e)['id']==before_e,'Rejected party merge leaves both native parties unchanged')
  level=int(float(lua(c['id']+',outdoors_squadleader_novice')));report['learned_sl_level']=level
  check(lua(c['id']+',squad')=='true','Grouped member actually learns original Squad Leader novice')
  for _ in range(30):
   party=state(a)
   if party['leader_id']==c['id']:break
   time.sleep(.1)
  check(level>report['levels'][d['id']] and party['leader_id']==c['id'],'Learning Squad Leader while grouped promotes highest-level Squad Leader')
  check(lua(c['id']+',surrender')=='false','Original individual surrender removes leader Squad Leader novice')
  source=list(map(float,lua(d['id']+',leader_mods').split(',')))
  expected=[math.ceil(min(30,max(0,value))*.5) for value in source]
  for _ in range(30):
   party=state(a);support=refresh(a)['squad_leader']['passives']
   actual=[support['ranged_defense'],support['melee_defense']]
   legacy=list(map(float,lua(a['id']+',mods').split(',')))
   if party['leader_id']==d['id'] and actual==expected and legacy==[0,0]:break
   time.sleep(.1)
  report['surrender_modifiers']={'remaining_leader_source':source,'expected_cu':expected,'member':actual,'retired_legacy':legacy}
  check(max(expected)>0 and actual==expected and legacy==[0,0] and party['leader_id']==d['id'],'Individual surrender elects remaining Squad Leader and applies bounded CU passives without legacy modifiers')
  lua(c['id']+',outdoors_squadleader_novice')
  for _ in range(30):
   if state(a)['leader_id']==c['id']:break
   time.sleep(.1)
  check(state(a)['leader_id']==c['id'],'Relearning Squad Leader restores highest-level eligible leader')
  check(ent(c,'group_leave').get('ok'),'Existing leave command removes leader')
  check(state(c)['id']=='0' and state(a)['leader_id']==d['id'],'Leaving leader promotes remaining Squad Leader')
  check(ent(d,'group_leave').get('ok') and state(d)['id']=='0','Squad Leader can leave through existing native command')
  support=refresh(a)['squad_leader']['passives']
  check(support['damage_bonus']==0 and support['action_mind_regen_bonus']==0 and support['melee_defense']==0 and support['ranged_defense']==0,'Last Squad Leader departure immediately removes CU support bonuses')
  replay=ent(a,'group_bump',**d_receipt)
  check(replay.get('mutation',{}).get('replayed') is True and state(d)['id']=='0','Consumed gesture replay after Leave returns receipt without rejoining')
  reverse=ent(d,'group_bump',target_id=a['id'],group_bump_id=d_receipt['group_bump_id'],request_id=d_receipt['request_id'])
  check(reverse.get('http_error')==400 and state(d)['id']=='0','Other participant cannot reuse globally consumed bump')
  # Evict the bounded entertainer receipt ledger using harmless stop actions.
  evictions=[]
  for index in range(65):
   out=req('/entertainer/stop',dict(account=a['account'],character_id=a['id'],live_session_id=sessions[a['id']],zone='tatooine',request_id='partyevict_'+secrets.token_hex(8)))
   evictions.append({'index':index,'ok':out.get('ok'),'error':out.get('error')})
   if not out.get('ok'):break
  report['receipt_evictions']=evictions
  check(len(evictions)==65 and all(x['ok'] for x in evictions),'Harmless native actions evict old bounded receipt without membership effects')
  expired=ent(a,'group_bump',**d_receipt)
  check(expired.get('http_error')==400 and expired.get('error')=='group_bump_receipt_expired' and state(d)['id']=='0','Evicted consumed bump fails receipt-only retry without rejoining')
  report['passed']=True
 finally:
  if helper:script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays');report['helper_removed']=helper not in script.read_text()
  for o in report['fixtures']:
   if o.get('id') not in sessions:continue
   refresh(o)
   if state(o)['id']!='0':ent(o,'group_leave')
   refresh(o);out=call(o,'/session/logout',live_session_id=sessions[o['id']],request_id='partylogout_'+secrets.token_hex(8),**pose(o));check(out.get('saved') and out.get('session_closed'),'Disposable party player saved and session closed')
  write();print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(OUT)}),flush=True)

if __name__=='__main__':main()
