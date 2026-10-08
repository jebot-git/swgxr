#!/usr/bin/env python3
"""Local native movement hardening and owner-summary regression; disposable account only."""
import json, math, re, secrets, time
from urllib.parse import urlencode
from services_smoke import ROOT, req, redact
from equipment_smoke import console

OUT = ROOT/'runtime/evidence/movement-budget/native.json'

def main():
    fixture={'account':'invtestbudget'+secrets.token_hex(3), 'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))}
    report={'passed':False,'native_execution':True,'remote_changed':False,'vr_launched':False,
            'fixture':fixture,'checks':[],'responses':[],
            'limitations':['Bound cloning location is verified unset on this disposable fixture; no original cloning registration UI transaction is performed. Residence registration is attempted with the original native command on a disposable owned house; see skipped cases for its result.']}
    session='';location={};added='';script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    def write():
        OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(redact(report),indent=2)+'\n')
    def check(ok,label):
        report['checks'].append({'passed':bool(ok),'label':label});write();print(label,bool(ok),flush=True);assert ok,label
    def call(path,**kw):
        out=req(path,dict(account=fixture['account'],character_id=fixture.get('id',''),**kw));report['responses'].append({'path':path,'response':redact(out)});write();return out
    def get(path):
        out=req(path+'?'+urlencode({'account':fixture['account'],'character_id':fixture['id'],'session_id':session}));report['responses'].append({'path':path,'response':redact(out)});write();return out
    def player(out):return out.get('snapshot',{}).get('player',out.get('player',out.get('live_response',{}).get('snapshot',{}).get('player',{})))
    def pose():return {k:location[k] for k in ('position','zone','building_id','cell_index')}
    def revision():return location['locomotion']['movement_revision']
    def update(position=None,revision_override=None,**fields):
        nonlocal location
        payload=pose();payload['position']=position or payload['position'];payload.update(fields)
        out=call('/session/update',session_id=session,ready=True,movement_revision=revision() if revision_override is None else revision_override,**payload)
        p=player(out)
        if p:location=p
        return out
    def lua(name):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset);match=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',stream.read())
            if match:return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise AssertionError('Fixture helper timed out: '+name)
    try:
        made=call('/characters',name=fixture['name'],species='human',profession='combat_brawler')
        check('character' in made,'Create disposable native character');fixture['id']=made['character']['id']
        location=call('/enter')['source_location'];opened=call('/session/start',**pose());session=opened['session_id'];location=player(opened);update()
        summary=location['player_summary']
        check(summary['character_id']==fixture['id'] and summary['ham']==location['ham'] and summary['max_ham']==location['max_ham'] and summary['wounds']==location['wounds'],'Owner summary HAM/maxima/wounds equal native live fields')
        check(all(h['status']=='unset' and h['id']=='0' for h in summary['homepoints'].values()),'Fresh native residence and bound clone are explicitly unset')
        pad=get('/datapad');check(pad.get('player_summary',{}).get('character_id')==fixture['id'],'Datapad projects native owner summary through existing replication request')
        state=call('/services/status',live_session_id=session,**pose())
        check(all(state['state']['wallet'][k]==summary['wallet'][k] for k in ('cash','bank')) and state['state']['gcw']['standings']==summary['faction']['standings'],'Summary credits and faction standings equal original services authority')
        location=player(state)
        added=f'''\n-- BEGIN SWGXR MOVEMENT BUDGET FIXTURE
function Tests:swgxrBudgetSetup(kind)
 local p=getSceneObject({fixture['id']});local c=CreatureObject(p)
 c:forcePeace();c:setPosture(0);c:clearState(131072)
 if kind=="freeze" then c:setState(131072);return "done" end
 if kind=="release" then return "done" end
 if kind=="armor" then awardSkill(p,"combat_brawler_master");local a=giveItem(SceneObject(p):getSlottedObject("inventory"),"object/tangible/wearables/armor/padded/armor_padded_s01_chest_plate.iff",-1);return tostring(SceneObject(a):getObjectID()) end
 if kind=="burst" then awardSkill(p,"outdoors_scout_master");return "done" end
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0);return "done"
end
function Tests:swgxrBudgetHome(kind)
 local p=getSceneObject({fixture['id']});local key="swgxrBudgetHouse:{fixture['id']}"
 local house=getSceneObject(readData(key))
 if kind=="cleanup" then
  SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0)
  if house~=nil then BuildingObject(house):destroyChildObjects();SceneObject(house):destroyObjectFromWorld();SceneObject(house):destroyObjectFromDatabase() end
  deleteData(key);return "done"
 end
 house=spawnSceneObject("tatooine","object/building/player/player_house_tatooine_small_style_01.iff",5100,getTerrainHeight(p,5100,-5500),-5500,0,1,0,0,0)
 if house==nil then return "missing_house" end
 writeData(key,SceneObject(house):getObjectID());BuildingObject(house):setOwnerID({fixture['id']})
 BuildingObject(house):grantPermission("ADMIN",{fixture['id']});BuildingObject(house):grantPermission("ENTRY",{fixture['id']})
 local cell=BuildingObject(house):getCell(1);if cell==nil then return "missing_cell" end
 SceneObject(p):teleport(0,0,0,SceneObject(cell):getObjectID())
 local code=CreatureObject(p):executeCommand("declareresidence",0,"")
 if code~=0 then return "declaration_failed_"..tostring(code).."_parent_"..tostring(SceneObject(p):getParentID()) end
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0)
 return tostring(SceneObject(house):getObjectID())
end
-- END SWGXR MOVEMENT BUDGET FIXTURE
'''
        script.write_text(script.read_text()+added);console('reloadscreenplays');check(lua('swgxrBudgetSetup:ground')=='done','Trusted native teleport fixture completes')
        location=player(get('/combat/session'));check(abs(location['position'][0]-5010)<.01,'Native teleport rebases pose while live session remains owned')
        update();before=list(location['position']);bad=[before[0]+500,before[1],before[2]];rev=revision()
        first=update(bad);check(first.get('http_error')==400 and first.get('error_code')=='native_movement_speed_rejected','Ordinary gameplay rejects500m with HTTP400')
        check(first.get('live_response',{}).get('session_id')==session and first['live_response']['mutation']['movement_accepted'] is False and math.dist(location['position'],before)<.01 and revision()==rev,'Ordinary rejection retains owned correction and unchanged accepted pose/revision')
        second=call('/services/status',live_session_id=session,position=bad,zone=location['zone'],building_id=location['building_id'],cell_index=location['cell_index'],movement_revision=rev)
        check(second.get('http_error')==400 and second.get('error_code')=='native_movement_speed_rejected' and math.dist(player(second)['position'],before)<.01,'Immediate alternate-verb500m retry remains rejected with unchanged pose')
        for endpoint, extra in [('/gathering/corpse/inspect', {'corpse_id': '1'}),
                                ('/gathering/survey', {'tool_id': '1', 'resource_id': '1'})]:
            blocked=call(endpoint,live_session_id=session,request_id='budget_'+secrets.token_hex(8),position=bad,zone=location['zone'],building_id=location['building_id'],cell_index=location['cell_index'],movement_revision=rev,**extra)
            check(blocked.get('http_error')==400 and blocked.get('error_code')=='native_movement_speed_rejected',endpoint+' validates impossible pose before object lookup or side effects')
        after=update();check(not after.get('error') and math.dist(location['position'],before)<.01,'Corrected stationary pose succeeds without a delayed rewind')
        stale=revision();time.sleep(1.05);p=list(location['position']);p[0]+=1;accepted=update(p)
        check(not accepted.get('error') and revision()>stale,'Legitimate horizontal movement advances shared revision')
        kept=list(location['position']);reply=update(before,revision_override=stale)
        check(reply.get('error_code')=='native_movement_stale_revision' and math.dist(location['position'],kept)<.01,'Queued stale pose cannot undo accepted movement')
        revision_before=revision();p=list(location['position']);p[1]+=.15;reply=update(p)
        check(not reply.get('error') and revision()==revision_before,'Client-native height difference alone does not spend movement or advance revision')
        for i in range(4):
            time.sleep(.5);p=list(location['position']);p[0]+=1;reply=update(p);check(not reply.get('error'),'Ordinary bounded walking cadence '+str(i+1))
        check(lua('swgxrBudgetSetup:freeze')=='done','Set native frozen state on disposable fixture')
        before=list(location['position']);p=list(before);p[0]+=1;reply=update(p)
        check(reply.get('error')=='native_movement_player_frozen','Native frozen movement guard retained')
        location=player(get('/combat/session'));check(math.dist(location['position'],before)<.01,'Frozen rejection preserves actual native pose')
        lua('swgxrBudgetSetup:release');update()
        item=lua('swgxrBudgetSetup:armor');check(item.isdigit(),'Create original armor on disposable fixture')
        equip=call('/inventory/equip',live_session_id=session,item_id=item,arrangement=0);check(equip.get('mutation',{}).get('success'),'Native armor equip succeeds')
        location=player(get('/combat/session'));pieces=location['player_summary']['armour']['pieces'];piece=next((x for x in pieces if x['id']==item),{})
        equipment=next((x for x in equip.get('inventory',{}).get('equipment',[]) if x['id']==item),{})
        check(piece.get('slots')==equipment.get('equipped_slots') and 'kinetic' in piece.get('protection_percent',{}) and len(pieces)==len({x['id'] for x in pieces}),'Summary reports equipped armor once with exact native slots/protection channels')
        unequip=call('/inventory/unequip',live_session_id=session,item_id=item);check(unequip.get('mutation',{}).get('success'),'Native unequip returns original armor')
        location=player(get('/combat/session'));check(not any(x['id']==item for x in location['player_summary']['armour']['pieces']),'Summary removes unequipped armor on normal snapshot')
        lua('swgxrBudgetSetup:burst')
        captured=dict(live_session_id=session,request_id='budgetmask_'+secrets.token_hex(8),movement_revision=revision(),**pose())
        first_mask=call('/scout/mask_scent',**captured);check(first_mask.get('mutation',{}).get('success'),'Native action commits an idempotent receipt with captured movement revision')
        time.sleep(.5);p=list(location['position']);p[0]+=1;update(p);kept=list(location['position'])
        replay=call('/scout/mask_scent',**captured)
        check(replay.get('mutation',{}).get('replayed') is True and not replay.get('error'),'Completed action replay ignores obsolete movement basis without repeating action')
        location=player(get('/combat/session'));check(math.dist(location['position'],kept)<.01,'Replayed stale receipt does not rewind or move the character')
        burst=call('/scout/burst_run',live_session_id=session,request_id='budget_'+secrets.token_hex(8),**pose());check(burst.get('mutation',{}).get('success'),'Original Burst Run activation accepted')
        location=player(get('/combat/session'));time.sleep(.7);p=list(location['position']);p[0]+=2;check(not update(p).get('error'),'Native speed increase retains valid bounded movement')
        house=lua('swgxrBudgetHome:declare');report['residence_fixture_result']=house
        if house.isdigit():
            check(True,'Original declare-residence command registers a disposable owned house')
            location=player(get('/combat/session'));home=location['player_summary']['homepoints']['residence']
            check(home['status']=='available' and home['id']==house and home['zone']=='tatooine' and abs(home['position'][0]-5100)<.01 and abs(home['position'][2]+5500)<.01,'Summary resolves actual native registered residence with source world coordinates')
            check(lua('swgxrBudgetHome:cleanup')=='done','Disposable residence removed through native object cleanup')
            location=player(get('/combat/session'));home=location['player_summary']['homepoints']['residence']
            check(home['status']==('unset' if home['id']=='0' else 'unavailable'),'Removed native residence is not presented as a valid home location')
        else:
            report.setdefault('skipped',[]).append({'label':'Native available/removed residence resolution',
                'reason':'Optional admin-spawned house fixture could not complete original registration: '+house,
                'passed':None})
            report['limitations'].append('Native available and removed residence cases were not exercised; original registration returned '+house+'. This skip is not a passing native check.')
            check(lua('swgxrBudgetHome:cleanup')=='done','Unregistered optional house fixture is removed')
        report['passed']=True
    finally:
        if added:
            try:
                lua('swgxrBudgetSetup:release')
                lua('swgxrBudgetHome:cleanup')
            finally:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays');report['helper_removed']=added not in script.read_text()
        if session:
            location=player(get('/combat/session'));out=call('/session/logout',live_session_id=session,request_id='budgetlogout_'+secrets.token_hex(8),**pose());check(out.get('saved') and out.get('session_closed'),'Disposable fixture saved and session closed')
            pad=get('/datapad');check(pad.get('player_summary',{}).get('character_id')==fixture['id'],'Fresh non-live datapad retains native owner summary')
        write();print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(OUT)}),flush=True)

if __name__=='__main__':main()
