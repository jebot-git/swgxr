# Tatooine remote test realm

Latest server update (2026-10-05): client-resolved vehicle motion and the
entertainment/session-retention corrections are deployed. The running Core3 SHA-256
is `75cffc9991be267a0e79c3257f9f58f0e65989611efd3737f4b196ec5fb1acce`.
Graceful shutdown preceded SQL, BerkeleyDB, authentication and previous-runtime
backup at `runtime/deploy/pre-vehicle-20261005T213915Z` on the VPS. All services are
active; account/character counts, private configuration, Tatooine-only scope and
the 05:00 UTC restart timer are preserved. Authenticated HTTPS verified native
readiness, `driver_motion: client_pose`, owned inventory, a persistent session,
and saved logout on the existing dedicated test character. No VR test was run,
as requested. Evidence: `runtime/deploy/vehicle-live/` and
`runtime/evidence/vehicle-live-https.json` locally.

The custom client connects to `https://45.147.228.101:18443` through the
account-bound TLS gateway. The native Core3 UDP protocol and MariaDB are inside
a Podman container with `--network none`. The adapter listens on host loopback
port 18080. This is a custom-client test endpoint, not a public retail-client
login server.

Private client profiles live under ignored `runtime/`. Run
`python3 tools/client/install_remote_profile.py --source PATH` to install a
default endpoint/CA profile for sign-in. Legacy bearer profiles also verify
native readiness before installation. `./run.sh --local` selects the local
backend explicitly. Legacy profiles contain credentials: do not commit or share them. New session
tokens and passwords stay in memory; endpoint-only profiles contain no login
credentials.
The issuing CA key stays on the development machine; only the server key,
certificate and token hashes belong on the VPS.

## Runtime and data boundary

Ubuntu 24.04 runs Podman with the Debian runtime image built by
`tools/deploy/Containerfile`, avoiding the host's older glibc. The approved
provisioner installs Podman and adds a dedicated 4 GiB swap file when needed.
The 2 GiB VPS is a small functional test host; swap use and two successful
connections do not establish MMO capacity or real-time combat latency.

`tools/deploy/package_runtime.py` stages runtime code, native binaries,
definitions and required adapter catalogs. User-provided TRE archives are
transferred separately and checked against SHA-256 hashes. Local characters,
accounts, inventory, markets, sessions, logs and BerkeleyDB state are excluded.
Local console fixtures are replaced by their pinned upstream script.

The first deployment imports the current SQL schema without local rows. Only
the galaxy identity and schema version 1008 are seeded. Core3 builds a new
BerkeleyDB world. The runtime overlays enable Tatooine only, disable space,
restrict resource generation to Tatooine, skip historical resource seed data
and omit the unimplemented JTL fixed resource pool. Shared definitions and
archives remain available because they are dependencies, not other-planet
database records.

## Administration

Run on the VPS as administrator, after staging the files and loading the image:

```sh
python3 /home/blux/swgxr/tools/deploy/runtime.py bootstrap --confirm-fresh-remote
python3 /home/blux/swgxr/tools/deploy/runtime.py install-units
systemctl enable --now swgxr.target
systemctl status swgxr-container swgxr-db swgxr-core3 swgxr-adapter swgxr-gateway
```

Bootstrap generates a private database password and configuration overlays. It
refuses unmarked existing database state; never delete these safeguards to
force a redeployment. Core3's graceful console exit saves state before the
database and container stop. Use `systemctl stop swgxr.target` for an orderly
stack shutdown. Keep the runtime directory and TLS credentials private.

For a native update, finish local validation, stop the stack, back up SQL and
BerkeleyDB while stopped, replace the runtime code/binaries, then start the
stack. Preserve `runtime/remote`, `runtime/server/adapter.secret` and private
client profiles, plus `runtime/auth` credential state. Changing the adapter
secret changes native account passwords. Gateway-only updates can restart
`swgxr-gateway`; adapter updates restart the adapter followed by the gateway.
The target uses Wants so leaf maintenance does not cascade into Core3 shutdown.
Always verify the individual services and native process afterwards.

## Verification

