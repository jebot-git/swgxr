# Isolated VPS runtime

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
`true` to enable account creation. Gateway runs as `blux` with an empty capability
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
