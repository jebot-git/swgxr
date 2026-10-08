#!/usr/bin/env python3
"""Exercise real last-charge settlement and replay on fresh owned slice fixtures."""
import argparse,json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--mutate-disposable-fixture',action='store_true',required=True);parser.parse_args()
    owner=json.loads((ROOT/'runtime/evidence/slicing-native-smoke.json').read_text())['fixtures'][1]
    assert owner['account'].startswith('invtestslicing')
    base=dict(account=owner['account'],character_id=owner['id']);session='';added=''
    report=dict(passed=False,native_execution=True,fixture=owner,fixture_grants=True,checks=[],responses=[])
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    def check(ok,label):report['checks'].append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
    def call(path,**fields):
        r=req(path,dict(base,**fields));report['responses'].append(dict(path=path,response=redact(r)));return r
    def service(action,**fields):return call('/services/'+action,session_id=session,zone='tatooine',request_id='lastcharge_'+secrets.token_hex(12),**fields)
    def pose(row):return {k:row[k] for k in ('position','building_id','cell_index')}
    def lua(name):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as stream:stream.seek(offset);match=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',stream.read())
            if match:return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise RuntimeError('Native helper timeout')
    try:
        loc=call('/enter')['source_location'];session=call('/session/start',**pose(loc))['session_id'];call('/session/update',session_id=session,ready=True,**pose(loc))
        before=call('/inventory/status',live_session_id=session);ids={i['id'] for i in before['items']}
        added=f'''\n-- BEGIN SWGXR LAST CHARGE FIXTURE\nfunction Tests:swgxrLastChargeGrant(charges)
 local p=getSceneObject({owner['id']});local inv=SceneObject(p):getSlottedObject("inventory");local tool=giveItem(inv,"object/tangible/slicing/slicing_laser_knife.iff",-1);TangibleObject(tool):setUseCount(tonumber(charges));giveItem(inv,"object/tangible/container/loot/player_loot_crate.iff",-1);return "granted"
end
function Tests:swgxrLastChargeState() return readScreenPlayData(getSceneObject({owner['id']}),"swgxr_slicing","state") end
-- END SWGXR LAST CHARGE FIXTURE\n'''
        script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.2);check(lua('swgxrLastChargeGrant:1')=='granted','Only isolated fixture receives original one-use tool and locked crate')
        items=call('/inventory/status',live_session_id=session)['items'];tool=next(i for i in items if i['id'] not in ids and i['template'].endswith('/slicing_laser_knife.iff'));crate=next(i for i in items if i['id'] not in ids and i['template'].endswith('/player_loot_crate.iff'))
        p=loc['position'];begun=service('slicing_begin',tool_id=tool['id'],target_id=crate['id'],target_kind='item',tool_position=p,target_position=p,anchor_position=p,heading_radians=0,**pose(loc))
        check(begun.get('ok'),'Native puzzle begins using original final tool charge')
        inv=begun['state']['inventory']['items'];check(any(i['id']==tool['id'] and i['use_count']==1 and i['slicing_locked'] for i in inv),'Final charge is retained and locked while puzzle is active')
        private=json.loads(lua('swgxrLastChargeState'));fields=dict(attempt_id=private['attempt_id'],paths=private['_witness'],**pose(loc))
        done=service('slicing_complete',**fields)
        check(done.get('ok') and done['state']['slicing']['status']=='succeeded','Final-charge puzzle completes native container reward')
        check(not any(i['id']==tool['id'] for i in done['state']['inventory']['items']),'Successful settlement consumes and removes exactly the exhausted tool')
        replay=service('slicing_complete',**fields)
        check(replay.get('ok') and replay['mutation'].get('already_finished') and not any(i['id']==tool['id'] for i in replay['state']['inventory']['items']),'New-request completion replay cannot consume another charge or recreate tool')
        before=call('/inventory/status',live_session_id=session);ids={i['id'] for i in before['items']}
        check(lua('swgxrLastChargeGrant:2')=='granted','Second isolated fixture pair starts with exactly two native tool charges')
        items=call('/inventory/status',live_session_id=session)['items'];tool2=next(i for i in items if i['id'] not in ids and i['template'].endswith('/slicing_laser_knife.iff'));crate2=next(i for i in items if i['id'] not in ids and i['template'].endswith('/player_loot_crate.iff'))
        begun=service('slicing_begin',tool_id=tool2['id'],target_id=crate2['id'],target_kind='item',tool_position=p,target_position=p,anchor_position=p,heading_radians=0,**pose(loc))
        check(begun.get('ok') and begun['state']['slicing']['active'],'Disposable character begins actual puzzle before logout')
        logout=call('/session/logout',live_session_id=session,**pose(loc));check(logout.get('saved') and logout.get('session_closed'),'Active-puzzle character saves and disconnects through native logout')
        session='';time.sleep(1)
        loc=call('/enter')['source_location'];session=call('/session/start',**pose(loc))['session_id'];call('/session/update',session_id=session,ready=True,**pose(loc))
        state=service('slicing_status');check(not state['state']['slicing']['active'] and state['state']['slicing']['status']=='disconnected','Fresh native login observes disconnected failed attempt')
        items=state['state']['inventory']['items'];remaining=next(i for i in items if i['id']==tool2['id']);failed=next(i for i in items if i['id']==crate2['id'])
        check(remaining['use_count']==1 and not remaining['slicing_locked'] and failed['slice_block_reason']=='already_sliced','Disconnect consumes one charge and permanently burns only the attempted target')
        again=service('slicing_status');check(next(i for i in again['state']['inventory']['items'] if i['id']==tool2['id'])['use_count']==1,'Repeated reconciliation cannot consume a second charge')
        report['passed']=True
    finally:
        if session:location=service('status')['state']['player'];call('/session/logout',live_session_id=session,**pose(location))
        if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
        path=ROOT/'runtime/evidence/slicing-last-charge-native-smoke.json';path.write_text(json.dumps(redact(report),indent=2)+'\n');print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']),evidence=str(path))),flush=True)


if __name__=='__main__':main()
