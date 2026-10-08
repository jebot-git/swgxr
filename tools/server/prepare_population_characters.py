#!/usr/bin/env python3
"""Create/reuse native characters only on explicitly provisioned loadtest accounts.

Private input: purpose=corecu_population_test, players[{account, token}].
Credentials must already exist; this tool neither bypasses public registration
limits nor touches administrative databases. All requests verify TLS and reject
redirects. An ambiguous creation is reconciled by roster, never resubmitted.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import ssl
import string
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.client.remote_connection import NoRedirect, validate_origin
from tools.client.remote_connection import SAFE_ERROR_MESSAGES


def private_write(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as out:
        os.fchmod(out.fileno(), 0o600)
        json.dump(value, out, indent=2)
        out.write('\n')
    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--url', required=True)
    parser.add_argument('--ca', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    origin = validate_origin(args.url)
    fixture = json.loads(args.fixtures.read_text())
    players = fixture.get('players', [])
    if (fixture.get('purpose') != 'corecu_population_test' or not players
            or len({p['account'] for p in players}) != len(players)
            or any(not p['account'].startswith('loadtest_') or not p.get('token') for p in players)):
        raise ValueError('Expected unique, provisioned loadtest_ accounts with private tokens.')
    context = ssl.create_default_context(cafile=str(args.ca))
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context), NoRedirect())
    report = {'passed': False, 'endpoint': origin, 'requested_characters': len(players),
              'native_characters_created': 0, 'native_characters_reused': 0,
              'unrelated_accounts_touched': False, 'requests': [], 'started_at': time.time()}

    def request(player, path, body=None, retries=2):
        raw = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(origin + path, data=raw,
            headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + player['token']})
        started = time.monotonic()
        record = {'path': path, 'success': False}
        try:
            with opener.open(req, timeout=90) as response:
                value = json.load(response)
                record.update(success=True, status=response.status)
                return value
        except urllib.error.HTTPError as exc:
            record['status'] = exc.code
            error = json.loads(exc.read(4096)).get('error', '')
            if error in SAFE_ERROR_MESSAGES:
                record['server_error'] = error
            if path == '/characters' and body is not None:
                record['creation_error'] = str(error).replace(player['token'], '[redacted]')[:512]
            if exc.code == 503 and error == 'Login failed - no account ID received' and retries:
                # Authentication failed before a native character operation was
                # admitted; cold auto-registration can require one retry.
                time.sleep(1)
                return request(player, path, body, retries - 1)
            if path == '/characters' and body is not None and (exc.code == 400 or error in (
                    'Core3 is processing another request; retry shortly', 'Core3 request queue is full; retry shortly',
                    'Login failed - no account ID received')):
                # Only our own generated creation payload is sent on this path.
                record['creation_rejection'] = str(error)[:512]
                player['creation_rejected'] = True
                private_write(args.fixtures, fixture)
            raise
        finally:
            record['seconds'] = time.monotonic() - started
            report['requests'].append(record)

    try:
        for index, player in enumerate(players):
            rows = request(player, '/characters').get('characters', [])
            created_now = False
            if not rows:
                # Save before sending so an interrupted run never blindly resubmits.
                if player.get('creation_sent') and not player.get('creation_rejected'):
                    raise ValueError('Earlier ambiguous character creation requires reconciliation.')
                player['creation_sent'] = True
                player['creation_rejected'] = False
                player['requested_name'] = 'Load' + ''.join(secrets.choice('bcdfghjklmnprstvwz') + secrets.choice('aeiou') for _ in range(4))
                private_write(args.fixtures, fixture)
                try:
                    result = request(player, '/characters', {
                        'name': player['requested_name'],
                        'species': 'human', 'sex': 'male', 'profession': 'combat_marksman'})
                    if str(result.get('character', {}).get('id', '')).isdigit():
                        rows = [result['character']]
                except (urllib.error.URLError, TimeoutError):
                    pass
                if not rows:
                    rows = request(player, '/characters').get('characters', [])
                created_now = True
            if len(rows) != 1 or not str(rows[0].get('id', '')).isdigit():
                raise ValueError('Dedicated fixture must own exactly one native character.')
            character_id = str(rows[0]['id'])
            if player.get('character_id') not in (None, '', character_id):
                raise ValueError('Saved fixture character identity changed.')
            player['character_id'] = character_id
            private_write(args.fixtures, fixture)
            report['native_characters_created' if created_now else 'native_characters_reused'] += 1
            print(json.dumps({'prepared': index + 1, 'total': len(players)}), flush=True)
        report['passed'] = True
    except Exception as exc:
        report['failure_type'] = type(exc).__name__
    finally:
        report['finished_at'] = time.time()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'requests'}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
