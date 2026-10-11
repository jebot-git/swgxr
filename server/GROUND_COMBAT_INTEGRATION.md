# Global ground PvE integration package

The staged package enables action combat across the ten original ground planets.
PvP, pets and JtL are excluded. Expansion worlds are not activated. This implements
the requested global transition; remote deployment, capacity and headset acceptance
remain separate from the local native and headless checks below.

## Activation and rollback

Install the code overlay over the current matching server/client checkout or
distribution. Preserve existing realm data, media and configuration. Apply the
separate private animation delta using `tools/client/install_ground_actions.py`
first with `--check`, then without it. It verifies hashes and matching skeletons,
adds animation-library entries and copies the new clips/catalog; it never
replaces body geometry. Do not publish the private original-animation archive.
For new asset preparations run `tools/assets/prepare_ground_actions.py` after
normal population export; original supplied TREs remain required.
The launcher now includes this step. Reviewed profile metadata is pinned in
`tools/assets/ground_action_profiles.json`; each locally generated profile must
match it. Optional prepared NPC sets do not change the negotiated revision.
The release includes metadata and conversion code, never original clips.

In the native CoreCU process environment set `SWGXR_GROUND_ACTIONS=global`.
The native catalogue defaults to `/workspace/runtime/assets/combat_actions/catalog.json`;
set `SWGXR_GROUND_ACTION_CATALOG` for another installation layout. The local
start script passes the activation variable through Podman. Remote systemd
activation must pass it through `podman exec --env` to the native child, as with
the existing prototype override. This package does not change running services.
Disable that variable to roll back selection to ordinary native AI. Restart
only after graceful native shutdown/save; preserve the existing daily restart.

Global selection covers Tatooine, Corellia, Naboo, Rori, Talus, Dantooine,
Dathomir, Endor, Lok and Yavin 4, using ordinary native spawns. The optional
`mos_eisley` mode retains the old 1,500 m home/current-position boundary centered
at source X/Z `(3528, -4804)`. `off` restores ordinary native combat.

## Attack integration

Native AI retains target selection, threat, pursuit, pathfinding, ability selection,
loot, XP, deaths and respawning. Basic and special CombatQueue commands are
intercepted inside CombatManager after their native target/equipment/posture checks.
The complete parsed attack data is retained for delivery, including argument
modifiers, status effects, Force properties and area ranges. Native AI builds its
attack maps from CombatQueue commands; noncombat utility commands and scripted
world effects are outside this interception.

The warning footprint uses native command reach and cone/area dimensions. Lanes
use first contact, cones/circles use cleave, and single-target Force or state-only
effects admit only the selected player. Thrown/splash/heavy area impacts are
centered on the target position and correct slowly before locking; other area
attacks are centered on the attacker. A target-bound warning also shows the
existing aim icon near the selected player's view, even when the attacker is
behind them. Purple distinguishes special preparation, moving toward red as
execution approaches. All shapes progressively fill and respect the terrain.
The icon announces targeting without spelling out the incoming command.

Special animation selection resolves command aliases through original standing
ASH/LAT mappings, preserving authored speed and full clip duration. Native command
speed can lengthen preparation and recovery; each event supplies independent
preparation, lock, delivery, contact, animation-end and recovery times. Melee
contact offsets without authored markers remain provisional. Missing special
aliases explicitly use the family's original basic clip with the special's native
geometry/timing; the event records `animation_fallback`. No hit is silently sent
through ordinary native combat merely because a special animation alias is absent.

At most one committed attack per mob is held through preparation, original clip
playback and recovery. Movement pauses while committed. Threat-target changes
before commitment cancel preparation; after commitment the aim stays fixed.
Death, stun, knockdown, peace/leashing, weapon changes, cell changes and movement
of the planted body cancel the strike. Target departure does not delete mobs or
an entire party encounter. Subsequent native AI selection can choose another
target. The longer of the action timeline and native weapon/command speed gates
release. Damage is not increased to compensate for slower attack frequency.

