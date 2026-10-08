"""Linux and Windows tester updater. TLS-authenticated, hashed chunks and atomic activation."""
from contextlib import contextmanager
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import tempfile
import time
from urllib.parse import urlsplit
try:
    from .launcher_platform import host_target, installation_lock
except ImportError:
    from launcher_platform import host_target, installation_lock
try:
    from . import client_release_protocol as protocol
except ImportError:
    try: import client_release_protocol as protocol
    except ImportError:
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        from server import client_release_protocol as protocol


def atomic(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.write-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        os.replace(name, path)
        if os.name != 'nt':
            directory = os.open(path.parent, os.O_RDONLY)
            try: os.fsync(directory)
            finally: os.close(directory)
    finally:
        if os.path.exists(name): os.unlink(name)


class RetryableError(ValueError):
    pass


class Transport:
    def __init__(self, origin, ca_certificate):
        u = urlsplit(origin)
        if u.scheme != 'https' or not u.hostname or u.username or u.password or u.path not in ('', '/') or u.query or u.fragment:
            raise ValueError('Server must be a plain HTTPS origin')
        self.origin = origin.rstrip('/'); self.host = u.hostname; self.port = u.port or 443
        self.ca = str(Path(ca_certificate).resolve(strict=True))
        self.context = ssl.create_default_context(cafile=self.ca)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.session = None

    def request(self, path, maximum, body=None):
        if not path.startswith('/') or path.startswith('//'): raise ValueError('Invalid service path')
        headers = {'Content-Type': 'application/json'}
        if body is None:
            if not self.session: raise ValueError('Sign in first')
            headers['Authorization'] = 'Bearer ' + self.session['token']
        conn = http.client.HTTPSConnection(self.host, self.port, context=self.context, timeout=60)
        try:
            conn.request('GET' if body is None else 'POST', path,
                         body=None if body is None else protocol.encode(body), headers=headers)
            response = conn.getresponse(); raw = response.read(maximum + 1)
            if len(raw) > maximum: raise ValueError('Server response exceeds the allowed size')
            if response.status not in (200,201):
                # Never echo an untrusted response or request containing credentials.
                messages = {400:'Check the account name and password (12–128 characters).',
                            401:'Sign in again; account, password or session is invalid.',
                            403:'Access denied. Check the invitation or tester access.',
                            404:'No client build is published for this testing target yet. Try again after the build is released.',409:'Account name is unavailable.',
                            429:'Too many attempts. Wait before trying again.',503:'Server busy. Try again shortly.'}
                error_type = RetryableError if response.status in (429, 503) else ValueError
                raise error_type(messages.get(response.status, 'Server request failed (HTTP %d).' % response.status))
            return raw
        finally: conn.close()

    def authenticate(self, account, password, invite_code=None):
        self.session = None
        body = dict(account=account, password=password)
        if invite_code is not None: body['invite_code'] = invite_code
        session = protocol.decode(self.request('/auth/register' if invite_code is not None else '/auth/login', 16384, body))
        if not isinstance(session, dict) or session.get('account') != account or not re.fullmatch(r'[A-Za-z0-9_-]{43}', session.get('token','')) or not isinstance(session.get('expires_at'), (int,float)) or session['expires_at'] <= time.time():
            raise ValueError('Server returned an invalid session')
        self.session = session
        return session

    def fetch(self, path, maximum):
        # Retry only reads; never replay registration or password submissions.
        for attempt in range(5):
            try: return self.request(path, maximum)
            except (RetryableError, OSError, http.client.HTTPException):
                if attempt == 4: raise
                time.sleep(min(2 ** attempt, 8))


class Patcher:
    def __init__(self, root, transport, channel='testing', progress=None, target=None):
        self.root = Path(root).resolve(); self.transport = transport
        self.target = target or host_target()
        if self.target not in protocol.PLATFORMS: raise ValueError('Unsupported client platform')
        self.channel = protocol.channel_name(channel)
        self.progress = progress or (lambda message: None)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        for name in ('cache','versions','state','logs'):
            path = self.root / name
            if path.is_symlink(): raise ValueError('Managed directory cannot be a symlink')
            path.mkdir(exist_ok=True, mode=0o700)
        self.locked = False

    @contextmanager
    def lock(self):
        with installation_lock(self.root / 'state' / 'lock'):
            self.locked = True
            try:
                # Recover interruption during repair of the same release directory.
                for old in (self.root / 'versions').glob('*.old'):
                    key = protocol.sha(old.name.removesuffix('.old'))
                    final = old.with_name(key)
                    if old.is_symlink() or final.is_symlink(): raise ValueError('Invalid installation directory')
                    if not final.exists(): old.rename(final)
                    else: shutil.rmtree(old)
                # A previous killed launcher can leave a short-lived token profile.
                for profile in (self.root / 'state').glob('connection-*.json'): profile.unlink()
                yield
            finally: self.locked = False

    def current(self):
        path = self.root / 'state' / 'current.json'
        if not path.exists(): return None
        value = protocol.decode(path.read_bytes()); protocol.sha(value['manifest_sha256'])
        if type(value.get('sequence')) is not int: raise ValueError('Invalid installed release record')
        return value

    def cached(self, key, maximum):
        protocol.sha(key); path = self.root / 'cache' / key
        if path.exists() and not path.is_symlink():
            raw = path.read_bytes()
            if len(raw) <= maximum and protocol.digest(raw) == key: return raw
        raw = self.transport.fetch('/patch/v1/blobs/' + key, maximum)
        if len(raw) > maximum or protocol.digest(raw) != key: raise ValueError('Download failed its integrity check; retry the update')
        atomic(path, raw)
        return raw

    def update(self):
        if not self.locked: raise RuntimeError('Installation lock required')
        descriptor = protocol.decode(self.transport.fetch('/patch/v1/channels/' + self.channel, 4096))
        key = protocol.sha(descriptor['manifest_sha256'])
        if descriptor.get('schema') != 1 or type(descriptor.get('manifest_size')) is not int or not 0 < descriptor['manifest_size'] <= protocol.MAX_MANIFEST: raise ValueError('Invalid release descriptor')
        raw = self.cached(key, descriptor['manifest_size'])
        if len(raw) != descriptor['manifest_size']: raise ValueError('Manifest size mismatch')
        release = protocol.manifest(protocol.decode(raw), self.channel, self.target)
        if release['sequence'] != descriptor.get('sequence') or release['version'] != descriptor.get('version'): raise ValueError('Release descriptor mismatch')
        current = self.current()
        if current and (release['sequence'] < current['sequence'] or (release['sequence'] == current['sequence'] and current['manifest_sha256'] != key)):
            raise ValueError('Refusing an older or conflicting release')
        final = self.root / 'versions' / key
        staging = self.root / 'versions' / (key + '.partial')
        if staging.is_symlink() or final.is_symlink(): raise ValueError('Invalid installation directory')
        if staging.exists(): shutil.rmtree(staging)
        staging.mkdir(mode=0o700)
        # Keep downloaded chunks across failures; nothing points at the staged files.
        try:
            for index, row in enumerate(release['files']):
                self.progress('Preparing %d/%d: %s' % (index+1, len(release['files']), row['path']))
                path = staging / row['path']; path.parent.mkdir(parents=True, exist_ok=True)
                hasher = hashlib.sha256(); size = 0
                with path.open('wb') as output:
                    for chunk_key in row['chunks']:
                        chunk = self.cached(chunk_key, protocol.CHUNK_SIZE)
                        hasher.update(chunk); size += len(chunk); output.write(chunk)
                    output.flush(); os.fsync(output.fileno())
                if size != row['size'] or hasher.hexdigest() != row['sha256']: raise ValueError('Client file failed verification')
                if row['relocate']:
                    raw = path.read_bytes().replace(protocol.ROOT_TOKEN, protocol.encode(final.as_posix())[1:-1])
                    protocol.decode(raw); atomic(path, raw)
                path.chmod(0o700 if row['executable'] else 0o600)
            atomic(staging / 'release.json', protocol.encode(release))
            if final.exists():
                # Same immutable release may be repaired while no client is running.
                old = final.with_name(key + '.old')
                if old.exists(): shutil.rmtree(old)
                final.rename(old)
                try: staging.rename(final)
                except BaseException: old.rename(final); raise
                shutil.rmtree(old)
            else: staging.rename(final)
            atomic(self.root / 'state' / 'current.json', protocol.encode(descriptor))
        finally:
            if staging.exists(): shutil.rmtree(staging)
        self.progress('Ready: ' + release['version'])
        return final

    def launch(self, *, desktop=False):
        if not self.locked: raise RuntimeError('Installation lock required')
        if not self.transport.session: raise ValueError('Sign in first')
        current = self.current()
        if not current: raise ValueError('Install the client first')
        folder = self.root / 'versions' / current['manifest_sha256']
        protocol.manifest(protocol.decode((folder / 'release.json').read_bytes()), self.channel, self.target)
        profile = dict(base_url=self.transport.origin, ca_certificate=self.transport.ca,
                       launcher_session=self.transport.session)
        fd, name = tempfile.mkstemp(prefix='connection-', suffix='.json', dir=self.root / 'state')
        try:
            with os.fdopen(fd, 'wb') as output: output.write(protocol.encode(profile))
            env = os.environ.copy(); env.pop('OBS_VKCAPTURE', None)
            env.update(DISABLE_XR_APILAYER_NOVENDOR_OBSMirror='1', DISABLE_OBS_VKCAPTURE='1')
            args = [str(folder / protocol.PLATFORMS[self.target]), '--path', str(folder / 'client'), '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
            if desktop: args += ['--xr-mode', 'off']
            args += ['--', '--connection-profile=' + name]
            if desktop: args += ['--desktop']
            with (self.root / 'logs' / 'client.log').open('ab') as log:
                return subprocess.run(args, cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
        finally: os.unlink(name)