`tools/client/remote_two_client_smoke.py` uses two dedicated accounts. It checks
native character creation/selection/entry, simultaneous live sessions,
mutual player presence and fresh-login persistence, then closes its sessions.
It leaves Core3 running. The Godot `remote_connection_probe.gd` checks the
actual Godot HTTPS path; run it with `--headless --xr-mode off`.

These checks validate networking and native state, not rendered VR or MMO load.
Live VR tests remain suspended until requested.

## Verified deployment — 2026-10-04

The realm is online and enabled at boot. All 51 transferred TRE archives
matched their source SHA-256 hashes. The running Core3 executable matches the
locally tested PvE reward build (`4ceb1e3c64a087084573d98b6bbbe1cc6a6559e3f98cd269333a5194b8520a69`).
No local player database was migrated; the two retained characters belong to
the dedicated network-test accounts. The configured `blux` account starts empty.

The first two-client run passed 38 checks. After a full Core3/MariaDB/container
restart, 36 checks passed with character creation forbidden, proving existing
character persistence. Both sessions saw each other's fresh presence and
closed cleanly. Actual Godot HTTPS probes passed before and after restart and
against the installed default profile. Unauthorized requests and cross-account
requests were rejected; adapter and SQL ports were unreachable externally.

The second run took 25.12 seconds: median operation 320 ms, maximum 3.93 s. A
44-second host sample during/after the run showed 42.3 MiB maximum swap usage and
91.2% mean CPU idle. Earlier cold runs used more swap. These measurements cover
two clients only and include native command work; they are not frame timings
or an MMO capacity estimate. Four GiB swap is configured on the 2 GiB host.

Evidence is under `runtime/evidence/remote-client/`: `vps-runtime-audit.json`,
`two-client-before-restart.json`, `two-client-after-restart.json`,
`vps-default-profile.json`, `vps-boundary.json`, and the host performance samples.
Native XP/loot evidence is under `runtime/evidence/pve-rewards-native*.json`.


## Account rollout — 2026-10-04

Password registration/login is deployed on the HTTPS gateway. The default
local profile still presents **Set password** for `blux`; no password was
chosen or account claimed on the user's behalf. Three dedicated disposable
auth test identities were created; their opaque sessions were all revoked.
The protected SQLite credential database is mode0600 in private `runtime/auth`.

Validation passed:74 Python tests;34 mocked Godot account/UI checks;41 existing
Godot TLS checks;31 live HTTPS/native checks;11 live Godot HTTPS auth checks;
30 existing two-client native checks with character recreation forbidden.
A new password account created a real Core3 character and retained access
across logout/login; another account was denied selection of that character.
Existing network-test characters and simultaneous sessions still worked.
No live VR test was launched.

Restarting the adapter initially exposed a dependency cycle: the target's
Requires edges combined with service PartOf caused a full graceful restart.
Core3 saved and stopped successfully, then restarted with its original data.
The target now uses Wants; service-to-service Requires and target PartOf remain.
A subsequent adapter/gateway restart preserved the Core3 supervisor PID and
start timestamp. All six runtime units are active. A target being active alone
is not a readiness assertion; check every service and authenticated health.

Auth UI desktop captures fit both1280×900 and1440×900. The final Vulkan capture
passed its34 assertions and wrote all images but timed out during renderer
shutdown; headless auth tests and the live Godot HTTPS probe exited normally.
This is not live headset validation, and the capture shutdown issue remains.

Evidence: `runtime/evidence/account-auth/`,
`runtime/evidence/remote-client/vps-auth-godot.json`, and
`runtime/evidence/account-ui/`.

## Gameplay RPC update — 2026-10-05

Patch0033 and both native binaries were installed after a clean Core3 shutdown.
The prior binaries/code, SQL dump, BerkeleyDB state and authentication database
were backed up under private `runtime/deploy/pre-gameplay-20261004T231026Z`.
The existing realm was retained; no local player records or configuration
secrets were deployed. All runtime services returned active, and the running
Core3 hash matches the locally tested build:
`4007d59989eeadf6c440edbcca1e8e9bdadd4d3d11b3f33aaf88c2e60c97c2e5`.

`tools/client/service_poll_probe.py` measures the same existing dedicated test
character over verified HTTPS. Three sequential reads per service before/after
the update gave these medians:

