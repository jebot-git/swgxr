#!/usr/bin/env python3
"""TLS account-authenticating boundary for the private SWGXR adapter (stdlib only)."""
import argparse
import hashlib
import hmac
import http.client
import http.server
import json
import re
import socket
import socketserver
import sqlite3
import ssl
import threading
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit
try:
    from .account_auth import AccountAuth, AuthError
    from .voice_protocol import TicketAuthority
except ImportError:  # Executable systemd entry point.
    from account_auth import AccountAuth, AuthError
    from voice_protocol import TicketAuthority

MAX_BODY = 16384
MAX_RESPONSE = 8 * 1024 * 1024
try:
    from .capacity import HTTP_CONNECTIONS
except ImportError:
    from capacity import HTTP_CONNECTIONS
MAX_CONNECTIONS = HTTP_CONNECTIONS
REQUEST_DEADLINE = 75
UPSTREAM = ('127.0.0.1', 18080)
GET = {'/health','/combat/session','/gathering/corpses','/crafting','/gathering','/inventory','/weapons','/datapad','/creation-options','/characters'}
POST = {'/session/sync','/session/life','/session/start','/session/update','/session/logout','/voice/session','/voice/presence','/services/presence','/performance','/characters','/enter','/waypoints','/datapad/delete'}
for prefix, actions in {
    '/combat/session/': 'start update fire melee taunt impact stop life',
    '/gathering/corpse/': 'inspect harvest loot',
    '/gathering/': 'status survey deploy collect holster return_tool',
    '/inventory/': 'status equip unequip consume split',
    '/services/': 'status open mission_refresh mission_accept mission_abort delivery_open delivery_pickup delivery_complete bazaar_buy bazaar_retrieve bazaar_sell bazaar_cancel bank_transfer pay crafting_station travel_purchase travel_board trainer_train vendor_place vendor_sell vendor_buy vendor_retrieve vendor_cancel vendor_customize vendor_recover fishing_status fishing_open fishing_bait fishing_cast fishing_action fishing_stop fishing_stow fishing_collect house_status house_preview house_place house_deposit house_permission_arm house_permission house_drop house_recover house_harvester_status house_harvester_select house_harvester_active house_harvester_power house_harvester_deposit house_harvester_collect house_harvester_recover house_factory_status house_factory_blueprint house_factory_remove_blueprint house_factory_input house_factory_withdraw house_factory_collect house_factory_active house_factory_power house_factory_deposit house_factory_recover',
    '/vehicles/': 'status activate call board dismount store recall pet_call pet_recall pet_store pet_command ch_status ch_tame ch_embolden ch_enrage ch_train_mount ch_train_command',
    '/entertainer/': 'status perform stop flourish register_location group_invite group_join group_leave group_bump image_open image_propose image_accept image_cancel',
    '/medic/': 'status provision select heal holster return_tool drag',
    '/scout/': 'inspect holster return_tool status forage trap camp disband mask_scent discard_mask_scent burst_run sample_dna discard_sample_dna ranger_status conceal rescue area_track',
    '/crafting/': 'status open select assemble finish cancel',
}.items():
    POST.update(prefix + action for action in actions.split())
POST.update('/services/' + action for action in
            ('recruiter_join', 'recruiter_promote', 'recruiter_status_toggle', 'recruiter_purchase', 'contraband_answer', 'underworld_accept'))
POST.update('/services/slicing_' + action for action in ('status', 'begin', 'complete', 'cancel'))


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate key')
        result[key] = value
    return result


def accounts_from_config(value, *, allow_empty=False):
    if not isinstance(value, dict) or not (0 if allow_empty else 1) <= len(value) <= 128:
        raise ValueError('Invalid account configuration')
    result = {}
    for account, digest in value.items():
        # Adapter prefixes swgxr_ and lowercases aliases: require its canonical key.
        if not re.fullmatch(r'[a-z0-9_]{1,24}', account) or not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('Invalid account configuration')
        if digest in result.values():
            raise ValueError('Account tokens must be unique')
        result[account] = digest
    return result


