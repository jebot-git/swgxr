#!/usr/bin/env python3
"""Exercise real consumed spice phases and derived weapon stats on a disposable owner."""
import argparse
import json
import math
import re
import secrets
import sys
import time
from services_smoke import ROOT, req, redact
from equipment_smoke import console
sys.path.insert(0, str(ROOT))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutate-disposable-fixture', action='store_true', required=True)
    parser.parse_args()
    owner = json.loads((ROOT/'runtime/evidence/slicing-native-smoke.json').read_text())['fixtures'][0]
    assert owner['account'].startswith('invtestslicing')
    base = dict(account=owner['account'], character_id=owner['id'])
    report = dict(passed=False, native_execution=True, privileged_fixture=True,
                  shortened_native_timers=True, fixture=owner, checks=[], responses=[])
    script = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    session = ''; added = ''

    def check(value, label):
        report['checks'].append(dict(passed=bool(value), label=label))
        print(label, bool(value), flush=True)
        assert value, label

    def call(path, **fields):
        result = req(path, dict(base, **fields))
        report['responses'].append(dict(path=path, response=redact(result)))
        return result

    def service():
        return call('/services/slicing_status', session_id=session, zone='tatooine',
                    request_id='spice_stats_'+secrets.token_hex(12))

    def pose(row):
        return {key: row[key] for key in ('position', 'building_id', 'cell_index')}

    def lua(name):
        log = ROOT/'runtime/server/core3-console.log'; offset = log.stat().st_size
        console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset)
                found = re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)', stream.read())
            if found:
                return found.group(1).strip().strip('[]')
            time.sleep(.1)
        raise RuntimeError('Native helper timeout '+name)

    def live():
        return call('/combat/session/update', session_id=session, ready=True, **pose(loc))['snapshot']

    def phase(name, expected):
        for _ in range(60):
            snapshot = live()
            effects = snapshot['player']['spice']['effects']
            if (not expected and not effects) or any(e['spice_id']==name and e['phase']==expected for e in effects):
                return snapshot
            time.sleep(.1)
        raise AssertionError('Native spice phase failed '+name+' '+expected)

    def attrs(state, item):
        return state['live_response']['service_attributes']['o'+item['id']]

    try:
        loc = call('/enter')['source_location']
        session = call('/session/start', **pose(loc))['session_id']
        call('/session/update', session_id=session, ready=True, **pose(loc))
        added = f'''
-- BEGIN SWGXR SPICE WEAPON FIXTURE
function Tests:swgxrSpiceWeaponPrepare()
 local p=getSceneObject({owner['id']});local c=CreatureObject(p);c:forcePeace()
 awardSkill(p,"combat_marksman_master")
 for i=0,8 do c:setWounds(i,0);c:setHAM(i,c:getMaxHAM(i)) end
 local inv=SceneObject(p):getSlottedObject("inventory")
 for _,name in ipairs({{"gunjack","droid_lube","grey_gabaki"}}) do giveItem(inv,"object/tangible/food/spice/spice_"..name..".iff",-1) end
 return "ready"
end
function Tests:swgxrSpiceWeaponExpire(arg)
 local name,phase=string.match(arg,"([^,]+),([^,]+)")
 return tostring(CreatureObject(getSceneObject({owner['id']})):setBuffDuration(getHashCode("spice."..name.."."..phase),1))
end
-- END SWGXR SPICE WEAPON FIXTURE
'''
        script.write_text(script.read_text()+added); console('reloadscreenplays'); time.sleep(.2)
        check(lua('swgxrSpiceWeaponPrepare')=='ready', 'Native disposable fixture ready')
        state = service(); items = state['state']['inventory']['items']
        for name, suffix, labels in [('gunjack','/pistol_fwg5.iff',['Rate of fire (RPM)','Capacity (shots)']),
                                    ('droid_lube','/knife_survival.iff',['Power','Stance recovery'])]:
            items = service()['state']['inventory']['items']
            weapon = next(i for i in items if i['template'].endswith(suffix) and i['slice_bonuses'])
            plain = next(i for i in items if i['template'].endswith(suffix) and not i['slice_bonuses'])
            if not weapon.get('equipped'):
                result = call('/inventory/equip', item_id=weapon['id'], arrangement=0, live_session_id=session)
                check(result.get('mutation',{}).get('success'), 'Native weapon equipped '+name)
            else:
                check(True, 'Fixture weapon already equipped '+name)
            before = service(); baseline = attrs(before, weapon); plain_baseline = attrs(before, plain)
            interval = before['live_response']['snapshot']['weapon']['fire_interval_seconds']
            spice = next(i for i in before['state']['inventory']['items'] if i['template'].endswith('/spice_'+name+'.iff'))
            check(spice['consumable'] and spice['consume_kind']=='spice' and spice['consume_available'], 'Inventory exposes crafted spice consumption '+name)
            used = call('/inventory/consume', item_id=spice['id'], live_session_id=session)
            check(used['mutation']['success'], 'Actual native consumable starts '+name)
            phase(name,'active')
            for desired, scale in [('active',1.2),('withdrawal',.5)]:
                if desired=='withdrawal':
                    check(lua('swgxrSpiceWeaponExpire:'+name+',up')=='true', 'Shorten actual native active timer')
                    current = phase(name,'withdrawal')
                    effect = next(e for e in current['player']['spice']['effects'] if e['spice_id']==name)
                    check(effect['duration_seconds']==180, 'Native weapon spice withdrawal lasts three minutes')
                current = service(); observed = attrs(current,weapon)
                profiles = req('/weapons?account='+owner['account']+'&character_id='+owner['id'])
                resolved = next((p for p in profiles.get('weapons',[]) if p.get('item_id')==weapon['id']), {})
                check(bool(resolved) and all(math.isclose(float(resolved[field]),float(observed[label]),abs_tol=.03) for field,label in ([("rpm",labels[0]),("capacity",labels[1])] if name=="gunjack" else [("power",labels[0]),("stance_recovery",labels[1])])), 'Live owner weapon API resolves current '+name+' '+desired+' stats')
                if name=='droid_lube':
                    from server.unarmed_protocol import resolve
                    unarmed = profiles['unarmed']; unmodified = resolve(unarmed['player_stats'])
                    check(all(math.isclose(float(unarmed[field]),float(unmodified[field])*scale,abs_tol=.03) for field in ('power','stance_recovery')), 'Unarmed native owner profile receives '+desired+' Zypolene scales')


                for label in labels:
                    expected = float(baseline[label])*scale
                    if label=='Capacity (shots)':
                        # Compose with the unrounded raw capacity and existing slice once.
                        expected = max(1,math.floor(float(plain_baseline[label])*(1+weapon['slice_bonuses'].get('capacity_pct',0)/100)*scale+.5))
                    check(math.isclose(float(observed[label]),expected,abs_tol=.03), name+' '+desired+' actual '+label)
                check(all(attrs(current,plain)[label]==plain_baseline[label] for label in labels), 'Unequipped item has no wielder spice mutation')
                if name=='gunjack':
                    check(math.isclose(current['live_response']['snapshot']['weapon']['fire_interval_seconds'],interval/scale,abs_tol=.02), 'Actual native attack speed follows '+desired+' Gunjack')
            check(lua('swgxrSpiceWeaponExpire:'+name+',down')=='true', 'Shorten actual native downer timer')
            phase(name,'')
            restored = attrs(service(),weapon)
            check(all(restored[label]==baseline[label] for label in labels), 'Expiry restores original sliced values '+name)
        state = service(); spice = next(i for i in state['state']['inventory']['items'] if i['template'].endswith('/spice_grey_gabaki.iff'))
        check(call('/inventory/consume', item_id=spice['id'], live_session_id=session)['mutation']['success'], 'Grey Gabaki consumes natively')
        current = phase('grey_gabaki','active')
        check(math.isclose(current['player']['spice']['modifiers']['cooldown_scale'],.9,abs_tol=1e-6), 'Grey owner projection gives reduced cooldown')
        check(lua('swgxrSpiceWeaponExpire:grey_gabaki,up')=='true', 'Shorten Grey active timer')
        phase('grey_gabaki','')
        check(True, 'Grey expires with no native withdrawal buff')
        report['passed'] = True
    finally:
        if session:
            try:
                for name in ('gunjack','droid_lube','grey_gabaki'):
                    lua('swgxrSpiceWeaponExpire:'+name+',up')
                time.sleep(1.3)
                for name in ('gunjack','droid_lube'):
                    lua('swgxrSpiceWeaponExpire:'+name+',down')
                time.sleep(1.3)
                location=service()['state']['player']
                call('/session/logout',live_session_id=session,**pose(location))
            except Exception as error:
                report['cleanup_error']=str(error)
        if added:
            script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
        out=ROOT/'runtime/evidence/spice-weapon-native-smoke.json'
        out.write_text(json.dumps(redact(report),indent=2)+'\n')
        print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']),evidence=str(out))),flush=True)


if __name__=='__main__':
    main()