| Native read | Before | After |
| --- | ---: | ---: |
| Services | 1588ms | 1201ms |
| Gathering | 1536ms | 1214ms |
| Crafting | 1512ms | 1152ms |
| Inventory | 1630ms | 1299ms |

The first post-restart services read took2329ms. These are small functional
samples, including transport and native authentication, not a controlled load
study or frame timings. The20–24% median reduction does not make one-shot RPCs
suitable for high-frequency MMO interactions; persistent-session routing and
further profiling remain necessary. Local native status reads measured364–419ms.
Admission queues and client deadlines now bound waiting rather than allowing
unlimited polling backlog. Recovery acknowledges the inventory in its committed
transaction instead of making extra logins after moving the tool.

Evidence is under `runtime/evidence/gameplay-20261005/`, including
`remote-poll-before.json`, `remote-poll-after.json`, `vps-applied.json`,
`vps-audit-after.json` and local native regression reports. No live VR test was
launched for this update.

After deployment, the two existing test accounts passed30 checks for native
entry, simultaneous sessions, mutual presence and persistence. Both test
sessions closed successfully; Core3 remained active. The run took20.88seconds
(median operation301ms; maximum3.60seconds across28 mixed requests). A separate
actual Godot HTTPS probe confirmed native readiness and the retained character
list using the configured CA. These mixed-session timings are not comparable
to the dedicated one-shot read table above.

## Persistent gameplay update — 2026-10-05

Patch0034 retains the native connection during normal gameplay. Inventory,
services, gathering, crafting, datapad, weapons and vehicle calls reuse it. The
HTTP adapter releases the completed native transaction lock before encoding and
sending a response, so a slow reader no longer occupies the native lane. Optional
client polls share a budget and yield to explicit interactions; seated vehicle
heartbeats suspend unrelated optional reads.

A graceful Core3 shutdown preceded installation. Private backup:
`runtime/deploy/pre-gameplay-20261005T001715Z`. No local database, credential store
or private configuration replaced the realm's data. All runtime units are active
and enabled through the existing target. The actual running binary hash is
`26f2d3ca36aadee8c4aecbc70ffe0b0a59aad2f2c5db39af8d7625440661453b`.

Three sequential verified-HTTPS reads per service on the same dedicated account:

| Native read | Previous one-shot median | Persistent median |
| --- | ---: | ---: |
| Services | 1201ms | 324ms |
| Gathering | 1214ms | 289ms |
| Crafting | 1152ms | 420ms |
| Inventory | 1299ms | 390ms |

These small functional samples cover request latency, not frame rate or MMO
capacity. The retained connection survived every read and saved/logged off
correctly. Local native tests passed39 checks for source position/cell/heading
persistence, vehicle retention and equipment, seated logout and durable retries,
actual sampling/recovery and concurrent inventory admission. An inventory read
during recovery returned busy in1ms; the native recovery transaction completed
in367ms and subsequent committed inventory arrived in308ms. The client retains
its last confirmed readout while awaiting that transaction.

Evidence: `runtime/evidence/gameplay-core1/` and
`runtime/evidence/session-20261005/`. Headset testing remains suspended.

The final actual Godot HTTPS probe passed11 checks, including production native
HAM/posture/sequence validation and a saved logout after mixed RPG reads. The two
existing dedicated test accounts passed30 checks for native entry, retained
characters, simultaneous presence and clean session closure. That mixed regression
took17.64seconds; its293ms median is not directly comparable to the per-service
table. The final Python suite passed139 tests. Core3 remains running.

## Multiplayer persistence update — 2026-10-05

Patches0035–0036 expand native session capacity and expose the original nearby
world. The adapter defaults to 10 simultaneous native sessions (configurable
1–16); admission never evicts an existing player. The deployed Core3 binary is
`a089d90d3b9c6031360d5dda154442d31493d3da4dc6b4757699068a2d54b3d1`;
the matching native client is
`abbaee0ef858f889f9ea195d4595ea0b09d74c26410d7717a2eebc044d33e4a6`.
The pre-update SQL/Berkeley DB/auth backup is
`runtime/deploy/pre-gameplay-20261005T005059Z`. The existing realm was retained;
only eight dedicated network-test aliases were added alongside the two existing
test accounts. No user account or authentication database was replaced.

