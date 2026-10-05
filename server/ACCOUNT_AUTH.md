# Remote gateway accounts

The TLS gateway handles account credentials. Core3 remains the authoritative character and RPG database. Registration creates only a gateway identity; the private adapter creates its corresponding native Core3 account lazily on the first authorized native RPC. Passwords never reach the adapter or Core3.

Configuration adds `auth_database` (persistent SQLite path) and `registration_enabled` (boolean, default `false`). Existing `accounts` contains legacy alias → SHA256 bearer mappings and can be empty when `auth_database` is configured. Preserve the auth database across updates and back it up with its SQLite WAL consistently. It contains sensitive credential hashes and sessions, and is created with mode0600. Gateway startup requires writable database storage.

| Method/path | Input | Success |
|---|---|---|
| POST `/auth/register` | `{account,password}` | 201 `{account,token,expires_at,expires_in}` |
| POST `/auth/login` | `{account,password}` | 200 same session envelope |
| GET `/auth/session` | Session Bearer | 200 `{account,expires_at,expires_in}` |
| POST `/auth/logout` | Session Bearer, `{}` | 200 `{logged_out:true}` |
| POST `/auth/claim` | Configured legacy Bearer, `{password}` | 200 new session envelope |

Public register/login requests must omit Authorization. Other API calls accept a session Bearer or a still-enabled legacy Bearer, enforce that account on upstream calls, and never forward Authorization. Auth routes accept only their documented fields and no query. Credential-like query keys are rejected on ordinary routes too. Errors contain a safe `error` string. Rate limits return429 with integer `retry_after` and `Retry-After`; unavailable auth storage returns503. Invalid/revoked/expired sessions return401.

New account names must match `[a-z][a-z0-9_]{2,23}` exactly. Passwords must contain12–128 Unicode characters and at most512 UTF-8 bytes. Passwords use scrypt N131072/r8/p1, random16-byte salts and32-byte hashes; unknown accounts perform a dummy scrypt verification. The process permits two concurrent KDF calls (~256MiB combined scrypt memory); additional calls receive429. A KDF failure returns503, and no password or token is logged.

Sessions contain32 random bytes (43-character URL-safe token), expire after24hours and store only SHA256 hashes. Logout revokes that session immediately. At most16 live session records are retained per account. Expired records are pruned when issuing sessions. Authentication limits use bounded in-memory histories: login20 attempts per IP and10 per account per5minutes, plus a global120/minute CPU budget; registration/claim5 per IP/account perhour plus global30/hour and120/day. Successful attempts count too. A distributed attack can exhaust the global budget and temporarily return429 to legitimate users; this intentionally bounds work on the two-vCPU realm. Histories reset on gateway restart; saturation fails closed.

All configured legacy aliases plus `health` are reserved against registration. Claim requires the matching valid legacy bearer, atomically creates password credentials and persistently disables that legacy credential. A claimed account uses password login thereafter. Legacy aliases incompatible with the new account grammar cannot be claimed; they retain their existing automation credential. Legacy session/logout calls return409 and instruct the user to claim first. Claims cannot be repeated or used to replace an existing password. There is no password reset/recovery endpoint in this milestone.

Verification: `python3 -m unittest tests.test_account_auth tests.test_remote_gateway tests.test_remote_auth -q`. Tests use temporary databases and a trusted ephemeral TLS certificate; they exercise real TLS registration/login/binding/logout/expiry/claim, concurrent registration, persistent credential migration, password/token storage, dummy verification, bounded KDF/rate/session resources, request framing and existing gateway protections. These tests do not create native Core3 characters or require a live headset.
