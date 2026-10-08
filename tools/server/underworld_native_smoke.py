#!/usr/bin/env python3
"""Actual local Core3 Underworld parcel/reward/abort regression.

Requires the 0060/0061 server and explicit disposable-fixture opt-in. Creates a
new invtestunderworld character, grants that fixture Novice Smuggler, Dirty Fighting IV and credits,
and uses normal gameplay/service requests thereafter. Never restarts services,
changes unrelated characters or enables planets. Grants and teleport transport
are test setup, not a claim of natural profession progression or VR validation.
"""
import argparse
import json
import re
import secrets
import time
from pathlib import Path

from services_smoke import ROOT, req, redact
from equipment_smoke import console


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutate-disposable-fixture', action='store_true', required=True)
    parser.add_argument('--test-encounters', action='store_true')
    parser.add_argument('--encounters-only', action='store_true')
    args = parser.parse_args()
    if args.encounters_only:
        args.test_encounters = True
    fixture = {'account': 'invtestunderworld' + secrets.token_hex(3),
               'name': 'Ivtest' + ''.join(secrets.choice('aeilnorstu') for _ in range(8))}
    created = req('/characters', dict(fixture, species='human', profession='combat_marksman'))
    assert 'character' in created, created
    fixture['id'] = created['character']['id']
    base = dict(account=fixture['account'], character_id=fixture['id'])
    report = dict(passed=False, native_execution=True, mocked=False, fixture_grants=True,
                  fixture=fixture, headset_tested=False, server_restart_tested=False,
                  checks=[], responses=[])
    session = ''
    active = ''
    zone = 'tatooine'
    screenplay = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    added = ''

    def check(value, label):
        report['checks'].append(dict(passed=bool(value), label=label))
        print(label, bool(value), flush=True)
        assert value, label

    def service(action, **fields):
        payload = dict(base, session_id=session, zone=zone, **fields)
        if action not in ('status', 'open', 'delivery_open'):
            payload.setdefault('request_id', 'underworld_' + secrets.token_hex(10))
        result = req('/services/' + action, payload)
        report['responses'].append(dict(action=action, request=redact(payload), response=redact(result)))
        return result

    def pose(row):
        return {k: row[k] for k in ('position', 'building_id', 'cell_index')}

    def contact(state, role):
        return next(c for c in state['delivery_contacts'] if c['mission_id'] == active and c['role'] == role)

    def lua_result(name):
        log = ROOT / 'runtime/server/core3-console.log'
        offset = log.stat().st_size
        console('runLuaFunction Tests:' + name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset)
                match = re.search('runLuaFunction Tests:' + name.split(':', 1)[0] + r': result=([^\n]+)', stream.read())
            if match:
                return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise RuntimeError('Native test helper timed out: ' + name)

    def total(wallet):
        return wallet['cash'] + wallet['bank']

    try:
        entered = req('/enter', base)
        initial = entered['source_location']
        started = req('/session/start', dict(base, **pose(initial)))
        check(started.get('session_live'), 'New dedicated fixture starts actual native gameplay session')
        session = started['session_id']
        req('/session/update', dict(base, session_id=session, **pose(initial), ready=True))
        added = f'''\nfunction Tests:swgxrUnderworldFixtureGrant()\n local p=getSceneObject({fixture['id']})\n if p==nil or CreatureObject(p):getFirstName()~="{fixture['name']}" then return end\n awardSkill(p,"combat_smuggler_novice")\n awardSkill(p,"combat_smuggler_combat_04")\n CreatureObject(p):addCashCredits(100000)\nend\nfunction Tests:swgxrUnderworldFixtureIncap()\n local p=getSceneObject({fixture['id']}) if p then CreatureObject(p):inflictDamage(p,0,100000,1) end\nend\nfunction Tests:swgxrUnderworldFixtureRecover()\n local p=getSceneObject({fixture['id']}) if p then for i=0,8 do CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end; CreatureObject(p):setPosture(0) end\nend\nfunction Tests:swgxrUnderworldFixtureExpire()\n local p=getSceneObject({fixture['id']}) if p then local s=readScreenPlayData(p,"swgxr_underworld","state");s=string.gsub(s,'"deadline_ms":%d+','"deadline_ms":1');writeScreenPlayData(p,"swgxr_underworld","state",s) end\nend\nfunction Tests:swgxrUnderworldFixtureEncounter()\n local p=getSceneObject({fixture['id']}) if p==nil then return end\n local s=readScreenPlayData(p,"swgxr_underworld","state");s=string.gsub(s,'"next_encounter_ms":%d+','"next_encounter_ms":0');s=string.gsub(s,'"encounter_x":[%d%.%-]+','"encounter_x":0');s=string.gsub(s,'"encounter_y":[%d%.%-]+','"encounter_y":0');writeScreenPlayData(p,"swgxr_underworld","state",s)\n for _,i in ipairs({{0,3,6}}) do CreatureObject(p):setMaxHAM(i,100000);CreatureObject(p):setBaseHAM(i,100000);CreatureObject(p):setHAM(i,100000) end\nend\nfunction Tests:swgxrUnderworldFixtureMoveOut()\n local p=getSceneObject({fixture['id']}) if p then SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0) end\nend\nfunction Tests:swgxrUnderworldFixtureLedger()\n local p=getSceneObject({fixture['id']});return readScreenPlayData(p,"swgxr_underworld","state")\nend\nfunction Tests:swgxrUnderworldFixtureEnemyWorld(oid)\n local p=getSceneObject(tonumber(oid));if p==nil then return "missing" end;return SceneObject(p):getZoneName()\nend\nfunction Tests:swgxrUnderworldFixturePeace()\n local p=getSceneObject({fixture['id']}) if p then local s=readScreenPlayData(p,"swgxr_underworld","state");local ids=string.match(s,'"encounter_ids":(%b[])') or "";for id in string.gmatch(ids,"%d+") do local n=getSceneObject(tonumber(id));if n then CreatureObject(n):setPvpStatusBitmask(0);CreatureObject(n):forcePeace();AiAgent(n):removeDefenders();AiAgent(n):setOblivious() end end;CreatureObject(p):forcePeace() end\nend\nfunction Tests:swgxrUnderworldFixtureStaleEnemy()\n local p=getSceneObject({fixture['id']}) if p==nil then return end\n local n=spawnMobile("tatooine","deliver_npc",0,-1037,getTerrainHeight(p,-1037,-3537),-3537,0,0)\n local oid=SceneObject(n):getObjectID();writeData("swgxrUnderworldUnrelated:{fixture['id']}",oid)\n local s=readScreenPlayData(p,"swgxr_underworld","state");s=string.gsub(s,'"encounter_ids":%b[]','"encounter_ids":["'..oid..'"]');s=string.gsub(s,'"encounter_incarnation":%d+','"encounter_incarnation":1');writeScreenPlayData(p,"swgxr_underworld","state",s)\nend\nfunction Tests:swgxrUnderworldFixtureUnrelatedExists()\n local n=getSceneObject(readData("swgxrUnderworldUnrelated:{fixture['id']}"));if n==nil then return "missing" end;return SceneObject(n):getZoneName()\nend\nfunction Tests:swgxrUnderworldFixtureCleanupUnrelated()\n local n=getSceneObject(readData("swgxrUnderworldUnrelated:{fixture['id']}"));if n then SceneObject(n):destroyObjectFromWorld() end;deleteData("swgxrUnderworldUnrelated:{fixture['id']}")\nend\nfunction Tests:swgxrUnderworldFixtureTier(n)\n local p=getSceneObject({fixture['id']}) if p==nil then return end\n local rows={{{{"naboo",1907,2352,1000}},{{"lok",400,5226,1500}},{{"endor",-838,1617,2000}},{{"dathomir",542,3053,2500}}}}\n local r=rows[tonumber(n)] if r==nil then return end\n writeScreenPlayData(p,"swgxr_underworld","state",'{{"reputation":'..r[4]..',"mission_id":""}}')\n SceneObject(p):switchZone(r[1],r[2],0,r[3],0)\n SceneObject(p):teleport(r[2],getTerrainHeight(p,r[2],r[3]),r[3],0)\n return SceneObject(p):getZoneName()\nend\n'''
        screenplay.write_text(screenplay.read_text() + added)
        console('reloadscreenplays')
        time.sleep(.5)
        console('runLuaFunction Tests:swgxrUnderworldFixtureGrant')
        time.sleep(.5)
        state = service('status', position=[-1039, 12, -3537], building_id='0', cell_index=0)
        check(state.get('ok') and state['state']['underworld']['eligible'], 'Granted isolated fixture has native novice eligibility')
        broker = next(t for t in state['state']['terminals'] if t.get('kind') == 'underworld' and t['name'] == 'Barak')
        if not args.encounters_only:
            opened = service('open', terminal_id=broker['id'], **pose(broker))
            check(opened.get('ok') and opened['state']['terminal']['eligible'], 'Named original-template Barak opens existing broker dialogue')
            before = total(opened['state']['wallet'])
            check(not opened['state']['underworld']['active_mission_id'], 'Opening dialogue is read-only')
            key = 'underworld_' + secrets.token_hex(12)
            fields = dict(terminal_id=broker['id'], request_id=key, **pose(broker))
            accepted = service('underworld_accept', **fields)
            check(accepted.get('ok'), 'Broker creates native persistent delivery mission')
            active = accepted['state']['underworld']['active_mission_id']
            check(bool(active) and total(accepted['state']['wallet']) == before - 500, 'Front money charged exactly once')
            replay = service('underworld_accept', **fields)
            check(replay.get('ok') and replay['mutation'].get('replayed') and total(replay['state']['wallet']) == before - 500, 'Durable request receipt prevents duplicate deposit and mission')
            duplicate = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            check(duplicate.get('http_error') == 400, 'Second simultaneous Underworld mission rejected')
            giver = contact(accepted['state'], 'giver')
            pickup = service('delivery_pickup', mission_id=active, npc_id=giver['id'], **pose(giver))
            check(pickup.get('ok'), 'Original delivery objective creates actual inventory parcel')
            check(pickup['state']['gcw']['scan']['contraband_count'] >= 1, 'Original patrol scanner counts bound Underworld parcel')
            feign = req('/session/update', dict(base, session_id=session, ready=True, **pose(giver), smuggler_pose=dict(tracked=True, feign=True, upright=False)))
            report['responses'].append(dict(action='feign', response=redact(feign)))
            check(feign.get('snapshot', {}).get('player', {}).get('feigning_death'), 'Fixture enters real native Feign Death during mission')
            check(service('status')['state']['underworld']['active_mission_id'] == active, 'Feigning alone does not fail Underworld mission')
            req('/session/update', dict(base, session_id=session, ready=True, **pose(giver), smuggler_pose=dict(tracked=True, feign=False, upright=True)))
            parcel = next(p for p in pickup['state']['parcels'] if p['mission_id'] == active)
            receiver = contact(pickup['state'], 'receiver')
            wrong = service('delivery_complete', mission_id=active, npc_id=receiver['id'], parcel_id=broker['id'], **pose(receiver))
            check(wrong.get('http_error') == 400, 'Unrelated native object cannot stand in for bound parcel')
            complete = service('delivery_complete', mission_id=active, npc_id=receiver['id'], parcel_id=parcel['id'], **pose(receiver))
            check(complete.get('ok'), 'Original receiver consumes bound parcel')
            old_active = active
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                final = service('status')['state']
                if not any(m['id'] == old_active for m in final['missions']):
                    break
                time.sleep(.2)
            check(not final['underworld']['active_mission_id'] and final['underworld']['reputation'] == 50, 'Completion persists 50 reputation and clears travel lock')
            check(total(final['wallet']) == before - 500 + 5000, 'Original mission reward pays exact configured credits')
            check(not any(p['id'] == parcel['id'] for p in final['parcels']), 'Consumed native parcel disappears')
            active = ''
            second = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            check(second.get('ok'), 'Next repeatable broker mission available')
            active = second['state']['underworld']['active_mission_id']
            abort = service('mission_abort', mission_id=active)
            check(abort.get('ok') and abort['state']['underworld']['reputation'] == 40, 'Native abort forfeits deposit and reduces reputation by 10')
            check(not abort['state']['underworld']['active_mission_id'], 'Abort clears native Underworld lifecycle')
            active = ''
            expiring = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            active = expiring['state']['underworld']['active_mission_id']
            console('runLuaFunction Tests:swgxrUnderworldFixtureExpire')
            time.sleep(.3)
            expired = service('status')['state']
            check(not expired['underworld']['active_mission_id'] and expired['underworld']['reputation'] == 30, 'Persisted expired deadline fails native mission with one penalty')
            active = ''
            incapping = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            active = incapping['state']['underworld']['active_mission_id']
            console('runLuaFunction Tests:swgxrUnderworldFixtureIncap')
            time.sleep(.3)
            incapacitated = service('status')['state']
            check(not incapacitated['underworld']['active_mission_id'] and incapacitated['underworld']['reputation'] == 20, 'Actual native incapacitation fails delivery and forfeits deposit')
            active = ''
            console('runLuaFunction Tests:swgxrUnderworldFixtureRecover')
            time.sleep(.3)
            for index, planet, name, reputation, deposit, reward in [(1, 'naboo', 'Ogden', 1000, 1000, 5000), (2, 'lok', 'Baldwin', 1500, 2000, 10000), (3, 'endor', 'Harding', 2000, 3000, 15000), (4, 'dathomir', 'Russell', 2500, 18000, 50000)]:
                check(lua_result('swgxrUnderworldFixtureTier:' + str(index)) == planet, 'Live isolated fixture enters native ' + planet + ' before logout')
                stopped = req('/combat/session/stop', dict(base, zone=planet, session_id=session))
                check(not stopped.get('http_error'), 'Native fixture session stops after ' + planet + ' setup')
                session = ''
                entered = req('/enter', base)
                location = entered['source_location']
                check(location['zone'] == planet, 'Isolated native fixture transported to enabled ' + planet)
                zone = planet
                started = req('/session/start', dict(base, zone=zone, **pose(location)))
                check(started.get('session_live'), 'Native session starts on ' + planet)
                session = started['session_id']
                req('/session/update', dict(base, zone=zone, session_id=session, **pose(location), ready=True))
                state = service('status')['state']
                broker = next(t for t in state['terminals'] if t.get('kind') == 'underworld' and t['name'] == name)
                opened = service('open', terminal_id=broker['id'], **pose(broker))
                check(opened.get('ok') and opened['state']['terminal']['eligible'], name + ' tier boundary permits native delivery')
                balance = total(opened['state']['wallet'])
                accepted = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
                check(accepted.get('ok'), name + ' generates actual same-planet native route')
                active = accepted['state']['underworld']['active_mission_id']
                giver = contact(accepted['state'], 'giver')
                picked = service('delivery_pickup', mission_id=active, npc_id=giver['id'], **pose(giver))
                check(picked.get('ok'), name + ' original native contact supplies parcel')
                parcel = next(p for p in picked['state']['parcels'] if p['mission_id'] == active)
                receiver = contact(picked['state'], 'receiver')
                complete = service('delivery_complete', mission_id=active, npc_id=receiver['id'], parcel_id=parcel['id'], **pose(receiver))
                check(complete.get('ok'), name + ' original native receiver consumes parcel')
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    state = service('status')['state']
                    if not any(m['id'] == active for m in state['missions']):
                        break
                    time.sleep(.2)
                check(state['underworld']['reputation'] == reputation + 25 and total(state['wallet']) == balance - deposit + reward, name + ' rewards exact native credits and reputation')
                active = ''
        if args.test_encounters:
            # Return only this new fixture to Tier 1; original reward tests above
            # have already completed. Exercise native scheduled interception and
            # cleanup separately, with high test HAM to avoid incidental deaths.
            extra = f'\nfunction Tests:swgxrUnderworldFixtureReturn() local p=getSceneObject({fixture["id"]});writeScreenPlayData(p,"swgxr_underworld","state",\'{{"reputation":0,"mission_id":""}}\');SceneObject(p):switchZone("tatooine",-1039,0,-3537,0);SceneObject(p):teleport(-1039,getTerrainHeight(p,-1039,-3537),-3537,0);return SceneObject(p):getZoneName() end\n'
            screenplay.write_text(screenplay.read_text() + extra)
            added += extra
            console('reloadscreenplays')
            time.sleep(.3)
            check(lua_result('swgxrUnderworldFixtureReturn') == 'tatooine', 'Live isolated fixture returns to Tatooine before logout')
            stopped = req('/combat/session/stop', dict(base, zone='tatooine', session_id=session))
            check(not stopped.get('http_error'), 'Native fixture session stops after outdoor setup')
            session = ''
            location = req('/enter', base)['source_location']
            zone = 'tatooine'
            started = req('/session/start', dict(base, zone=zone, **pose(location)))
            session = started['session_id']
            req('/session/update', dict(base, zone=zone, session_id=session, **pose(location), ready=True))
            state = service('status')['state']
            broker = next(t for t in state['terminals'] if t.get('kind') == 'underworld' and t['name'] == 'Barak')
            accepted = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            active = accepted['state']['underworld']['active_mission_id']
            giver = contact(accepted['state'], 'giver')
            picked = service('delivery_pickup', mission_id=active, npc_id=giver['id'], **pose(giver))
            check(picked.get('ok'), 'Interception fixture owns original bound parcel')
            console('runLuaFunction Tests:swgxrUnderworldFixtureMoveOut')
            time.sleep(.3)
            req('/combat/session/stop', dict(base, session_id=session))
            session = ''
            location = req('/enter', base)['source_location']
            started = req('/session/start', dict(base, zone=zone, **pose(location)))
            session = started['session_id']
            ready = req('/session/update', dict(base, zone=zone, session_id=session, **pose(location), ready=True))
            check(not ready['snapshot']['player']['on_load_screen'], 'Outdoor fixture acknowledges actual native scene readiness')
            deadline = time.monotonic() + 180
            spawned = None
            while time.monotonic() < deadline:
                console('runLuaFunction Tests:swgxrUnderworldFixtureEncounter')
                time.sleep(.3)
                state = service('status')['state']
                update = req('/session/update', dict(base, zone=zone, session_id=session, **pose(state['player']), ready=True))
                report['encounter_probe'] = update
                if state['underworld'].get('encounter_count', 0) > 0:
                    ledger = json.loads(lua_result('swgxrUnderworldFixtureLedger'))
                    spawned = ledger['encounter_ids']
                    report['encounter_ledger'] = ledger
                    report['encounter_snapshot'] = update
                    break
                time.sleep(2)
            check(state['underworld'].get('encounter_count', 0) == 1, 'Native scheduled ground interception spawns after parcel pickup and travel')
            # Capture the exact native actor id and confirm terminal-outcome cleanup.
            actors = update['snapshot'].get('actors', update['snapshot'].get('world', {}).get('actors', []))
            check(bool(spawned) and all(any(a['id'] == oid for a in actors) for oid in spawned), 'Exact ledger-bound criminals appear in authoritative live actor snapshot')
            console('runLuaFunction Tests:swgxrUnderworldFixturePeace')
            time.sleep(.3)
            check(all(lua_result('swgxrUnderworldFixtureEnemyWorld:' + oid) == 'tatooine' for oid in spawned), 'Exact recorded criminals remain in native world before abort cleanup')
            aborted = service('mission_abort', mission_id=active)
            check(aborted.get('ok'), 'Native mission abort allowed after isolated fixture leaves combat')
            active = ''
            update = req('/session/update', dict(base, zone=zone, session_id=session, **pose(aborted['state']['player']), ready=True))
            check(all(lua_result('swgxrUnderworldFixtureEnemyWorld:' + oid) in ('', 'missing') for oid in spawned), 'Exact recorded criminals have no native world membership after abort')
            check(not any(a['id'] in spawned for a in update['snapshot'].get('actors', update['snapshot'].get('world', {}).get('actors', []))), 'Native mission abort removes its recorded transient criminal')
            stale = service('underworld_accept', terminal_id=broker['id'], **pose(broker))
            check(stale.get('ok'), 'Isolated fixture starts restart-safety mission')
            active = stale['state']['underworld']['active_mission_id']
            console('runLuaFunction Tests:swgxrUnderworldFixtureStaleEnemy')
            time.sleep(.3)
            check(lua_result('swgxrUnderworldFixtureUnrelatedExists') == 'tatooine', 'Unrelated fixture NPC exists before stale-id cleanup test')
            aborted = service('mission_abort', mission_id=active)
            active = ''
            check(aborted.get('ok') and lua_result('swgxrUnderworldFixtureUnrelatedExists') == 'tatooine', 'Stale process incarnation cannot delete unrelated native NPC')
            console('runLuaFunction Tests:swgxrUnderworldFixtureCleanupUnrelated')
        report['passed'] = True
    finally:
        if active:
            try:
                console('runLuaFunction Tests:swgxrUnderworldFixturePeace')
                time.sleep(.3)
                service('mission_abort', mission_id=active)
            except Exception as error:
                report['cleanup_error'] = str(error)
        if added:
            console('runLuaFunction Tests:swgxrUnderworldFixtureCleanupUnrelated')
        if session:
            req('/session/logout', dict(base, live_session_id=session))
        if added:
            current = screenplay.read_text()
            for snippet in [added.split('\nfunction Tests:swgxrUnderworldFixtureReturn')[0], ('\nfunction Tests:swgxrUnderworldFixtureReturn' + added.split('\nfunction Tests:swgxrUnderworldFixtureReturn', 1)[1]) if '\nfunction Tests:swgxrUnderworldFixtureReturn' in added else '']:
                if snippet:
                    current = current.replace(snippet, '')
            screenplay.write_text(current)
        console('reloadscreenplays')
        output = ROOT / 'runtime/evidence/underworld-native-smoke.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(redact(report), indent=2) + '\n')
        print(json.dumps(dict(passed=report['passed'], checks=len(report['checks']), evidence=str(output))))


if __name__ == '__main__':
    main()