Profiles are generated from original rig-bound clips and retain source hashes,
archive names and conversion errors. Humanoid weapon classes and supported
creature rigs have separate profiles. Overlong/ambiguous/unavailable mappings are recorded in the conversion audit.
Attackable CLL-8 droids use their original firing clip, omitted from their shared
LAT. The supplied EG-6 and mouse-droid media contain no authored attack clip;
these two families retain their original standing animation with a visible warning,
and `visual_fallback` explicitly identifies that limitation. Noncombat Jabba,
Sy Snootles, Bomarr and shuttle appearances remain outside attack profiles. Melee contact timing remains
provisional until the later pose-inspection suite; authored ranged firing markers
are used where present. Supported ranged lanes select the nearest reported contact
once; these are committed line attacks, not a new ballistic projectile simulator.

Protocol and astromech droids use their authored `attack_light_standing` mapping
for basic unarmed attacks. Their humanoid double-jab alias selects heavy clips
lasting 4.33/5.50 seconds and caused 14 omissions in the first preparation pass.
The light clips retain their full 2.87/2.33-second duration and original speed;
no decoder changes, truncation or duration-limit relaxation are involved.

CombatManager attack costs are committed once at delivery. Command-wrapper
bookkeeping, including native cooldowns and any consumable reservation, still runs
at queue admission. Per-victim native outcomes suppress
repeated costs and automatic secondary area expansion only for that exact NPC.
Native armor, secondary defenses and RPG effects remain in CombatManager. The
scoped override cannot apply to another attacker or a player counterattack.

## Transport and client behavior

Protocol 2 negotiates an exact generated catalogue revision. Unsupported clients
retain ordinary mob combat. The server keeps expiring native-session capabilities;
clients cannot set damage, another player's victim ID or global activation.
Eligible nearby players in the same zone/cell are snapshotted per attack, without
explicit encounter enrollment. Pets/NPC-vs-NPC keep their existing native path.

Preparation/final state is published repeatedly and recoverable in native batch
replies. Monotonic attack state revisions supersede per-client transport cache
sequence numbers. Up to 32 acknowledgements/receipts share one existing owned
native transaction, preserving the account command budget. Client contact batches
receive priority behind an in-flight operation. The native client's action-reply
wait is bounded to 10 ms to limit missed-notification stalls; this is not a claim
that the measured remote latency target has already been met.

Four timestamps estimate server-clock offset while excluding native processing
time. The lowest-delay estimate anchors each new attack; existing countdowns do
not jump when another clock sample arrives. A client acknowledges final aim only
when its world is ready, XR focus is valid and the actor's original animation is
available. It first acknowledges a warning presented at least 100 ms before aim
lock (600 ms before delivery for these profiles). Final aim must be presented
before delivery minus 50 ms. Negotiation advertises `receipt_clock: presentation_v1`;
only then does the client include `presented_at` on warning/lock receipts, using
the synchronized server clock. The native policy allows up to one second for
transport, never beyond settlement, and rejects future, pre-attack, late-visible
or wrong-revision receipts. Older clients retain arrival-time validation; newer
clients omit the field for older servers. A missing/late acknowledgement or missing valid contact coverage waives
that victim's hit and records an outcome; it never produces an unseen fallback
hit. This deliberately replaces the old fixture's native fallback policy.

A contact includes a bounded sample position and coverage interval. Native active
window LOS, current session/zone/cell, proximity, revision and geometry checks
bound accepted hits. Exact duplicate reports are idempotent; contradictory ones
cannot replace an accepted result. This remains client-authoritative contact:
a modified client reporting dishonest misses is not solved by identity checks.
Waived and reported outcomes are exposed in bounded native batch diagnostics.

Telegraph geometry remains a horizontal footprint. Its subdivided vertices sample
the outdoor native heightmap for drawing, without changing range or countdown.
Interior vertices use floor collision in the active cell. The full outline stays
visible while area fills to delivery. Original animation/audio timing remains
separate from native damage confirmation. No player tracking node is animated.

## CL tracking and presentation feedback (2026-10-11)

The server scales preparation steering by `min(3, 0.5 + (max(1, CL)-1)/60)`.
CL 1/31/91/151 therefore permits at most 6/12/24/36 degrees per second and
1/2/4/6 metres per second of lateral target correction. Both limits apply;
the stricter one wins. The 100 ms steering tick cap, warning acknowledgements,
final 500 ms aim lock and native target/aggro selection remain unchanged.
This is initial tuning for group testing, not validated tank/healer balance.

