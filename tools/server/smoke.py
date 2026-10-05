#!/usr/bin/env python3
"""Live acceptance test: never substitutes a fake server."""
import argparse
import json
from pathlib import Path
import sys
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:18080')
    parser.add_argument('--account', default='viability')
    parser.add_argument('--name', default='Tavren')
    parser.add_argument('--expect-id', help='Require an existing identity; never create a replacement.')
    parser.add_argument('--report', default='smoke-report.json')
    args = parser.parse_args()
    report = {'started_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'checks': []}
    def request(path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(args.url + path, data=data, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=75) as response:
            return json.load(response)
    try:
        health = request('/health')
        report['health'] = health
        if not health.get('core3', {}).get('ready'):
            raise RuntimeError('Actual Core3 login and zone are not ready.')
        report['checks'].append('actual_core3_login_and_zone')
        chars = request('/characters?account=' + args.account)['characters']
        char = next((c for c in chars if c['name'].lower() == args.name.lower()), None)
        if args.expect_id and (char is None or char['id'] != args.expect_id):
            raise RuntimeError('Persistent character identity was not retained across restart.')
        if char is None:
            char = request('/characters', {'account': args.account, 'name': args.name,
                                          'species': 'human_male'})['character']
            report['checks'].append('created_character_in_core3')
        else:
            report['checks'].append('reused_persistent_character')
        report['character'] = char
        # This performs a new Core3 login process, not a cache lookup.
        fresh = request('/characters?account=' + args.account)['characters']
        if char['id'] not in [c['id'] for c in fresh]:
            raise RuntimeError('Character missing from fresh Core3 login enumeration.')
        report['checks'].append('persistent_character_visible_on_new_login')
        entry = request('/enter', {'account': args.account, 'character_id': char['id']})
        if entry.get('backend') != 'core3' or not entry.get('core3_zone_verified'):
            raise RuntimeError('Entry did not verify an actual Core3 zone scene.')
        report['entry'] = entry
        report['checks'].append('selected_character_and_received_core3_scene')
        report['status'] = 'passed'
        exit_code = 0
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        report['status'] = 'blocked' if not report['checks'] else 'failed'
        report['error'] = str(exc)
        if isinstance(exc, urllib.error.HTTPError):
            report['response'] = exc.read().decode()
        exit_code = 1
    target = ROOT / 'runtime/server' / Path(args.report).name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return exit_code

if __name__ == '__main__':
    sys.exit(main())
