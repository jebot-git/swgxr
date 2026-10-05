#!/usr/bin/env python3
"""Normal gameplay session uses native ranged authority and public peer cues.

Uses the existing authorized Varek fixture, no skill or equipment grants.
Creates/removes one original test lair. No live headset or remote realm mutation.
"""
import json, secrets, time
from services_smoke import ROOT, req, redact
from live_combat_smoke import Test
from equipment_smoke import console


def main():
    shooter = json.loads((ROOT/'runtime/server/ranged-test-fixture.json').read_text())
    peer = json.loads((ROOT/'runtime/server/services-fixture.json').read_text())
    assert shooter['id'] == '281474993659303' and shooter['account'] == 'rangetest1a142'
    assert peer['account'].startswith('invtest')
    report = {'passed': False, 'native_execution': True, 'checks': [], 'responses': []}
    saved, sessions, spawned = {}, {}, set()
    t = Test(shooter, 'http://127.0.0.1:18080')
    pose = dict(position=shooter['position'], heading_radians=0, building_id='0', cell_index=0)
    def check(value, label):
        report['checks'].append({'passed': bool(value), 'label': label})
        print(label, bool(value), flush=True)
        assert value, label
    def call(f, path, **data):
        out = req(path, dict(account=f['account'], character_id=f['id'], **data))
        report['responses'].append({'path': path, 'response': redact(out)})
        assert not out.get('http_error'), out
        return out
    try:
        for f in (peer, shooter):
            saved[f['id']] = call(f, '/enter')['source_location']
            started = call(f, '/session/start', **pose, **({'spawn_test_lair': True} if f is shooter else {}))
            sessions[f['id']] = started['session_id']
            check(started['source_kind'] == 'core3_gameplay_session', 'Original normal gameplay session starts '+('shooter' if f is shooter else 'observer'))
            call(f, '/session/update', session_id=sessions[f['id']], ready=True, **pose)
        check(started['snapshot']['weapon']['certified'] and started['snapshot']['weapon']['item_id'] == shooter['weapon_item_id'], 'Normal gameplay envelope exposes actual certified owned weapon')
        t.session = sessions[shooter['id']]
        native = t.poll()
        lair_id = native['snapshot']['test_lair_id']
        assert lair_id
        spawned.add(lair_id)
        lair = t.actor(lair_id)
        assert lair is not None
        before = lair['health']
        accepted, damaged, public = False, False, False
        for attempt in range(5):
            call(peer, '/session/update', session_id=sessions[peer['id']], ready=True, **pose)
            launch, impact = t.shot(t.actor(lair_id))
            report['responses'].append({'path': 'native_fire_impact', 'response': {'launch': redact(launch), 'impact': redact(impact)}})
            accepted |= bool(impact.get('mutation', {}).get('success'))
            damaged |= bool(t.actor(lair_id) and t.actor(lair_id)['health'] < before)
            seen = call(peer, '/session/sync', session_id=sessions[peer['id']], sequence=attempt+1, tracking={}, **pose)
            kinds = {e['kind'] for e in seen['events'] if e['actor_id'] == shooter['id']}
            public |= {'fire', 'impact'} <= kinds
            if accepted and damaged and public:
                break
        check(accepted, 'Existing combat fire/impact accepts owned normal gameplay session')
        check(damaged, 'Original native attack decreases actual lair condition')
        check(public, 'Other player receives only confirmed native fire/impact cues')
        observed = call(peer, '/session/update', session_id=sessions[peer['id']], ready=True, **pose)
        check(next(a for a in observed['snapshot']['world']['actors'] if a['id'] == lair_id)['health'] < before, 'Other player receives actual changed lair health in shared native world')
        t.poll()
        spawned.update(a['id'] for a in t.last['snapshot']['actors'] if a.get('lair_id') == lair_id)
        report['passed'] = True
    finally:
        if t.session:
            try:
                t.poll()
                lair_id = t.last['snapshot'].get('test_lair_id', '')
                spawned.update(a['id'] for a in t.last['snapshot']['actors'] if a.get('lair_id') == lair_id)
            except Exception:
                pass
        for f in (shooter, peer):
            if f['id'] not in sessions:
                continue
            try:
                call(f, '/session/logout', live_session_id=sessions[f['id']], request_id='restore_'+secrets.token_hex(8), **{k: saved[f['id']][k] for k in ('position', 'building_id', 'cell_index', 'heading_radians')})
            except Exception as error:
                report.setdefault('cleanup_errors', []).append(str(error)); report['passed'] = False
        if spawned:
            path = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
            original = path.read_text()
            cleanup = '\nfunction Tests:swgxrCleanupMultiplayerLair()\n' + ''.join(f' local p=getSceneObject({oid}) if p~=nil then SceneObject(p):destroyObjectFromWorld() end\n' for oid in sorted(spawned)) + 'end\n'
            try:
                path.write_text(original+cleanup)
                console('reloadscreenplays'); time.sleep(.5)
                console('runLuaFunction Tests:swgxrCleanupMultiplayerLair'); time.sleep(.5)
            finally:
                path.write_text(original); console('reloadscreenplays')
        report['cleaned_ephemeral_ids'] = sorted(spawned)
        (ROOT/'runtime/evidence/multiplayer-native-combat.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'passed': report['passed'], 'checks': len(report['checks'])}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
