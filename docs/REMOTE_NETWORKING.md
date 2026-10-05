# Remote networking

## Authenticated TLS gateway

`server/remote_gateway.py` is the public account-authenticating boundary for the
private adapter. Installing this code does not start or expose the adapter,
Core3, SQL, firewall, systemd or any VR application.

Run `python3 server/remote_gateway.py --config /etc/swgxr/gateway.json`. Public default is
`0.0.0.0:18443`; the sole upstream is `127.0.0.1:18080` and cannot be overridden
from the CLI or request. Use a certificate whose SAN contains `IP:45.147.228.101`.
The Godot remote profile must trust that exact certificate/issuing CA and use
`https://45.147.228.101:18443`; do not disable certificate or hostname validation.
Keep adapter, Core3 UDP and SQL private. Public ports are the HTTPS gateway18443
and the separate TLS voice relay18444; no native game or SQL ports are exposed.

Configuration (owner-only permissions, no plaintext bearer secrets):

```json
{
  "certificate": "/etc/swgxr/gateway-cert.pem",
  "private_key": "/etc/swgxr/gateway-key.pem",
  "accounts": {"testaccount": "64-character lowercase SHA256 of its legacy bearer token"},
  "auth_database": "/home/blux/swgxr/runtime/auth/accounts.sqlite3",
  "registration_enabled": true
}
```

Configuration account aliases must be lowercase letters, digits or underscores
(1–24 characters). Uppercase aliases are rejected because the private adapter
normalizes case; this prevents multiple gateway identities sharing one account.

Each account needs a unique cryptographically random token (`secrets.token_urlsafe(32)`
or longer, 43–128 URL-safe characters). Store its SHA256 hex digest in `accounts`;
transfer the plaintext token to the corresponding player's client profile through
an approved private channel. Do not put tokens in command lines, URLs or logs.
Revoking/rotating a token requires updating the configuration and restarting only
the gateway. Protect private key/config/profile files with mode0600; the public
certificate can be distributed to clients. Legacy profiles remain available for
dedicated automation. Interactive clients use registration and password login.

Every game request, including health and creation options, requires exactly one
`Authorization: Bearer ...` header. Every GET query or POST JSON body is bound to
the authenticated account: missing account is injected, mismatches and duplicate
keys are rejected. POST queries, browser Origins, compressed/chunked requests,
GET bodies and redirects are rejected. Only exact current adapter endpoints are
allowed; action-family wildcards are deliberately absent. Future adapter actions
require a reviewed allowlist update. No incoming headers other than validated
JSON semantics are forwarded. Authorization never reaches the private adapter.

Limits: 16 concurrent accepted connections, 16KiB request body/header aggregate,
4096-character request target, 8MiB upstream response, 8-second inbound inactivity,
60-second upstream deadline and 75-second absolute connection deadline. TLS
handshakes happen in bounded workers, so a slow handshake cannot block accept.
Responses are JSON/no-store and close the connection. Error responses and server
logging never interpolate request targets, bodies or credentials. No third-party
Python packages are used. The underlying HTTP parser also has stdlib line/count
limits before the aggregate header check; this is a bounded prototype gateway,
not a substitute for a production edge proxy/rate-limit service.

Validation: `python3 -m unittest discover -s tests -p test_remote_gateway.py -v`. Tests start only ephemeral loopback HTTPS
and echo fixtures, create disposable one-day IP-SAN certificates using the
already-installed OpenSSL executable, and never contact Core3 or the actual
adapter. Actual trusted/untrusted TLS, account binding, malformed requests,
endpoint restrictions, body/response limits, connection admission and redacted
logs are covered. No VPS, GPU or live headset validation is claimed.


## Account creation and sign-in

The holographic account panel provides **Sign in**, **Create account**, and,
when an existing legacy profile is present, **Set password**. The last option
claims that exact account and permanently disables its legacy bearer token.
The user chooses their own password; deployment never invents one for `blux`.
After a successful claim the client replaces the profile with endpoint and CA
only. A fresh launch requires sign-in. Passwords and short-lived sessions are
never saved in the profile, command line, environment or logs.

Optional **Remember login** requests an independent, revocable 90-day credential
only after successful password authentication. The client saves it in
`user://remembered_logins.json`, bound to the exact HTTPS origin and account.
The server stores only its SHA-256 verifier in the additive `remembered_logins`
table; it cannot be used directly as a gameplay bearer. **Sign in** exchanges it
for a fresh 24-hour session without filling or saving the password field.
Sign-out revokes the session but preserves the remembered credential. **Forget
saved login** revokes that credential before removing the local entry; failed
revocation is retryable. Each account retains at most eight remembered logins.
Unchecking Remember disables startup lookup; use Forget to revoke an existing
credential. Expired or revoked credentials require password sign-in.

