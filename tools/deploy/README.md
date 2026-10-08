# Isolated VPS runtime

The current package target is **12 vCPUs / 24 GB RAM with all ten original ground
planets**, selected with `--profile corecu-all-planets-12cpu-24gb` when preparing
capacity overlays or packaging. It uses six zone workers, two navmesh workers
and a 1 GiB database buffer pool; connected-player admission remains unlimited.
The [all-planets procedure](../../docs/VPS_DEPLOYMENT.md#all-planets-package--12-vcpu--24-gb-target)
supersedes the older Tatooine-only preparation below for this package. A
`--prepare-only` package explicitly contains source/build inputs without current
binaries and must not be deployed. Normal runtime packaging still requires a
current linked build receipt.

The optional `corecu-tatooine-32` profile prepares a 32-player sizing target
without a connected-player ceiling. Stage it with
`tools/deploy/prepare_capacity_profile.py`; the migration and synthetic-load
procedure is in [VPS deployment](../../docs/VPS_DEPLOYMENT.md#corecu-capacity-preparation--not-deployed).
It uses four zone threads, one navmesh worker, a 2048-process container budget,
512 MiB InnoDB buffer pool and 128 concurrent gateway requests on an 8-vCPU,
16-GB-class host. These are initial budgets, not measured capacity. The default
native and voice admission limits are zero (unlimited); the profile preserves
Tatooine-only scope. The two-thread settings below describe the legacy profile.
Packaging now requires a successful current native build receipt and includes
the `corecu` executable plus the `core3` compatibility executable.

The deployment uses a rootful Podman runtime image
`localhost/swgxr-runtime:20261004` and container `swgxr-core3-build`, with
`--network none`. Native Core3 UDP, MariaDB TCP and native clients communicate
only inside that network namespace. Host adapter HTTP binds127.0.0.1:18080.
Only the separately authenticated TLS gateway listens publicly on18443.

After the integrator uploads the verified runtime bundle and image, on the VPS:

```
sudo python3 /home/blux/swgxr/tools/deploy/runtime.py bootstrap --confirm-fresh-remote
sudo python3 /home/blux/swgxr/tools/deploy/runtime.py install-units
sudo systemctl enable --now swgxr.target
```

`bootstrap` requires `runtime/remote/schema.sql` with the empty schema and only
the galaxy2 and db_metadata1008 seed rows. It derives remote overlays from the
packaged native `config-local.lua` and resource manager script, generates a
random private DB password, creates empty SQL/BDB directories, and starts
nothing. It never invokes the legacy init-db script or imports local accounts,
characters or BDB. An existing marked bootstrap is retained without resetting
credentials or state; an unmarked populated database is rejected. Initial SQL
import is performed by the supervised DB process before Core3 is allowed to
start. An interrupted first import leaves Core3 blocked; inspect and restore the
fresh schema before retrying rather than importing over partial tables.

Generated files live under `runtime/remote`: `db-password`, `config-local.lua`,
`resource_manager.lua`, `bootstrap.json`, `schema-ready`, `mysql/`, `databases/`,
and `logs/`. The config and resource overrides are read-only container mounts
onto the standard native paths. Native source files are never modified.
Tatooine alone is enabled, with two zone threads, one navmesh job, no scripted
initial resource population and a fixed iron pool without JTL additions.

The integrator supplies `runtime/remote/gateway.json` with certificate/key paths
and optional hashed legacy per-account tokens. Set `auth_database` to
`/home/blux/swgxr/runtime/auth/accounts.sqlite3` and `registration_enabled` to
`true` to enable account creation with administrator-issued invitations (see below). Gateway runs as `blux` with an empty capability
set and a read-only filesystem except for the private `runtime/auth` directory.
`install-units` creates this directory owned by `blux`, mode0700. Back up its
SQLite database consistently along with native state; it contains password
hashes, session hashes and persistent legacy-token revocations.
Its certificate, key and configuration must be
readable by `blux`; key and configuration stay mode0600 and owned by `blux`.
The host adapter runs root because its native calls use rootful Podman. Protect
the workspace, credential files and rootful container administration accordingly.

Services have ordered startup/readiness and shutdown. Core3 readiness requires
a timestamp written by `ExecStartPre` and the native `[Core] initialized` marker;
it is startup evidence, not an authenticated game session. Verify actual login
and zone readiness separately through authenticated gateway `/health`.
At2GB plus swap, startup allows ten minutes. Core3 uses a private FIFO;
stopping its unit sends `exit` and waits up to210seconds for save-and-exit.
Database/container shutdown refuses while Core3 remains alive. If graceful
shutdown times out, inspect the native log and processes before recovery; do
not erase databases or force a second Core3 process over the same BDB files.

Use `sudo systemctl restart swgxr.target` for coordinated clean restart, or
`sudo systemctl stop swgxr.target` to stop all services. Individual processes
restart on failure, but dependency failures can leave upper layers stopped.
The target uses Wants, so restarting a leaf service does not stop the target
and cascade into native shutdown. Explicit target shutdown still propagates
through PartOf. Required dependencies remain between the individual services.
Check each service, rather than treating an active target as proof all are
healthy; after fixing a failure explicitly start the affected upper layers.
Do not assume unattended full-stack recovery. No advanced automatic dependency recovery is
configured. Existing unmanaged containers with the same name are refused.

Console output rotates at32MiB and retains one rotated and one previous-start
file. The timer checks native/MariaDB logs every minute, keeps a32MiB tail
before truncating oversized active logs, and bounds native zArchive history
to64files/128MiB. Native log writes may exceed that threshold between checks.
Systemd output has per-unit log rate limits. Credentials/SQL are not printed.

Validation is read-only or uses disposable directories:
`python3 tools/deploy/test_runtime.py` and Python compilation. Unit templates
can be rendered into a temporary directory and checked with
`systemd-analyze verify`; installing units and live restart tests are separate
remote administrator actions.

## AppArmor and crun signal stacking

The runtime retains AppArmor and `no-new-privileges`. On the target Ubuntu host,
crun stacks its profile with the container profile. The stock container signal
peer rule does not recognize this combined label, preventing MariaDB bootstrap
from signalling its own processes. This matches the [upstream container-libs
report](https://github.com/podman-container-tools/container-libs/issues/805).

`apparmor/swgxr-core3` derives from the [upstream container profile
source](https://github.com/containers/common/blob/main/pkg/apparmor/apparmor_linux_template.go),
retains its proc/sys/mount restrictions, and permits send/receive signals only
for both exact label orders `swgxr-core3//&crun` and `crun//&swgxr-core3`.
It does not allow arbitrary
stacked peers or disable either system AppArmor or the crun profile.
`container-start` installs/reloads this dedicated profile on the host, verifies
that it enforces, and explicitly selects it for the runtime container. An old
container created with the default profile is rejected; the administrator must
stop its processes and recreate the container while preserving the mounted
runtime data. Profile syntax can be checked without loading it into the kernel:
`apparmor_parser -Q -K tools/deploy/apparmor/swgxr-core3`.

## Daily 05:00 UTC game restart

`swgxr-daily-restart.timer` schedules the persistent game stack every day at
**05:00 UTC**, with one-second timer accuracy and no randomized delay. The target
starts the timer; existing deployments can activate it with
`sudo systemctl enable --now swgxr-daily-restart.timer` after installing units.
`Persistent=false` intentionally avoids an immediate catch-up restart when the
schedule is first enabled or the machine boots after05:00. Check the actual next
run with `systemctl list-timers swgxr-daily-restart.timer`.

The oneshot runs `tools/deploy/scheduled_restart.py`: disconnect voice/gateway/
adapter sessions, request native Core3 `exit`, wait for confirmed save-and-exit,
then start Core3 and its adapter, gateway and voice dependants. MariaDB, the
container, persistent BerkeleyDB files and existing backup retention are retained.
Players reconnect after the native login/zone readiness check passes. This is a
game-service restart, not an operating-system reboot.

Native graceful shutdown runs before systemd stops the Core3 supervisor. If the
210-second save timeout expires, the job fails and logs the phase without sending
a forced kill or starting a second Core3 process. Inspect
`journalctl -u swgxr-daily-restart.service` and native logs before intervening;
frontends stay stopped after a failed graceful shutdown. Successful completion
logs all four active services and actual native login/zone readiness. The oneshot
is serialized by systemd; enabling the timer does not execute the restart itself.

Validation: `python3 -m unittest tools.deploy.test_scheduled_restart
 tools.deploy.test_runtime` (write on one shell line). Live deployment validation
checks unit syntax, enabled/active timer state, its next UTC elapse, unchanged
service PIDs during schedule installation, and authenticated `/health` readiness.

## Desktop launcher, updates and invitations

The Linux/Windows x86_64 testing launcher is `tools/client/launcher.py`
(Python 3.10+ and Tk). These are source bootstraps, not standalone executables.
`tools/client/package_launcher.py` produces a small bootstrap containing the
launcher, the public server origin and CA certificate. It contains no passwords,
private keys, invitations or game assets. Testers create an account with an
administrator-issued invitation, install/update once, then press Play VR.
Subsequent releases download only missing SHA-256 chunks; each chunk is 4 MiB
or smaller. The launcher remains a desktop application.

Prepare the launcher first; this requires only the public server CA, without a
client build or a server deployment:

```bash
python3 tools/client/package_launcher.py --target linux-x86_64 --output runtime/releases/testing-launcher/swgxr-launcher-linux-x86_64.tar.gz --origin https://87.106.27.237:18443 --ca runtime/client/server-ca.pem
python3 tools/client/package_launcher.py --target windows-x86_64 --output runtime/releases/testing-launcher/swgxr-launcher-windows-x86_64.zip --origin https://87.106.27.237:18443 --ca runtime/client/server-ca.pem
```

The packages use `testing-linux-x86-64` and `testing-windows-x86-64`, respectively.
Channel names retain the existing gateway's letters/digits/hyphens format.
Each manifest declares `linux-x86_64` or `windows-x86_64`; the patcher refuses a
platform mismatch before installing files. An unpublished channel displays a
clear “no client build” message. Existing bootstraps using `testing` remain valid;
new packages do not implicitly consume that older Linux release.

After the client is finished, prepare its imported project, target-native
extensions, converted assets, engine and license notices. Publish each payload
**locally**, using separate channel sequences:

```bash
python3 tools/client/prepare_payload.py --output runtime/releases/client-payload-linux --engine /path/to/Godot --engine-notices /path/to/godot-licenses
python3 tools/client/publish_release.py --target linux-x86_64 --channel testing-linux-x86-64 --payload runtime/releases/client-payload-linux --store runtime/releases/client-patches --source-root /home/blux/swgxr --version 2026.10.08.1 --sequence 1
python3 tools/client/publish_release.py --target windows-x86_64 --channel testing-windows-x86-64 --payload /path/to/prepared-windows-payload --store runtime/releases/client-patches --source-root /home/blux/swgxr --version 2026.10.08.1 --sequence 1
```

The publisher runs on Linux and accepts either target. The current
`prepare_payload.py` assembles and probes Linux builds only. Windows client
assembly remains a separate build step: supply `engine/godot.exe`, Windows
GDExtension DLLs and dependencies, the imported project and assets in the same
layout. Use a Godot executable supporting loose projects and `--path`. Validate
that payload on Windows before publication; renaming a Linux engine is not a
Windows build. Launcher preparation does not publish any client or deploy files.

Use a Linux x86_64 Godot 4.7+ binary that supports `--path`; the payload tool
checks this with a dummy-renderer, XR-off probe. The installed 4.7.2 export
template disables path overrides and is unsuitable for this loose-file layout.
A standard editor binary works, without opening its editor. Prefer a portable
upstream binary for distribution; a distro binary still needs that distro's
shared libraries. The client native extensions also require compatible system
libraries. This preparation does not establish compatibility across Linux
versions or provide a Windows client. Keep the XR Tools pin unchanged.

The payload includes converted assets for the prepared ground planets and the
combat/entertainment catalogs. Original ISOs/TREs, extraction directories,
credentials and server databases are excluded. Catalog paths pointing into the
source workspace are relocated into the installed release; hashes verify the
canonical downloaded bytes before relocation. Release contents are a snapshot;
rerun preparation after source or asset changes. Use a new payload destination
and an increasing sequence for every subsequent publication.

To enable hosting after transferring the verified store and gateway changes,
set these fields in the existing private `runtime/remote/gateway.json`, retaining
its TLS, account, auth database and voice settings:

```json
{
  "client_patch_root": "/home/blux/swgxr/runtime/releases/client-patches",
  "registration_enabled": true,
  "registration_invites_required": true
}
```

The gateway service user must be able to read the store (published files are
private by default). Transfer immutable `blobs/` before `channels/`; expose the
new channel descriptor only after all blobs arrive. Restart the existing gateway
service to load configuration changes. Do not replace its auth database. No
additional public port is needed: authenticated patch downloads use HTTPS TCP
18443, alongside the existing API. Keep patch storage out of any public web root.
Only invited accounts and accounts explicitly listed in the private store's
`access.json` (`{"accounts":["existing_tester"]}`) can download assets. A valid
legacy login alone does not grant download access.

On the server, issue invitations against the **existing** gateway database:

```bash
python3 tools/deploy/invite_account.py --database /home/blux/swgxr/runtime/auth/accounts.sqlite3 --uses 1 --hours 168
python3 tools/deploy/invite_account.py --database /home/blux/swgxr/runtime/auth/accounts.sqlite3 --revoke
```

Replace the example database path with `auth_database` from gateway.json. The
first command displays the random code once for private distribution; the
second prompts privately for a code to revoke. Only SHA-256 digests are stored.
Codes have bounded uses and expiry. Registration, code consumption, session
creation and tester access commit together. Duplicate accounts and other failed
registrations do not consume a use. Existing-account sign-in needs no invitation.
Revoking an invitation stops future redemptions; it does not revoke accounts
already created. Registration retains the existing rate limits and scrypt
password hashing. Gateway configuration requires invitations by default;
`registration_enabled` is still false unless explicitly enabled.

Linux testers extract the bootstrap and run `./launch.sh`. The default install
directory is `$XDG_DATA_HOME/swgxr`, or `~/.local/share/swgxr`. Windows testers
install 64-bit Python with Tcl/Tk and the Python launcher, extract all ZIP files,
and run `launch.cmd`; installation defaults to `%LOCALAPPDATA%\swgxr`.
Windows long-path support must be enabled before installing large asset trees.
`--install-dir "PATH"` overrides the location on either platform. The client uses
Forward+ Vulkan and the user's active OpenXR runtime; the launcher has no headset
or runtime dependency. For explicit desktop regression or asset inspection,
start `./launch.sh --desktop` or `launch.cmd --desktop`; the button reads
**Play desktop (test)** and the game receives `--xr-mode off` and `--desktop`.
Play checks for the current release before starting the game. The session
passes through a temporary file (mode 0600 on Linux, inherited user-directory
permissions on Windows), never command-line credentials;
the launcher deletes it after the client exits. The launcher does not save
passwords or invitations. Updates and gameplay hold an exclusive installation
lock. Interrupted downloads retain verified chunks for retry, while activation
only occurs after the complete new release verifies. Deleted release files are
absent from the new version. Corrupt downloads and older/conflicting release
sequences are rejected. Transport verifies the bundled CA and hostname, and
never follows redirects.

Allow space for the cache, retained installed releases and staging (at least
three times the initial payload, plus later retained versions). There is no
automatic cache/version pruning yet. Older releases and unused chunks can be
removed manually while the launcher and game are closed; retain the version
named by `state/current.json`. Obtain the bootstrap through a trusted channel:
release hashes protect transport/content integrity under the pinned server CA,
not against an administrator or compromised signing endpoint. CA rotation or
launcher code upgrades currently require a new small bootstrap; client content
and engine updates do not require another full client download.

Offline verification on Linux:
`python3 -m unittest tests.test_launcher_platform tests.test_client_launcher tests.test_account_auth`.
The portable suite can also run on Windows from the repository with
`py -3 -m unittest tests.test_launcher_platform`; it checks both target manifests,
archive contents and isolated imports, installation and path relocation, process
locking, platform rejection, executable selection and temporary-session cleanup.
Its child-process launch is mocked; it does not validate a client binary or VR.
Native Windows validation is still required before calling the Windows launcher
platform-tested.
The invite concurrency tests use a cheap test-only KDF; the existing account auth
suite exercises production scrypt. Full TLS integration additionally uses
`tests.test_remote_gateway` and `tests.test_remote_auth` and requires permission
to create local sockets. No automated check here launches a live VR client.
