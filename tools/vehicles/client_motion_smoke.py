#!/usr/bin/env python3
"""Verify negotiated vehicle poses on the loopback Core3 fixture, without XR.

Uses existing invtestvehicle accounts and rides; restores player/vehicle poses
and releases seats. Does not grant items or change the live realm.
"""
import json
import math
import time
import urllib.error

import live_smoke as native


_request = native.request


def diagnostic_request(path, data=None):
    try:
        return _request(path, data)
    except urllib.error.HTTPError as error:
        payload = json.loads(error.read())
        print(json.dumps({'path': path, 'http_status': error.code,
                          'error': payload.get('error', '')}), flush=True)
        raise


native.request = diagnostic_request


def run():
    report = {"passed": False, "native_execution": True, "headset_tested": False,
              "checks": [], "cleanup_errors": []}
    initial = []
    original = None
    spawned_here = False
    device = None

    def check(condition, label):
        report["checks"].append({"passed": bool(condition), "label": label})
        print(label, bool(condition), flush=True)
        assert condition, label

    def submit(index, vehicle, **overrides):
        controls = dict(mode="client_pose", vehicle_id=vehicle["id"],
                        position=vehicle["position"], heading_radians=vehicle["heading_radians"],
                        speed=0, held=True, throttle=0, steer=0)
        controls.update(overrides)
        return native.request('/combat/session/update', dict(native.bases[index],
                              ready=True, vehicle_controls=controls))

    def state(response):
        assert not response.get('error_code'), response.get('error_code')
        return response['snapshot']['player']['vehicles']

    def ride(snapshot):
        return next(v for v in snapshot['vehicles'] if v['id'] == original['id'])

    def board(index, seat_name):
        seat = next(s for s in original['seats'] if s['id'] == seat_name)
        hand = native.local(original, seat['position'])
        native.bases[index]['position'] = [hand[0], original['position'][1], hand[2]]
        native.update(index)
        return native.act(index, 'board', vehicle_id=original['id'], seat=seat_name, hand=hand)

    def rejected(index, vehicle, **fields):
        try:
            response = submit(index, vehicle, **fields)
        except urllib.error.HTTPError as error:
            return error.code == 400
        return bool(response.get('error_code') or response.get('error'))

    try:
        for fixture in native.fixtures:
            pose = native.request('/medic/status', dict(account=fixture['account'],
                                  character_id=fixture['id']))['state']['position']
            initial.append(pose)
            base = dict(account=fixture['account'], character_id=fixture['id'], position=pose)
            started = native.request('/combat/session/start', base)
            base['session_id'] = started['session_id']
            native.bases.append(base)
            native.update(len(native.bases) - 1)
        snapshot = native.act(0, 'status')['state']
        check(snapshot.get('driver_motion') == 'client_pose', 'Running Core3 advertises client pose support')
        check(not snapshot['seat'], 'Fixture begins unseated')
        device = next(d for d in snapshot['datapad'] if 'landspeeder_x34' in d['template'])
        spawned_here = not device['spawned']
        original = (native.called(device) if spawned_here else
                    next(v for v in snapshot['vehicles'] if v['device_id'] == device['id']))
        check(all(not seat['occupant_id'] for seat in original['seats']), 'Fixture ride begins unoccupied')
        board(0, 'driver')
        board(1, 'passenger')
        target = list(original['position'])
        target[0] += 1.25
        target[1] += .2
        heading = math.remainder(original['heading_radians'] + .2, 2 * math.pi)
        updated = state(submit(0, original, position=target, heading_radians=heading, speed=2))
        moved = ride(updated)
        check(math.dist(moved['position'], target) < .002 and abs(moved['speed'] - 2) < .001,
              'Native ride publishes the exact resolved client pose and bounded speed')
        check(abs(math.remainder(moved['heading_radians'] - heading, 2 * math.pi)) < .001,
              'Native ride publishes client heading')
        observed = native.act(1, 'status')['state']
        check(math.dist(ride(observed)['position'], target) < .002,
              'Passenger observes the same pose without extra throttle integration')
        expected = native.local(moved, original['seats'][1]['position'])
        check(math.dist(observed['position'], expected) < .002, 'Passenger is carried to the original seat socket')
        check(rejected(1, moved, position=original['position']), 'Passenger cannot submit driver poses')
        check(rejected(0, moved, vehicle_id='1'), 'Driver cannot submit a different ride ID')
        check(rejected(0, moved, speed=original['max_speed'] + 1), 'Native ride speed cap rejects client overspeed')
        check(rejected(0, moved, position=[8192, target[1], target[2]]), 'Native world boundary rejects out-of-zone motion')
        check(math.dist(ride(native.act(0, 'status')['state'])['position'], target) < .002,
              'Rejected packets preserve the accepted vehicle pose')
        time.sleep(4.2)
        stale = ride(native.act(0, 'status')['state'])
        check(abs(stale['speed']) < .001 and math.dist(stale['position'], target) < .002,
              'Stale client motion stops speed without extrapolating position')
        state(submit(0, original))
        legacy = native.update(0, 1, 0, True)
        for _ in range(3):
            legacy = native.update(0, 1, 0, True)
        check(math.dist(ride(legacy)['position'], original['position']) > .05,
              'Legacy controls still integrate on the updated server')
        report['passed'] = True
    finally:
        if original and native.bases:
            try:
                snapshot = native.act(0, 'status')['state']
                if snapshot['seat'].get('id') == 'driver':
                    state(submit(0, original))
                for index in reversed(range(len(native.bases))):
                    if native.act(index, 'status')['state']['seat']:
                        native.act(index, 'dismount')
                if spawned_here:
                    native.bases[0]['position'] = original['position']
                    native.update(0, position=original['position'])
                    touch = native.local(original, [0, .7, 0])
                    native.act(0, 'store', device_id=device['id'], left=touch, right=touch)
            except Exception as error:
                report['cleanup_errors'].append(str(error))
        for index, base in enumerate(native.bases):
            try:
                native.update(index, position=initial[index])
                native.request('/combat/session/stop', base)
            except Exception as error:
                report['cleanup_errors'].append(str(error))
        report['passed'] &= not report['cleanup_errors']
        output = native.ROOT / 'runtime/evidence/vehicle-client-motion-native.json'
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(run())
