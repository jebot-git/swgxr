#!/usr/bin/env python3
"""Explicit live registration/login/Core3 isolation probe, without rendering or XR.

Creates two disposable authprobe_* accounts and one persistent native character.
Passwords/tokens exist in memory only; evidence never contains credentials.
"""
import argparse
import json
from pathlib import Path
import secrets
import string
import time
import urllib.error
import urllib.request

if __package__:
    from .remote_connection import NoRedirect, RemoteConnection
else:
    from remote_connection import NoRedirect, RemoteConnection

ROOT = Path(__file__).resolve().parents[2]


def run(profile):
    connection = RemoteConnection.load(profile)
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=connection._context), NoRedirect())
    report = {'passed': False, 'endpoint': connection.base_url, 'native_execution': True,
              'xr': 'not launched', 'checks': [], 'requests': []}
    sessions = []

    def check(condition, label):
        report['checks'].append({'passed': bool(condition), 'label': label})
        if not condition:
            raise AssertionError(label)

    def request(path, body=None, token='', expected=200):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        raw = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(connection.base_url + path, data=raw, headers=headers)
        started = time.monotonic()
        try:
            response = opener.open(req, timeout=90)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            status = response.code
            data = json.loads(response.read(8 * 1024 * 1024))
        report['requests'].append({'path': path.split('?')[0], 'status': status,
                                   'milliseconds': round((time.monotonic()-started)*1000, 2)})
        check(status == expected, path.split('?')[0] + ': expected HTTP ' + str(expected))
        return data

    try:
        request('/characters', expected=401)
        identities = []
        for _ in range(2):
            account = 'authprobe_' + secrets.token_hex(5)
            password = secrets.token_urlsafe(24)
            result = request('/auth/register', {'account': account, 'password': password}, expected=201)
            sessions.append(result['token'])
            check(result['account'] == account and result['expires_at'] > time.time(), 'Registration binds expiring session')
            identities.append((account, password, result['token']))
        first, second = identities
        for account, _, token in identities:
            session = request('/auth/session', token=token)
            check(session['account'] == account, 'Session identity verified')
            roster = request('/characters', token=token)
            check(roster.get('backend') == 'core3' and roster.get('characters') == [], 'New account has empty native roster')
        request('/characters?account=' + first[0], token=second[2], expected=403)
        health = request('/health', token=first[2])
        check(health.get('backend') == 'core3' and health.get('core3', {}).get('ready') is True, 'Native backend remains ready')
        name = 'Auth' + ''.join(secrets.choice(string.ascii_lowercase) for _ in range(9))
        created = request('/characters', {'name': name, 'species': 'human', 'sex': 'male', 'profession': 'combat_marksman'}, first[2], expected=201)
        character_id = str(created.get('character', {}).get('id', ''))
        check(created.get('backend') == 'core3' and character_id.isdigit(), 'Registered account owns real Core3 character')
        denied = request('/characters/' + character_id, token=second[2], expected=400)
        check('character' not in denied, 'Other account cannot select character by ID')
        request('/auth/logout', {}, first[2])
        sessions.remove(first[2])
        request('/characters', token=first[2], expected=401)
        request('/auth/login', {'account': first[0], 'password': secrets.token_urlsafe(24)}, expected=401)
        signed = request('/auth/login', {'account': first[0], 'password': first[1]})
        sessions.append(signed['token'])
        check(signed['token'] != first[2], 'Login issues a fresh session')
        roster = request('/characters', token=signed['token'])
        check(character_id in {str(row['id']) for row in roster.get('characters', [])}, 'Native character persists across logout/login')
        other = request('/characters', token=second[2])
        check(other.get('characters') == [], 'Second account roster remains isolated')
        report['passed'] = True
    except Exception as exc:
        report['failure_type'] = type(exc).__name__
    finally:
        for token in sessions:
            try:
                request('/auth/logout', {}, token)
            except Exception:
                report['passed'] = False
                report['cleanup_failed'] = True
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, default=ROOT/'runtime/client/connection.json')
    parser.add_argument('--evidence', type=Path, default=ROOT/'runtime/evidence/account-auth/vps-native-auth.json')
    args = parser.parse_args()
    report = run(args.profile)
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': len(report['checks']), 'evidence': str(args.evidence)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