class Gateway(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'SWGXR-Gateway'
    sys_version = ''

    def log_message(self, format, *args):
        # Base implementation includes attacker-controlled request URLs. Never use it.
        pass

    def send_error(self, code, message=None, explain=None):
        self.reply(code, {'error': 'Request rejected'})

    def reply(self, status, data):
        body = json.dumps(data, separators=(',', ':')).encode()
        self.send_bytes(status, body, retry_after=data.get('retry_after'))

    def send_bytes(self, status, body, retry_after=None):
        self.close_connection = True
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        if retry_after is not None: self.send_header('Retry-After', str(int(retry_after)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.proxy()

    def do_POST(self):
        self.proxy()

    def proxy(self):
        try:
            self.close_connection = True
            if len(self.path) > 4096 or len(str(self.headers)) > 16384:
                return self.reply(431, {'error':'Request headers too large'})
            if self.headers.get('Origin') or self.headers.get('Transfer-Encoding') or self.headers.get('Content-Encoding') or self.headers.get('Expect'):
                return self.reply(400, {'error':'Unsupported request framing'})
            path = urlsplit(self.path)
            if path.scheme or path.netloc or path.fragment or not self.path.startswith('/') or self.path.startswith('//') or '%' in path.path:
                return self.reply(400, {'error':'Invalid request target'})
            is_auth = path.path.startswith('/auth/')
            allowed = path.path in GET or re.fullmatch(r'/characters/[0-9]{1,20}', path.path) if self.command == 'GET' else path.path in POST
            if not allowed and not is_auth:
                return self.reply(404, {'error':'Unknown endpoint'})
            query = unique(parse_qsl(path.query, keep_blank_values=True, strict_parsing=True, max_num_fields=64))
            if any(key.lower() in {'password','pass','passwd','pwd','token','remember_token','access_token','refresh_token','authorization','bearer','secret','api_key'} for key in query):
                return self.reply(400, {'error':'Credentials in query strings are forbidden'})
            lengths = self.headers.get_all('Content-Length', [])
            if len(lengths) > 1 or (lengths and not re.fullmatch(r'[0-9]{1,8}', lengths[0])):
                return self.reply(400, {'error':'Invalid request framing'})
            length = int(lengths[0]) if lengths else 0
            if length > MAX_BODY:
                return self.reply(413, {'error':'Request body too large'})
            body = None
            data = None
            if self.command == 'POST':
                if path.query or not 0 < length <= MAX_BODY or self.headers.get_content_type() != 'application/json':
                    return self.reply(400, {'error':'Expected bounded JSON request'})
                raw = self.rfile.read(length)
                if len(raw) != length:
                    return self.reply(400, {'error':'Incomplete request body'})
                data = json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                if not isinstance(data, dict):
                    raise ValueError()
            elif length:
                return self.reply(400, {'error':'GET request body forbidden'})
            if is_auth:
                return self.auth_route(path, data)
            account, credential, legacy_credential = self.authenticate()
            if path.path.startswith('/voice/') and self.server.voice_tickets is None:
                raise AuthError(503,'Voice transport is not configured')
            if 'account' in query and query['account'] != account:
                return self.reply(403, {'error':'Account mismatch'})
            if self.command == 'POST':
                if 'password' in data:
                    return self.reply(400, {'error':'Passwords are accepted only by authentication endpoints'})
                if 'account' in data and data['account'] != account:
                    return self.reply(403, {'error':'Account mismatch'})
                data['account'] = account
                body = json.dumps(data, separators=(',', ':'), allow_nan=False).encode()
                if len(body) > MAX_BODY:
                    return self.reply(413, {'error':'Request body too large after account binding'})
                target = path.path
            else:
                query['account'] = account
                target = path.path + '?' + urlencode(query)
            # No user-controlled upstream, proxy headers, credentials, redirects or cookies.
            upstream = http.client.HTTPConnection(*self.server.upstream, timeout=60)
            upstream_deadline = None
            try:
                upstream.connect()
                upstream_socket = upstream.sock
                def expire_upstream():
                    try: upstream_socket.shutdown(socket.SHUT_RDWR)
                    except OSError: pass
                upstream_deadline = threading.Timer(60, expire_upstream)
                upstream_deadline.daemon = True
                upstream_deadline.start()
                upstream.request(self.command, target, body, {'Content-Type':'application/json','Connection':'close'})
                response = upstream.getresponse()
                if 300 <= response.status < 400:
                    return self.reply(502, {'error':'Upstream redirect refused'})
                raw = response.read(MAX_RESPONSE + 1)
                if len(raw) > MAX_RESPONSE:
                    return self.reply(502, {'error':'Upstream response too large'})
                if response.getheader('Content-Type','').split(';')[0].strip() != 'application/json':
                    return self.reply(502, {'error':'Invalid upstream content'})
                if path.path=='/voice/session' and response.status==200:
                    native=json.loads(raw)
                    if native.get('backend')!='core3' or native.get('character_id')!=data.get('character_id'):
                        raise AuthError(502,'Invalid native voice identity')
                    import time
                    expiry=time.time()+86400 if legacy_credential else self.server.auth_store.session(credential)['expires_at']
                    native['relay_port']=18444
                    native['ticket']=self.server.voice_tickets.issue(account,native['character_id'],native['native_session_id'],hashlib.sha256(credential.encode()).hexdigest(),legacy_credential,expiry)
                    raw=json.dumps(native,separators=(',',':')).encode()
                self.send_bytes(response.status, raw)
            finally:
                if upstream_deadline is not None: upstream_deadline.cancel()
                upstream.close()
        except AuthError as error:
            result = {'error':error.message}
            if error.retry_after is not None: result['retry_after'] = error.retry_after
            self.reply(error.status, result)
        except sqlite3.Error:
            self.reply(503, {'error':'Authentication storage unavailable'})
        except (ValueError, UnicodeError, RecursionError):
            self.reply(400, {'error':'Invalid request'})
        except (OSError, http.client.HTTPException):
            try:
                self.reply(502, {'error':'Private backend unavailable'})
            except OSError:
                pass


    def authenticate(self, *, legacy_only=False):
        auth = self.headers.get_all('Authorization', [])
        if len(auth) != 1 or not re.fullmatch(r'Bearer [A-Za-z0-9_-]{43,128}', auth[0]):
            raise AuthError(401, 'Authentication required')
        token = auth[0][7:]
        digest = hashlib.sha256(token.encode('ascii')).hexdigest()
        account = None
        for name, expected in self.server.accounts.items():
            if hmac.compare_digest(digest, expected): account = name
        store = self.server.auth_store
        if account is not None and (store is None or store.legacy_enabled(account)):
            return account, token, True
        if not legacy_only and store is not None:
            return store.session(token)['account'], token, False
        raise AuthError(401, 'Authentication required')

    def auth_route(self, path, data):
        store = self.server.auth_store
        if store is None: raise AuthError(503, 'Account authentication is not configured')
        if path.query: raise AuthError(400, 'Authentication query strings are forbidden')
        route, ip = path.path, self.client_address[0]
        if self.command == 'POST' and route in ('/auth/resume', '/auth/forget'):
            if self.headers.get_all('Authorization', []): raise AuthError(400, 'Saved login does not accept bearer credentials')
            if set(data) != {'account', 'remember_token'}: raise AuthError(400, 'Expected account and saved login token')
            method = store.resume if route == '/auth/resume' else store.forget
            return self.reply(200, method(data['account'], data['remember_token'], ip))
        if self.command == 'POST' and route == '/auth/remember':
            _, token, legacy = self.authenticate()
            if legacy: raise AuthError(409, 'Legacy credential must be claimed before remembering login')
            if data: raise AuthError(400, 'Remember body must be empty')
            return self.reply(200, store.remember(token))
        if self.command == 'POST' and route in ('/auth/register', '/auth/login'):
            # Public entry points accept no bearer or credentials in another channel.
            if self.headers.get_all('Authorization', []): raise AuthError(400, 'Sign-in does not accept bearer credentials')
            if set(data) != {'account','password'}: raise AuthError(400, 'Expected account and password')
            method = store.register if route == '/auth/register' else store.login
            return self.reply(201 if route == '/auth/register' else 200, method(data['account'], data['password'], ip))
        if self.command == 'POST' and route == '/auth/claim':
            account, _, _ = self.authenticate(legacy_only=True)
            if set(data) != {'password'}: raise AuthError(400, 'Expected password')
            return self.reply(200, store.claim(account, data['password'], ip))
        if (self.command == 'GET' and route == '/auth/session') or (self.command == 'POST' and route == '/auth/logout'):
            _, token, legacy = self.authenticate()
            if legacy: raise AuthError(409, 'Legacy credential must be claimed before using session endpoints')
            if self.command == 'POST' and data: raise AuthError(400, 'Logout body must be empty')
            return self.reply(200, store.session(token) if route == '/auth/session' else store.logout(token))
        raise AuthError(404, 'Unknown authentication endpoint')


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    block_on_close = False
    request_queue_size = MAX_CONNECTIONS
    allow_reuse_address = True

    def __init__(self, address, context, accounts, *, upstream=UPSTREAM, auth_database=None, registration_enabled=False, voice_secret=None):
        # Upstream override is internal for ephemeral tests; CLI never accepts one.
        if upstream[0] != '127.0.0.1':
            raise ValueError('Only private loopback upstream is supported')
        self.context, self.accounts, self.upstream = context, accounts_from_config(accounts, allow_empty=auth_database is not None), upstream
        if not isinstance(registration_enabled, bool): raise ValueError('registration_enabled must be boolean')
        if registration_enabled and auth_database is None: raise ValueError('Registration requires auth_database')
        self.auth_store = AccountAuth(auth_database, reserved=self.accounts, registration_enabled=registration_enabled) if auth_database is not None else None
        self.voice_tickets=TicketAuthority(Path(voice_secret).read_bytes()) if voice_secret else None
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        super().__init__(address, Gateway)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        sockets = [request]
        def expire():
            for sock in sockets:
                try: sock.shutdown(socket.SHUT_RDWR)
                except OSError: pass
        deadline = threading.Timer(REQUEST_DEADLINE, expire)
        deadline.daemon = True
        deadline.start()
        try:
            request.settimeout(8)
            secure = self.context.wrap_socket(request, server_side=True, do_handshake_on_connect=False)
            sockets.append(secure)
            secure.do_handshake()
            self.finish_request(secure, address)
        except Exception:
            pass
        finally:
            deadline.cancel()
            for sock in sockets:
                self.shutdown_request(sock)
            self.slots.release()

    def handle_error(self, request, client_address):
        # No traceback can include request/JSON/token values in systemd logs.
        pass


def tls_context(certificate, private_key):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certificate, private_key)
    return context


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=18443)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(), object_pairs_hook=unique)
    server = Server((args.bind,args.port), tls_context(config['certificate'],config['private_key']), config.get('accounts', {}), auth_database=config.get('auth_database'), registration_enabled=config.get('registration_enabled', False), voice_secret=config.get('voice_secret'))
    print('SWGXR authenticated TLS gateway ready', flush=True)
    try: server.serve_forever()
    finally: server.server_close()

if __name__ == '__main__':
    main()
