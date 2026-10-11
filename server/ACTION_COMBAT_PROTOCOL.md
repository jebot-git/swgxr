Current ordinary-mob integration: [Mos Eisley package](GROUND_COMBAT_INTEGRATION.md).
The prototype history below describes protocol 1; protocol 2 uses warning acknowledgements and waives uncovered hits instead of native fallback.

# Isolated action combat prototype

This opt-in native encounter is development-only. It requires the Core3 process
environment `SWGXR_ACTION_COMBAT_PROTOTYPE=1`, an existing trusted
`swgxr_livecombat/test_authorized` character, and an owned ready live session.
It never changes ordinary spawn templates, player attack contact rules or the
deployed realm. Native health, guard costs, armor, secondary defenses, threat,
death and rewards remain Core3-owned.

`POST /combat/session/action_combat` takes the ordinary account/character/session
identity and `action_combat: {action: start|status|stop|contact, ...}`. Start creates
three temporary original native creatures near the fixture outdoors on Tatooine.
The first prototype targets its owner; other clients can observe the same attacks.
It is not yet a party encounter or a production anticheat boundary.

Attack events travel as `swgxr.action.event` native attributes, independently of
RPC snapshots, into the 25 ms native motion publisher and `/session/sync`.
Each carries an encounter ID, actor/target/attack IDs, source origin, preparation/final
direction, role, phase, server time and absolute wind-up/active/recovery deadlines.
The adapter fences them by character, zone, cell and native visibility. Events
are bounded and expire; terminal events replace earlier states for each attack.

The client renders source-space warning geometry, evaluates its body against the
same committed footprint throughout the active interval and submits one boolean
contact receipt with coverage timestamps and the final `aim_revision`. No damage amount is accepted. A late
warning cannot authorize a miss. First receipt wins; duplicate, stale and foreign
receipts cannot cause a second outcome. Missing receipts fall back to native body
positions sampled during the active window, never a later settlement position.
The receipt deadline is 650 ms after the active window in this prototype.

Contact/status replies are compact and do not publish a fake full RPG snapshot.
The owned native mutation lane and rate limit remain in force. Client contacts
receive priority over queued ordinary UI requests, without interrupting an
in-flight mutation. This is not a claim of a production low-latency transport.

Disconnect, leaving the encounter, loading, incapacitation/death, stop and the
bounded encounter lifetime cancel outstanding actions and remove fixture mobs.
No animation drives the player's HMD, controllers or physics body. Warning meshes
are diagnostic prototype presentation; full party aggro remains follow-up work.

## Local validation and inspection

Build the pinned native server/client through the normal Core3 build and record
its build receipt. Start the local server with
`SWGXR_ACTION_COMBAT_PROTOTYPE=1 bash tools/server/start-core3.sh`. Wait for a
previous server to exit fully before replacement; the startup guard rejects an
overlapping process. Run an adapter using the updated sources on loopback 18081.
The existing dedicated ranged fixture is required; do not substitute a tester's
account. The driver restores only that fixture's native health and position.

```
python3 tools/server/action_combat_smoke.py --out runtime/action-prototype/native-test.json
python3 tools/server/action_combat_smoke.py --godot --seconds 24 --latency-ms 100 --out runtime/action-prototype/live-godot-100.json
godot --headless --xr-mode off --path client --script res://tests/action_combat_smoke.gd
```

Desktop visual inspection uses the full production stage and a real native
session, with the dedicated character holding position. It requires explicit
launch authorization and does not test a headset:

```
godot --path client --xr-mode off --rendering-method forward_plus --rendering-driver vulkan --display-driver wayland --resolution 1280x720 --script res://tests/action_combat_visual.gd -- --desktop --local --backend=http://127.0.0.1:18081 --account=rangetest1a142 '--enter-character=Varek Solun' --combat-items --combat-view-output=/home/blux/swgxr/runtime/action-prototype/live-view
```

The inspection harness saves an atomic JPEG twice per second and status JSON.
The encounter expires after 180 seconds; closing the client disconnects its
native session. This does not enable the prototype on the deployed realm.

2026-10-11 evidence in ignored `runtime/action-prototype/`:

- 50 Python/native regression tests pass, including 72 physical resolver cases.
  Godot policy tests pass 24 checks; movement regression passes 918 checks.
- Native stationary trial: 22 attacks, 12 accepted reports, five deliberately
  omitted reports resolved by native fallback, 393 health damage and 33 healing.
  Duplicate, foreign and stopped-encounter reports are rejected.
