"""Gateway credentials and revocable sessions; never a replacement Core3 store."""
import hashlib
import hmac
import math
import os
import re
import secrets
import sqlite3
import threading
import time
from collections import deque
from contextlib import contextmanager
from pathlib import Path

SESSION_SECONDS = 24 * 60 * 60
REMEMBER_SECONDS = 90 * 24 * 60 * 60
# OWASP scrypt minimum: N=2^17, r=8, p=1 (~128 MiB per call).
SCRYPT_N, SCRYPT_R, SCRYPT_P = 131072, 8, 1
KDF_SLOTS = threading.BoundedSemaphore(2)

class AuthError(Exception):
    def __init__(self, status, message, retry_after=None):
        super().__init__(message)
        self.status, self.message, self.retry_after = status, message, retry_after


def account_name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-z][a-z0-9_]{2,23}', value):
        raise AuthError(400, 'Account must contain 3–24 lowercase letters, digits or underscores, starting with a letter')
    return value


def password_bytes(value):
    if not isinstance(value, str) or not 12 <= len(value) <= 128:
        raise AuthError(400, 'Password must contain 12–128 characters')
    try:
        encoded = value.encode('utf-8')
    except UnicodeError:
        raise AuthError(400, 'Invalid password encoding') from None
    if len(encoded) > 512:
        raise AuthError(400, 'Password is too long')
    return encoded


def derive(password, salt):
    if not KDF_SLOTS.acquire(blocking=False):
        raise AuthError(429, 'Authentication busy; try again shortly', 2)
    try:
        return hashlib.scrypt(password, salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P,
                              dklen=32, maxmem=192 * 1024 * 1024)
    except (ValueError, MemoryError):
        raise AuthError(503, 'Password verification unavailable') from None
    finally:
        KDF_SLOTS.release()


class RateLimits:
    """Bounded fixed-window histories; saturation fails closed, never evicts limits."""
    def __init__(self, clock=time.monotonic, capacity=4096):
        self.clock, self.capacity, self.lock, self.entries = clock, capacity, threading.Lock(), {}

    def check(self, action, ip, account):
        now = self.clock()
        if action in ('register', 'claim'):
            rules = [(('create-ip', ip), 5, 3600), (('create-account', account), 5, 3600),
                     (('create-global',), 30, 3600), (('create-day',), 120, 86400)]
        else:
            rules = [(('login-ip', ip), 20, 300), (('login-account', account), 10, 300),
                     (('login-global',), 120, 60)]
        with self.lock:
            for key, (window, stamps) in list(self.entries.items()):
                while stamps and stamps[0] <= now - window: stamps.popleft()
                if not stamps: del self.entries[key]
            retry = 0
            for key, limit, window in rules:
                if key in self.entries and len(self.entries[key][1]) >= limit:
                    retry = max(retry, math.ceil(self.entries[key][1][0] + window - now))
            if retry: raise AuthError(429, 'Too many authentication attempts', max(1, retry))
            if len(self.entries) + sum(key not in self.entries for key, _, _ in rules) > self.capacity:
                raise AuthError(429, 'Authentication busy; try again later', 60)
            for key, _, window in rules:
                if key not in self.entries: self.entries[key] = (window, deque())
                self.entries[key][1].append(now)


