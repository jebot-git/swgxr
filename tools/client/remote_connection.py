"""Private remote profiles and verified, non-redirecting SWGXR HTTPS requests.

Profiles and certificates belong under ignored runtime/client, never source control.
The public representation deliberately excludes bearer credentials.
"""
from dataclasses import dataclass, field
import json
from pathlib import Path
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request

MAX_BODY_BYTES = 16 * 1024
SAFE_ERROR_MESSAGES = frozenset({
    'native_response_timeout',
    'session_not_live',
    'Persistent Core3 zone session exited.',
    'Persistent Core3 command timed out; session must be restarted.',
    'Live session identity does not match this owned character.',
    'A fresh owned native session is required for multiplayer sync',
    'Fresh presentation sequence required',
    'Presentation update rate exceeded',
    'Refresh the native position/cell before sharing tracking',
    'Valid public action cursor required',
    'Public action cursor is ahead of the server',
    'Normalized tracked orientation required',
    'Tracked transform is outside the body presentation bounds',
    'Core3 is processing another request; retry shortly',
    'Core3 request queue is full; retry shortly',
    'Inventory refresh waits for an authoritative transaction; retain last confirmed readout',
})


def safe_http_diagnostic(exc):
    """Retain only known static errors; never a reflected body, URL or credential."""
    out = {'http_status': exc.code}
    try:
        value = json.loads(exc.read(4096))
        if isinstance(value, dict) and value.get('error') in SAFE_ERROR_MESSAGES:
            out['server_error'] = value['error']
        else:
            out['server_error'] = 'Unrecognized server message omitted'
    except (ValueError, OSError, TypeError):
        out['server_error'] = 'Unreadable server message omitted'
    return out


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def validate_origin(value):
    if not isinstance(value, str) or not value.startswith('https://'):
        raise ValueError('Remote base_url must use HTTPS.')
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise ValueError('Remote base_url is not a valid HTTPS origin.') from exc
    if (not parsed.hostname or parsed.username is not None or parsed.password is not None
            or parsed.path not in ('', '/') or parsed.query or parsed.fragment
            or any(character.isspace() or character in '\\' for character in value)
            or (port is not None and not 1 <= port <= 65535)):
        raise ValueError('Remote base_url must be an HTTPS origin without credentials, path, query, or fragment.')
    if not re.fullmatch(r'https://(?:\[[0-9A-Fa-f:]+\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::[0-9]{1,5})?/?', value):
        raise ValueError('Remote base_url contains an invalid hostname or port.')
    return value.rstrip('/')


def validate_path(path, account, body=None):
    if (not isinstance(path, str) or not path.startswith('/') or path.startswith('//')
            or '#' in path or '\\' in path or any(ord(character) < 32 or ord(character) == 127 for character in path)):
        raise ValueError('Remote request must use a relative service path.')
    accounts = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query, keep_blank_values=True).get('account', [])
    if len(accounts) > 1 or any(value != account for value in accounts):
        raise ValueError('Remote request account differs from the authenticated profile.')
    if body is not None:
        if not isinstance(body, dict):
            raise ValueError('Remote request body must be a JSON object.')
        if 'account' in body and body['account'] != account:
            raise ValueError('Remote request account differs from the authenticated profile.')


@dataclass(frozen=True)
class RemoteConnection:
    base_url: str
    account: str
    token: str = field(repr=False)
    ca_certificate: Path
    profile_path: Path
    _context: ssl.SSLContext = field(repr=False)

    @classmethod
    def load(cls, path):
        path = Path(path).expanduser().resolve()
        try:
            value = json.loads(path.read_text())
        except (OSError, ValueError) as exc:
            raise ValueError('Cannot read the private remote connection profile.') from exc
        if not isinstance(value, dict):
            raise ValueError('Remote connection profile must be a JSON object.')
        base = validate_origin(value.get('base_url'))
        account = value.get('account', '')
        token = value.get('token', '')
        if not isinstance(account, str) or (account and not re.fullmatch(r'[A-Za-z0-9_]{1,24}', account)):
            raise ValueError('Remote account must contain 1–24 letters, digits, or underscores.')
        if (not isinstance(token, str) or len(token) > 4096
                or (token and not re.fullmatch(r'[A-Za-z0-9._~+/\-]+=*', token))
                or bool(account) != bool(token)):
            raise ValueError('Remote legacy credentials require both a valid account and bearer token.')
        certificate = value.get('ca_certificate')
        if not isinstance(certificate, str) or not Path(certificate).is_absolute():
            raise ValueError('Remote ca_certificate must name an absolute PEM certificate path.')
        certificate = Path(certificate)
        if not certificate.is_file():
            raise ValueError('Remote CA certificate file is unavailable.')
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        try:
            context.load_verify_locations(cafile=str(certificate))
        except (OSError, ssl.SSLError) as exc:
            raise ValueError('Remote CA certificate is invalid.') from exc
        # PROTOCOL_TLS_CLIENT retains CERT_REQUIRED and hostname/IP SAN checks.
        return cls(base, account, token, certificate.resolve(), path, context)

    @property
    def authenticated(self):
        return bool(self.account and self.token)

    def request_json(self, path, *, method='GET', body=None, timeout=55):
        if not self.authenticated:
            raise ValueError('Sign in through the client before requesting account data.')
        validate_path(path, self.account, body)
        raw = None if body is None else json.dumps(body, separators=(',', ':')).encode('utf-8')
        if raw is not None and len(raw) > MAX_BODY_BYTES:
            raise ValueError('Remote request exceeds the gateway JSON body limit.')
        request = urllib.request.Request(self.base_url + path, data=raw, method=method,
            headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + self.token})
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=self._context), NoRedirect())
        try:
            with opener.open(request, timeout=timeout) as response:
                value = json.load(response)
        except urllib.error.HTTPError as exc:
            exc.safe_diagnostic = safe_http_diagnostic(exc)
            exc.close()
            raise
        if not isinstance(value, dict):
            raise ValueError('Remote service did not return a JSON object.')
        return value


def connection_arguments(args, root):
    """Select private default profile, with explicit --local taking precedence.

    Returned command arguments contain only profile path, public URL, and account.
    Tokens are never copied into process arguments or environment variables.
    """
    args = list(args)
    profile_values = [argument.split('=', 1)[1] for argument in args if argument.startswith('--connection-profile=')]
    if '--connection-profile' in args or any(not value for value in profile_values):
        raise ValueError('--connection-profile requires a file path.')
    if len(profile_values) > 1:
        raise ValueError('Select only one remote connection profile.')
    if '--local' in args:
        if profile_values:
            raise ValueError('--local and --connection-profile cannot be combined.')
        return args, None
    if '--offline' in args:
        if profile_values:
            raise ValueError('A remote connection profile cannot be combined with --offline.')
        return args, None
    selected = Path(profile_values[0]).expanduser().resolve() if profile_values else Path(root) / 'runtime/client/connection.json'
    if not profile_values and not selected.exists():
        return args, None
    connection = RemoteConnection.load(selected)
    for key, expected in (('backend', connection.base_url), ('account', connection.account)):
        supplied = [argument.split('=', 1)[1] for argument in args if argument.startswith('--' + key + '=')]
        if any(value.rstrip('/') != expected for value in supplied):
            raise ValueError('Remote profile conflicts with the requested ' + key + '.')
    args = [argument for argument in args if not argument.startswith(('--connection-profile=', '--backend=', '--account='))]
    args += ['--connection-profile=' + str(connection.profile_path), '--backend=' + connection.base_url]
    if connection.authenticated:
        args += ['--account=' + connection.account]
    return args, connection
