# CoreCU remote test realm

## Movement, player summary and party update — 8 October 2026

Source release `9c709fd` was pushed to `origin/main`. Its server delta was
installed through SSH on `blux@87.106.27.237` after native save-and-exit,
SQL export and private persistent-state/runtime backups. The verified bundle
contains 21 files, with 20 changed on the server. It adds the native movement
budget, owned player summaries and authenticated fist-bump parties, including
Squad Leader priority and receipt-only retries after a consumed gesture.

The running CoreCU binary matches SHA-256
`abb54caf2ba4ee1bc90183a1a05442d9f41b1d30354afb6f259f42692410d4f7`.
All managed services and native readiness passed the post-update audit. The
50 native accounts, 47 characters, schema 1008, private configuration and ten
original ground planets were preserved. The daily restart remains enabled at
05:00 UTC; the verified next run is 2026-10-09 05:00 UTC.

Release validation passed 397 Python tests, a clean headless Godot import,
47 local native party checks and 154 focused client checks. Seven authenticated
HTTPS checks on the deployed server used an existing dedicated test character
to verify entry, owned player summaries, movement revisions, a stationary
heartbeat, native party state and saved logout. No character was created or
granted skills during deployment verification. No VR client was launched;
client gesture checks use mocked tracking and the dummy renderer.

Remote rollback state: `runtime/deploy/pre-galaxy-update-20261008T051402Z`.
Local receipts: `runtime/deploy/galaxy-update-live/{release-proof,applied,audit-after,tls-health-after}.json`.
The old test environment was not accessed or restarted.

## Core5 interaction update — 8 October 2026

The verified 14-file delta was installed over SSH on `blux@87.106.27.237` after
native save-and-exit, SQL export and a private persistent-state/runtime backup.
It updates both native executables and the native client, slicing-knife template,
crafting metadata, creature inspection and failed-service movement corrections.
The knife now retains native equipment validation with the original permitted
player race/gender templates; adding a slot alone was insufficient.

The linked build passed 30 native Core5 integration checks and 19 native movement
checks. The release also passed 37 focused Python checks and nine actual loopback
HTTP client-correction checks. Fixture grants were confined to the local test
realm; its helper and spawned creature were removed and its session saved.

The post-deployment audit verifies the running binary hash, all managed services,
native readiness and authenticated TLS health. All 50 accounts and 47 characters
remain, with schema 1008, unchanged private configuration and ten original ground
planets. Space stays disabled. The daily restart remains enabled at 05:00 UTC.
The old test host was not touched, and no VR client was launched.

Remote rollback state: `runtime/deploy/pre-core5-20261008T025543Z`.
Local receipts: `runtime/deploy/core5-live/{release-proof,applied,audit-after}.json`.
Native validation: `runtime/evidence/core5-release/`.

## Live migration — 7 October 2026

The authorized target is now `blux@87.106.27.237`. The previous
`45.147.228.101` environment completed a native save and is offline, with its
game services and automatic restart timers disabled. Its rollback state is
`runtime/deploy/migration-old-20261007T141928Z` on the old host. Verified local
SQL and private-state copies remain under `runtime/deploy/galaxy-migration/`.

The new server runs the fresh CoreCU build with all ten original ground planets
and no space zones. The pre-fixture migration audit preserved 18 native accounts,
15 native characters and seven gateway credential records. Dedicated load-test
accounts are recorded separately and do not replace that preservation evidence.
The new TLS certificate covers `87.106.27.237` under the existing trusted CA;
the local client profile and Zevrion's remembered login now use the new origin.

The daily graceful restart is enabled at **05:00 UTC**, with one-second
accuracy, no randomized delay and no missed-run catch-up. It saves the native
world before restarting the game services, retaining the database and container.
The next run verified during deployment was 2026-10-08 05:00 UTC.

Deployment corrected the readiness check to recognize the CoreCU initialization
message and added idempotent graceful cleanup after a failed systemd startup.
The final runtime archive, installed supervisor and package manifest agree.
Receipts are `runtime/deploy/corecu-new-host/{applied,audit-after,release-proof}.json`.
The exact linked build passed 19 native movement checks and 40 entry/readiness/
save/re-entry checks across the ten original ground planets. Capacity and voice
results are recorded separately rather than inferred from startup or policy tests.