class AccountAuth:
    def __init__(self, database, *, reserved=(), registration_enabled=False, clock=time.time):
        if not isinstance(registration_enabled, bool): raise ValueError('registration_enabled must be boolean')
        self.database = str(Path(database).absolute())
        self.reserved = frozenset(reserved) | {'health'}
        self.registration_enabled, self.clock = registration_enabled, clock
        self.limits = RateLimits()
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        # Create privately before SQLite opens it; preserve existing database contents.
        fd = os.open(self.database, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        os.chmod(self.database, 0o600)
        with self.connection() as db:
            db.executescript('''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS credentials (
                account TEXT PRIMARY KEY, salt BLOB NOT NULL, password_hash BLOB NOT NULL,
                created_at INTEGER NOT NULL, legacy_disabled INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES credentials(account),
                expires_at INTEGER NOT NULL);
              CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires_at);
              CREATE TABLE IF NOT EXISTS remembered_logins (
                token_hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES credentials(account),
                expires_at INTEGER NOT NULL);
              CREATE INDEX IF NOT EXISTS remembered_logins_expiry ON remembered_logins(expires_at);
            ''')
        self.dummy_salt = secrets.token_bytes(16)
        self.dummy_hash = derive(secrets.token_bytes(32), self.dummy_salt)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.database, timeout=5)
        db.execute('PRAGMA foreign_keys=ON')
        try:
            with db: yield db
        finally: db.close()

    def legacy_enabled(self, account):
        with self.connection() as db:
            row = db.execute('SELECT legacy_disabled FROM credentials WHERE account=?', (account,)).fetchone()
            return not row or not row[0]

    def _session(self, db, account):
        token = secrets.token_urlsafe(32)
        now, expires = int(self.clock()), int(self.clock()) + SESSION_SECONDS
        db.execute('DELETE FROM sessions WHERE expires_at<=?', (now,))
        # Bound retained sessions per account, including repeated successful logins.
        db.execute('DELETE FROM sessions WHERE token_hash IN (SELECT token_hash FROM sessions WHERE account=? ORDER BY expires_at DESC, rowid DESC LIMIT -1 OFFSET 15)', (account,))
        db.execute('INSERT INTO sessions VALUES (?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), account, expires))
        return {'account': account, 'token': token, 'expires_at': expires, 'expires_in': SESSION_SECONDS}

    def register(self, account, password, ip):
        account, password = account_name(account), password_bytes(password)
        self.limits.check('register', ip, account)
        if not self.registration_enabled: raise AuthError(403, 'Registration is disabled')
        if account in self.reserved: raise AuthError(409, 'Account is unavailable')
        salt = secrets.token_bytes(16)
        digest = derive(password, salt)
        try:
            with self.connection() as db:
                db.execute('INSERT INTO credentials VALUES (?,?,?,?,0)', (account, salt, digest, int(self.clock())))
                return self._session(db, account)
        except sqlite3.IntegrityError:
            raise AuthError(409, 'Account is unavailable') from None

    def login(self, account, password, ip):
        account, password = account_name(account), password_bytes(password)
        self.limits.check('login', ip, account)
        with self.connection() as db:
            row = db.execute('SELECT salt,password_hash FROM credentials WHERE account=?', (account,)).fetchone()
        salt, expected = row if row else (self.dummy_salt, self.dummy_hash)
        valid = hmac.compare_digest(derive(password, salt), expected)
        if not valid or row is None: raise AuthError(401, 'Account or password is incorrect')
        with self.connection() as db: return self._session(db, account)

    def claim(self, account, password, ip):
        # Caller MUST have verified the configured legacy bearer for this alias.
        account, password = account_name(account), password_bytes(password)
        self.limits.check('claim', ip, account)
        if account not in self.reserved or account == 'health': raise AuthError(403, 'Legacy account cannot be claimed')
        salt = secrets.token_bytes(16)
        digest = derive(password, salt)
        try:
            with self.connection() as db:
                db.execute('INSERT INTO credentials VALUES (?,?,?,?,1)', (account, salt, digest, int(self.clock())))
                return self._session(db, account)
        except sqlite3.IntegrityError:
            raise AuthError(409, 'Account has already been claimed') from None

    def session(self, token):
        with self.connection() as db:
            row = db.execute('SELECT account,expires_at FROM sessions WHERE token_hash=? AND expires_at>?',
                             (hashlib.sha256(token.encode('ascii')).hexdigest(), int(self.clock()))).fetchone()
        if row is None: raise AuthError(401, 'Session expired or invalid; sign in again')
        return {'account': row[0], 'expires_at': row[1], 'expires_in': max(0, row[1] - int(self.clock()))}

    def logout(self, token):
        self.session(token)
        with self.connection() as db:
            db.execute('DELETE FROM sessions WHERE token_hash=?', (hashlib.sha256(token.encode('ascii')).hexdigest(),))
        return {'logged_out': True}

    @staticmethod
    def remembered_digest(token):
        if not isinstance(token, str) or not re.fullmatch(r'swgr_[A-Za-z0-9_-]{43}', token):
            raise AuthError(401, 'Saved login expired or invalid; enter your password')
        return hashlib.sha256(token.encode('ascii')).hexdigest()

    def remember(self, session_token):
        account = self.session(session_token)['account']
        token = 'swgr_' + secrets.token_urlsafe(32)
        expires = int(self.clock()) + REMEMBER_SECONDS
        with self.connection() as db:
            db.execute('DELETE FROM remembered_logins WHERE expires_at<=?', (int(self.clock()),))
            db.execute('DELETE FROM remembered_logins WHERE token_hash IN (SELECT token_hash FROM remembered_logins WHERE account=? ORDER BY expires_at DESC,rowid DESC LIMIT -1 OFFSET 7)', (account,))
            db.execute('INSERT INTO remembered_logins VALUES (?,?,?)', (self.remembered_digest(token), account, expires))
        return {'account': account, 'remember_token': token, 'expires_at': expires}

    def resume(self, account, token, ip):
        account = account_name(account)
        self.limits.check('login', ip, account)
        digest = self.remembered_digest(token)
        with self.connection() as db:
            row = db.execute('SELECT account FROM remembered_logins WHERE token_hash=? AND account=? AND expires_at>?',
                             (digest, account, int(self.clock()))).fetchone()
            if row is None:
                raise AuthError(401, 'Saved login expired or invalid; enter your password')
            return self._session(db, account)

    def forget(self, account, token, ip):
        account = account_name(account)
        self.limits.check('login', ip, account)
        digest = self.remembered_digest(token)
        with self.connection() as db:
            db.execute('DELETE FROM remembered_logins WHERE token_hash=? AND account=?', (digest, account))
        return {'forgotten': True}
