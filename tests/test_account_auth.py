import hashlib
from contextlib import closing
import os
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from server import account_auth as auth

PASSWORD='test-only passphrase 2026'

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.path=Path(self.temp.name)/'accounts.sqlite'
        self.store=auth.AccountAuth(self.path,reserved={'blux'},registration_enabled=True)
    def tearDown(self): self.temp.cleanup()
    def test_portable_login_is_hashed_restart_safe_and_revocable(self):
        session=self.store.register('alice',PASSWORD,'ip')
        remembered=self.store.remember(session['token'])
        self.store.logout(session['token'])
        reopened=auth.AccountAuth(self.path)
        resumed=reopened.resume('alice',remembered['remember_token'],'ip')
        self.assertEqual(resumed['account'],'alice')
        self.assertNotEqual(resumed['token'],session['token'])
        self.assertEqual(resumed['expires_in'],auth.SESSION_SECONDS)
        for file in Path(self.temp.name).glob('*'):
            self.assertNotIn(remembered['remember_token'].encode(),file.read_bytes())
        with self.assertRaises(auth.AuthError):reopened.session(remembered['remember_token'])
        with self.assertRaises(auth.AuthError):reopened.resume('other',remembered['remember_token'],'ip')
        reopened.forget('alice',remembered['remember_token'],'ip')
        with self.assertRaises(auth.AuthError):reopened.resume('alice',remembered['remember_token'],'ip')
        self.assertEqual(reopened.session(resumed['token'])['account'],'alice')

    def test_portable_login_expiry_and_device_bound(self):
        session=self.store.register('alice',PASSWORD,'ip')
        remembered=[self.store.remember(session['token']) for _ in range(10)]
        with closing(sqlite3.connect(self.path))as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM remembered_logins').fetchone()[0],8)
        with self.assertRaises(auth.AuthError):self.store.resume('alice',remembered[0]['remember_token'],'ip')
        self.assertEqual(self.store.resume('alice',remembered[-1]['remember_token'],'ip')['account'],'alice')
        self.store.clock=lambda:remembered[-1]['expires_at']
        with self.assertRaises(auth.AuthError):self.store.resume('alice',remembered[-1]['remember_token'],'ip')
        for token in [None,[],{},'short','swgr_'+'x'*42,'swgr_'+'é'*43]:
            with self.assertRaises(auth.AuthError):self.store.remembered_digest(token)
    def test_credentials_and_sessions_are_hashes(self):
        result=self.store.register('alice',PASSWORD,'127.0.0.1')
        self.assertEqual(len(result['token']),43)
        self.assertEqual(result['expires_in'],86400)
        self.assertEqual(os.stat(self.path).st_mode&0o777,0o600)
        with closing(sqlite3.connect(self.path))as db:
            row=db.execute('SELECT salt,password_hash FROM credentials').fetchone()
            session=db.execute('SELECT token_hash FROM sessions').fetchone()[0]
        self.assertEqual(len(row[0]),16);self.assertEqual(len(row[1]),32)
        self.assertEqual(session,hashlib.sha256(result['token'].encode()).hexdigest())
        for file in Path(self.temp.name).glob('*'):
            self.assertNotIn(PASSWORD.encode(),file.read_bytes());self.assertNotIn(result['token'].encode(),file.read_bytes())
    def test_dummy_unknown_and_wrong_password_same_work(self):
        self.store.register('alice',PASSWORD,'ip')
        with patch.object(auth,'derive',wraps=auth.derive)as derive:
            for account in ('alice','unknown'):
                with self.assertRaises(auth.AuthError)as caught:self.store.login(account,'wrong password value','ip')
                self.assertEqual(caught.exception.status,401)
            self.assertEqual(derive.call_count,2)
    def test_expiry_logout_and_restart(self):
        first=self.store.register('alice',PASSWORD,'ip')
        second=self.store.login('alice',PASSWORD,'ip')
        reopened=auth.AccountAuth(self.path)
        self.assertEqual(reopened.session(first['token'])['account'],'alice')
        reopened.logout(first['token'])
        with self.assertRaises(auth.AuthError):self.store.session(first['token'])
        self.store.clock=lambda:second['expires_at']
        with self.assertRaises(auth.AuthError):self.store.session(second['token'])
    def test_register_race_atomic_unique(self):
        barrier=threading.Barrier(2)
        def register(_):
            barrier.wait()
            try:return self.store.register('racer',PASSWORD,'ip')['account']
            except auth.AuthError as e:return e.status
        with ThreadPoolExecutor(2)as pool:results=list(pool.map(register,range(2)))
        self.assertCountEqual(results,['racer',409])
        with closing(sqlite3.connect(self.path))as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM credentials').fetchone()[0],1)
    def test_reserved_claim_is_persistent(self):
        for account in ('blux','health'):
            with self.assertRaises(auth.AuthError)as caught:self.store.register(account,PASSWORD,'ip')
            self.assertEqual(caught.exception.status,409)
        for legacy in ('ab','1alice'):
            self.store.reserved=self.store.reserved|{legacy}
            with self.assertRaises(auth.AuthError):self.store.claim(legacy,PASSWORD,'ip')
            self.assertTrue(self.store.legacy_enabled(legacy))
        self.assertTrue(self.store.legacy_enabled('blux'))
        session=self.store.claim('blux',PASSWORD,'ip')
        self.assertFalse(auth.AccountAuth(self.path,reserved={'blux'}).legacy_enabled('blux'))
        self.assertEqual(self.store.session(session['token'])['account'],'blux')
        with self.assertRaises(auth.AuthError):self.store.claim('blux',PASSWORD,'ip2')
    def test_kdf_limit_is_process_wide_and_released(self):
        self.assertTrue(auth.KDF_SLOTS.acquire(False));self.assertTrue(auth.KDF_SLOTS.acquire(False))
        try:
            with self.assertRaises(auth.AuthError)as caught:auth.derive(b'password',b'16-byte-salt-0000')
            self.assertEqual(caught.exception.status,429)
        finally:auth.KDF_SLOTS.release();auth.KDF_SLOTS.release()
        with patch.object(auth.hashlib,'scrypt',side_effect=ValueError('test')):
            with self.assertRaises(auth.AuthError)as caught:auth.derive(b'password',b'salt')
            self.assertEqual(caught.exception.status,503)
        self.assertTrue(auth.KDF_SLOTS.acquire(False));self.assertTrue(auth.KDF_SLOTS.acquire(False))
        auth.KDF_SLOTS.release();auth.KDF_SLOTS.release()
    def test_test_registration_can_grant_client_access_explicitly(self):
        self.store.register('normal',PASSWORD,'ip')
        self.assertFalse(self.store.has_client_access('normal'))
        enabled=auth.AccountAuth(self.path,registration_enabled=True,registration_grants_client_access=True)
        enabled.register('tester',PASSWORD,'ip')
        self.assertTrue(enabled.has_client_access('tester'))
        self.assertTrue(auth.AccountAuth(self.path).has_client_access('tester'))
        self.assertFalse(enabled.has_client_access('normal'))
        with self.assertRaises(ValueError):auth.AccountAuth(self.path,registration_grants_client_access='true')
    def test_validation_and_default_disabled(self):
        for account in ('ab','Alice','1alice','a'*25,'élice','../../x'):
            with self.assertRaises(auth.AuthError):auth.account_name(account)
        for password in ('x'*11,'x'*129,None,'a'*11+'\ud800'):
            with self.assertRaises(auth.AuthError):auth.password_bytes(password)
        self.assertEqual(len(auth.password_bytes('😀'*128)),512)
        with self.assertRaises(auth.AuthError)as caught:auth.AccountAuth(self.path).register('valid',PASSWORD,'ip')
        self.assertEqual(caught.exception.status,403)
    def test_bounded_rate_limits_and_expiration(self):
        now=[0.0];limits=auth.RateLimits(clock=lambda:now[0])
        for _ in range(10):limits.check('login','ip','alice')
        with self.assertRaises(auth.AuthError)as caught:limits.check('login','otherip','alice')
        self.assertEqual(caught.exception.retry_after,300)
        now[0]=300;limits.check('login','ip','alice')
        tiny=auth.RateLimits(capacity=3);tiny.check('login','ip','alice')
        with self.assertRaises(auth.AuthError):tiny.check('login','other','bob')
        self.assertLessEqual(len(tiny.entries),3)
        login_global=auth.RateLimits()
        for i in range(120):login_global.check('login',f'ip{i}',f'user{i}')
        with self.assertRaises(auth.AuthError)as caught:login_global.check('login','newip','newuser')
        self.assertLessEqual(caught.exception.retry_after,60)
        global_limit=auth.RateLimits()
        for i in range(30):global_limit.check('register',f'ip{i}',f'user{i}')
        with self.assertRaises(auth.AuthError):global_limit.check('register','newip','newuser')
    def test_retained_sessions_bounded(self):
        with patch.object(auth,'derive',return_value=b'x'*32):
            self.store.register('alice',PASSWORD,'ip')
            for i in range(20):self.store.login('alice',PASSWORD,f'ip{i}');self.store.limits=auth.RateLimits()
        with closing(sqlite3.connect(self.path))as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM sessions').fetchone()[0],16)

if __name__=='__main__':unittest.main()
