import ast
import contextlib
import hashlib
import http.client
import http.server
import io
import importlib
import json
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from server import remote_gateway as gateway

TOKEN = 'A' * 43
OTHER = 'B' * 43

class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self): self.echo()
    def do_POST(self): self.echo()
    def echo(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.server.seen.append({'path': self.path, 'body': json.loads(data) if data else None, 'authorization': self.headers.get('Authorization')})
        status = self.server.status
        raw = self.server.body or json.dumps(self.server.seen[-1]).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(raw)))
        if status == 302: self.send_header('Location','https://example.invalid/secret')
        self.end_headers()
        try: self.wfile.write(raw)
        except OSError: pass

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='swgxr-gateway-')
        base = Path(cls.temp.name)
        cls.cert, cls.key = base/'cert.pem', base/'key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=SWGXR ephemeral test','-addext','subjectAltName=IP:127.0.0.1,IP:45.147.228.101','-keyout',str(cls.key),'-out',str(cls.cert)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        cls.upstream = http.server.ThreadingHTTPServer(('127.0.0.1',0),Upstream)
        cls.upstream.seen,cls.upstream.status,cls.upstream.body = [],200,None
        cls.gateway = gateway.Server(('127.0.0.1',0),gateway.tls_context(cls.cert,cls.key),{'alice':hashlib.sha256(TOKEN.encode()).hexdigest(),'bob':hashlib.sha256(OTHER.encode()).hexdigest()},upstream=cls.upstream.server_address)
        cls.context = ssl.create_default_context(cafile=str(cls.cert))
        for server in (cls.upstream,cls.gateway):threading.Thread(target=server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls):
        for server in (cls.gateway,cls.upstream):server.shutdown();server.server_close()
        cls.temp.cleanup()
    def setUp(self):
        self.upstream.seen.clear();self.upstream.status=200;self.upstream.body=None
    def request(self,method='GET',path='/health',body=None,token=TOKEN,headers=None,context=None):
        conn=http.client.HTTPSConnection(*self.gateway.server_address,context=context or self.context,timeout=3)
        head={'Authorization':'Bearer '+token,'Content-Type':'application/json'} if token else {}
        head.update(headers or {})
        try:
            conn.request(method,path,body,head);response=conn.getresponse();return response.status,response.read()
        finally:conn.close()
    def test_authentication(self):
        for token in (None,'C'*43,'short'):
            self.assertEqual(self.request(token=token)[0],401)
        self.assertFalse(self.upstream.seen)
    def test_account_binding_query_and_body(self):
        code,body=self.request(path='/characters?character_id=123')
        self.assertEqual(code,200);self.assertIn('account=alice',json.loads(body)['path'])
        self.assertIsNone(json.loads(body)['authorization'])
        code,body=self.request('POST','/enter',json.dumps({'character_id':'123'}))
        self.assertEqual(code,200);self.assertEqual(json.loads(body)['body']['account'],'alice')
        self.assertEqual(self.request('POST','/enter','{"account":"bob"}')[0],403)
        self.assertEqual(self.request(path='/characters?account=bob')[0],403)
        self.assertEqual(self.request('POST','/enter','{"account":null}')[0],403)
    def test_owned_melee_route(self):
        data=dict(character_id='123',session_id='owned',shot_id='s1',item_id='456',origin=[0,1,0],direction=[0,0,1])
        code,body=self.request('POST','/combat/session/melee',json.dumps(data))
        self.assertEqual(code,200)
        self.assertEqual(json.loads(body)['body'],dict(data,account='alice'))
        self.assertEqual(self.request('POST','/combat/session/melee',json.dumps(dict(data,account='bob')))[0],403)

    def test_owned_pve_bounty_service_routes(self):
        for action, field in (('informant','target_id'), ('probe','item_id'),
                              ('seek','item_id'), ('track','item_id')):
            path = '/services/bounty_' + action
            payload = dict(character_id='123', session_id='owned',
                           request_id='bounty-request-001', **{field:'456'})
            if action == 'probe':
                payload['search_planet'] = 'naboo'
            with self.subTest(action=action):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path, json.dumps(payload), token=None,
                                              headers={'Content-Type':'application/json'})[0], 401)
                self.assertEqual(self.request('POST', path, json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_pistoleer_routes(self):
        data = dict(character_id='123', session_id='owned', shot_id='volley-001',
                    item_id='456', origin=[0, 1, 0], direction=[0, 0, 1])
        requests = [('/combat/session/pistoleer', dict(data, ability_id=ability))
                    for ability in ('fan_shot', 'run_and_gun')]
        requests.append(('/combat/session/fire', dict(data, ability_id='showdown',
                        target_id='789', volley_id='volley-001', volley_index=0)))
        for path, payload in requests:
            with self.subTest(path=path, ability=payload['ability_id']):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path,
                                 json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_carbineer_routes(self):
        data = dict(character_id='123', session_id='owned', shot_id='carbine-001',
                    item_id='456', origin=[0, 1, 0], direction=[0, 0, 1], two_hands=True)
        requests = [('/combat/session/carbineer', dict(data, ability_id=ability))
                    for ability in ('full_auto_sweep', 'tactical_brace', 'charge_blast')]
        requests.extend(('/combat/session/fire', dict(data, ability_id=ability, target_id='789'))
                        for ability in ('crippling_shot', 'wild_shot', 'charge_shot'))
        for path, payload in requests:
            with self.subTest(path=path, ability=payload['ability_id']):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path,
                                 json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_rifleman_routes(self):
        data = dict(character_id='123', session_id='owned', shot_id='rifleman-001',
                    item_id='456', origin=[0, 1, 0], direction=[0, 0, -1], two_hands=True)
        requests = [('/combat/session/rifleman', dict(data, ability_id='rifleman_focus'))]
        requests.extend(('/combat/session/fire', dict(data, ability_id=ability, target_id='789'))
                        for ability in ('lethal_shot', 'piercing_shot', 'surprise_shot', 'sniper_shot'))
        requests.extend(('/combat/session/fire', dict(data, shot_id='rifleman-00'+str(index+1),
                        ability_id='flurry_shot', target_id='789',
                        volley_id='rifleman-001', volley_index=index)) for index in range(3))
        for path, payload in requests:
            with self.subTest(path=path, ability=payload['ability_id']):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path,
                                 json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_commando_routes(self):
        data = dict(character_id='123', session_id='owned', shot_id='commando-001',
                    item_id='456', origin=[0, 1, 0], direction=[0, 0, -1], two_hands=True)
        requests = [('/combat/session/commando', dict(data, ability_id=ability))
                    for ability in ('', 'overdrive')]
        requests += [('/combat/session/commando', dict(data, ability_id=ability, target_id='789'))
                     for ability in ('focused_discharge', 'acid_spray')]
        requests += [('/scout/grenade', dict(character_id='123', item_id='456', target_id='789',
                                           position=[0, 0, 0], request_id='grenade-001'))]
        for path, payload in requests:
            with self.subTest(path=path, payload=payload):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path, json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_squad_leader_routes(self):
        base = dict(character_id='123', session_id='owned', shot_id='squad-001',
                    item_id='456', target_id='789', origin=[0,1,0], direction=[0,0,-1])
        requests = [('/combat/session/squadleader', dict(base, ability_id=ability))
                    for ability in ('steady_aim','rally','form_up','boost_morale','retreat','volley_fire')]
        mark = dict(volley_mark_id='volley_123_12345678', volley_target_id='789')
        requests += [('/combat/session/fire', dict(base, ability_id='lethal_shot', **mark)),
                     ('/scout/grenade', dict(character_id='123', item_id='456', target_id='789',
                                            position=[0,0,0], request_id='grenade-001', **mark))]
        for path, payload in requests:
            with self.subTest(path=path, payload=payload):
                code, body = self.request('POST', path, json.dumps(payload))
                self.assertEqual(code, 200)
                self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
                admitted = len(self.upstream.seen)
                self.assertEqual(self.request('POST', path, json.dumps(dict(payload, account='bob')))[0], 403)
                self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_doctor_route(self):
        for ability in ('reviveplayer', 'extinguishfire', 'healstate'):
            data = dict(character_id='123', session_id='owned', request_id='doctor-tls-001',
                        ability=ability, item_id='456', target_id='789', focus_id='457',
                        pose=dict(tracked=True, crossed=False, grips=False, left=[0,1,0], right=[.3,1,0]))
            code, body = self.request('POST', '/medic/doctor', json.dumps(data))
            self.assertEqual(code, 200)
            self.assertEqual(json.loads(body)['body'], dict(data, account='alice'))
            admitted = len(self.upstream.seen)
            self.assertEqual(self.request('POST', '/medic/doctor', json.dumps(dict(data, account='bob')))[0], 403)
            self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_bounty_combat_route(self):
        base = dict(character_id='123', session_id='owned', shot_id='bounty-tls-001',
                    item_id='456', origin=[0,1,0], direction=[0,0,-1], two_hands=True)
        for payload in (dict(base, ability_id='underhand_shot'),
                        dict(base, ability_id='duelist_stance', target_id='789', two_hands=False)):
            code, body = self.request('POST', '/combat/session/bountyhunter', json.dumps(payload))
            self.assertEqual(code, 200)
            self.assertEqual(json.loads(body)['body'], dict(payload, account='alice'))
            admitted = len(self.upstream.seen)
            self.assertEqual(self.request('POST', '/combat/session/bountyhunter',
                                         json.dumps(dict(payload, account='bob')))[0], 403)
            self.assertEqual(len(self.upstream.seen), admitted)

    def test_owned_inventory_unequip_route(self):
        data = dict(character_id='123', item_id='456')
        code, body = self.request('POST', '/inventory/unequip', json.dumps(data))
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)['body'], dict(data, account='alice'))
        self.assertEqual(len(self.upstream.seen), 1)
        self.assertEqual(self.request('POST', '/inventory/unequip',
                                     json.dumps(dict(data, account='bob')))[0], 403)
        self.assertEqual(len(self.upstream.seen), 1)
        self.upstream.status = 400
        self.upstream.body = b'{"error":"owned_equipped_item_required"}'
        code, body = self.request('POST', '/inventory/unequip', json.dumps(data))
        self.assertEqual(code, 400)
        self.assertEqual(json.loads(body)['error'], 'owned_equipped_item_required')

    def test_duplicate_keys(self):
        for path in ('/characters?account=alice&account=bob','/characters?account=alice&%61ccount=alice','/characters?x=1&x=2'):
            self.assertEqual(self.request(path=path)[0],400)
        self.assertEqual(self.request('POST','/enter','{"account":"alice","account":"bob"}')[0],400)
        self.assertFalse(self.upstream.seen)
    def test_body_limits_and_framing(self):
        self.assertEqual(self.request('POST','/enter','x'*(gateway.MAX_BODY+1))[0],413)
        self.assertEqual(self.request('GET','/health','x')[0],400)
        self.assertEqual(self.request('POST','/enter','{}',headers={'Transfer-Encoding':'chunked'})[0],400)
        self.assertEqual(self.request('POST','/enter','{"x":NaN}')[0],400)
        self.assertEqual(self.request('POST','/enter','{}',headers={'Origin':'https://example.invalid'})[0],400)
        self.assertFalse(self.upstream.seen)
    def test_allowlist_and_targets(self):
        for method,path in [('GET','/admin'),('POST','/services/unknown'),('GET','http://example.invalid/health'),('GET','//example.invalid/health'),('GET','/%68ealth'),('POST','/enter?account=alice')]:
            self.assertIn(self.request(method,path,'{}' if method=='POST' else None)[0],(400,404))
        self.assertFalse(self.upstream.seen)
    def test_upstream_bounds_and_redirect(self):
        self.upstream.status=302
        self.assertEqual(self.request()[0],502)
        self.upstream.status=200;self.upstream.body=b'x'*(gateway.MAX_RESPONSE+1)
        self.assertEqual(self.request()[0],502)
    def test_tls_authenticity(self):
        with self.assertRaises(ssl.SSLCertVerificationError):self.request(context=ssl.create_default_context())
        with socket.create_connection(self.gateway.server_address,timeout=3) as raw:
            with self.context.wrap_socket(raw,server_hostname='45.147.228.101') as tls:
                self.assertIn(tls.version(),('TLSv1.2','TLSv1.3'))
        with socket.create_connection(self.gateway.server_address,timeout=3) as raw:
            with self.assertRaises(ssl.SSLCertVerificationError):self.context.wrap_socket(raw,server_hostname='192.0.2.99')
    def test_redacted_logging_and_response(self):
        captured=io.StringIO()
        with contextlib.redirect_stderr(captured):
            code,body=self.request(path='/bad?token='+TOKEN,token=OTHER)
        self.assertEqual(code,404);self.assertNotIn(TOKEN,body.decode()+captured.getvalue());self.assertNotIn(OTHER,captured.getvalue())
    def test_duplicate_headers_and_plaintext(self):
        requests = [
            'GET /health HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer '+TOKEN+'\r\nAuthorization: Bearer '+OTHER+'\r\n\r\n',
            'POST /enter HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer '+TOKEN+'\r\nContent-Length: 2\r\nContent-Length: 2\r\nContent-Type: application/json\r\n\r\n{}',
        ]
        for raw_request, status in zip(requests,(401,400)):
            with socket.create_connection(self.gateway.server_address,timeout=3) as raw:
                with self.context.wrap_socket(raw,server_hostname='127.0.0.1') as tls:
                    tls.sendall(raw_request.encode())
                    self.assertIn((' '+str(status)+' ').encode(),tls.recv(4096))
        with socket.create_connection(self.gateway.server_address,timeout=3) as raw:
            raw.sendall(b'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n')
            try: self.assertNotIn(b'HTTP/1.1 200',raw.recv(4096))
            except ConnectionResetError: pass
        self.assertFalse(self.upstream.seen)

    def test_action_allowlist_matches_adapter_protocols(self):
        root=Path(__file__).resolve().parents[1]
        for family in ('vehicles','medic','scout','crafting','services','entertainer'):
            module=importlib.import_module('server.'+family+'_protocol')
            actions=getattr(module,'ACTIONS',None)
            if actions is None:
                tree=ast.parse((root/'server'/f'{family}_protocol.py').read_text())
                function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='command')
                condition=next(n for n in function.body if isinstance(n,ast.If)).test
                self.assertIsInstance(condition,ast.Compare)
                self.assertIsInstance(condition.ops[0],ast.NotIn)
                actions=ast.literal_eval(condition.comparators[0])
            if family=='entertainer':
                from server.image_design_protocol import ACTIONS as image_actions
                actions=tuple(actions)+image_actions
            actual={p.rsplit('/',1)[1] for p in gateway.POST if p.startswith('/'+family+'/')}
            if family=='services':actual.remove('presence')
            self.assertEqual(actual,set(actions),family+' action allowlist needs review')

    def test_account_config(self):
        digest=hashlib.sha256(TOKEN.encode()).hexdigest()
        for bad in ({},{'x':'plaintext'},{'x':digest,'y':digest},{'../../x':digest},
                    {'Alice':digest},{'alice':digest,'Alice':hashlib.sha256(OTHER.encode()).hexdigest()}):
            with self.assertRaises(ValueError):gateway.accounts_from_config(bad)
    def test_canonical_account_identity(self):
        self.assertEqual(gateway.accounts_from_config({'alice_1':hashlib.sha256(TOKEN.encode()).hexdigest()}).keys(),{'alice_1'})
        self.assertEqual(self.request(path='/characters?account=Alice')[0],403)
        self.assertEqual(self.request('POST','/enter','{"account":"Alice"}')[0],403)
        self.assertFalse(self.upstream.seen)

    def test_connection_limit(self):
        held=[]
        try:
            for _ in range(gateway.MAX_CONNECTIONS):
                self.assertTrue(self.gateway.slots.acquire(False));held.append(1)
            with socket.create_connection(self.gateway.server_address,timeout=3) as raw:
                self.assertEqual(raw.recv(1),b'')
        finally:
            for _ in held:self.gateway.slots.release()

if __name__=='__main__':unittest.main(verbosity=2)
