import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace
from unittest.mock import patch
from email.message import Message
from urllib.parse import urlsplit

from server import account_auth as auth
from server import client_release_protocol as protocol
from server.client_patches import PatchStore
from server.remote_gateway import Gateway
from tools.client.patcher import Patcher, Transport, RetryableError
from tools.client.publish_release import publish


class Invitations(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.kdf=patch.object(auth,'derive',side_effect=lambda password,salt:__import__('hashlib').sha256(password+salt).digest())
        self.kdf.start();self.addCleanup(self.kdf.stop)
        self.now=1000
        self.auth=auth.AccountAuth(Path(self.temp.name)/'auth.db',registration_enabled=True,invites_required=True,clock=lambda:self.now)
    def register(self,name,code):return self.auth.register(name,'long test password','127.0.0.1',code)
    def test_required_expiry_revoke_exhaustion_and_hash_only(self):
        with self.assertRaises(auth.AuthError):self.register('missing',None)
        code=self.auth.issue_invite(uses=2,hours=1)
        first=self.register('first',code)
        self.assertTrue(self.auth.has_client_access('first'))
        self.assertEqual(self.auth.session(first['token'])['account'],'first')
        with self.auth.connection() as db:
            self.assertEqual(db.execute('SELECT code_hash,uses_left FROM invitations').fetchone(),(self.auth.invite_digest(code),1))
        self.now+=3600
        with self.assertRaises(auth.AuthError):self.register('expired',code)
        code=self.auth.issue_invite();self.auth.revoke_invite(code)
        with self.assertRaises(auth.AuthError):self.register('revoked',code)
        self.auth.limits=auth.RateLimits()
        code=self.auth.issue_invite();self.register('last',code)
        with self.assertRaises(auth.AuthError):self.register('spent',code)
        self.assertEqual(self.auth.login('first','long test password','ip')['account'],'first')
    def test_duplicate_account_rolls_back_redemption(self):
        code=self.auth.issue_invite(uses=2);self.register('existing',code)
        with self.assertRaises(auth.AuthError) as error:self.register('existing',code)
        self.assertEqual(error.exception.status,409)
        self.register('second',code)
    def test_simultaneous_redemption_exactly_once(self):
        code=self.auth.issue_invite();barrier=threading.Barrier(2)
        def run(name):
            barrier.wait()
            try:self.register(name,code);return 201
            except auth.AuthError as error:return error.status
        with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,['alpha','bravo']))
        self.assertCountEqual(results,[201,403])
        with self.auth.connection() as db:self.assertEqual(db.execute('SELECT count(*) FROM credentials').fetchone()[0],1)
    def test_gateway_register_invitation_and_exact_fields(self):
        handler=object.__new__(Gateway);handler.server=SimpleNamespace(auth_store=self.auth)
        handler.headers=Message();handler.command='POST';handler.client_address=('127.0.0.1',1)
        handler.reply=lambda code,body:(code,body)
        code=self.auth.issue_invite()
        status,session=handler.auth_route(urlsplit('/auth/register'),dict(account='gateway',password='long test password',invite_code=code))
        self.assertEqual(status,201);self.assertEqual(session['account'],'gateway')
        with self.assertRaises(auth.AuthError):handler.auth_route(urlsplit('/auth/login'),dict(account='gateway',password='long test password',invite_code=code))
        with self.assertRaises(auth.AuthError):handler.auth_route(urlsplit('/auth/register'),dict(account='another',password='long test password'))


