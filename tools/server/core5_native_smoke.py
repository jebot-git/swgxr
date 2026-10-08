#!/usr/bin/env python3
"""Local Core3 Core5 regression using one explicitly privileged disposable fixture."""
import json
import math
import re
import secrets
import time
from services_smoke import ROOT, req, redact
from equipment_smoke import console

OUT=ROOT/'runtime/evidence/core5-release/native-integration.json'

def main():
    owner={'account':'invtestcorefive'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))}
    report={'passed':False,'native_execution':True,'remote_changed':False,'headset_tested':False,'fixture':owner,'checks':[],'responses':[],
            'fixture_setup':'Original Artisan character; explicit admin grants original skills, charged knife, locked loot container, food tool, and disposable bantha. No earned progression claimed.'}
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    session='';added='';location={};craft_session='';attempt='';spent_charge=False
    def write():
        OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(redact(report),indent=2)+'\n')
    def check(ok,label):
        report['checks'].append({'passed':bool(ok),'label':label});write();print(label,bool(ok),flush=True);assert ok,label
    def call(path,**fields):
        for _ in range(6):
            result=req(path,dict(account=owner['account'],character_id=owner.get('id',''),**fields))
            report['responses'].append({'path':path,'response':redact(result)});write()
            if not (result.get('error_code')=='backend_busy' and result.get('mutation_started') is False):return result
            time.sleep(.5)
        return result
    def key():return 'corefive_'+secrets.token_hex(8)
    def pose():return {k:location[k] for k in ('position','building_id','cell_index','zone')}
    def native_player(result):return result.get('snapshot',{}).get('player',result.get('player',{}))
    def update():
        nonlocal location
        out=call('/session/update',session_id=session,ready=True,**pose())
        player=native_player(out)
        if player:location=player
        return out
    def inventory():return call('/inventory/status',live_session_id=session)
    def inv_part(result):return result['inventory'] if 'items' in result.get('inventory',{}) else result
    def item(result,item_id):return next((i for i in inv_part(result).get('items',[]) if i['id']==item_id),{})
    def equipped(result,item_id):return next((i for i in inv_part(result).get('equipment',[]) if i['id']==item_id),{})
    def lua(name):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset);match=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',stream.read())
            if match:return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise AssertionError('Fixture helper timeout: '+name)
    def craft(action,**fields):return call('/crafting/'+action,live_session_id=session,request_id=key(),**fields)
    def service(action,**fields):return call('/services/'+action,live_session_id=session,request_id=key(),**pose(),**fields)
    try:
        made=req('/characters',dict(owner,species='human',profession='crafting_artisan'));check('character' in made,'Create disposable original Artisan character');owner['id']=made['character']['id']
        location=call('/enter')['source_location'];opened=call('/session/start',**pose());session=opened['session_id'];update()
        added=f'''
-- BEGIN SWGXR COREFIVE FIXTURE
function Tests:swgxrCoreFiveSetup()
 local p=getSceneObject({owner['id']});if p==nil then return "missing" end
 local inv=SceneObject(p):getSlottedObject("inventory")
 awardSkill(p,"crafting_artisan_master")
 awardSkill(p,"combat_smuggler_novice")
 local k=giveItem(inv,"object/tangible/slicing/slicing_laser_knife.iff",-1);TangibleObject(k):setUseCount(10)
 giveItem(inv,"object/tangible/container/loot/player_loot_crate.iff",-1)
 giveItem(inv,"object/tangible/crafting/station/food_tool.iff",-1)
 SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0)
 local n=spawnMobile("tatooine","bantha",0,5040,getTerrainHeight(p,5040,-5500),-5500,0,0)
 if n==nil then return "missing_bantha" end
 writeData("swgxrCoreFive:{owner['id']}",SceneObject(n):getObjectID());return tostring(SceneObject(n):getObjectID())
end
function Tests:swgxrCoreFiveKnowledge()
 awardSkill(getSceneObject({owner['id']}),"outdoors_scout_master");return "granted"
end
function Tests:swgxrCoreFiveCleanup()
 local n=getSceneObject(readData("swgxrCoreFive:{owner['id']}"));if n~=nil then SceneObject(n):destroyObjectFromWorld();SceneObject(n):destroyObjectFromDatabase() end
 deleteData("swgxrCoreFive:{owner['id']}");return "clean"
end
-- END SWGXR COREFIVE FIXTURE
'''
        script.write_text(script.read_text()+added);console('reloadscreenplays');target_id=lua('swgxrCoreFiveSetup');check(target_id.isdigit(),'Create original native inspection target and explicit disposable fixture items')
        # A privileged fixture teleport must establish a fresh normal movement baseline.
        stopped=call('/combat/session/stop',session_id=session);session=''
        location=call('/enter')['source_location'];opened=call('/session/start',**pose());session=opened['session_id'];update()
        inv=inventory();knife=next(i for i in inv['items'] if i['template'].endswith('/slicing_laser_knife.iff'));crate=next(i for i in inv['items'] if i['template'].endswith('/player_loot_crate.iff'))
        check(knife.get('tool_kind')=='slicing' and knife.get('use_count')==10 and knife.get('equip_available') and 'hold_r' in knife.get('equip_slots',[]),'Original charged slicing knife exposes native hold_r equipment arrangement')
        held=call('/inventory/equip',live_session_id=session,item_id=knife['id'],arrangement=0)
        check(held.get('mutation',{}).get('success') and 'hold_r' in equipped(held,knife['id']).get('equipped_slots',[]),'Explicit knife equip occupies native weapon hand')
        hip=call('/gathering/holster',live_session_id=session,tool_id=knife['id'],request_id=key(),zone='tatooine')
        check(hip.get('state',{}).get('hip_tool',{}).get('id')==knife['id'] and not equipped(inventory(),knife['id']),'Equipped knife moves to owned persistent hip escrow and frees weapon hand')
        recovered=call('/gathering/return_tool',live_session_id=session,tool_id=knife['id'],request_id=key(),zone='tatooine')
        check(recovered.get('state',{}).get('hip_tool') is None and bool(item(inventory(),knife['id'])),'Exact hip knife recovers to inventory')
        held=call('/inventory/equip',live_session_id=session,item_id=knife['id'],arrangement=0)
        check(bool(equipped(held,knife['id'])),'Recovered knife re-equips without a duplicate item')
        returned=call('/inventory/unequip',live_session_id=session,item_id=knife['id'])
        check(returned.get('mutation',{}).get('success') and bool(item(returned,knife['id'])) and not equipped(returned,knife['id']),'Knife unequip returns same object to inventory')
        call('/gathering/holster',live_session_id=session,tool_id=knife['id'],request_id=key(),zone='tatooine')
        current=service('status');location=current['state']['player']
        p=location['position'];begun=service('slicing_begin',target_kind='item',target_id=crate['id'],tool_id=knife['id'],tool_position=p,target_position=p,anchor_position=p,heading_radians=0)
        state=begun.get('state',{}).get('slicing',{});attempt=state.get('attempt_id','')
        check(state.get('active') and bool(attempt),'Hip-reserved original knife starts actual authoritative locked-container puzzle')
        locked=call('/gathering/return_tool',live_session_id=session,tool_id=knife['id'],request_id=key(),zone='tatooine')
        check(locked.get('http_error')==400,'Active slicing lease prevents reserved hip tool transfer')
        cancelled=service('slicing_cancel',attempt_id=attempt);attempt='';spent_charge=True
        check(cancelled.get('state',{}).get('slicing',{}).get('active') is False,'Cancelling native puzzle releases its lease')
        call('/gathering/return_tool',live_session_id=session,tool_id=knife['id'],request_id=key(),zone='tatooine')
        check(item(inventory(),knife['id']).get('use_count')==9,'Native cancellation consumes exactly one reserved knife charge')
        inv=inventory();generic=next(i for i in inv['items'] if i['template'].endswith('/generic_tool.iff'));food=next(i for i in inv['items'] if i['template'].endswith('/food_tool.iff'))
        lists=[]
        for tool in (generic,food):
            opened=craft('open',tool_id=tool['id'],**pose());state=opened.get('state',{});craft_session=state.get('session_id','');rows=state.get('schematics',[])
            check(bool(craft_session) and bool(rows) and state.get('tool_template')==tool['template'],'Original crafting tool opens native session with authoritative tool identity')
            check(all(row.get('tool_compatible') is True and int(row['category_id']) in state['tool_tabs'] and row['complexity']<=state['max_complexity'] for row in rows),'Every offered recipe satisfies original selected-tool tab and complexity limits')
            check(all(isinstance(row.get('category'),str) and row['category'] and 'description' in row for row in rows),'Native recipes expose localized original category and description metadata')
            selected=rows[-1];selection=craft('select',tool_id=tool['id'],session_id=craft_session,index=selected['index'],**pose())
            check(selection.get('state',{}).get('schematic',{}).get('id')==selected['id'],'Selecting preserved native row index loads that exact recipe')
            lists.append({r['id']:r for r in rows});craft('cancel',session_id=craft_session);craft_session=''
        check(any(row['category_id']=='1' for row in lists[0].values()) and all(row['category_id']!='1' for row in lists[1].values()),'Original generic tool offers known weapon recipes while food tool excludes them')
        denied=call('/scout/inspect',live_session_id=session,target_id=target_id,**pose())
        check(denied.get('http_error')==400 and denied.get('error')=='creature_knowledge_required','Untrained fixture cannot bypass original creature-knowledge inspection gate')
        check(lua('swgxrCoreFiveKnowledge')=='granted','Grant original Scout mastery only on disposable fixture')
        inspected=call('/scout/inspect',live_session_id=session,target_id=target_id,**pose());inspection=inspected.get('mutation',{}).get('inspection',{})
        check(inspected.get('state',{}).get('inspect_available') and inspection.get('id')==target_id and any(a.get('key')=='aggro' for a in inspection.get('attributes',[])),'Trained inspection returns actual skill-gated original creature attributes')
        check(any(a.get('key')=='challenge_level' for a in inspection.get('attributes',[])),'Higher original creature-knowledge threshold reveals native challenge level')
        update();time.sleep(1.1);before=list(location['position']);bad=list(before);bad[0]+=500
        rejected=call('/services/status',live_session_id=session,position=bad,zone='tatooine',building_id='0',cell_index=0)
        live=rejected.get('live_response',{});player=live.get('snapshot',{}).get('player',{})
        check(rejected.get('http_error')==400 and rejected.get('ok') is False and rejected.get('error_code')=='native_movement_speed_rejected','Impossible service movement returns confirmed native HTTP400 rejection')
        check(live.get('character_id')==owner['id'] and live.get('session_id')==session and live.get('mutation',{}).get('movement_accepted') is False and math.dist(player.get('position',bad),before)<.1,'Failed service retains exact owned authoritative correction envelope')
        location=player;accepted=update();check(not accepted.get('error_code') and native_player(accepted).get('position') is not None,'Applying corrected pose immediately restores normal native movement updates')
        report['passed']=True
    finally:
        if session:
            if attempt:
                try:service('slicing_cancel',attempt_id=attempt)
                except Exception:pass
            if craft_session:
                try:craft('cancel',session_id=craft_session)
                except Exception:pass
        if added:
            try:report['fixture_removed']=lua('swgxrCoreFiveCleanup')=='clean'
            finally:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays');report['helper_removed']=added not in script.read_text()
        if session:
            current=call('/combat/session/snapshot',session_id=session).get('snapshot',{}).get('player',{})
            if current:location=current
            saved=call('/session/logout',live_session_id=session,request_id=key(),**pose());report['logout']=redact(saved)
            check(saved.get('saved') and saved.get('session_closed'),'Disposable fixture saves current native position and releases session')
            if spent_charge:
                inv=call('/inventory/status');row=next((i for i in inv.get('items',[]) if i.get('tool_kind')=='slicing'),{})
                check(bool(row) and row.get('use_count')==9,'Knife inventory location and remaining charges persist across native logout and fresh read')
        write();print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(OUT)}),flush=True)

if __name__=='__main__':main()