Passive SSH monitoring collects managed journals, native console output and
five-second CPU/memory/swap samples in
`runtime/evidence/galaxy-live-session/server-debug.jsonl`. The VR launch enables
the independent mono spectator, continuous client telemetry and a bounded
script/baseline performance profile in the same evidence directory. These are
observers; no debugger breakpoint or tracking override is installed.

The remote capacity exercise admitted and saved/closed 31 of 32 requested fixture
sessions, but failed before its measured phase. A two-client diagnostic completed
without request errors at approximately 1.2 native updates/second and 6 presentation
updates/second, below the requested 2/10 targets. Thus 32-player capacity remains
unvalidated. The ramp/cleanup sample showed peak native RSS of 3.70 GiB and no
swap use. Verified TLS voice passed all 37 checks using synthetic Opus frames;
this does not test headset microphone capture or audible output. The consolidated
receipt is `runtime/evidence/corecu-new-host-capacity-validation.json`.

The first live VR connection captured Zevrion moving in Bestine and a spectator
image. WiVRn subsequently restarted, invalidating that OpenXR instance; its logs
and profile are preserved under `runtime/evidence/galaxy-live-session/attempt1/`.
Monitoring also identified a stale-combat queue that could prevent the heartbeat
needed to refresh authority. The client now discards expired gestures and lets
that heartbeat run, with regression checks for both frame-processing orders.
The VR client remains closed at the user’s request; prompt before the next live
test launch.

## All-planets package — 12 vCPU / 24 GB target

User direction on 2026-10-07 supersedes the earlier Tatooine-only preparation
for this package. The reviewed profile is `corecu-all-planets-12cpu-24gb`:
Tatooine, Naboo, Corellia, Rori, Talus, Dantooine, Dathomir, Endor, Lok and
Yavin IV. Kashyyyk, Mustafar and space are not implemented by the pinned original
ground-world stack and are not enabled. Nothing in this preparation changes the
currently running VPS.

The profile targets 32 real players without a connected-client ceiling. It uses
six zone workers, two navmesh jobs, a 1 GiB InnoDB buffer pool, 64 database
connections, 128 concurrent gateway requests and a 2048-process container budget.
The host check requires 12 vCPUs and at least 22 GiB actual RAM, accommodating
advertised 24 GB machines. These are initial budgets, not a capacity guarantee.
Synthetic clients may exceed 32; the harness now preserves each fixture's saved
ground planet and reports the planets exercised. Run both a crowded single-zone
case and a case spread across all ten planets.

Public inbound firewall rules are **TCP 18443** (authenticated HTTPS login and
gameplay), **TCP 18444** (TLS WebSocket voice), and the configured SSH port
(normally **TCP 22**, preferably restricted to administrator addresses). No
public UDP rule is required by this custom-client deployment. Keep adapter
18080, MariaDB 3306 and native Core3 ports private. Additional planets need no
additional ports. Apply equivalent rules to a provider firewall if one is used.

Public settings are staged in
`runtime/deploy/corecu-all-planets-12cpu-24gb-profile/`. For an existing realm,
stage private overlays with its own generated DB credential:

```sh
python3 tools/deploy/prepare_capacity_profile.py runtime/deploy/all-planets-private --profile corecu-all-planets-12cpu-24gb --source runtime/remote
```

Stop the old stack and confirm saved shutdown before installing a new profile.
Back up SQL, BerkeleyDB, authentication, secrets and configuration. Replace only
the stopped managed container when increasing its PID budget; retain mounted
data. Apply the staged configuration/resource overlays and capacity files,
install updated units, then start and audit. Do not bootstrap over an existing
realm. Fresh bootstrap can read the packaged capacity profile and generate
private all-planets overlays itself; it still requires the approved empty schema
and the separately supplied original TRE media.

### Build and package status

The earlier restricted preparation environment could not operate Podman or bind
sockets, so its source preparation bundle remains marked **NOT DEPLOYABLE**.
That historical artifact contains pinned Core3/Engine3 Git bundles,
current patches, build/deployment tools, public capacity settings and required
adapter catalogs, and excludes account/database state, private credentials and
TRE archives. It is not a client asset distribution.

The subsequent authorized migration built the current `corecu` executable in
the working local Podman environment. The linked receipt is
`runtime/server/native-build.json`; the separate installable package is
`runtime/deploy/corecu-all-planets-runtime/`, with `deployable: true` and
`linked_build_verified: true` in its package status. The source-only archive is
not relabelled or installed as a binary release. The fresh build passed 368
Python tests and 19 native movement integration checks before deployment.

