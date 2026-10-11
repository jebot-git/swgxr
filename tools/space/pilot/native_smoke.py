#!/usr/bin/env python3
"""Native trainer/quest regression on a named, isolated invtest character.
Does not launch a client. Objective callback tests are explicitly distinguished
from real flight/combat tests in the resulting evidence.
"""
import argparse,json,os,re,subprocess,time,urllib.request,urllib.error,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trainer',action='append',help='Optional focused trainer subset; Akal and Oberhaur are always included')
    parser.add_argument('--fixture',type=Path,required=True);parser.add_argument('--port',type=int,default=18080)
    parser.add_argument('--out',type=Path,default=ROOT/'runtime/evidence/pilot-native-integration.json');a=parser.parse_args()
    f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and str(f['id']).isdigit()
    os.umask(0o077);sid='';player={};checks=[];samples=[]
    def check(value,label):
        checks.append({'passed':bool(value),'label':label});print(label,bool(value),flush=True);assert value,label
    def call(path,data=None,required=True):
        nonlocal player
        body=None if data is None else {'account':f['account'],'character_id':f['id'],'session_id':sid,**data}
        request=urllib.request.Request(f'http://127.0.0.1:{a.port}'+path,None if body is None else json.dumps(body).encode(),{'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=60) as r:result=json.load(r)
        except urllib.error.HTTPError as e:result={'http_error':e.code,**json.load(e)}
        player=result.get('live_response',result).get('snapshot',{}).get('player',player)
        if required and (result.get('http_error') or result.get('ok') is False):raise AssertionError((path,result.get('error'),result.get('error_code')))
        return result
    def console(command):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size
        subprocess.run(['podman','exec','swgxr-core3-build','bash','-lc','printf "%s\\n" "$1" > /workspace/runtime/server/core3-console','probe',command],check=True)
        if not command.startswith('runLuaFunction'):time.sleep(.5);return ''
        marker=':'.join(command.split(':')[:2])+': result='
        for _ in range(300):
            with log.open() as stream:stream.seek(offset);lines=stream.read().splitlines()
            row=next((line for line in lines if marker in line),None)
            if row:return row.split(marker,1)[1].strip().removeprefix('[').removesuffix(']')
            time.sleep(.1)
        raise AssertionError('Native fixture console timeout')
    def service(action,required=True,**extra):
        return call('/services/'+action,{'zone':'tatooine','position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'request_id':uuid.uuid4().hex,**extra},required)
    mapping=json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text())
    if a.trainer:mapping={k:v for k,v in mapping.items() if k in set(a.trainer)|{'akal_colzet','oberhaur'}}
    mobiles='{'+','.join(json.dumps(m) for m in mapping)+'}'
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
    lua=r'''
function Tests:swgxrPilotIntegration(mode)
 local p=getSceneObject(__ID__)
 if p==nil or string.lower(CreatureObject(p):getFirstName())~="__NAME__" then return "guard_failed" end
 if mode=="setup" then
  CreatureObject(p):forcePeace();SceneObject(p):switchZone("tatooine",3600,5,-4780,0)
  local out={}
  for i,mobile in ipairs(__MOBILES__) do
   local npc=spawnMobile("tatooine",mobile,0,3601,5,-4780,0,0)
   if npc==nil then return "spawn_failed:"..mobile end
   AiAgent(npc):setWait(3600000)
   local id=SceneObject(npc):getObjectID();writeData("pilotIntegration:"..mobile,id)
   table.insert(out,mobile.."="..id)
  end
  return table.concat(out,",")
 elseif mode=="form" then
  local inventory=SceneObject(p):getSlottedObject("inventory")
  local item=giveItem(inventory,"object/tangible/space/mission_objects/transfer_auth.iff",-1)
  if not item then return "missing" end
  writeData("pilotIntegration:form",SceneObject(item):getObjectID())
  return "created"
 elseif mode=="form_debug" then
  local item=PilotSource.transferForm(p)
  return "item="..tostring(item~=nil)..";name="..SceneObject(p):getCustomObjectName()..";display="..SceneObject(p):getDisplayedName()
 elseif mode=="signed" then
  local item=getSceneObject(readData("pilotIntegration:form"))
  if item and PilotSource.get(item,"obj.signature")==SceneObject(p):getCustomObjectName() then return "signed" end
  return "unsigned"
 elseif mode=="journal" then
  local q=PilotQuests.instances["patrol:tatooine_imperial_1"]
  PilotQuests.clear(p,"patrol","tatooine_imperial_1");PilotQuests.clear(p,"destroy_surpriseattack","tatooine_imperial_1")
  PilotQuests.grant(p,getSceneObject(readData("pilotIntegration:akal_colzet")),"patrol","tatooine_imperial_1")
  if not SpaceHelpers:isSpaceQuestActive(p,"patrol","tatooine_imperial_1") then return "not_active" end
  return "active"
 elseif mode=="reward" then
  local q=PilotQuests.instances["destroy:tatooine_imperial_2"]
  PilotQuests.clear(p,"destroy","tatooine_imperial_2");PilotQuests.grant(p,nil,"destroy","tatooine_imperial_2")
  local before=CreatureObject(p):getBankCredits()
  if PilotQuests.reward(p,"destroy","tatooine_imperial_2",200,nil) then return "premature_reward" end
  -- Deliberate native completion callback injection; not a flight/kill test.
  q:completeQuest(p,"false")
  if not PilotQuests.reward(p,"destroy","tatooine_imperial_2",200,nil) then return "no_reward" end
  if PilotQuests.reward(p,"destroy","tatooine_imperial_2",200,nil) then return "duplicate_reward" end
  return tostring(CreatureObject(p):getBankCredits()-before)
 elseif mode=="failure" then
  PilotQuests.clear(p,"assassinate","tatooine_imperial_4")
  local q=PilotQuests.instances["assassinate:tatooine_imperial_4"]
  PilotQuests.grant(p,nil,"assassinate","tatooine_imperial_4");q:resetQuest(p)
  if not PilotQuests.query(p,"hasAbortedQuest","assassinate","tatooine_imperial_4") then return "abort_missing" end
  PilotQuests.clear(p,"assassinate","tatooine_imperial_4");PilotQuests.grant(p,nil,"assassinate","tatooine_imperial_4")
  if not SpaceHelpers:isSpaceQuestActive(p,"assassinate","tatooine_imperial_4") then return "retry_failed" end
  return "retry_active"
 elseif mode=="cleanup" then
  local item=getSceneObject(readData("pilotIntegration:form"))
  if item then SceneObject(item):destroyObjectFromWorld();SceneObject(item):destroyObjectFromDatabase() end
  deleteData("pilotIntegration:form")
  for _,mobile in ipairs(__MOBILES__) do
   local n=getSceneObject(readData("pilotIntegration:"..mobile))
   if n then SceneObject(n):destroyObjectFromWorld();SceneObject(n):destroyObjectFromDatabase() end
   deleteData("pilotIntegration:"..mobile)
  end
  for _,pair in ipairs({{"patrol","tatooine_imperial_1"},{"destroy_surpriseattack","tatooine_imperial_1"},{"destroy","tatooine_imperial_2"},{"assassinate","tatooine_imperial_4"}}) do PilotQuests.clear(p,pair[1],pair[2]) end
  return "clean"
 end
 return "unknown"
end
'''.replace('__ID__',str(f['id'])).replace('__NAME__',f['name'].split()[0].lower()).replace('__MOBILES__',mobiles)
    report={'passed':False,'native_corecu':True,'client_launched':False,'fixture_id':f['id'],'checks':checks,'samples':samples,'objective_validation':'Native callback injection; real flight/combat separately required.'}
    try:
        sid=call('/combat/session/start',{'zone':'tatooine','position':[3600,5,-4780]})['session_id']
        call('/session/update',{'zone':player.get('zone','tatooine'),'position':player['position'],'building_id':player['building_id'],'cell_index':player['cell_index'],'ready':True})
        script.write_text(original+lua);console('reloadscreenplays')
        setup=console('runLuaFunction Tests:swgxrPilotIntegration:setup')
        check('spawn_failed' not in setup and 'guard_failed' not in setup,'Native trainer fixtures spawned')
        npcs=dict(pair.split('=') for pair in setup.split(','));call('/jtl/status',{})
        for name,npc in npcs.items():
            opened=service('open',False,terminal_id=npc)
            samples.append({'open':name,'terminal':opened.get('state',{}).get('terminal'),'error':opened.get('error')})
            view=service('pilot_begin',terminal_id=npc)['state']['terminal'];samples.append({'trainer':name,'view':view})
            check(view.get('kind')=='pilot_trainer' and bool(view.get('screen_token')) and bool(view.get('dialogue')) and view['dialogue']!='Speak to this pilot trainer about enlistment, training and missions.','Native conversation opens: '+name)
            check('@conversation/' not in view['dialogue'],'Dialogue text resolves: '+name)
        npc=npcs['akal_colzet'];view=service('pilot_begin',terminal_id=npc)['state']['terminal']
        bad=service('pilot_choose',False,terminal_id=npc,screen_token='stale',option=0)
        check(bad.get('http_error') or bad.get('ok') is False,'Stale trainer request rejected')
        check(console('runLuaFunction Tests:swgxrPilotIntegration:form')=='created','Original transfer authorization item exists')
        samples.append({'form_debug':console('runLuaFunction Tests:swgxrPilotIntegration:form_debug')})
        transfer=service('pilot_begin',terminal_id=npcs['oberhaur'])['state']['terminal']
        samples.append({'transfer_form':transfer})
        option=next(o for o in transfer['options'] if 'sign' in o.get('name','').lower())
        service('pilot_choose',terminal_id=npcs['oberhaur'],screen_token=transfer['screen_token'],option=option['option'])
        check(console('runLuaFunction Tests:swgxrPilotIntegration:signed')=='signed','Explicit trainer Sign action persists signature on owned form')
        check(console('runLuaFunction Tests:swgxrPilotIntegration:journal')=='active','Akal mission creates native journal assignment')
        jtl=call('/jtl/status',{})['state'];samples.append({'journal':jtl.get('missions')})
        check(any(m.get('attributes',{}).get('Quest CRC')==1170275280 for m in jtl.get('missions',[])),'Akal assignment appears in player datapad')
        check(float(console('runLuaFunction Tests:swgxrPilotIntegration:reward'))==200,'Completion gates reward and replay cannot pay twice')
        check(console('runLuaFunction Tests:swgxrPilotIntegration:failure')=='retry_active','Aborted mission can be accepted again')
        report['passed']=True
    except Exception as error:report['error']=str(error);raise
    finally:
        if sid:
            try:console('runLuaFunction Tests:swgxrPilotIntegration:cleanup')
            finally:
                script.write_text(original);console('reloadscreenplays');call('/combat/session/stop',{},False)
        a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
