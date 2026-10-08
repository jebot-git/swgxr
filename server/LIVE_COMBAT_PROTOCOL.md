# Persistent local Core3 combat bridge

## Physical melee guard extension

Patch `0071-physical-melee-guard.patch` accepts optional `guard_pose` on the owned `/session/update` (native `update`) request. Omission or `{"mode":"none"}` releases protection. Active poses contain exactly `mode` (`parry` or `boxing`), native `item_id`, `main` (`left` or `right`), and three-component vectors `head`, `forward`, `left`, `right`, `axis`. `head` is a source-world point; `forward` is a horizontal source-world unit direction. Hands are head-relative coordinates in a yaw-aligned frame (X right, Y up, negative Z forward), and `axis` is the normalized held weapon's longitudinal axis in that frame. Python validates types and bounds; native code validates pose geometry, native equipment, certification and proximity. No client damage multiplier is accepted.

Held poses refresh every 350 ms in the normal gameplay client and expire natively after 850 ms. Mode transitions bypass the ordinary idle-heartbeat delay; native request serialization still applies. `snapshot.player.physical_guard` contains `active`, cumulative `blocks`, and, when state exists, `mode` and `broken_seconds`. The client uses new confirmed block counts for haptics. Guard state is ephemeral and cleared at native session start/stop. It does not modify the presentation-only multiplayer pose cache. See [CoreCU combat policy](../docs/CORECU_COMBAT.md#physical-melee-guarding) for tuning and validation limits.

Patch `0023-live-native-combat-session.patch` keeps a real authenticated Core3 zone client connected while the Godot client supplies local movement and registered projectile contacts. Actual Core3 lairs spawn their own original AI creatures. Native attack validation, accuracy, armor, damage, threat, retaliation, death and experience remain authoritative. This is a bounded local test bridge, not a production MMO transport or an anticheat boundary.

`server/live_combat.py` owns one persistent session per account. Requests use the loopback adapter on port 18080; private IPC files live in mode-0700 `runtime/server/livecombat/<session_id>`. Credential options are mode 0600 and removed after login. Account identity is normalized to lowercase. Legacy roster and character-creation RPCs for the active account are rejected with HTTP 409 because reconnecting that character would evict its live zone session. Supported gameplay operations reuse the owned connection. Other accounts and health checks remain available.

## Requests

All POST bodies contain `account` and string `character_id`. After start they also contain string `session_id`.

| Endpoint | Additional fields |
|---|---|
| POST `/combat/session/start` | `position:[x,y,z]`, `heading_radians`, optional `spawn_test_lair:false` |
| GET `/combat/session` | identity fields in query string |
| POST `/combat/session/update` | `position:[x,y,z]`, `heading_radians`, optional `ready:true` |
| POST `/combat/session/fire` | unique `shot_id`, source `item_id`, `origin:[x,y,z]`, normalized `direction:[x,y,z]` |
| POST `/combat/session/melee` | unique `shot_id`, native `item_id`, head `origin:[x,y,z]`, normalized head-aim `direction:[x,y,z]` |
| POST `/combat/session/taunt` | unique `shot_id`, head `origin:[x,y,z]`, normalized head-aim `direction:[x,y,z]` |
| POST `/combat/session/impact` | registered `shot_id`, source `target_id`, `hit_position:[x,y,z]`, `projectile_age_seconds` |
| POST `/combat/session/stop` | no additional fields |

Coordinates use source SWG axes: X east, Y elevation, Z north/south. They are not Godot stage-relative coordinates. Finite outdoors Tatooine positions are bounded to X/Z ±8192 and elevation ±2048. Movement updates preserve native knocked-down, incapacitated and dead posture; these states reject movement with a fresh snapshot. Local collision/movement still belongs to Godot.

## Response

Every valid live response includes `backend:"core3"`, `source_kind:"core3_live_combat"`, `character_id`, `session_id`, increasing `sequence`, `session_live` and `snapshot`. Stop returns `session_live:false`. Recoverable action rejection retains HTTP 200 and the live snapshot but sets `mutation.success:false` and `error_code`; clients must inspect this, not just HTTP success. Lost identity/session returns HTTP 409. Never automatically retry a mutation.

`snapshot` contains boolean `ready`, `full:true`, `truncated`, `radius_m:128`, `test_lair_id`, `actors`, `player` and `weapon`. Actors are actual outdoor native AI/lairs, capped at 96; clients must disarm rather than silently treating a truncated snapshot as complete. Actor records contain source ID/templates, name, source position, heading in radians, original customization, scale, native health, death, posture and combat state. Creature `lair_id` comes from its actual native home LairObject, not an inferred template hash. Creature HAM can be negative at native death.

`player` includes native `on_load_screen` and `invulnerable` diagnostic flags; source position; primary `ham`, `max_ham`, `wounds` arrays in health/action/mind order; `shock_wounds`; native posture/incapacitated/dead flags; equipped `weapon_item_id`; `target_id`; and native pistol/general `experience`. Display `ham` clamps negative native values to zero; `raw_ham` retains the signed source values. `weapon` includes actual instance ID, certification, native attack interval, range, min/max damage, damage type, `kind` (`melee` or `ranged`), `unarmed`, and this prototype's finite projectile speed 160 m/s. Melee snapshots expose no advanced ability entries while those professions remain provisional.

A successful launch commits original `CombatManager::applySpecialAttackCost` once, including misses. It captures exact owned certified weapon identity, damage values, origin, direction and range. Cadence uses native `calculateWeaponAttackSpeed`. Impact consumes that registered shot once, checks age/range/direction/target bounds and ownership, then calls a copy of the original player `AttackCommand` with cost multipliers zero. This retains original range, LOS, target/posture checks and native combat effects without charging twice. Player target ID stays zero before and after the action so `PlayerObject::doRecovery` cannot start automatic player attacks; enemy threat/retaliation remain active. The server does not trust client damage or reward values.

## Basic melee attacks

Patch 0072 handles a swing or punch in a single `/combat/session/melee` request. Native code selects one attackable AI creature or lair in a 30-degree cone around the submitted head aim, allowing bounded target-volume tolerance. It checks ownership, readiness, standing native posture, weapon identity/certification, origin proximity (2.5 m), range and LOS. Reach is capped at 4 m for weapons and 2 m for unarmed, or the lower native weapon range. Unarmed requests carry the actual native default-weapon ID. Stowing a weapon visually is not native unequipping.

The normal native attack resolves immediately; there is no subsequent projectile impact request or locally applied damage. Shared cadence prevents alternating fists or weapon changes from bypassing attack timing. HAM is charged once even on a whiff, and replayed shot IDs are rejected. `mutation` reports `shot_id`, `ham_cost_committed`, `hit`, `damage`, and `target_id`; a whiff succeeds with zero damage and an empty target. A selected target also supplies `before`, `after`, and `native_result`. Native miss/block results can produce zero damage. The client sends no target, damage, status chance or advanced ability.

Melee inherits native combat checks, CoreCU armour/penetration, effects, retaliation, death and XP. Target selection does not turn the native attack into an area/cone attack. This integration has policy, protocol, mocked-client and native syntax checks; a linked build and actual encounter test remain pending because the current sandbox cannot run Podman. Earlier live ranged evidence below does not validate this new melee route.

## Brawler chest-gesture taunt

Patch `0073-chest-gesture-taunt.patch` adds an owned `taunt` request. Native `snapshot.player.taunt` supplies `learned`, `range_m`, `interval_seconds` and `cooldown_remaining_seconds`. Availability requires both Novice Brawler and the original granted `taunt` ability; all Brawler branches and advanced builds retaining those prerequisites can use it. No profession boxes or grants are changed.

The client recognizes two inward chest taps within 1.25 seconds, with grip closing a free tracked hand and trigger released. The same or alternating hands work; each beat requires withdrawing the fist before returning. Head-relative yaw coordinates remove world translation/turning. Tracking gaps, occupied hands, menus, focus loss and inability to fight suppress the gesture. During the gesture the reticle follows the head, and swing/fire/guard input is suppressed. A successful native taunt produces a short haptic on the hand that completed the gesture.

The server independently selects the closest eligible AI intersecting the reticle width (3% of depth plus bounded body volume), within the original 64 m taunt range and native LOS. Players, pets, dead/incapacitated actors, unattackable actors, taunt-immune actors and already-taunted actors are skipped. Selection is revalidated under the target lock. The request accepts no target, damage, threat amount or client claim of skill ownership.

The original `TauntCommand` handles HAM costs, threat, skill-modifier success chance and duration. Its random-roll bounds now clamp at zero so high taunt modifiers cannot create negative random ranges against low-level enemies. The attempt uses native command duration (at least one second), shares ordinary combat cadence, and records a creature cooldown that survives live-session stop/start while the creature remains loaded. Shot IDs share the existing replay budget. No eligible target causes rejection without native combat costs. `mutation.success` means the native command accepted the attempt; `mutation.taunted` separately confirms the threat state took effect. Responses include `shot_id`, `target_id`, `native_result` and `interval_seconds`. The client never retries an uncertain mutation.

Gesture, routing, receipt and reticle geometry tests use mocked tracking/transport and standalone C++; native command-registration syntax checks pass. Linked-server, live encounter and controller-hardware validation remain pending under the existing Podman/sandbox limitation.

## Limits and lifecycle

- Retained gameplay/combat sessions have no fixed population ceiling after patch0074. `SWGXR_MAX_NATIVE_SESSIONS=0` (default) means unlimited; an operator can explicitly set any positive admission limit. Native replies advertise `native_session_capacity:0`. Admission never evicts another player. The 60-second inactivity expiration remains enabled.
- Presentation and voice participant registries also have no fixed population ceiling. `SWGXR_MAX_VOICE_CLIENTS=0` is the default; positive values opt into a voice admission limit. Each world snapshot still contains at most 32 nearby players and 96 actors. These visibility budgets do not limit connected clients.
- The deployment target is 32 players, not an admission limit. HTTP defaults to 128 concurrent requests (`SWGXR_HTTP_CONNECTIONS`); request sizes, rates, queues and hardware budgets remain bounded. Engine3's `LoginAllowedConnections`/`ZoneAllowedConnections` values size initial connection hash tables and do not enforce population limits.
- At most 128 pending/recent shots per native session, eight-second lifetime; shot identifiers are not durable cross-session idempotency receipts.
- Contact ray tolerance 3 m, origin within 3.5 m of native player position, source range plus 2 m contact margin. Travel must fit both reported flight age and server elapsed time (100 ms timing margin), at 160 m/s.
- Native actor query radius 128 m, at most 96 actors. This is a full bounded snapshot, not general zone replication or dynamic interest management.
- No rewind/lag compensation, reliable event stream, player-vs-player support, interior live movement, source ability queue, item crafting or production authentication hardening is claimed.
- Source LOS validation dispatch is present. The initial open-plains fixture does not supply a deterministic negative LOS obstacle test; do not claim one from that fixture.
- A native mutation may commit before an IPC failure. A failed client must disarm and reconnect/read state; it must not retry with a new shot ID.

## Test profile and verification

The explicitly authorized isolated `Varek Solun` fixture is stored locally in `runtime/server/ranged-test-fixture.json`. It has the entire native Master Marksman prerequisite tree and the strongest stock source pistol certified by that tree, FWG5; no Pistoleer grant is required. Source FWG5 damage is **heat**, 40–150, no armor piercing, range 64 m; source attack time 3 s becomes 2.1 s with Master Marksman pistol speed. The ordinary source HAM cost formula remains active.

`spawn_test_lair:true` requires native PlayerObject `swgxr_livecombat/test_authorized=1`. It calls the real source `CreatureManager::spawnLair` for `tatooine_worrt_lair_neutral_small` at [3810, native terrain height, -4780]. Native worrts are attackable and initially nonaggressive. The controlled site is inside Mos Eisley's original CITY+NOSPAWNAREA region (center 3460,-4768, radius456), so ordinary area spawners do not add hostile encounters at the site. The direct test call still creates a genuine native lair and native children. Recommended player position is [3790,5,-4780]. The earlier [4100,5,-4780] site admitted hostile Valarian spawns and is no longer used. Actual-stage ground, body clearance and player-to-lair sight line passed at the new site. Repeated explicit starts may create separate real test lairs; this is an administrative test affordance, not world generation policy.

`tools/configure_core3.py` applies the ordered complete patch stack including 0023 and refuses unrecognized vendor modifications. Build using `SWGXR_BUILD_JOBS=4 tools/server/build.sh`, then gracefully restart Core3 onto the new binary and restart the adapter. Preserve the database and leave Core3 running after tests.

`tools/server/live_combat_smoke.py` requires exclusive ownership of the authorized fixture. It tests real source actor spawning, registered launch costs/cadence, invalid/replayed/range contacts, native damage/AI/death/XP and no queued autofire. Its JSON evidence records whether native retaliation was actually observed. This is backend validation, not headset/rendering validation. Root owns the subsequent live OpenXR launch and rendered evidence.

Latest backend evidence: `runtime/evidence/live-combat-core3.json` passed 145 checks, recorded 405 cumulative native HAM damage, 130 native lair condition damage, one native worrt death and +118 pistol/+11 general XP. A ten-second interval with a living damaged target verified no autonomous player attacks. Original AI moved away from the player; no retaliatory player HAM loss was observed. This proves native reactive movement, not successful enemy attack damage. Final player HAM was full 1100/900/700 with zero primary wounds.

## Loading readiness

Live native clients defer the original CmdSceneReady packet, leaving the original player loading protection active from zone entry. Local IPC transport readiness does not mean the player can fight. Start reports `snapshot.ready:false`, and fire is rejected with `session_not_ready` without cost. Only an explicit update with `ready:true`, after client world/actor loading and initial headset focus, invokes the original `PlayerObject::notifySceneReady`; the readiness latch then remains true until stop. Later focus changes or `ready:false` cannot re-enable protection during combat. Stop sets loading protection while disconnecting. This uses the original attackability rule, not permanent god mode. The native snapshot separately exposes `on_load_screen` and `invulnerable` to verify that distinction.

The final readiness-only native test (`runtime/evidence/live-combat-readiness.json`) passed 17 checks at the protected city-edge site. It confirmed actual passive lair children, loading protection without invulnerability, no pre-ready shot cost, monotonic activation, and full 1100/900/700 HAM with zero wounds. The session stopped cleanly and Core3 remained running for the subsequent VR launch.

## Original appearance impact bounds and command pacing

Patch 0025 replaces the origin-radius target check with the original appearance enclosing sphere, including its offset center. The source `AppearanceTemplate` API covers LOD/component appearances, unlike `getTemplateRadius`, which only recognizes mesh appearances. World contact points use the same axis conversion and inverse orientation as `CollisionManager::getAxisAlignedVector`; creature source height scales both center and radius. Valid authored spheres retain a 2 m contact margin. Missing or invalid source bounds use a bounded 3 m origin fallback. Source range, flight timing, ray direction, certification, costs and native LOS checks remain in force. Bounds metadata is returned on impacts, not repeated on every actor update.

The Core3 command callback silently discards commands when its existing five-per-second budget is exceeded. The adapter now shares a monotonic 275 ms minimum interval across movement, snapshots, firing and impacts, with a 1.05 s separation after initial zone-in attribute commands. This respects the existing source limiter without replaying mutations; effective live RPC frequency is at most about 3.6 Hz.

Final actual-source validation: `live-impact-native-bounds.json` passed 76 checks. The original outer log vertex (5.56 m from origin, previously rejected) caused 153 native condition damage; the same vertex rotated 90° caused 198. An outside-sphere contact was rejected. Mixed updates/fire/impact ran 13.18 seconds with no command-response timeout. `tools/server/live_impact_native_smoke.py --mutate-dedicated-fixture` reproduces this only with exclusive ownership of the explicitly authorized Varek fixture, cleans up its ephemeral lair/children and restores its test HAM/posture. `live_impact_bounds_check.py` separately verifies all 390 original vertices and transformed coverage (4 rotations, 3 scales).

## Authoritative life actions and medical interiors

`POST /combat/session/life` accepts the same owned session identity plus
`action: "recover" | "medical_transport"`. Responses retain the standard native
mutation and complete snapshot. Alive characters cannot use these life actions.
They do not require an equipped weapon. No client supplies healing or a clone
facility/destination.

For an active VR session, original `setIncapacitationTimer` records its source
interval (including original food modifiers). The original recovery task waits
for the `recover` intent, then for that interval. The client sends this once after
its hold gesture. Only the original task restores posture and survivable HAM;
there is no full-health grant. Repeated intents do not reset/accelerate the timer.
The gate is confined to registered live sessions, removed at explicit stop, and
fails open after a 60-second disconnected lease. Ordinary clients retain their
original automatic recovery. Reconnect uses the remaining original timer when
the initial duration was not observed by this session.

`medical_transport` selects the player's designated facility from Core3's own
clone menu when available, otherwise its first nearest eligible facility. For
incapacitated players it invokes original `killPlayer` followed by original
`sendPlayerToCloner`; dead players only invoke cloning. Original clone wounds,
shock, insurance/condition decay, other native death consequences and the
three-second resurrection task remain active. The source clone point determines
both medical building and cell. Duplicate actions during cloning are rejected.
This is a serialized native operation, not a database transaction with rollback;
a native failure after suicide remains a real dead state that can be retried.

`player` adds `zone`, `cell_id`, `building_id`, `cell_index`, `local_position`,
`heading_radians`, `cloning`, `recovery_requested`, and
`recovery_remaining_seconds`. `position` remains source **world** `[x,Y-up,z]`;
`local_position` is original cell-local `[x,Y-up,z]`. IDs are decimal strings;
outdoors uses IDs `"0"` and cell index zero. The source authored cell key is
`building_id + ":" + cell_index`, not the separate native cell object ID.

`snapshot.transport` is `{}` when absent. A native clone creates
`{id, facility_id, destination: {position, local_position, zone, cell_id,
building_id, cell_index, heading_radians}}`. This remains pending until the client
streams the real destination and sends `update` with `transport_ack:id`, matching
building/index and a position within three meters of the confirmed spawn.
Ordinary movement is ignored while transport is pending; stale/nonmatching acks
are rejected. This native-only relocation temporarily uses original load-screen
protection. The initial `ready` flag stays monotonic; focus loss cannot initiate
transport protection. Polling remains available during loading, incap and death.

Movement updates may include `building_id` and `cell_index`. The backend resolves
that source building/cell in the current zone and converts world coordinates
using the inverse of Core3's original building transform. Missing cell fields
preserve the current parent; explicit `"0"`/zero exits outdoors. This remains the
prototype's client-authoritative locomotion boundary, not server collision or
anti-cheat authority. Dead/incapacitated/knocked-down movement is ignored while
snapshots remain live. Session start never revives a character or moves an
immobilized character to the requested spawn.

Native concurrency capability: patched Core3 replies include top-level
`native_concurrency: "engine_cross_lock_v1"`, including the owned start reply.
This advertises the Engine3 cross-lock around the shared live-session map: a
queued command waiting for that map temporarily releases its player lock, so an
active world snapshot can acquire nearby-player locks. The old ordinary C++
mutex could deadlock when simultaneous callers each held their own player.
The adapter must derive this capability from the real native reply; missing or
unknown capability retains serialized HTTP admission. Per-account IPC remains
serialized even on a capable server to protect each request/response mailbox.

## Smuggler extensions

Session `update` accepts optional `smuggler_pose:{tracked,feign,upright}` with
strict boolean fields and mutually exclusive start/release intent. Core3 ignores
untracked intent and validates the learned ability. `snapshot.player` projects
`feigning_death` and `feign_death_available`. Feign may be pending with normal
posture or active with posture 13; `incapacitated` is false for simulated incap.
Death takes precedence. Client movement and body presentation use the confirmed
flag; physical posture requests never predict an authority transition.

`snapshot.weapon.abilities` exposes eligible native ranged abilities and remaining
cooldowns. `fire.ability_id` accepts `lethal_shot`, `last_ditch`, `low_blow`,
`restraining_shot`, or `concussion_shot_improved`. Omission is a basic shot. Native
skill, weapon and cooldown validation occurs before costs are consumed. The shot
receipt stores the command and multiplier until the single accepted impact.
See [Smuggler behavior and tuning](../docs/SMUGGLER.md).

### Native spice phases

Owner snapshots include `player.spice`, projected from persistent Core3 buffs:

```json
{"revision":12345,"effects":[{"episode_id":"12345","spice_id":"gunjack","phase":"active","elapsed_seconds":10,"remaining_seconds":290,"duration_seconds":300}],"modifiers":{"cooldown_scale":1,"health_regen_scale":1,"action_regen_scale":1,"mind_regen_scale":1,"melee_power_scale":1,"melee_recovery_scale":1,"ranged_capacity_scale":1.2,"ranged_rpm_scale":1.2,"melee_damage_scale":1},"autoaim":false,"melee_cone_degrees":0}
```

`revision` identifies the native buff object; it is **not** a monotonic sequence.
The surrounding session/owner sequence fences stale responses. No buff produces
revision zero and an empty effects array. Existing Core3 rules permit one spice
phase at a time. Native IDs include `droid_lube` (Zypolene Droid Lubricant),
`neutron_pixey` (Neutron Pixie), and `crash_n_burn` (Crash and Burn).

The client may interpolate the remaining presentation time, but cannot grant,
renew, consume or end an authoritative effect. Phase changes refresh equipped
weapon attributes. Dynamic native attributes and `weapon.fire_interval_seconds`
already contain applicable spice modifiers; clients must not multiply them again.
Screen tint, outlines, false hostility and virtual hand effects remain local.
Crash and Burn's withdrawal is not presented as a notification; healer feedback
continues to indicate healing while actual HAM and recipient feedback show damage.

While Giggledust is active, `world.spice_outlines` adds up to 256 nearest living,
authoritatively aggressive AI actors within 64 m, including other building cells.
Rows carry their actual cell/heading, `outline_only: true` and
`attackable: false`. `spice_outlines_truncated` reports the bound. This owner-only
list feeds noncolliding visual proxies; it never enters ordinary targeting,
physics or radar registries. Normal actor rows expose `aggressive` separately
from `attackable`, so a target's hostility is not inferred from attack permission.
