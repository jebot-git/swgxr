#!/usr/bin/env python3
"""Explicit administrator provisioning of exactly32 new dedicated load fixtures.

Run as the gateway database owner, after backing up and auditing the migrated
realm. This bounded administrative import uses the normal credential KDF and
session format. It does not alter public registration limits or existing rows.
The private export is prepared before the atomic database transaction, making
interruption recoverable. No credential values are written to stdout.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from server.account_auth import SESSION_SECONDS, account_name, derive, password_bytes
def private_write(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as out:
        os.fchmod(out.fileno(), 0o600)
        json.dump(value, out, indent=2)
        out.write('\n')
    temp.replace(path)


def seed(database, output, prefix):
    if not database.is_file():
        raise ValueError('Existing audited authentication database required.')
    if not re.fullmatch(r'loadtest_[a-z0-9]{4,8}', prefix):
        raise ValueError('Use a unique loadtest_ prefix followed by4–8 lowercase letters/digits.')
    names = [account_name(prefix + '_' + str(n).zfill(2)) for n in range(1, 33)]
    if output.exists():
        fixture = json.loads(output.read_text())
        if (fixture.get('purpose') != 'corecu_population_test'
                or [p['account'] for p in fixture.get('players', [])] != names):
            raise ValueError('Existing export belongs to another fixture set.')
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        fixture = {'purpose': 'corecu_population_test', 'provisioning': 'administrator_new_accounts_only',
                   'created_at': int(time.time()), 'players': [
                       {'account': name, 'password': secrets.token_urlsafe(32), 'token': secrets.token_urlsafe(32),
                        'expires_at': int(time.time()) + SESSION_SECONDS} for name in names]}
        private_write(output, fixture)
    db = sqlite3.connect('file:' + str(database.resolve()) + '?mode=rw', uri=True, timeout=30)
    try:
        db.execute('PRAGMA foreign_keys=ON')
        existing = {row[0] for row in db.execute('SELECT account FROM credentials')}
        overlap = existing.intersection(names)
        if overlap:
            if overlap != set(names):
                raise ValueError('Partial fixture collision; refusing to alter accounts.')
            # A previous completed transaction is safe to resume only with its own
            # private password and exact exported session; never adopt another row.
            for player in fixture['players']:
                salt, digest = db.execute('SELECT salt,password_hash FROM credentials WHERE account=?', (player['account'],)).fetchone()
                if not hmac.compare_digest(derive(password_bytes(player['password']), salt), digest):
                    raise ValueError('Fixture credentials do not match existing accounts.')
                session = db.execute('SELECT account,expires_at FROM sessions WHERE token_hash=?',
                                     (hashlib.sha256(player['token'].encode()).hexdigest(),)).fetchone()
                if session != (player['account'], player['expires_at']) or player['expires_at'] <= time.time():
                    raise ValueError('Fixture session mismatch or expiry requires explicit renewal.')
            return {'passed': True, 'new_auth_accounts': 0, 'reused_auth_accounts': 32,
                    'original_auth_accounts_preserved': len(existing) - 32, 'public_limits_changed': False}
        prepared = []
        for player in fixture['players']:
            salt = secrets.token_bytes(16)
            prepared.append((player, salt, derive(password_bytes(player['password']), salt)))
        with db:
            for player, salt, digest in prepared:
                db.execute('INSERT INTO credentials(account,salt,password_hash,created_at,legacy_disabled) VALUES(?,?,?,?,0)',
                           (player['account'], salt, digest, fixture['created_at']))
                db.execute('INSERT INTO sessions(token_hash,account,expires_at) VALUES(?,?,?)',
                           (hashlib.sha256(player['token'].encode()).hexdigest(), player['account'], player['expires_at']))
        return {'passed': True, 'new_auth_accounts': 32, 'reused_auth_accounts': 0,
                'original_auth_accounts_preserved': len(existing), 'public_limits_changed': False}
    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prefix', required=True)
    args = parser.parse_args()
    try:
        result = seed(args.database, args.output, args.prefix)
    except Exception as exc:
        result = {'passed': False, 'failure_type': type(exc).__name__}
    print(json.dumps(result))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