The portable file is written atomically with owner-only permissions on Unix.
Treat it as a credential: copying the file, server profile and CA to another
installation transfers login access. No machine key or OS keyring is needed.
Windows uses the per-user data folder's ACLs and has not been runtime-tested.
The last account and preference are in `user://login_preferences.cfg`. Existing
legacy Secret Service entries are not automatically migrated or read; the old
keyring helper/probes remain only as historical regression tools.

`remember_password_smoke.gd` exercises the production main/login UI with mocked
HTTP and real portable files, including installation copy, origin/account
isolation, password override, expired/revoked tokens and failed revocation.
Python auth tests cover persisted hash-only verifiers and verified HTTPS routes.
These tests run with XR disabled and do not validate live headset rendering.

The 2026-10-05 deployed VPS probe passed 20 checks using actual Godot verified
HTTPS and a dedicated account with no character: registration, native empty
roster, login/logout, portable-file persistence and reopening, session resumption,
server revocation and rejection of the revoked token. The temporary token file
was removed and both credential types revoked after the probe. Evidence:
`runtime/evidence/yoke-recall-login/portable-login-live.json`. The accompanying
Python/TLS suite passed 34 tests, portable UI/store smoke 22 checks and existing
account UI smoke 34 checks.


A new client profile needs only:

```json
{
  "base_url": "https://45.147.228.101:18443",
  "ca_certificate": "/absolute/path/to/server-ca.pem"
}
```

The installer validates the local trust material. Server availability and TLS
are verified on sign-in; an expired legacy credential does not block launching
the login screen. The explicit `--local` mode remains a trusted, unauthenticated
loopback development interface and is labelled accordingly. Do not expose it.

Accounts use 3–24 lowercase ASCII letters, digits or underscores, starting with
a letter. Passwords use 12–128 characters, at most512 UTF-8 bytes. Password
hashes use salted scrypt N=131072,r=8,p=1, with at most two concurrent KDF calls.
The credential database is SQLite; character and RPG state remains in Core3.
Native accounts are provisioned through the existing private adapter on first
authorized native RPC. Reserve **all** existing native aliases in gateway
configuration before enabling public registration; `health` is always reserved.

| Endpoint | Authorization | Result |
| --- | --- | --- |
| POST `/auth/register` | None; account/password JSON |201, signed-in session |
| POST `/auth/login` | None; account/password JSON |200, signed-in session |
| POST `/auth/claim` | Existing legacy bearer; password JSON |200, session; old bearer disabled |
| GET `/auth/session` | Session bearer | Account and expiry |
| POST `/auth/logout` | Session bearer; empty JSON object | Session revoked |

Registration defaults disabled unless explicitly configured. Session tokens
have32 random bytes, expire after24hours and are stored only as SHA-256 hashes
on the server. Each account retains at most16 sessions. Logout revokes only
that session. Login errors do not distinguish an unknown account from a wrong
password. There is no password-reset or recovery UI in this milestone.

Authentication is rate limited per account and IP, with global budgets and a
bounded limiter table. Saturation returns429 and Retry-After, including when
both password workers are occupied. These limits protect this small test VPS;
a global budget can temporarily reject legitimate users during abuse. They
are process-local and reset on gateway restart. Registration is capped at120
attempts/day globally. Storage failure denies access.

The client clears account-owned roster, creation data and inventory on logout.
It blocks account switching during an entered world; session expiry freezes
movement and rebuilds the application before allowing another sign-in.
Account revision checks discard stale replies from the previous session.

Local verification: gateway/auth unit and TLS tests, the Godot mocked account
flow, existing TLS/IP-SAN regression, and launcher tests. The explicit
`tools/client/account_auth_smoke.py` performs a live HTTPS test, creating two
dedicated test accounts and one native character. It checks isolation and
persistence across logout/login, revokes its sessions and leaves Core3 alive.
It emits credential-free evidence and does not launch XR.

## Voice deployment and checks

`swgxr-voice.service` runs the bounded standard-library TLS relay as `blux`.
`tools/deploy/runtime.py install-units` creates a private32-byte signing secret,
adds its path and the native state path to existing gateway configuration, and
sets the shared state directory to root:blux mode02750. The root adapter publishes
state mode0640; the relay reads native metadata and the existing auth database.
The secret is never replaced on repeat installation. Start the voice unit after
the gateway. Stopping/restarting voice does not restart Core3.

Core3 patch0032 supplies actual group/faction membership; deploy the matching
native executable before enabling `/voice/session`. Tickets are short-lived,
one-use and bound to the gateway session. No password or auth bearer travels in
voice packets. Audio is forwarded as bounded opaque Opus frames without recording.

Run the explicit Godot synthetic remote probe with two existing dedicated test
profiles, `--headless --xr-mode off --audio-driver Dummy --path client --script
res://tests/voice_remote_probe.gd -- --profile1=<nettest_one.json>
--profile2=<nettest_two.json> --evidence=<report.json>`. This checks actual TLS
admission, Core3-derived channel grants, native Opus decoding and channel
isolation; it never captures the microphone or validates headset rendering.
See [protocol, bounds and prototype limitations](../server/VOICE_PROTOCOL.md).
