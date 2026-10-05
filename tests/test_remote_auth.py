import hashlib
import json
import secrets
import sqlite3
import unittest
import threading
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
from server import account_auth as auth
from tests import test_remote_gateway as base
from tests.test_remote_gateway import TOKEN,OTHER

PASSWORD='local-test passphrase 2026'

class AuthTests(base.Tests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.gateway.auth_store=auth.AccountAuth(cls.temp.name+'/auth.sqlite',reserved=cls.gateway.accounts,registration_enabled=True)
    def setUp(self):
        super().setUp()
        self.gateway.auth_store.limits=auth.RateLimits()
    def auth_request(self,route,payload=None,token=None,method='POST'):
        status,raw=self.request(method,route,json.dumps(payload or {})if method=='POST'else None,token=token,headers={'Content-Type':'application/json'})
        return status,json.loads(raw)
    def register(self):
        account='tlsuser'+secrets.token_hex(4)
        code,session=self.auth_request('/auth/register',{'account':account,'password':PASSWORD})
        self.assertEqual(code,201,session)
        return session
    def test_portable_saved_login_over_verified_tls(self):
        session=self.register();account=session['account']
        code,saved=self.auth_request('/auth/remember',{},session['token'])
        self.assertEqual(code,200)
        payload={'account':account,'remember_token':saved['remember_token']}
        self.assertEqual(self.auth_request('/auth/logout',{},session['token'])[0],200)
        code,resumed=self.auth_request('/auth/resume',payload)
        self.assertEqual(code,200);self.assertEqual(resumed['account'],account)
        self.assertEqual(self.auth_request('/auth/resume',payload,resumed['token'])[0],400)
        self.assertEqual(self.request(path='/characters',token=saved['remember_token'])[0],401)
        self.assertEqual(self.request(path='/characters?remember_token=secret')[0],400)
        self.assertEqual(self.auth_request('/auth/forget',payload)[0],200)
        self.assertEqual(self.auth_request('/auth/resume',payload)[0],401)
        self.assertEqual(self.auth_request('/auth/resume',dict(payload,account='other'))[0],401)
        self.assertFalse(self.upstream.seen)
    def test_auth_new_account_tls_and_binding(self):
        session=self.register();token=session['token']
        self.assertFalse(self.upstream.seen)
        code,state=self.auth_request('/auth/session',token=token,method='GET')
        self.assertEqual(code,200);self.assertEqual(state['account'],session['account'])
        self.assertNotIn('token',state)
        code,raw=self.request(path='/characters',token=token)
        self.assertEqual(code,200);self.assertIn('account='+session['account'],json.loads(raw)['path'])
        self.assertIsNone(json.loads(raw)['authorization'])
        self.assertEqual(self.request(path='/characters?account=alice',token=token)[0],403)
        self.assertEqual(self.request('POST','/enter','{"account":"alice"}',token=token)[0],403)
        self.assertEqual(self.auth_request('/auth/login',{'account':session['account'],'password':PASSWORD})[0],200)
    def test_auth_registration_race_over_actual_tls(self):
        account='tlsrace'+secrets.token_hex(4)
        barrier=threading.Barrier(2)
        def register(_):
            barrier.wait()
            return self.auth_request('/auth/register',{'account':account,'password':PASSWORD})[0]
        with ThreadPoolExecutor(2)as pool:results=list(pool.map(register,range(2)))
        self.assertCountEqual(results,[201,409])
        self.assertFalse(self.upstream.seen)
    def test_auth_logout_expiry(self):
        session=self.register()
        self.assertEqual(self.auth_request('/auth/logout',token=session['token']), (200,{'logged_out':True}))
        self.assertEqual(self.request(token=session['token'])[0],401)
        code,new=self.auth_request('/auth/login',{'account':session['account'],'password':PASSWORD});self.assertEqual(code,200)
        with patch.object(self.gateway.auth_store,'clock',return_value=new['expires_at']):
            self.assertEqual(self.auth_request('/auth/session',token=new['token'],method='GET')[0],401)
            self.assertEqual(self.request(token=new['token'])[0],401)
    def test_auth_migration_persistently_disables_legacy(self):
        # Separate configured legacy alias so inherited alice/bob regressions remain usable.
        legacy='M'*43;account='migration'
        self.gateway.accounts[account]=hashlib.sha256(legacy.encode()).hexdigest()
        self.gateway.auth_store.reserved=frozenset(self.gateway.accounts)|{'health'}
        try:
            self.assertEqual(self.auth_request('/auth/claim',{'password':PASSWORD},token='Z'*43)[0],401)
            self.assertEqual(self.auth_request('/auth/register',{'account':account,'password':PASSWORD})[0],409)
            code,session=self.auth_request('/auth/claim',{'password':PASSWORD},token=legacy)
            self.assertEqual(code,200,session)
            self.assertEqual(self.request(token=legacy)[0],401)
            self.assertEqual(self.auth_request('/auth/claim',{'password':PASSWORD},token=legacy)[0],401)
            self.assertEqual(self.request(token=session['token'])[0],200)
            self.assertFalse(auth.AccountAuth(self.gateway.auth_store.database,reserved=self.gateway.accounts).legacy_enabled(account))
            self.assertEqual(self.auth_request('/auth/login',{'account':account,'password':PASSWORD})[0],200)
        finally:del self.gateway.accounts[account]
    def test_auth_no_password_forwarding_or_sensitive_errors(self):
        for payload in ({'account':'bad','password':'short'},{'account':'Bad','password':PASSWORD},{'account':'unknown','password':PASSWORD}):
            code,data=self.auth_request('/auth/login',payload)
            self.assertIn(code,(400,401));self.assertNotIn(PASSWORD,json.dumps(data))
        self.assertEqual(self.request('POST','/enter',json.dumps({'password':PASSWORD}))[0],400)
        self.assertEqual(self.auth_request('/auth/login',{'account':'valid','password':PASSWORD},token=TOKEN)[0],400)
        self.assertEqual(self.auth_request('/auth/register?account=alice',{'account':'valid','password':PASSWORD})[0],400)
        self.assertFalse(self.upstream.seen)
    def test_auth_credentials_never_forwarded_in_query(self):
        for key in ('password','Password','%70assword','token','authorization','access_token','secret'):
            self.assertEqual(self.request(path='/characters?'+key+'=private-value')[0],400)
        self.assertFalse(self.upstream.seen)
    def test_auth_voice_ticket_bound_to_owned_account_session(self):
        from server.voice_protocol import TicketAuthority
        authority=TicketAuthority(b'v'*32)
        previous=self.gateway.voice_tickets;self.gateway.voice_tickets=authority
        try:
            session=self.register()
            self.upstream.body=json.dumps({'backend':'core3','character_id':'123','native_session_id':'','ticket':'local-only','expires_in':30}).encode()
            status,raw=self.request('POST','/voice/session','{"character_id":"123"}',token=session['token'])
            self.assertEqual(status,200)
            ticket=json.loads(raw)['ticket'];claims=authority.consume(ticket)
            self.assertEqual(claims['a'],session['account']);self.assertEqual(claims['c'],'123')
            self.assertEqual(claims['h'],hashlib.sha256(session['token'].encode()).hexdigest())
            self.assertFalse(claims['l']);self.assertEqual(claims['x'],session['expires_at'])
            self.assertNotIn(session['token'],ticket)
            self.assertEqual(self.upstream.seen[-1]['body']['account'],session['account'])
            self.assertEqual(self.request('POST','/voice/session','{"character_id":"123","account":"other"}',token=session['token'])[0],403)
        finally:self.gateway.voice_tickets=previous
    def test_auth_rate_limit_and_closed_storage(self):
        for _ in range(10):self.gateway.auth_store.limits.check('login','127.0.0.1','limited')
        status,data=self.auth_request('/auth/login',{'account':'limited','password':PASSWORD})
        self.assertEqual(status,429);self.assertGreater(data['retry_after'],0)
        with patch.object(self.gateway.auth_store,'connection',side_effect=sqlite3.OperationalError('secret path')):
            status,data=self.auth_request('/auth/login',{'account':'other','password':PASSWORD})
            self.assertEqual(status,503);self.assertNotIn('secret',json.dumps(data))
            self.assertEqual(self.request()[0],503)
        self.assertFalse(self.upstream.seen)
    def test_auth_registration_disabled_and_unknown_route(self):
        with patch.object(self.gateway.auth_store,'registration_enabled',False):
            self.assertEqual(self.auth_request('/auth/register',{'account':'valid','password':PASSWORD})[0],403)
        self.assertEqual(self.auth_request('/auth/missing')[0],404)
        self.assertEqual(self.auth_request('/auth/session',token=TOKEN,method='GET')[0],409)

if __name__=='__main__':unittest.main()