class TransportTests(unittest.TestCase):
    def transport(self):
        transport=object.__new__(Transport)
        transport.host='server.test';transport.port=18443;transport.context=object()
        transport.session=dict(token='x'*43)
        return transport
    def test_redirect_does_not_forward_credentials(self):
        transport=self.transport()
        connection=SimpleNamespace(request=lambda *args,**kwargs:None,
            getresponse=lambda:SimpleNamespace(status=302,read=lambda size:b''),close=lambda:None)
        with patch('tools.client.patcher.http.client.HTTPSConnection',return_value=connection) as factory:
            with self.assertRaises(ValueError):transport.request('/patch/v1/channels/testing',4096)
        self.assertEqual(factory.call_count,1)
        self.assertEqual(factory.call_args.args,('server.test',18443))
    def test_registration_is_never_retried_and_omits_bearer(self):
        transport=self.transport();requests=[]
        connection=SimpleNamespace(request=lambda *args,**kwargs:requests.append((args,kwargs)),
            getresponse=lambda:SimpleNamespace(status=503,read=lambda size:b''),close=lambda:None)
        with patch('tools.client.patcher.http.client.HTTPSConnection',return_value=connection):
            with self.assertRaises(RetryableError):transport.authenticate('tester','secret long password','swgi_'+'a'*32)
        self.assertEqual(len(requests),1)
        self.assertNotIn('Authorization',requests[0][1]['headers'])
        self.assertEqual(requests[0][0],('POST','/auth/register'))
    def test_unpublished_target_explains_client_build_is_pending(self):
        transport=self.transport()
        connection=SimpleNamespace(request=lambda *args,**kwargs:None,
            getresponse=lambda:SimpleNamespace(status=404,read=lambda size:b''),close=lambda:None)
        with patch('tools.client.patcher.http.client.HTTPSConnection',return_value=connection):
            with self.assertRaisesRegex(ValueError,'No client build is published for this testing target yet'):
                transport.fetch('/patch/v1/channels/testing-windows-x86-64',4096)

    def test_download_retry_is_bounded(self):
        transport=self.transport()
        with patch.object(transport,'request',side_effect=RetryableError('Busy')) as request,patch('tools.client.patcher.time.sleep'):
            with self.assertRaises(RetryableError):transport.fetch('/patch/v1/channels/testing',4096)
        self.assertEqual(request.call_count,5)


class LocalTransport:
    def __init__(self,store):self.store=PatchStore(store);self.calls=[];self.fail=None
    def fetch(self,path,maximum):
        self.calls.append(path)
        if path==self.fail:raise OSError('Interrupted download')
        raw=self.store.read(path,'tester',entitled=True)
        if len(raw)>maximum:raise ValueError('Oversize')
        return raw