On a separate build workspace with Podman available, restore the bundled sources
before supplying original TRE archives under `runtime/assets/active_tre`:

```sh
git clone source/Core3.bundle vendor/Core3
git clone source/engine3.bundle vendor/Core3/MMOCoreORB/utils/engine3
python3 tools/configure_core3.py --planets all
SWGXR_BUILD_JOBS=6 tools/server/provision.sh
```

The source bundles contain the recorded pinned HEADs. `provision.sh` checks the
Core3 revision, installs build dependencies into an isolated development
container and invokes `build.sh`. This is a build-host procedure, not the VPS
database bootstrap. Complete native integration tests before producing the
installable runtime package:

```sh
python3 tools/deploy/package_runtime.py runtime/deploy/corecu-all-planets-runtime --profile corecu-all-planets-12cpu-24gb
```

Normal packaging refuses missing or stale linked binaries. For an explicitly
unfinished handoff, `--prepare-only` produces the source bundle described above;
that switch never marks the output deployable. Both package modes record file
hashes under `runtime/remote/runtime-sha256.json`. Transfer the verified original
media and the pinned runtime container image separately.

### Validation coverage and remaining release gates

`tools/deploy/validate_release_assets.py` audits all ten world manifests and
geometry, every planet environment/audio and authored interior, all referenced
converted entity catalogs, player animations, inventory, corpses, datapad,
combat and pet assets. Source omissions remain separately recorded. This checks
the source dependency union rather than claiming every dynamic Lua spawn or
encounter has executed. Fresh evidence is under
`runtime/evidence/all-planets-release/`, `release-repaired-assets/`,
`release-entity-coverage.json`, `release-native/` and `release-godot/`.

The validation work repairs stale material-refresh model hashes and updates the
environment smoke fixture to pass the terrain manifest required by regional
environment selection. Missing original wearables/client-data references and
unsupported particle/static appearance types remain explicit limitations;
neither a passing structural check nor a historical native run removes them.

Before installation, complete a linked build plus native startup, login,
save/restart, interplanetary travel, indoors/outdoors, vehicles/droids/pets,
combat/status/shields/traps, crafting/economy and TLS/voice tests on that exact
build. Run the 32-player load test on the target host and capture memory, swap,
CPU and latency. Offline Python, C++ syntax/policy and headless Godot checks do
not establish those runtime outcomes. No live headset or GPU validation is
claimed.

## CoreCU capacity preparation — not deployed

Prepared on 2026-10-07 for a **32-player sizing target**, with no fixed connected
population limit so synthetic clients can exceed that target. Patch0074 removes
the native 16-session ceiling; adapter, presentation and voice registries no
longer impose their previous fixed population ceilings. Native and voice
admission default to unlimited (`SWGXR_MAX_NATIVE_SESSIONS=0` and
`SWGXR_MAX_VOICE_CLIENTS=0`). Positive values remain available as explicit
operator limits; this test profile requires zero for both.

Per-request budgets remain: each snapshot exposes at most 32 nearby players
and 96 actors, gateway requests default to 128 concurrent operations, and
existing authentication, rate, queue and idle-expiry policies still apply.
`LoginAllowedConnections=64` and `ZoneAllowedConnections=64` size Engine3's
initial hash tables; they are not admission limits. Hardware/process/descriptor
budgets can still constrain a stress run. Native session work still shares its
native mutex, so Python request concurrency alone does not prove throughput.

The staged public profile is
`runtime/deploy/corecu-tatooine-32-preparation/`. It selects four zone workers,
one navmesh worker, a 2048-process container budget, a 512 MiB InnoDB buffer pool
and 64 database connections. Its host check requires at least eight vCPUs and
14 GiB actual RAM, allowing typical advertised 16 GB machines; swap does not
count. Tatooine alone and no space are enforced. The existing 2 GiB live host
does not meet this profile. No new host, runtime bundle or deployment has been
created by this preparation.

To install later on a suitably sized host:

1. Complete `tools/server/build.sh` successfully, then package with
   `tools/deploy/package_runtime.py`. Packaging verifies source and binary
   hashes against `runtime/server/native-build.json`, rejecting stale binaries.
