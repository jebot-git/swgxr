"""Standalone profile, auth isolation, real TLS/IP-SAN and redirect tests.

All generated keys, tokens and fixtures are ephemeral and confined to ignored
runtime evidence. Client scripts run without a game scene, asset loading or XR.
"""
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
from unittest.mock import patch

if __package__:
    from .remote_connection import RemoteConnection, connection_arguments
else:
    from remote_connection import RemoteConnection, connection_arguments

STAGE = Path(__file__).resolve().parents[2]
EVIDENCE = STAGE / 'runtime/evidence/remote-client'
EVIDENCE.mkdir(parents=True, exist_ok=True)


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.server.paths.append(self.path)
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', self.server.redirect_url)
            self.end_headers()
            return
        authorized = self.headers.get('Authorization') == 'Bearer ' + self.server.token
        raw = json.dumps({'backend':'core3', 'authorized':authorized, 'core3':{'ready':True}}).encode()
        self.send_response(200 if authorized else 401)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class RemoteConnectionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='remote-tls-',dir=EVIDENCE)
        cls.folder = Path(cls.temporary.name)
        cls.servers = []
        cls.token = 'isolated-test-only-bearer-0123456789'
        cls.ca = cls.certificate_authority('ca')
        cls.unknown_ca = cls.certificate_authority('unknown-ca')
        good_cert, good_key = cls.server_certificate('good','127.0.0.1')
        bad_cert, bad_key = cls.server_certificate('bad','192.0.2.1')
        cls.sink = cls.server()
        cls.good = cls.server(good_cert,good_key)
        cls.bad = cls.server(bad_cert,bad_key)
        cls.good.redirect_url = 'http://127.0.0.1:' + str(cls.sink.server_port) + '/should-never-receive-token'
        cls.profile = cls.write_profile('good',cls.good,cls.ca)
        cls.bad_profile = cls.write_profile('bad',cls.bad,cls.ca)
        cls.unknown_profile = cls.write_profile('unknown',cls.good,cls.unknown_ca)

    @classmethod
    def openssl(cls,*args):
        subprocess.run(['openssl',*map(str,args)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

    @classmethod
    def certificate_authority(cls,name):
        cls.openssl('req','-x509','-newkey','rsa:2048','-nodes','-days','2','-sha256',
            '-subj','/CN=SWGXR isolated '+name,'-keyout',cls.folder/(name+'.key'),'-out',cls.folder/(name+'.pem'),
            '-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign')
        return cls.folder/(name+'.pem')

    @classmethod
    def server_certificate(cls,name,ip):
        key=cls.folder/(name+'.key');csr=cls.folder/(name+'.csr');cert=cls.folder/(name+'.pem')
        cls.openssl('req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=isolated-server', '-keyout',key,'-out',csr)
        extensions=cls.folder/(name+'.ext')
        extensions.write_text('subjectAltName=IP:'+ip+'\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n')
        cls.openssl('x509','-req','-in',csr,'-CA',cls.ca,'-CAkey',cls.folder/'ca.key','-CAcreateserial',
            '-days','2','-sha256','-extfile',extensions,'-out',cert)
        return cert,key

    @classmethod
    def server(cls,cert=None,key=None):
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),FixtureHandler)
        server.paths=[];server.token=cls.token;server.redirect_url=''
        if cert:
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(str(cert),str(key))
            server.socket=context.wrap_socket(server.socket,server_side=True)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        cls.servers.append(server)
        return server

    @classmethod
    def write_profile(cls,name,server,ca):
        path=cls.folder/(name+'-profile.json')
        path.write_text(json.dumps({'base_url':'https://127.0.0.1:'+str(server.server_port),'account':'fixture','token':cls.token,'ca_certificate':str(ca)}))
        path.chmod(0o600)
        return path

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers:
            server.shutdown();server.server_close()
        cls.temporary.cleanup()

    def test_verified_ip_san_authentication(self):
        connection=RemoteConnection.load(self.profile)
        self.assertTrue(connection.request_json('/health')['authorized'])
        self.assertTrue(connection._context.check_hostname)
        self.assertEqual(connection._context.verify_mode,ssl.CERT_REQUIRED)
        self.assertNotIn(self.token,repr(connection))

    def test_wrong_ip_san_and_unknown_ca_fail(self):
        for path in (self.bad_profile,self.unknown_profile):
            with self.subTest(path=path.name),self.assertRaises(urllib.error.URLError):
                RemoteConnection.load(path).request_json('/health')

    def test_redirect_never_forwards_credentials(self):
        before=len(self.sink.paths)
        with self.assertRaises(urllib.error.HTTPError):
            RemoteConnection.load(self.profile).request_json('/redirect')
        self.assertEqual(len(self.sink.paths),before)

    def test_default_remote_and_explicit_local(self):
        folder=self.folder/'launch-root';(folder/'runtime/client').mkdir(parents=True,exist_ok=True)
        (folder/'runtime/client/connection.json').write_text(self.profile.read_text())
        args,connection=connection_arguments(['--desktop'],folder)
        self.assertIsNotNone(connection)
        self.assertTrue(any(value.startswith('--connection-profile=') for value in args))
        self.assertFalse(any(self.token in value for value in args))
        with patch.object(RemoteConnection,'load',side_effect=AssertionError('Local override must not read credentials')):
            self.assertIsNone(connection_arguments(['--local'],folder)[1])
            self.assertIsNone(connection_arguments(['--offline'],folder)[1])

    def test_configured_origin_and_account_cannot_be_overridden(self):
        for args in ([f'--connection-profile={self.profile}','--backend=https://evil.example'],
                     [f'--connection-profile={self.profile}','--account=other'],
                     [f'--connection-profile={self.profile}','--local']):
            with self.subTest(args=args),self.assertRaises(ValueError): connection_arguments(args,self.folder)

    def test_endpoint_only_profile_and_partial_credentials(self):
        value=json.loads(self.profile.read_text())
        value.pop('account');value.pop('token')
        path=self.folder/'endpoint-only.json';path.write_text(json.dumps(value))
        connection=RemoteConnection.load(path)
        self.assertFalse(connection.authenticated)
        before=len(self.good.paths)
        with self.assertRaisesRegex(ValueError,'Sign in'):
            connection.request_json('/characters')
        self.assertEqual(len(self.good.paths),before)
        args,_=connection_arguments([f'--connection-profile={path}'],self.folder)
        self.assertFalse(any(arg.startswith('--account=') for arg in args))
        with self.assertRaisesRegex(ValueError,'account'):
            connection_arguments([f'--connection-profile={path}','--account=someone'],self.folder)
        for credentials in ({'account':'fixture'}, {'token':self.token}):
            path.write_text(json.dumps(dict(value,**credentials)))
            with self.assertRaises(ValueError):RemoteConnection.load(path)

    def test_request_path_and_account_guards(self):
        connection=RemoteConnection.load(self.profile)
        before=len(self.good.paths)
        for path in ('//evil.example/health','https://evil.example/health','/health\r\nX: value', '/health#fragment',
                     '/characters?account=other','/characters?account=fixture&account=fixture'):
            with self.subTest(path=path),self.assertRaises(ValueError):connection.request_json(path)
        with self.assertRaises(ValueError):connection.request_json('/services/pay',body={'account':'other'})
        with self.assertRaises(ValueError):connection.request_json('/services/pay',body={'data':'x'*17000})
        self.assertEqual(len(self.good.paths),before)

    def test_invalid_profile_fails_without_credential_echo(self):
        value=json.loads(self.profile.read_text())
        for field,bad in [('base_url','http://127.0.0.1:18080'),('base_url','https://user:secret@127.0.0.1'),
                          ('base_url','https://127.0.0.1/path'),('token','secret\r\nX: bad'),('ca_certificate','relative.pem')]:
            copy=dict(value);copy[field]=bad;path=self.folder/'invalid.json';path.write_text(json.dumps(copy))
            with self.subTest(field=field,bad=bad),self.assertRaises(ValueError) as caught:RemoteConnection.load(path)
            self.assertNotIn(self.token,str(caught.exception));self.assertNotIn('secret',str(caught.exception))

    def test_actual_godot_tls_client(self):
        command=['godot','--headless','--xr-mode','off','--path',str(STAGE/'client'),
                 '--script','res://tests/remote_connection_smoke.gd','--',f'--profile={self.profile}',
                 f'--wrong-san-profile={self.bad_profile}',f'--unknown-ca-profile={self.unknown_profile}']
        environment=dict(os.environ);environment['DISABLE_XR_APILAYER_NOVENDOR_OBSMirror']='1';environment['DISABLE_OBS_VKCAPTURE']='1';environment.pop('OBS_VKCAPTURE',None)
        before=len(self.sink.paths)
        try:
            result=subprocess.run(command,text=True,capture_output=True,env=environment,timeout=30)
        except subprocess.TimeoutExpired as exc:
            captured=(exc.stdout or b'')+(exc.stderr or b'')
            assert self.token.encode() not in captured
            (EVIDENCE/'godot-remote-tls.log').write_bytes(captured)
            raise
        # No valid token occurs in normal/errors output; assert before storing evidence.
        self.assertNotIn(self.token,result.stdout+result.stderr)
        evidence=EVIDENCE/'godot-remote-tls.log';evidence.write_text(result.stdout+result.stderr)
        self.assertEqual(result.returncode,0,'Godot TLS test failed; inspect isolated staged evidence.')
        self.assertEqual(len(self.sink.paths),before)
        report=next(json.loads(line) for line in result.stdout.splitlines() if line.startswith('{"checks"'))
        self.assertTrue(report['passed']);self.assertGreaterEqual(report['checks'],25)


if __name__=='__main__':unittest.main(verbosity=2)
