#!/usr/bin/env python3
"""Measure read-only service RPCs on an existing dedicated remote test character.

No renderer, XR session or fixture creation. Optional persistent mode enters and
logs off the existing test character at its saved position. Results contain timings
and response kinds only; credentials and player snapshots are never written.
"""
import argparse
import json
from pathlib import Path
import statistics
import secrets
import time
from urllib.parse import urlencode

from remote_connection import RemoteConnection

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, default=ROOT/'runtime/deploy/credentials/nettest_one.json')
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--persistent', action='store_true', help='Keep the original native connection across all reads, then save/logout.')
    parser.add_argument('--rounds', type=int, choices=range(1, 11), default=3)
    args = parser.parse_args()
    connection = RemoteConnection.load(args.profile)
    if connection.account not in ('nettest_one', 'nettest_two'):
        raise ValueError('Only dedicated network-test accounts may be probed.')
    report = {'passed': False, 'native_execution': True, 'rendering': 'none',
              'xr': 'not launched', 'requests': [], 'summary': {}, 'persistent': args.persistent}
    session_id = ''
    identity = {}
    pose = {}
    try:
        roster = connection.request_json('/characters?' + urlencode({'account': connection.account}))
        character = roster['characters'][0]
        identity = {'account': connection.account, 'character_id': str(character['id'])}
        if args.persistent:
            entry = connection.request_json('/enter', method='POST', body=identity)
            location = entry['source_location']
            pose = {key: location[key] for key in ('position', 'building_id', 'cell_index', 'heading_radians')}
            started = connection.request_json('/session/start', method='POST', body=dict(identity, **pose))
            session_id = started.get('session_id', '')
            if not session_id or not started.get('session_live') or started.get('source_kind') != 'core3_gameplay_session':
                raise AssertionError('Native gameplay session was not confirmed.')
        operations = [('services', '/services/status', identity),
                      ('gathering', '/gathering?' + urlencode(identity), None),
                      ('crafting', '/crafting?' + urlencode(identity), None),
                      ('inventory', '/inventory?' + urlencode(identity), None)]
        for _ in range(args.rounds):
            for kind, path, body in operations:
                start = time.monotonic()
                value = connection.request_json(path, method='POST' if body is not None else 'GET', body=body)
                elapsed = round((time.monotonic() - start) * 1000, 2)
                valid = value.get('backend') == 'core3' and value.get('source_kind') == 'core3_' + kind
                report['requests'].append({'kind': kind, 'milliseconds': elapsed, 'passed': valid})
                if not valid:
                    raise AssertionError('Native response type did not match requested service.')
        for kind, _, _ in operations:
            times = [r['milliseconds'] for r in report['requests'] if r['kind'] == kind]
            report['summary'][kind] = {'median_ms': round(statistics.median(times), 2), 'max_ms': max(times), 'count': len(times)}
        if args.persistent:
            updated = connection.request_json('/session/update', method='POST', body=dict(identity, **pose, session_id=session_id))
            report['same_session_after_reads'] = updated.get('session_id') == session_id and updated.get('session_live') is True
            if not report['same_session_after_reads']:
                raise AssertionError('Native session was evicted by an RPG read.')
        report['passed'] = True
    except Exception as exc:
        report['failure_type'] = type(exc).__name__
    finally:
        if session_id:
            try:
                saved = connection.request_json('/session/logout', method='POST', body=dict(identity, **pose, live_session_id=session_id, request_id=secrets.token_hex(16)))
                report['logout_saved'] = saved.get('saved') is True and saved.get('session_closed') is True
                report['passed'] = report['passed'] and report['logout_saved']
            except Exception as exc:
                report['passed'] = False
                report['cleanup_failure_type'] = type(exc).__name__
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