- Godot diagnostic-body trials at 0/50/100/200 ms added round-trip delay each
  accepted 15 reports and avoided seven attacks, with no movement rejection.
  These use native Core3 and the real contact controller, but are dummy-renderer
  trials, not full-stage GPU or headset validation. The 0 ms run preceded the
  retired-event cache fix; its repeated late-warning counter is not latency data.
- At 100 ms added RTT, contact response p50/p95 was 222/433 ms; native bridge
  p50/p95 was 82/92 ms and adapter queue p95 was 214 ms. Native action execution
  itself was about 0.014 ms. At 200 ms added RTT, total p50/p95 was 333/522 ms.
  Thus application queue/bridge overhead remains material even on loopback.
  Injected HTTP delay is not a measurement of geographic network latency.
- A separate C++ policy simulation covers 105,300 deterministic latency/loss
  trials. It is not an MMO population or server throughput benchmark.
- Full-stage desktop Forward+ Vulkan inspection on Intel Arc A770 verified
  original Tatooine geometry, native creature/NPC appearances and visible attack
  warnings. The initial stationary inspection reached 21 native contacts with
  zero fallbacks. No live XR validation was performed.

Remaining prototype limits include owner-only targeting, simple LOS/floor-gated
repositioning rather than crowd navigation, diagnostic warning presentation,
unvalidated sustained multi-encounter load, and unverified worrt contact-frame
timing. Native interruption policy is covered in isolation; full gameplay
knockdown recovery and party threat transitions require additional integration.

## Required original attack animation preservation

User direction following live inspection: mob attack animations must remain
visible for combat readability. Ground warnings supplement the authored skeletal
attack; they do not replace it. The prototype now holds the original first pose
while the lane warns, then plays the full original clip at `delivery_at`. The
NPC pose layer retains ownership through `animation_end_at`, even if native
settlement already published recovery. Cancellation or death releases it early.
The player body, camera and tracking nodes are never controlled by this layer.

`python3 tools/assets/audit_action_animation_timing.py` measures the relevant
original ANS headers and LAT speed scales from supplied TREs. Its ignored JSON
report records individual source hashes, archive origins and frame messages.
Measured playback durations (not server attack cooldowns):

| Original action | Seconds |
| --- | ---: |
| Worrt light/heavy (same frog clip) | 0.50 |
| Worrt special 1/2 (same special clip) | 1.43 |
| Standing pistol single shot | 1.00 |
| Standing pistol three/five-shot variants | 1.20 / 1.80 |
| Thug ordinary one-handed melee candidates | 0.42–1.58 |
| Thug ordinary polearm candidates | 0.80–2.00 |
| Standing heal-other, proposed support presentation | 2.67 |

The ordinary thug weapon pool includes a DL-44, batons, a wooden staff and a
dagger. The isolated ranged fixture now explicitly equips a native DL-44,
renders its original held model, and uses the standing single-shot animation.
The melee ranges above cover basic standing ASH aliases only, excluding combos,
mounted actions and additive-only masks. Runtime blend/crossfade overhead is not
included. The support fixture now uses the standing heal-other clip.

The clip identity and delivery/end timing are distributed with the native attack.
Playback preserves native clip speed and its full recovery tail. Ranged contact
starts at the original `fire1` marker: the front-facing pistol single shot
releases at 0.333 s into its 1.00 s clip. Support healing resolves after its
2.67 s animation. Worrt
`event_attacklight` occurs at frame zero and is an audio cue, not a proven contact
frame: its physical contact phase still requires pose inspection, so its prior
250 ms contact window at delivery remains an explicit prototype approximation.

Preparation is integrated into the ordinary character animation exporter.
Existing local NPC catalogs can be refreshed without re-exporting geometry via
`python3 tools/assets/prepare_action_combat_animations.py`. This refreshed 277
rig-bound clips with source hashes and no conversion failures. Validation after
the change passed 51 Python/native tests, 30 Godot timing checks, and three
original-rig pose tests (first pose held, bones animate during delivery, physics
transform unchanged, locomotion released). An 18-second native Godot trial with
100 ms injected RTT produced five contacts, four avoided attacks, zero fallbacks
and 28 native healing. These rig and AI tests use the dummy renderer.

The separately authorized full-stage desktop Vulkan demo records actual
wall-clock frames and the game's master audio bus to `live-view/frames`,
`video-frames.json` and `combat-audio.wav`. Encode using the recorded frame
intervals rather than assuming a constant capture FPS; the server runs in real
time. The headset remains off.