Protocol 2 events additionally expose `enemy_cl`, `tracking_degrees_per_second`,
`tracking_metres_per_second` and `weapon_template`. These are server-derived
presentation/diagnostic fields, not new client authority. The exact catalog revision
requires matching client preparation. The template identifies the strike's captured native weapon; native weapon
changes still cancel the strike. Pistol/rifle/carbine profiles remain ranged.

The client shows the existing SWG target-aim icon for the selected victim (amber
during correction, white after lock) and the animal-attack icon in red for any
eligible player inside the lane. The old overhead warning text is removed.
Native weapon snapshots and strike events replace stale source-placement guns,
including hiding a gun when the native AI changes to unarmed combat. Original
instruments and other decorative attachments are preserved. Unprepared original
weapon art is reported explicitly, without a substitute gun.

## Retreat pressure and disengagement

Before final aim lock, preparation cancels if every engaged living player remains
beyond usable reach plus 1.5 m (melee) or 4 m (ranged) for 200 ms. A 400 ms
reposition delay releases native pathfinding before another attack. An engaged
nearby tank preserves the attack even if another player retreats. After lock,
retreat cannot cancel the committed strike; it must miss through contact geometry.

A native player encounter leashes after three continuous seconds with either the
mob more than 160 m from home or every engaged player beyond
`clamp(weaponRange + 24, 64, 128)` metres. Reentering those bounds resets the timer.
Nearby bystanders do not prolong combat. Mixed NPC/pet engagements preserve native
pursuit behavior. Leashing uses the native peace/return-home machinery, not despawn.
These values are initial test tuning, not a completed group-balance pass.

## Evidence and remaining acceptance

Local evidence is under `runtime/evidence/global-ground-*`. The native smoke uses
ordinary worrt and dark-Jedi templates outside the old Mos Eisley boundary. It
checks global revision negotiation, basic warning, target-bound Force warning,
original special animation selection, Force cone, sustained home leash and
pre-lock out-of-reach cancellation. Administrative placement and selected attack
indices are fixture setup; this does not claim real walking, remote latency,
headset rendering, multiplayer capacity or final damage/effect balance validation.

The headless rig suite covers every prepared family with original basic and, where
available, special clips: first-frame hold, full playback and unchanged actor
transform. Small authored skeletal recoil is retained; larger root travel stays
in place. Policy/protocol tests cover geometry, target identity, cancellation
hysteresis, lock commitment, CL tracking and scoped native resolution.

The later sustained multiplayer suite still needs group threat/healing, crowded
warnings, interiors/slopes, packet loss, ability effects, loot/death/respawn and
original contact-pose review. Matching build receipts and package hashes identify
the staged code. No remote deployment or headset result is implied.

## Recording regression: rec1 / rec2 (2026-10-11)

The captured client diagnostic window contained 128 outcomes: 122 waived for
missing acknowledgement and six delivered (425 damage total). Warning/lock
network arrival was being tested against the presentation deadline. The negotiated
presentation timestamp above preserves the visible dodge window while allowing
the acknowledgement's return journey. It does not increase damage multipliers,
invent client contacts, or prove geographic network latency. New diagnostics
retain bounded request RTT, native/adapter timing and timestamp-capability state.

Native combat captures per-target secondary defense and actual Health/Action/Mind
loss under a thread-local attacker-owned scope. `mutation.combat_results` feeds
short-lived contact-point numbers and Blocked/Dodged/Countered/Deflected/Miss
labels. Warcry emits its actual applied/resisted/ineffective result. Projectile
contacts retain the local impact point; melee uses the nearest body collider
surface, with native position fallback after death removes an actor. Failed
mutations cannot produce damage text. This covers ordinary and special attacks.

A holstered but still equipped pistol disables fist contact/reticles. Actually
unequipping it restores native unarmed attacks and permits learned Warcry.
Humanoid guards/enemies now receive the same bounded authored-floor projection
as citizens; body, contact collider and label move together. This addresses stair
penetration, not a verified fix for every horizontal navmesh/corner crossing.
Active delivery mission serialization again supplies the native pickup/delivery
phase and current waypoint instead of falling back to the terminal offer origin.