The realm is already persistent. Retain `runtime/remote/mysql`, `databases`,
`db-password`, `config-local.lua`, `resource_manager.lua`, `bootstrap.json`, and
`schema-ready`, plus authentication SQLite/WAL files and private keys. Use the
remote systemd/runtime workflow; the legacy local bootstrap is inappropriate for
this realm. Graceful shutdown sends Core3 `exit` and waits for saves. The default
periodic object flush is five minutes, so persistence is not a zero-loss crash
guarantee. Native sessions are ephemeral, with a 60s inactivity timeout; clients
must continue native heartbeats as well as presentation traffic.

A 90s two-player normal-gameplay soak passed 124 checks with successful saved
logouts. A separate 10s two-player visibility/tracking test passed 60 checks at
9.30 actual pose replies/s per player. The ten-player diagnostic observed all
nine peers from every client at 7.94–8.37 pose replies/s, but then failed native
freshness and admission checks. That diagnostic was not a successful ten-player soak; see the subsequent
lock correction and final validation below. The first failed visibility run also exposed a harness loading
flag error, which was corrected and covered by a regression test.

Evidence: `runtime/evidence/persistence-ready/`. These are verified-HTTPS native
protocol simulations, not FPS or headset measurements. The post-update audit
confirmed all services active, the target enabled, Tatooine-only simulation,
the original schema, and a private container network. Live XR remains suspended.

## Mission parcels and native concurrency — 2026-10-05

Patches0037–0038 add original delivery/crafting handoffs and replace the live
native bridge's ordinary mutex with Engine cross-locking. Queue commands enter
with the player locked; a waiting command must release that lock while another
player's world snapshot needs it. The adapter enables concurrent session updates
only after the owned native start reply advertises `engine_cross_lock_v1`. Older
binaries retain global serialization. Each account still has one bounded IPC
request lane; RPG mutations retain their global admission gate.

An initial ten-client parallel experiment on the older native binary exposed
this lock inversion and hung the server. Its 210s graceful shutdown timed out.
The identified process was frozen, Berkeley DB files and a SQL dump were backed
up in `runtime/deploy/pre-native-crosslock-recovery-20261005T0130Z`, and only then
was the hung process terminated. No realm databases were replaced. All ten
dedicated test characters were subsequently restored to their exact saved
positions through native logout; recovery evidence is
`persistence-ready/concurrent-recovery-restores.json`. This recovery is not a
zero-loss crash guarantee.

The fixed native bridge passed 123 local concurrency checks with 40 simultaneous
owned updates, original peer snapshots and fresh position readback after cleanup.
The combined original delivery/crafting suite passed 114 checks, including native
parcel persistence, exact rewards, stable receipt retries, actual timed crafting,
cancellation during escrow/production and isolation from another mission.

The final deployment used a successful graceful save/stop and created another
SQL/Berkeley DB/auth backup, `runtime/deploy/pre-gameplay-20261005T014152Z`.
Only source and native binaries changed; realm/private configuration was retained.
Final Core3 SHA256: `ec3e6e282c6d35456a48fa670cadac4147efd93489d994b037600ba5d43cb97b`.
Native client remains `abbaee0ef858f889f9ea195d4595ea0b09d74c26410d7717a2eebc044d33e4a6`.

Final verified-HTTPS run `persistence-ready/ten-concurrent-capability-final.json`
passed 872 checks with ten original characters, all nine peers visible to every
client and a 91.01s concurrent soak. It completed 8,015 pose replies at
8.611–8.940 actual replies/s per client against the requested 10Hz. All 300 native
heartbeats succeeded. Seven optional inventory reads were deferred with explicit
503 busy admission; there were no native heartbeat or presentation errors.
Median native refresh gaps were 2.955–2.981s; the maximum 8.742s includes the
initial readiness wave; during the soak the largest heartbeat response gap was
4.258s. All ten saved logout positions were verified by fresh
entry afterward. The complete setup/soak/readback run took 221.599s.