2. Stage private overlays on the VPS in a new directory, preserving its existing
   generated database password:

   ```sh
   python3 tools/deploy/prepare_capacity_profile.py runtime/deploy/corecu-32-private --source runtime/remote
   ```

3. Gracefully stop the old stack **before activating capacity.json**, confirm
   native save-and-exit, and back up SQL, BerkeleyDB, authentication, secrets,
   private configuration and the previous runtime as described below. Remove
   only the stopped managed container to replace its old PID budget; preserve
   all mounted data. Do not run fresh bootstrap against an existing realm.
4. Install the verified runtime bundle and copy the staged `capacity.json`,
   `capacity.env`, `config-local.lua` and `resource_manager.lua` to the private
   `runtime/remote/` directory. Preserve private ownership/modes and credentials.
   Install updated units, start the stack and run `tools/deploy/audit.py` plus
   authenticated native readiness and persistence checks. Audit checks the
   host, profile, Tatooine scope and container PID budget.
5. Run population testing before treating 32-player capacity as verified. For
   rollback, gracefully stop and restore the previous runtime/configuration and
   matching stopped container settings; preserve the persistent databases.

The synthetic harness uses existing dedicated accounts and characters. Keep
fixtures private under ignored `runtime/`, with this structure (one unique
account and native character per client; token needed only for HTTPS):

```json
{"purpose":"corecu_population_test","players":[{"account":"loadtest001","character_id":"12345","token":"PRIVATE_ACCOUNT_BEARER"}]}
```

```sh
python3 tools/server/population_smoke.py --fixtures runtime/server/population-fixtures.json --clients 32 --seconds 120 --report runtime/evidence/population-32.json
```

For remote testing add the verified HTTPS gateway URL and CA with `--url` and
`--ca`. Counts above 32, such as `--clients 64`, are accepted when sufficient
fixtures exist. Each client sends stationary native updates at 2 Hz and separate
presentation updates at 10 Hz. Earlier logins are refreshed during ramp-up; the
measured phase starts after all fixtures connect. Results include latency,
update counts, visible peers and saved logout. Passing requires at least 90% of
requested aggregate rates, no request errors and successful cleanup. No accounts
are created, no skills granted, and no attacks issued. Position fixtures in a
shared area beforehand to exercise crowd visibility. This is a stationary
session/presentation test: clustered combat, economy, voice and save/restart
tests remain necessary, with CPU/RAM/swap monitoring, before capacity approval.

Offline validation covers uncapped admission above former limits, owned-request
concurrency, profile/data preservation and native syntax. Linked build, live
load, container migration and deployment remain unverified: this environment
cannot operate Podman or bind test sockets. No VR test was run.

## Last verified live deployment

Latest server update (2026-10-07): Smuggler abilities, faction delegation,
ground Underworld missions, slicing and all 15 spice effects are deployed.
The running Core3 SHA-256 is
`28beac80f8fe218ec5a6c1ef8b02f62cce54c988011a0baaebcb281f7c560804`.
Graceful shutdown preceded SQL, BerkeleyDB, authentication and previous-runtime
backup at `runtime/deploy/pre-smuggler-20261007T032546Z` on the VPS. All services
are active; account/character counts, private configuration, Tatooine-only scope
and the 05:00 UTC restart timer are preserved. Authenticated HTTPS verified native
readiness, slicing/Underworld state, spice/Feign state, the private outline
channel, current weapon profiles, inventory, a persistent native session and
saved logout on the existing dedicated test character. No VR test was run.
Evidence: `runtime/deploy/smuggler-live/` and
`runtime/evidence/smuggler-live-https.json` locally.

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

## Smuggler, slicing and spices — 2026-10-07

The 45-file delta bundle was checked before and after transfer; 44 files changed
on the VPS. It installs the locally validated native build, adapter/gateway
support, native Underworld screenplay and supporting source patches0059–0067.
The unchanged native client was included for hash verification. Existing planet,
resource, credential and administrator configuration files were excluded.
The Underworld screenplay respects enabled zones, so only its Tatooine broker
is enabled on this test realm.

Core3 completed its native save-and-exit before consistent SQL, stopped BerkeleyDB,
authentication and previous-runtime backups were taken. No realm database was
replaced. The post-update audit verified all seven runtime units active, the
running executable hash, unchanged account/character counts, original schema,
private container networking and Tatooine-only simulation/resource generation.
The daily restart timer remains active and enabled for05:00UTC.

