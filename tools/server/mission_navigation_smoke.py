#!/usr/bin/env python3
"""Native mission presentation regression; administrative placement of one disposable fixture only."""
import json, math, secrets
from services_smoke import ROOT, req, redact
from seed_bazaar import Native


def main():
    native = Native('swgxr-core3-build')
    fixture = {'account': 'invtestmnav'+secrets.token_hex(4)}
    for _ in range(10):
        fixture['name'] = 'Ivtest'+''.join(secrets.choice('aeilnorst') for _ in range(9))
        created = req('/characters', dict(fixture, species='human', profession='crafting_artisan'))
        if 'character' in created: break
    assert 'character' in created, created
    fixture['id'] = created['character']['id']
    base = dict(account=fixture['account'], character_id=fixture['id'])
    report = dict(passed=False, native_execution=True, administrative_placement=True, xr=False, fixture=fixture, checks=[], responses=[])
    session = ''; location = {}; mission_id = ''
    def check(ok, label):
        report['checks'].append(dict(passed=bool(ok), label=label)); print(label, bool(ok), flush=True)
        assert ok, label
    def call(path, **fields):
        if session: fields.setdefault('live_session_id' if path=='/session/logout' else 'session_id', session)
        if path.startswith('/services/') and path not in ('/services/status','/services/open'):fields.setdefault('request_id','nav_'+secrets.token_hex(12))
        result = req(path, dict(base, **fields)); report['responses'].append(dict(path=path,response=redact(result))); return result
    def place(row):
        nonlocal session,location
        if session:
            result=call('/session/logout', **location);check(result.get('saved',result.get('mutation',{}).get('success',False)) or result.get('source_kind')=='core3_session_logout','Close fixture session before administrative relocation');session=''
        position=row['position'];native.call('swgxrMissionNavigationPlace:'+','.join(str(float(v)) for v in position))
        location={key:row[key] for key in ('position','building_id','cell_index')}
        result=call('/session/start',**location);check(result.get('session_live',False),'Fresh owned session at actual fixture location');session=result['session_id']
        call('/session/update',ready=True,**location)
    source=f'''
function Tests:swgxrMissionNavigationPlace(arg)
 local x,y,z=string.match(arg,"([^,]+),([^,]+),([^,]+)")
 local p=getSceneObject({fixture['id']});CreatureObject(p):forcePeace();SceneObject(p):teleport(tonumber(x),tonumber(y),tonumber(z),0);return "placed"
end
'''
    entered=call('/enter');check('source_location' in entered,'Fixture enters actual Core3')
    with native.screenplay('swgxrMissionNavigationPlace',source):
        try:
            catalog=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())
            terminal=min((r for r in catalog['static_terminals'] if r['kind']=='mission' and r['template'].endswith('/terminal_mission.iff') and r['cell_index']==0),key=lambda r:math.dist(r['position'],[3500,5,-4860]))
            place(terminal)
            opened=call('/services/open',terminal_id=terminal['id'],**location);check(opened.get('ok',False),'Open original mission terminal')
            offer=next(r for r in opened['state']['terminal']['missions'] if r['type']=='deliver' and r.get('supported') and not r.get('active'))
            result=call('/services/mission_accept',terminal_id=terminal['id'],mission_id=offer['id'],**location);check(result.get('ok',False),'Accept original delivery objective');mission_id=offer['id']
            active=next(r for r in result['state']['missions'] if r['id']==mission_id)
            check(active.get('status')=='Collect parcel' and active.get('waypoint',{}).get('active') is True,'Mission publishes pickup phase and active native waypoint')
            giver=next(r for r in result['state']['delivery_contacts'] if r['mission_id']==mission_id and r['role']=='giver');place(giver)
            result=call('/services/delivery_pickup',npc_id=giver['id'],mission_id=mission_id,**location);check(result.get('ok',False),'Native giver hands over parcel')
            active=next(r for r in result['state']['missions'] if r['id']==mission_id)
            receiver=next(r for r in result['state']['delivery_contacts'] if r['mission_id']==mission_id and r['role']=='receiver');waypoint=active.get('waypoint',{})
            check(active.get('status')=='Deliver parcel' and waypoint.get('active') is True and math.dist([waypoint['position'][0],waypoint['position'][2]],[receiver['position'][0],receiver['position'][2]])<1,'Native progress and waypoint advance to recipient')
            result=call('/services/mission_abort',mission_id=mission_id,**location);check(result.get('ok',False) and not any(r['id']==mission_id for r in result['state']['missions']),'Cancellation removes native mission and waypoint presentation');mission_id=''
            report['passed']=True
        finally:
            if mission_id:call('/services/mission_abort',mission_id=mission_id,**location)
            if session:call('/session/logout',**location)
            (ROOT/'runtime/evidence/mission-combat-20261010/mission-navigation-native.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