This validates a short ten-player stationary protocol pilot with light RPG reads.
It does not establish ten-player combat/vehicle throughput or live headset frame
rate. The first unique avatar appearance still has a measured main-thread build
hitch; repeated appearances use the cache. Public world/deployment limits remain
documented in SESSION_PROTOCOL.md. The final audit confirms enabled services,
Tatooine-only simulation, retained accounts/characters/schema and the exact
0038 binary. Core3, adapter, gateway and voice are left running.

The final actual Godot HTTPS client probe passed 11 checks against the deployed
server, including production session state reconciliation and saved logout.
Final regressions passed 172 server tests and 45 deployment/client-tool tests;
Godot editor import completed with XR disabled.

## core2 recording corrections — 2026-10-05

Additive native patch0039 filters empty mission slots after original terminal
refresh, connects artisan surveys to original objective completion and permits
owned resource-waypoint deletion. Native vehicle descriptors support configured
or repository-relative paths and recover from an initially absent catalog.
The VPS package previously omitted `runtime/assets/vehicles/catalog.json`,
causing the recorded X31 call failure. The catalog is now included in packaging
and required by startup and read-only audit, with all six supported source
vehicle descriptors checked. Client geometry/textures are not needed by Core3.

A successful graceful shutdown preceded the update. The original persistent
realm and private configuration were retained; SQL/Berkeley DB/auth backup is
`runtime/deploy/pre-core2-20261005T025239Z`. Core3 binary SHA256 is
`b9c762ae84d67e5beea13ac7dd8012efadbc6c4b3c278878b98f396e083b40c7`.
Local native validation passed 61 mission/survey/waypoint checks and six actual
owned vehicle call/store checks, with test locations restored. All supervised
services and the new vehicle catalog passed the deployed runtime audit.
Client fixes cover original vegetation alpha tests, offhand tool pickup,
inventory visibility with held survey tools, stable fingertip clicking, source
coordinate conversion and bounded exterior doorway repairs. Evidence:
`runtime/evidence/core2/`. Live XR testing remains suspended.

Deployed HTTPS checks passed 14 terminal/persistence checks and 14 exact X31
vehicle checks. One original starter deed on dedicated `nettest_one` was activated
(no grants or purchases); its original X31 was stored, called through the
previously failing path, checked for two seats/source movement statistics, and
stored again. Fresh logins verified the persistent control device and consumed
deed. The test character's original source position/cell/heading was restored;
no user character was modified. Artisan and Explorer refresh each returned 12
valid original offers in the test.

## Daily graceful restart — 2026-10-05

The deployed `swgxr-daily-restart.timer` is enabled and active, scheduled for
**05:00 UTC every day** (`OnCalendar=*-*-* 05:00:00 UTC`). Its first scheduled
run after installation is **2026-10-06 at 05:00 UTC**. `Persistent=false` avoids
an immediate catch-up restart after installation or boot. Installing the timer
did not restart any game service: Core3, adapter, gateway and voice retained
their existing PIDs and verified HTTPS native readiness passed afterward.

The timer runs `tools/deploy/scheduled_restart.py`. It stops voice, gateway and
adapter, requests the existing native console save-and-exit, and waits for Core3
to finish before restarting Core3 and those dependent services. MariaDB, the
container, persistent realm data and backup retention are left intact. It then
checks all four services and native login/zone readiness. An inactive game target
causes the scheduled operation to skip.

If native save-and-exit fails or times out, the operation stops without killing
Core3 or launching another instance; frontends remain stopped for investigation.
Other restart or readiness failures also fail the oneshot and record the phase
in its journal. Inspect the schedule and structured maintenance log with:

```sh
systemctl list-timers swgxr-daily-restart.timer
journalctl -u swgxr-daily-restart.service --since today --no-pager
```

The installed units passed `systemd-analyze verify`; the UTC calendar and next
elapse were checked on the VPS. Eighteen deployment tests passed, including five
covering the restart sequence and failure boundaries. The scheduled restart
itself has **not** been executed as an immediate test. Evidence:
`runtime/evidence/core2/daily-restart-verification.json` and
`daily-restart-installed.txt`. Installation backups are retained on the VPS at
`runtime/remote/maintenance-backups/20261005T091832Z`.

Current starport native snapshots also show moving helper droids, so the NPC
simulation was running during this check. The sunk-NPC presentation correction
is separate from scheduled maintenance; snapshot evidence is
`runtime/evidence/core2/remote-starport-npcs.json`.