The corrected recording is `runtime/action-prototype/combat-animation-demo.mp4`
(34.8 s, H.264/AAC). It contains 510 captured frames resampled to a 30 fps output
using recorded wall-clock intervals; it is not a claim of 30 unique captures per
second. Pose telemetry verifies warning holds and delivery playback for all
three roles, including the original DL-44 attachment. Audio is captured from the
game's master bus only. An initial recording exposed the separate
`mos_eisley_easy` worrt catalog missing its clip; that catalog was refreshed and
the entire recording repeated. The original-rig test now uses this exact worrt.

## Preparation tracking assessment (simulation only)

`python3 tools/server/simulate_action_dodging.py` runs 28,800 deterministic
single-mob trials over 0/50/100/200 ms RTT, 200–350 ms reaction time and 0–60 ms
extra one-way jitter. The player accelerates at 10 m/s² toward 3.5 m/s, slows to
0.6 m/s for 550 ms, and obtains a firing opportunity after 150 ms below 1 m/s.
Ranged dodges strafe; melee dodges retreat diagonally out of the broad cone.
The simulator's contact geometry matches native policy in 1,500 randomized
cross-language comparisons. It models opportunities to shoot, not projectile
accuracy, actual native RPG shots, crowd collision or simultaneous attackers.

Recommended initial tuning: rotate at no more than 12°/s during early warning,
also cap lane movement at the target's distance to 2 m/s, and stop correcting
300 ms before delivery. Keep the mob's feet planted during preparation; pursuit
and repositioning happen between attacks. Both the visible lane and posed body
must turn together; the warning mesh cannot remain frozen while hidden aim moves.
The final lock must preserve the same footprint through delivery and contact.
Do not predict or snap toward a player's dodge endpoint.

At 100 ms RTT, the capped recommendation gave these results (200 trials/cell):

| Strategy | Melee hit | Ranged hit | Median firing opportunity, melee/ranged |
| --- | ---: | ---: | --- |
| Slow to shoot after only 350 ms of dodging | 33% | 0% | 1.09 / 1.09 s |
| Clear the warning and wait for final aim lock, then slow | 2.5% | 0% | 1.28 / 1.45 s |

All moving strategies obtained a firing opportunity before recovery ended.
Stationary players were hit in every trial. Without the lateral cap, 12°/s
tracking plus a 300 ms lock hit early-shooting ranged players 9.5% of the time;
removing that final lock raised this to 93.5%. At 200 ms RTT, the recommended
melee dodge-first strategy still took hits in 10% of trials; a live overlap test
should assess a longer melee warning before raising turn speed or cone width.

The native prototype now implements this tuning. Preparation runs on its 50 ms
AI task, publishes changed aim at most 10 Hz and always publishes the final lock.
`lock_at`, `aim_locked` and `aim_revision` accompany the existing attack timeline.
Feet stay planted; source origin never changes during preparation. Steering uses
the current authoritative target position, without velocity prediction, and a
stalled tick can consume at most 100 ms of steering time. Support healing keeps
its selected aim because it has no hostile dodge footprint.

Warning meshes rebuild when the aim revision changes. NPC body/collider facing
uses the same source-space event pose, bypassing travel interpolation during the
held/full attack clip. Animation never drives this pose. Contacts name the locked
revision; native code rejects outdated revisions. A client that receives no lock,
or receives it after delivery, cannot report hit/miss coverage. The existing
native active-window fallback still applies to missing receipts: this remains a
client-primary hybrid prototype, not a strict client-exclusive contact system.
That fallback and the fixed 300 ms lock need real remote latency assessment.
The earlier animation video predates preparation steering.

Private remote combat testing uses a `runtime/remote/combat-test-mode` marker
and service overrides. The public gateway and voice stay stopped while the
SSH-authenticated loopback client connects; no unauthenticated adapter port is
exposed. The daily 05:00 UTC restart restarts native CoreCU and its adapter only
in this mode. Existing realm databases and enabled planet configuration are
preserved. Remove the mode/overrides using the staged rollback procedure before
returning to the public realm.


## Multiplayer data ownership

Client-authoritative contact does not require transmitting animation bones,
warning meshes or a frame-by-frame AI simulation. The server sends nearby clients
attack identity, actor/target IDs, profile/geometry, source origin, preparation
heading revisions, absolute delivery/contact/recovery times, the immutable final
lock and cancellation. This prototype publishes changed preparation headings at
up to 10 Hz; observers consume them without submitting contacts. A production
transport should reliably deliver begin/final-lock/cancellation/results while
allowing intermediate heading revisions to supersede one another.

