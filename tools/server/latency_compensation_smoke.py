#!/usr/bin/env python3
"""Exercise bounded ordinary-bolt timing against local Core3 using a new marksman."""
import json
import secrets
import time
from services_smoke import ROOT, req, redact


def main():
    fixture = {'account': 'invtesttiming'+secrets.token_hex(4)}
    for _ in range(10):
        fixture['name'] = 'Ivtest'+''.join(secrets.choice('aeilnorst') for _ in range(9))
        created = req('/characters', dict(fixture, species='human', profession='combat_marksman'))
        if 'character' in created:
            break
    assert 'character' in created, created
    fixture['id'] = created['character']['id']
    base = dict(account=fixture['account'], character_id=fixture['id'])
    report = dict(passed=False, native_execution=True, server_mocked=False,
                  headset_tested=False, gpu_tested=False, fixture=fixture, checks=[], responses=[])
    session = ''
    location = {}

    def check(ok, label):
        report['checks'].append(dict(passed=bool(ok), label=label))
        print(label, bool(ok), flush=True)
        assert ok, label

    def call(path, **fields):
        if session:
            fields.setdefault('live_session_id' if path=='/session/logout' else 'session_id', session)
        started = time.monotonic()
        result = req(path, dict(base, **fields))
        report['responses'].append(dict(path=path, elapsed_ms=round((time.monotonic()-started)*1000, 3), response=redact(result)))
        return result

    try:
        entered = call('/enter')
        check('source_location' in entered, 'Disposable marksman enters real Core3')
        inventory = call('/inventory/status')
        pistol = next(row for row in inventory['items'] if row.get('template','').endswith('/pistol_cdef.iff'))
        equipped = call('/inventory/equip', item_id=pistol['id'])
        check(equipped.get('mutation',{}).get('success', False), 'Equip owned native CDEF pistol')
        player = call('/services/status')['state']['player']
        location = {key: player[key] for key in ('position','building_id','cell_index')}
        started = call('/session/start', **location)
        check(started.get('session_live', False), 'Persistent ordinary gameplay session owns fixture')
        session = started['session_id']
        ready = call('/session/update', ready=True, **location)
        weapon = ready['snapshot']['weapon']
        check(ready['snapshot']['player'].get('on_load_screen') is False and weapon['item_id']==pistol['id'], 'Native readiness and weapon identity confirmed')
        origin = list(ready['snapshot']['player']['position'])
        origin[1] += 1

        def fire(identity, age=.12):
            return call('/combat/session/fire', shot_id=identity, item_id=pistol['id'],
                        origin=origin, direction=[1,0,0], two_hands=True,
                        firing_posture='standing', launch_age_seconds=age)

        first = fire('timing_native_first')
        first_finished = time.monotonic()
        mutation = first['mutation']
        interval = mutation['interval_seconds']
        check(mutation.get('success') and mutation.get('latency_compensated') and mutation.get('ham_cost_committed'), 'Ordinary native fire commits once and exposes timing receipt')
        check(mutation['accepted_launch_age_seconds']==.12 and 0<mutation['cooldown_remaining_seconds']<=interval, 'Native receipt bounds launch age and next ordinary arrival')
        duplicate = fire('timing_native_first')
        check(duplicate.get('error_code')=='duplicate_shot' and not duplicate['mutation'].get('ham_cost_committed',False), 'Duplicate native launch cannot commit another cost')
        check(all(a>=b for a,b in zip(duplicate['snapshot']['player']['ham'],first['snapshot']['player']['ham'])), 'Duplicate receipt loses no additional native HAM')
        early = fire('timing_native_too_early', age=999)
        check(early.get('error_code')=='cadence' and not early['mutation'].get('ham_cost_committed',False), 'Forged launch age cannot bypass native sustained cadence')
        # The next packet intentionally arrives somewhat before strict recovery.
        # Local HTTP/native overhead is recorded; policy tests prove exact bounds.
        delay = first_finished+interval-.15-time.monotonic()
        if delay>0:
            time.sleep(delay)
        second = fire('timing_native_jitter')
        check(second['mutation'].get('success') and second['mutation'].get('latency_compensated'), 'Delayed/jittered ordinary launch accepted with native reservation')
        rejected = fire('timing_native_no_burst')
        check(rejected.get('error_code')=='cadence' and not rejected['mutation'].get('ham_cost_committed',False), 'Compensated launch does not permit a catch-up burst')
        report['passed'] = True
    finally:
        if session:
            call('/session/logout', **location)
        out = ROOT/'runtime/evidence/aim-latency-20261010/native-timing.json'
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(dict(passed=report['passed'], checks=len(report['checks']))), flush=True)


if __name__=='__main__':
    main()