class Releases(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.payload=self.root/'payload';self.store=self.root/'store'
        self.put('client/project.godot',b'config_version=5\n')
        self.put('engine/godot',b'fake-engine');(self.payload/'engine/godot').chmod(0o755)
        self.put('runtime/assets/sample.json',json.dumps({'path':str(self.payload/'runtime/assets/mesh.bin')}).encode())
        self.put('runtime/assets/mesh.bin',b'a'*protocol.CHUNK_SIZE+b'b'*100)
        self.put('client/removed.gd',b'old')
        self.transport=LocalTransport(self.store);self.patcher=Patcher(self.root/'install',self.transport)
    def put(self,path,raw):
        path=self.payload/path;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    def publish(self,sequence):return publish(self.payload,self.store,version='test'+str(sequence),sequence=sequence,source_root=self.payload)
    def update(self):
        with self.patcher.lock():return self.patcher.update()
    def test_two_releases_resume_delta_deletion_and_relocation(self):
        first=self.publish(1);one=self.update()
        self.assertEqual(json.loads((one/'runtime/assets/sample.json').read_text())['path'],str(one/'runtime/assets/mesh.bin'))
        self.put('runtime/assets/mesh.bin',b'a'*protocol.CHUNK_SIZE+b'c'*100)
        (self.payload/'client/removed.gd').unlink();second=self.publish(2)
        changed=protocol.digest(b'c'*100);self.transport.fail='/patch/v1/blobs/'+changed
        self.transport.calls=[]
        with self.assertRaises(OSError):self.update()
        self.assertEqual(self.patcher.current(),first);self.assertTrue((one/'client/removed.gd').exists())
        self.transport.fail=None;self.transport.calls=[];two=self.update()
        self.assertEqual(self.patcher.current(),second);self.assertFalse((two/'client/removed.gd').exists())
        self.assertEqual(self.transport.calls,['/patch/v1/channels/testing','/patch/v1/blobs/'+changed])
    def test_windows_publication_uses_independent_channel_and_sequence(self):
        linux=self.publish(1)
        (self.payload/'engine/godot').unlink()
        self.put('engine/godot.exe',b'fixture windows engine')
        windows=publish(self.payload,self.store,version='windows1',sequence=1,
                        channel='testing-windows-x86-64',target='windows-x86_64')
        self.assertEqual(protocol.decode((self.store/'channels/testing.json').read_bytes()),linux)
        self.assertEqual(protocol.decode((self.store/'channels/testing-windows-x86-64.json').read_bytes()),windows)
        manifest=protocol.decode((self.store/'blobs'/windows['manifest_sha256']).read_bytes())
        self.assertEqual(manifest['platform'],'windows-x86_64')
        self.assertTrue(next(row for row in manifest['files'] if row['path']=='engine/godot.exe')['executable'])
        patcher=Patcher(self.root/'windows install',self.transport,'testing-windows-x86-64',target='windows-x86_64')
        with patcher.lock():installed=patcher.update()
        self.assertTrue((installed/'engine/godot.exe').is_file())

    def test_corrupt_chunk_is_rejected_and_current_preserved(self):
        first=self.publish(1);self.update();self.put('client/new.gd',b'new');self.publish(2)
        (self.store/'blobs'/protocol.digest(b'new')).write_bytes(b'bad')
        with self.assertRaises(ValueError):self.update()
        self.assertEqual(self.patcher.current(),first)
    def test_downgrade_and_sequence_reuse_refused(self):
        first=self.publish(1);self.update();self.publish(2);self.update()
        (self.store/'channels/testing.json').write_bytes(protocol.encode(first))
        with self.assertRaises(ValueError):self.update()
        with self.assertRaises(ValueError):self.publish(1)
    def test_traversal_case_collision_symlink_rejected(self):
        descriptor=self.publish(1)
        manifest=protocol.decode((self.store/'blobs'/descriptor['manifest_sha256']).read_bytes())
        for name in ('../outside','runtime/client/connection.json','client/../../outside','client/CON','/absolute','client/a\\b'):
            with self.assertRaises(ValueError):protocol.safe_path(name)
        manifest['files'].append(dict(manifest['files'][0]));manifest['files'][-1]['path']=manifest['files'][0]['path'].upper()
        with self.assertRaises(ValueError):protocol.manifest(manifest)
        (self.root/'install/versions').rename(self.root/'elsewhere');(self.root/'install/versions').symlink_to(self.root/'elsewhere')
        with self.assertRaises(ValueError):Patcher(self.root/'install',self.transport)
    def test_interrupted_same_release_repair_recovers(self):
        self.publish(1);installed=self.update()
        installed.rename(installed.with_name(installed.name+'.old'))
        stale=self.root/'install/state/connection-stale.json';stale.write_text('temporary token')
        with self.patcher.lock():
            self.assertTrue(installed.is_dir());self.assertFalse(stale.exists())

    def test_lock_prevents_concurrent_update_or_game(self):
        other=Patcher(self.root/'install',self.transport)
        with self.patcher.lock():
            with self.assertRaises(ValueError):
                with other.lock():pass
        with other.lock():pass
    def test_invited_or_allowlisted_downloads_only(self):
        self.publish(1);store=PatchStore(self.store)
        with self.assertRaises(PermissionError):store.read('/patch/v1/channels/testing','stranger')
        (self.store/'access.json').write_text('{"accounts":["tester"]}')
        self.assertTrue(store.read('/patch/v1/channels/testing','tester'))
        self.assertTrue(store.read('/patch/v1/channels/testing','invited',entitled=True))
        with self.assertRaises(ValueError):store.read('/patch/v1/blobs/../../secret','tester')
    def test_session_profile_private_and_removed_after_game(self):
        self.publish(1);self.update()
        self.transport.session=dict(account='tester',token='x'*43,expires_at=9999999999)
        self.transport.origin='https://example.test';self.transport.ca='/public/ca.pem'
        seen=[]
        def run(args,**kwargs):
            profile=Path(next(a.split('=',1)[1] for a in args if a.startswith('--connection-profile=')))
            self.assertEqual(profile.stat().st_mode&0o777,0o600)
            self.assertEqual(json.loads(profile.read_text())['launcher_session'],self.transport.session)
            self.assertNotIn('x'*43,' '.join(args));self.assertEqual(args[args.index('--xr-mode')+1],'off')
            seen.append(profile);return SimpleNamespace(returncode=0)
        with self.patcher.lock(),patch('tools.client.patcher.subprocess.run',side_effect=run):self.patcher.launch(desktop=True)
        self.assertFalse(seen[0].exists())
    def test_gateway_download_authentication_and_invite_entitlement(self):
        self.publish(1)
        handler=object.__new__(Gateway)
        handler.server=SimpleNamespace(patch_store=PatchStore(self.store),patch_slots=threading.BoundedSemaphore(1),auth_store=SimpleNamespace(has_client_access=lambda account:account=='tester'))
        handler.authenticate=lambda:('tester','token',False)
        handler.reply=lambda code,body:(code,body);handler.send_bytes=lambda code,body,**kwargs:(code,body)
        self.assertEqual(handler.patch_route('/patch/v1/channels/testing')[0],200)
        handler.authenticate=lambda:('stranger','token',False)
        self.assertEqual(handler.patch_route('/patch/v1/channels/testing')[0],403)
        def denied():raise auth.AuthError(401,'Authentication required')
        handler.authenticate=denied
        with self.assertRaises(auth.AuthError):handler.patch_route('/patch/v1/channels/testing')

if __name__=='__main__':unittest.main()