The affected player's client submits one hit/miss receipt for the attack and
final aim revision, plus coverage times. Ordinary body movement already travels
to the server. Player-fired projectiles retain their existing launch and contact
messages. No damage, armor, health, reward, animation pose or per-frame warning
geometry comes from the contact receipt. CoreCU validates ownership, identity,
revision and timing and resolves native RPG outcomes once. Missing receipts still
use the explicitly documented native fallback in this prototype.

Production multiplayer needs an explicit per-victim/contact-index receipt key
for cleaves/AoE, one agreed contact authority for PvP, and server contact handling
for NPC-versus-NPC actions. The current encounter is owner-only and cannot be
represented as finished party combat. The tracking target is an aiming intent,
not a complete list of players eligible to be struck by a shared footprint.

## Remote preparation-tracking validation, 2026-10-11

The authorized deployment on `87.106.27.237` preserves existing realm state and
planet configuration and runs the opt-in fixture behind an SSH loopback tunnel.
Native binaries and all 254 staged files were hash-verified after installation.
The public gateway/voice remain stopped; the 05:00 UTC timer remains enabled.
The ignored deployment script and rollback are under
`runtime/deploy/action-combat-20261011/` on both development and remote hosts.

Local verification: 25 Python/native/deployment checks, 35 Godot timing checks,
918 NPC motion checks and all three original animation rigs pass. The native
policy suite includes 105,300 latency/loss cases and steering cap, wraparound,
lock immutability, stalled-tick and stale-revision receipt checks. Dummy-renderer
checks are not GPU evidence. Local native testing with 100 ms injected RTT
accepted 11 receipts, avoided six attacks and used two native fallbacks when the
final lock arrived late.

A separate 36-second remote Godot diagnostic-body trial injected no latency:
20 accepted contacts, no rejected receipts, nine avoided attacks, no late warning
or lock, no native fallback and no movement rejection. Real network results:

| Measurement | Median | 95th percentile |
| --- | ---: | ---: |
| Contact request including network | 211 ms | 366 ms |
| Native bridge within contact request | 83 ms | 93 ms |
| Adapter queue within contact request | 0.073 ms | 167 ms |
| Native contact execution | 0.026 ms | 0.035 ms |
| Movement update request | 313 ms | 335 ms |
| Motion/event sync request | 101 ms | 134 ms |

A separate TCP-connect baseline to remote SSH measured 37 ms median across 12
samples, with one 1.09 s outlier. ICMP returned no replies; this does not establish
game packet loss. These are SSH-tunneled application measurements, not public
HTTPS gateway timings or a loaded MMO benchmark. The bridge and serialized
request queues remain substantial contributors beyond geographic latency.

The first full-stage Forward+ Vulkan recording is
`runtime/action-prototype/remote-combat-test-first.mp4`, with original game audio.
Its 827 real captures are resampled to a 30 fps video (59.7 s); the largest capture
gap is 0.968 s. AI uses ordinary locomotion/collision, dodges after a 250 ms
reaction delay and slows to shoot through ordinary client projectile code. Native
results: eight incoming contacts, 15 misses, one fallback, 22 healing; 13 player
launches, three confirmed player contacts and three rejected shot operations.
This records observed failures as well as successes. All three original mobs'
hold/play animation phases appear. Across 754 paired body/warning samples, aim
revisions agree; 26 committed attacks retain their aim, and 19 attacks visibly
steer during preparation. An instrumented repeat preserves individual request
queue/bridge timings alongside the video for reevaluation.

The instrumented full-stage repeat is
`runtime/action-prototype/remote-combat-test.mp4` (59.1 s, 864 captures,
0.209 s largest capture interval, original game audio). Its 19 incoming reports
were accepted, with 15 avoided attacks and no native fallback. Contact request
p50/p95 was 332/529 ms, including client dispatch queueing (170 ms median across
all action RPCs); the native bridge remained about 83 ms. Controller-local
receipt queueing reached 196 ms when attacks overlapped. Adapter queueing in this
serialized full-client run was below 0.12 ms, unlike the parallel diagnostic-body
trial. Native contact execution stayed below 0.031 ms. Thus full-client
serialization and the file/native bridge, rather than native attack calculation,
are the observed large delay sources in this fixture.