The verified-HTTPS smoke used the existing dedicated `nettest_one` character,
without grants, purchases or new characters. It confirmed native readiness,
Smuggler Feign/spice state, slicing and ground-PvE Underworld state, private
outline data, weapon profiles, owned inventory and session continuity, then
saved and closed the session. Its first run exposed a probe-only assumption
about the weapon response envelope; the corrected probe passed against the
existing authenticated-attributes schema. The complete spice effects were
validated locally as recorded in `docs/SMUGGLER.md`; these deployment checks
verify the installed runtime and live protocol, not live headset gameplay.

## Test character update — 2026-10-07

User-authorized native provisioning added all18 Smuggler boxes through Master
to `blux`'s existing test character **Zevrion** (`281474993622560`). Its previous
skills were preserved; all28 supported master professions are present. The
character now resides at the original Bestine Starport arrival point on
Tatooine (source x−1361.1917, y−3600.0254, height12; exterior).

Nine native checks passed, including exact identity, preserved skills, all28
masters, movement, saved logout and independent-login persistence of skills and
location. Temporary console helpers were removed and the original script hash
restored. The test session was saved and closed; game services remain active.
Evidence: `runtime/deploy/smuggler-character/result.json`.


## Test inventory and instrument update — 2026-10-07

Zevrion received one slicing laser knife with 10 charges (object
`281474993832482`) and one locked sliceable loot container
(`281474993832483`). Both objects were verified after saving and independently
logging back in. Existing skills and the current saved position were preserved;
temporary administrative screenplay changes were restored. The nine-check
receipt is `runtime/deploy/instrument-live/result.json`.

Carried instruments now require the native weapon slot before music performance.
The inventory exposes equipped items and a Return to inventory action; grabbing
an equipped item waits for native unequip confirmation. Nearby static instruments
remain at their world location. Client checks cover offhand rejection, failed
unequip recovery, and same-cell/range restrictions on static selection. These
headless checks do not establish headset interaction quality; the next live test
requires the user’s go-ahead.


The exact instrument build passed 23 actual native checks and 11 Python checks.
Coverage includes no implicit equip, exact item recovery, immediate music stop
on unequip or displacement, native range restrictions, and original audio
projection for placed nalargons after inventory refresh. Test fixtures and
script helpers were cleaned up. Evidence:
`runtime/evidence/instrument-native.json` and
`runtime/deploy/instrument-live/validation.json`.


The seven-file instrument delta was deployed to `87.106.27.237` after graceful
native shutdown and consistent SQL/persistent-state/runtime backups at
`runtime/deploy/pre-instrument-20261007T152657Z` on the VPS. Six files changed;
the native client executable was included for verification and retained. Post-
update audit confirmed native readiness, unchanged account/character counts and
ten ground planets, unchanged private configuration, and the active/enabled
05:00 UTC restart timer. Receipts:
`runtime/deploy/instrument-live/{applied,audit-after}.json`. No VR client was
launched after the user’s request to prompt first.

## Combat loadouts and launcher gateway — 2026-10-08

Deployed the current prepared native build and gateway to `87.106.27.237`.
The delta contains 35 files, with 34 changed, including native patches through
0086, combat loadout persistence and authenticated client patch distribution.
The package includes current working-tree changes; per-file SHA256 values in
`runtime/deploy/combat-loadouts-live/package-manifest.json` identify its contents.
Native executable SHA256:
`357f983ffb4a8faa42b176430f0d61e79682f94f299dd94ca42a64fabf94da83`.

Core3 saved and stopped before consistent SQL, BerkeleyDB, authentication,
private configuration and runtime backups were taken at
`/home/blux/swgxr/runtime/deploy/pre-combat-loadouts-20261008T174627Z` on the VPS.
The post-deployment audit confirmed active services, native readiness, unchanged
account/character counts and private configuration, all ten original ground
planets and the enabled daily restart at 05:00 UTC. The old VPS remains offline.
Authenticated, certificate-verified HTTPS health also passed. Receipts are in
`runtime/deploy/combat-loadouts-live/{applied,audit-after,tls-health-after}.json`.

Validation before deployment included 111 Python tests, the verified native
build receipt and the previously recorded 400 client checks and 15 native
loadout policy assertions. No production client payload was published and the
VR client remained closed.