## Datapad recall and portable login deployment — 2026-10-05

Native patch0040 adds vehicle recall from the datapad and original follower-droid
call/recall, including helper R2 units. Droid pickup requires both tracked hands
within the native contact volume. Control-device ownership, reach, combat rules,
pet limits and call/store cooldowns remain Core3 authority. Original droid store
is asynchronous: the client waits for authoritative removal. The helper's
original scene-ready auto-call behavior is retained.

Local native checks passed18 assertions using existing fixture devices, including
vehicle/droid recall, two-hand droid storage, invalid contact/range rejection,
restored original spawned states and fresh-login identity/location readback.
The production datapad/gesture test passed21 checks with mocked tracking,
including pause, menu, tracking-loss, life and stale-state release/regrip guards.
These are not live headset tests.

A successful graceful save/exit preceded deployment. SQL, Berkeley DB and auth
state were backed up to `runtime/deploy/pre-recall-login-20261005T100243Z`.
Only runtime source and the native executable were replaced; existing realm data,
private configuration and the daily05:00UTC timer were retained. Native SHA256:
`13a61f715c003cfdeaec3c1598e88b0ee63ce64152b7c596a40ad54cfa637437`.
The same deployment includes the tested account-auth/gateway portable-login
routes; authentication schema changes are additive and do not reset accounts.
Deployment evidence: `runtime/evidence/core2/recall-login-deployment.json`.

After deployment all four game services and verified HTTPS native readiness
passed. The daily restart timer remains enabled, next2026-10-06 at05:00UTC.
The dedicated remote fixture passed19 native checks: actual X31 call/recall,
helper R2 call/recall and two-hand storage, original device/spawn-state restoration,
recruitment-center cell snapshots, saved logout and exact fresh-login source
position/cell/heading readback. No grants or user-account mutations were used.
Evidence: `runtime/evidence/core2/remote-recall-login-proof.json`.

The actual Godot pinned-HTTPS portable-login probe passed20 checks using a new
auth-only test identity with no character: saved token reload/resume, revocation
followed by401 rejection, session logout and temporary-file cleanup. Evidence:
`runtime/evidence/yoke-recall-login/portable-login-live.json`. Core3, adapter,
gateway and voice remain running; no live VR test was launched.


## Ten-planet preparation — local validation, remote unchanged

**User deployment hold (2026-10-05):** the live test server remains Tatooine-only
until the player test server is ready. Restored planets stay in local development.
Do not include planet restoration or expanded travel in unrelated live-server
updates. Capacity upgrades alone do not lift this hold; wait for the user's
instruction to expand the player test server.

The client and native patch0041 support all ten original ground planets. Local
Core3 startup took12seconds with all zones; its RSS measured4,337,156KiB
(4.14GiB) with no swap. This exceeds the current VPS's2GiB physical RAM before
MariaDB, adapter, gateway, voice and OS overhead. The remote realm therefore
retains its existing Tatooine configuration and persistent data. Merely adding
swap does not establish acceptable multiplayer response latency. An8GiB host is
a starting capacity target for subsequent measurement, not a16-player guarantee.

`tools/deploy/prepare_planet_profile.py runtime/deploy/<new-directory> --planets all`
stages private configuration/resource overlays from the existing remote profile.
It preserves the DB credential, excludes space zones, and does not touch running
services or realm data. Apply through the established graceful save/backup/restart
procedure only after the user lifts the deployment hold and capacity is available;
check all native routes and retained
character state before exposing expanded travel. Do not rerun fresh bootstrap or
replace realm databases.

Local original-ticket Tatooine→Naboo→Tatooine tests passed30 checks, including
saved destination logout/reentry, retained owned sessions, original return-ticket
consumption, rejected stale-zone movement and actual Naboo resource surveying.
Forty-one RPCs measured median0.350s and p951.272s, including temporary login and
character entry; this is functional evidence, not a load benchmark. Evidence:
`runtime/evidence/planets-native-roundtrip.json` and
`runtime/evidence/planets-native-capacity.json`. Client mock/replay and original
geometry tests plus desktop Vulkan captures do not validate live XR.