The repeat launched 14 ordinary player shots, confirmed two contacts and rejected
one launch as `invalid_launch_pose`. Native launch validation bounds muzzle/body
distance to 3.5 m on foot. The third-person debug camera anchors its weapon away
from the body; this run does not distinguish that effect from stale native body
position. Keep the rejection as evidence rather than weakening the guard. Across
594 paired body/warning samples there were no revision mismatches, and all 20
recorded final locks remained unchanged. The complete reevaluation archive is
`runtime/action-prototype/remote-combat-evidence.zip`, including both recordings,
per-frame attack revisions/player positions, request timing traces, native results,
network baseline and SHA-256 hashes. The connected desktop client returns to
manual controls after recording; the bounded encounter expires after 180 seconds.

## Shared ground PvE lanes (2026-10-11)

This prototype applies only to ground mobs attacking consenting test players.
PvP is excluded pending a balancing pass. JtL retains its separate combat system.
No PvP, ship targeting, ship damage or space network contracts are changed here.

An authorized player starts the encounter; other authorized, ready players join
by `encounter_id`. It is limited to eight outdoor Tatooine participants within
45 m of the encounter home. The encounter owner remains the tracking target.
Each attack freezes its eligible victim roster at preparation start; joining
later takes effect on the next attack. Observers receive telegraphs but cannot
submit outcomes. Leaving cancels that player's pending contacts, including if
that player immediately rejoins. Owner departure ends the bounded encounter.

`eligible_victim_ids` and `hit_policy` accompany the shared aim and timeline.
Melee is `cleave`; the diagnostic ranged footprint is explicitly `piercing_lane`.
It is a static shared active interval, not a non-piercing traveling projectile:
frontmost interception/occlusion by another player's body is not implemented.
Support remains native mob-to-mob healing, with no player victim roster.

Clients sample their own feet against the final committed footprint and send the
existing receipt, including final aim revision and coverage interval. There is
no client-supplied victim identity: ownership comes from the authenticated native
session. Each `(encounter, attack, victim)` has an independent once-only ledger.
One player's miss cannot consume another player's hit; missing coverage falls
back separately to native active-window samples. Native eligibility, equipment,
defenses and damage resolution remain authoritative. Bounded status analytics
retain the latest 128 victim results; normal native health replication reports
outcomes to clients. Results do not extend or restart animation playback.

Telegraphs retain their full outline while a translucent interior progressively
fills. Filled area grows linearly from preparation start to `delivery_at` (the
start of full animation playback), then stays full through the attack. Melee
uses square-root radius growth; ranged uses linear lane-length growth. The
ranged authored contact marker follows delivery by 10/30 s; the countdown does
not incorrectly grant that extra time as preparation. Server-clock estimates
and aim revisions drive both shape and fill; no extra network tick is required.
`TRACKING YOU` identifies the aim target; `IN ATTACK PATH` independently identifies
an eligible local player currently inside the footprint; `AIM LOCKED` signals
the final commitment. These cues never move head, hands or body.

`python3 -m tools.server.action_combat_multiplayer --fixtures ... --out ...`
starts three separate headless Godot processes connected to three real native
characters through the remote SSH tunnel. Target, crossing and clear clients
exercise the production receipt controller. This is network/native validation,
not headset or GPU validation. Fixture provisioning is an isolated admin step;
no game account reset or public exposure is required.

### Remote three-client result

Private VPS deployment was verified against staged SHA-256 hashes, with the
public gateway/voice still offline and the 05:00 UTC restart preserved. A 48 s
run used three separate Godot processes and three real native sessions, with no
artificial latency. All 81 normal receipts were accepted; 84 victim settlements
included three native fallbacks after final-lock coverage was lost. Target:
21 hits / 475 native damage / 7 misses. Crossing non-target: 6 hits / 133 native
damage / 22 misses. Clear participant: zero hits or damage / 28 misses.
Exact duplicate receipts from all three clients, unjoined access, a forged
victim identity, stale replay and access after leaving were rejected. No movement
errors or duplicate settlements were observed. This is not a capacity benchmark.

Contact round-trip medians were 200/189/211 ms for target/crossing/clear; p95s were
400/355/333 ms. Native request bridge medians were approximately 83 ms; adapter
queue p95s were 198/178/143 ms. Native receipt handling stayed below 0.1 ms.
These measurements implicate request transport and queueing rather than contact
computation; they do not establish that geographic network RTT exceeds 100 ms.
Evidence: `runtime/action-prototype/multiplayer-evaluation.json` and
`multiplayer-remote/evidence.json`. The progressive-fill preview was separately
rendered in Forward+ Vulkan on Arc A770 (`progressive-telegraphs.png`); neither
that isolated graphic nor the headless remote run validates live XR rendering.