Evidence under `runtime/evidence/rec-review/`: six native ordinary smuggler
attacks with 250 ms added send delay all delivered; over 24.66 seconds Health
fell from 3,000 to 2,513 despite regeneration. A separate native unarmed fixture
confirms per-target HAM loss and Warcry results. Native mission navigation checks
verify pickup, parcel acquisition, recipient waypoint and abort cleanup. Client
dummy-renderer checks cover original Bestine slopes, receipt timing, weapon
gating and hit text. These are isolated local tests, not remote or headset proof.

## Delivery stability (2026-10-11)

Patch `0151-ground-combat-delivery-stability.patch` adds negotiated capabilities;
older clients retain their previous payload format. These changes preserve native
RPG damage, defenses, costs and cadence. PvP and JtL are unchanged.

1. `contact_evidence: sample_v1` preserves an actually observed positive contact
   across missing frames. Short sweeps cover at most 75 ms and 1.5 m between two
   valid tracked samples. Gaps or missing tracking cannot prove a miss or invent
   a hit. `contact_at` uses the attack's immutable native-clock anchor.
2. `combat_receipts: replay_v1` caches the native mutation by verb and shot ID,
   bound to its canonical intent and native session (512 entries, 30 seconds).
   A lost-reply query uses `receipt_only`, never re-executes an unknown attack,
   and returns a fresh snapshot with the original mutation. Client recovery has
   three retries and a 25-second limit; an explicit unstarted busy rejection may
   retry the original command. Reconnect/session replacement does not recover
   old results. Ground receipt responses expose rejection reasons and bounded
   retryability; retries retain original presentation/contact timestamps.
3. `receipt_bundle: ground_v1` permits pending ground receipts to ride combat
   requests. Standalone urgent receipts retain FIFO order. Unsent same-session,
   same-room heartbeats coalesce, while room changes and arrival acknowledgements
   remain separate. An in-flight request cannot indefinitely defer a new batch.
   Diagnostics separate client queue, adapter queue/rate wait, bridge round trip
   and native action time; request rate limits remain unchanged.
4. `melee_contact: presented_v1` makes ordinary melee select the rendered native
   actor collider, with world-wall occlusion. The request includes the exact
   native observation timestamp, presented target and contact positions. Native
   session history bounds age, origin, reach, direction, displacement and room;
   a later server target position no longer retargets or discards that contact.
   An explicit whiff cannot select another server target. Ability and volley
   targeting remain their existing explicit native paths. Movement history is
   bounded to 64 observations / 2.5 seconds, with two-second proof age limits.
5. After the preceding native checks passed, cleave/targeted victims gained
   independent once-only settlement. Single-interceptor lanes wait for all
   eligible reports or the existing deadline, select smallest distance along
   the locked lane, and break ties by contact time then actor ID. They do not
   select by network arrival order. Positive timestamped contacts require a
   native LOS observation within 120 ms and floor-height agreement within 1.25 m
   of the historical victim position, in the same zone/cell. Missing historical
   geometry fails closed; legacy contacts retain their compatibility LOS path
   with an added height bound. This is bounded client-authority plausibility,
   not validation of an untrusted client's complete tracking trajectory.

Focused evidence is stored under `runtime/evidence/ground-stability-review/`.
The native fixture scripts are `combat_stability_smoke.py` (moved-target melee,
replay identity, unchanged replay costs/HAM and bundled receipts),
`ground_damage_smoke.py --positive-evidence --strikes 1` (one native delivery
from partial coverage), and `ground_settlement_smoke.py` (two native sessions,
synthetic stationary contact receipts). Headless client tests use the dummy
renderer with XR disabled. Damage tuning, prolonged combat, remote latency and
headset validation remain separate future work; this pass does not release or
deploy the patch to the remote server or Downloads client.

### Deployment follow-up

The user-authorized test.17 deployment on 2026-10-11 installed patch 0151 on the
live realm after backup and verified native readiness/capability negotiation.
Linux/Windows packages and incremental bundles from test.13–16 were published;
the closed Downloads client was updated. See `docs/VPS_DEPLOYMENT.md` for hashes
and receipts. This deployment does not add prolonged damage/balance or headset
validation to the focused results above.
