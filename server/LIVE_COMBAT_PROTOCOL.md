# Persistent local Core3 combat bridge

## Physical melee guard extension

Patch `0071-physical-melee-guard.patch` accepts optional `guard_pose` on the owned `/session/update` (native `update`) request. Omission or `{"mode":"none"}` releases protection. Active poses contain exactly `mode` (`parry` or `boxing`), native `item_id`, `main` (`left` or `right`), and three-component vectors `head`, `forward`, `left`, `right`, `axis`. `head` is a source-world point; `forward` is a horizontal source-world unit direction. Hands are head-relative coordinates in a yaw-aligned frame (X right, Y up, negative Z forward), and `axis` is the normalized held weapon's longitudinal axis in that frame. Python validates types and bounds; native code validates pose geometry, native equipment, certification and proximity. No client damage multiplier is accepted.

Held poses refresh every 200 ms in the normal gameplay client and expire natively after 850 ms. Mode transitions bypass the ordinary idle-heartbeat delay; native request serialization still applies. `snapshot.player.physical_guard` contains `active`, cumulative `blocks`, and, when state exists, `mode` and `broken_seconds`. The client uses new confirmed block counts for haptics. Guard state is ephemeral and cleared at native session start/stop. It does not modify the presentation-only multiplayer pose cache. See [CoreCU combat policy](../docs/CORECU_COMBAT.md#physical-melee-guarding) for tuning and validation limits.

Patch `0023-live-native-combat-session.patch` keeps a real authenticated Core3 zone client connected while the Godot client supplies local movement and registered projectile contacts. Actual Core3 lairs spawn their own original AI creatures. Native attack validation, armor, damage, threat, retaliation, death and experience remain authoritative. Validated player physical contacts bypass the innate hit/miss roll; secondary defenses resolve normally and NPC attacks keep native accuracy. This is a bounded local test bridge, not a production MMO transport or an anticheat boundary.

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

`player` includes native `on_load_screen` and `invulnerable` diagnostic flags; source position; primary `ham`, `max_ham`, `wounds` arrays in health/action/mind order; `shock_wounds`; native posture/incapacitated/dead flags; equipped `weapon_item_id`; `target_id`; and native pistol/general `experience`. Display `ham` clamps negative native values to zero; `raw_ham` retains the signed source values. `weapon` includes actual instance ID, certification, native attack interval, range, min/max damage, damage type, `kind` (`melee` or `ranged`), `unarmed`, and this prototype's finite projectile speed 160 m/s. Melee snapshots expose learned compatible Brawler targeted strikes and separate support gesture entries.

A successful launch commits original `CombatManager::applySpecialAttackCost` once, including misses. It captures exact owned certified weapon identity, damage values, origin, direction and range. Cadence uses native `calculateWeaponAttackSpeed`. Impact consumes that registered shot once, checks ownership, reported flight age/range/direction and native target eligibility, then resolves the client-authoritative contact through a prepared native command with cost multipliers zero. Patch 0099 bypasses current target geometry/LOS/range rechecks for confirmed projectile receipts, retaining native outcomes without charging twice. Player target ID stays zero before and after the action so `PlayerObject::doRecovery` cannot start automatic player attacks; enemy threat/retaliation remain active. The server does not trust client damage or reward values.

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

The Core3 callback permits at most 20 XR session envelopes per second; ordinary commands retain the original five-per-second limit. The adapter shares a monotonic 80 ms minimum interval across movement, snapshots, firing and impacts, retaining the initial zone-in separation. Native ownership, action cadence and movement validation remain authoritative. The client serializes native requests through receipt consumption and adopts successful service envelopes before stamping the next movement revision. Requests queued across a room change are cancelled before mutation; economic mutations are not automatically replayed. Bounded audit timings record native request latency and rejection codes without credentials.

Final actual-source validation: `live-impact-native-bounds.json` passed 76 checks. The original outer log vertex (5.56 m from origin, previously rejected) caused 153 native condition damage; the same vertex rotated 90° caused 198. An outside-sphere contact was rejected. Mixed updates/fire/impact ran 13.18 seconds with no command-response timeout. `tools/server/live_impact_native_smoke.py --mutate-dedicated-fixture` reproduces this only with exclusive ownership of the explicitly authorized Varek fixture, cleans up its ephemeral lair/children and restores its test HAM/posture. `live_impact_bounds_check.py` separately verifies all 390 original vertices and transformed coverage (4 rotations, 3 scales).

## Doctor care and friendly VATS

`POST /medic/doctor` accepts the usual owned `character_id` and live session ID,
a unique `request_id`, `ability` (`reviveplayer`, `extinguishfire`, or
`healstate`), exact supply `item_id`, patient `target_id`, and medical `pose`.
The pose contains boolean `tracked`, `crossed`, `grips` and finite three-number
`left`/`right` world hand positions. Heal State additionally requires `focus_id`
for the medical tool. The adapter strips client effect, condition, amount,
duration, command and range overrides. The exact state pack determines which
condition is treated.

The client opens friendly VATS only with the Doctor tool held; an owned tool or
held state pack alone is insufficient. Stow, tool change, stale state, invalid
tracking or captured controls clears its patient and markers. Active friendly
VATS captures weapon combat input. Core3 independently checks owned focus and
supply, training, patient eligibility, range, LOS, resources and shared recovery;
physical holding/gesture recognition remains tracked client input.

Native `state.doctor` contains per-ability `learned`, `range_m`,
`cooldown_seconds` (remaining), `action_cost`, `mind_cost`,
`requires_medical_focus` and `supplies`. Each supply has `item_id`, `charges` and
`label`; state supplies also carry native `state_mask` and `state` (`stunned`,
`dizzy`, `blinded`, `intimidated`). The map also contains scalar
`healing_multiplier`, `emergency_healing_multiplier`, `wound_healing_multiplier`
and `wound_fraction_cap`. Patient records expose
`doctor_needs` and `revivable`; these are eligibility hints, rechecked at use.
The existing durable medical receipt path handles retries without consuming
another charge. Doctor has no ultimate or combat loadout entry.

`POST /medic/combat_medic` uses the same owned session and durable receipt path.
It requires `ability: applypoison|applydisease`, exact supply `item_id`, Doctor
tool `focus_id`, hostile `target_id`, `request_id` and tracked medical `pose`.
The native pack determines Health poison versus Action disease, single/area
delivery, range and quality. Client potency, radius, duration, pool and cost
overrides are discarded. Native validation covers command training, medicine
use level, accessible nested ownership, charges, target hostility, immunity,
LOS, range and shared offensive medical recovery. One valid attempt consumes
one charge and its resources even if the target resists.

`state.combat_medic` contains `abilities` (at most two), `supplies` (at most
256) and eligible hostile `targets` (at most 32). Ability entries include `id`,
`learned`, `cooldown_seconds`, `action_cost`, `mind_cost` and `recovery_group`.
Supplies contain `item_id`, `ability`, localized `label`, `charges`, `range_m`,
`area_radius_m`, raw pre-resistance `potency`, `duration_seconds` and
`target_cap`; zero radius denotes single-target delivery. Targets contain `id`,
`name`, world `position`, `eligible`, `dead`, `relation: hostile`, per-ability
`ability_available`, and local `bounds: {center,size}`. Live model collision
bounds take precedence in client targeting. Client markers lock target relation,
tool and exact supply for each press/release; changing any invalidates the action.

Heal Mind uses existing `/medic/select` and `/medic/heal` with `ability: healmind`;
for those direct-tool routes `item_id` identifies the focus, and a Heal Mind cast
requires tracked `pose`. Patient `needs.healmind` excludes self, droids and dead
targets. Its ability entry reports five-metre range and
`mind_cost_kind: transferred_amount`, with `mind_transfer_fraction_max: 0.22`.
`mind_cost: 0` denotes no fixed payment: the healer pays actual patient Mind gain
plus the Action cost. Native transfer leaves at least one Mind and accounts for
fatigue, missing Mind and spice effects. The client requests Heal Mind after a
Doctor-tool trigger double tap within 0.30 seconds, binding the same tool,
recipient and character epoch throughout. Single tap waits for that window
before Tend Damage (or explicitly selected First Aid); a 0.65-second hold casts
only Quick Heal. Native selection remains an internal dispatch step, not a
player-facing requirement for Heal Mind.

Ordinary stim inventory entries expose `medical_healing_amount`,
`medical_healing_percent`, `medical_healing_preview_scope`, `medical_stim_tier`
and `medical_stim_quality`. These are native calculation previews, before battle
fatigue/spice effects and overheal clipping; they do not grant client authority.
Heal Damage now costs 6% base Action and 8% base Mind. Existing client request
fields are unchanged.

Recognized ranged/area stims also expose these calculated healing fields and
`medical_target_cap` (one or five). Offensive packs expose
`combat_medical_supply`, `combat_medical_ability`, `combat_medical_available`,
`combat_medical_range_m`, `combat_medical_area_m`, `combat_medical_potency` and
`combat_medical_duration_seconds`; their `medical_use_hint` directs use through
the held Doctor tool. They do not acquire the friendly held-supply action.

CoreCU snapshots retain `profession_resistance` as the derived profession
profile and add `effective_resistance` with `profession_rating`, `native_rating`,
`baseline_rating`, `preparation_rating`, total `rating`, `chance_reduction` and
`duration_reduction`. `defense_context: "standard_native_modifiers"` identifies
the ordinary native modifiers used by the preview; attack-specific defense
inputs may alter final resolution. Doctor poison/disease prophylaxis adds once
after the bounded native/profession baseline comparison.

## Authoritative life actions and medical interiors

`POST /combat/session/life` accepts the same owned session identity plus
`action: "recover" | "force_of_will" | "medical_transport"`. Responses retain the standard native
mutation and complete snapshot. Alive characters cannot use these life actions.
Ordinary recovery and medical transport do not require an equipped weapon; Force
of Will requires the certified unarmed family. No client supplies healing or a
clone facility/destination.

For an active VR session, original `setIncapacitationTimer` records its source
interval (including original food modifiers). The original recovery task waits
for the `recover` intent, then for that interval. The client sends this once after
its hold gesture. For ordinary recovery, the original task restores posture and survivable HAM;
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

## Target-bound ranged abilities (patch 0085)

The client submits `ability_id` plus `target_id` in `/combat/session/fire` when
shooting a local anatomical marker or using the two-trigger ultimate chord.
`target_id` is an optional additive field for legacy launch compatibility; the
current target-marker client always supplies it for specials. The adapter validates
the decimal source-object ID. Core3 validates the target's current zone, AI type,
attackability, living/active state, range and LOS before committing SAC and cooldown.
The immutable shot stores that target; impact against a different ID is rejected.
Actual projectile collision and existing impact proofs still apply: no guaranteed
hit, no damage supplied by the marker, and no target UI replication.

Native ability descriptors now include `conditions_met`, `max_range_m`,
`min_range_m` (currently zero), and `ultimate`. Skill and weapon restrictions still
filter the native list; the client additionally checks current pools, cooldown,
weapon condition, reload/capacity, target range and scenery before showing markers.
Last Ditch and Master Pistoleer's Showdown are exposed ranged ultimates. The former primed-ability
lookup is removed from native ranged launch routing.

## Weapon-family combat loadouts

Patch 0086 adds `POST /combat/session/loadout` through the existing authenticated,
owned live session. The request carries the normal `character_id`, `session_id`
and optional movement revision plus:

```json
{
  "item_id": "99",
  "loadout": {
    "family": "pistols",
    "slots": ["concussion_shot_improved", "lethal_shot", "low_blow", "restraining_shot"],
    "ultimate": "last_ditch",
    "revision": 0
  }
}
```

Exactly four regular slots are required; an empty string means an empty slot.
There is one separate ultimate ID (also clearable with an empty string). Duplicate
IDs, unknown/unlearned abilities, wrong-family abilities and ultimate/regular slot
mixing are rejected. Core3 derives the family from the actual equipped weapon and
checks both its item ID and the saved family revision before writing. A stale
proposal never overwrites a newer saved selection. Editing does not reset ability
cooldowns or costs. New family loadouts start empty.

The owned `snapshot.weapon` now carries `ability_catalog` (learned, weapon-compatible
choices), `ability_loadout` (family, four slots, ultimate, revision) and `abilities`
(only equipped eligible choices). Cooldown and temporary state prerequisites do
not remove choices from the editor; they still gate use. Lost skill grants remove
usable selections from the snapshot. Preferences persist on the Core3 PlayerObject
under screenplay namespace `swgxr_combat_loadout`, keyed by weapon family, so
changing items within a family retains the same slots while another family has
its own selection. The client does not save these RPG choices in local JSON.

Native fire additionally rejects a learned but unequipped special before resource
spending. An already accepted projectile keeps its original ability through
impact. The currently implemented native catalog contains ranged specials,
Last Ditch and the merged Brawler Warcry. Held melee families can use the learned Warcry gesture;
other melee specials remain provisional.
The protocol/editor already represent those families without inventing abilities.


## Merged Warcry gesture (patch 0088)

`POST /combat/session/warcry` uses the owned session envelope plus `shot_id`,
`item_id`, `origin:[x,y,z]` and normalized `direction:[x,y,z]`. No target IDs,
rank, damage or client effect list are accepted. Warcry is not a projectile and
cannot be submitted through `/fire`. The native session validates ownership,
readiness, equipment, learned grants, SAC, cooldown,
shared cadence and bounded pose. Shot receipts reject duplicates.

`player.warcry` carries learned/conditions flags, remaining cooldown,
fixed Action/Mind costs and the shared attack interval. The weapon catalog has a
single `warcry` entry with activation `overhead_weapon_pump`; it has no anatomical
target marker. `mutation` returns `success`, `shot_id`, `attempted`, `affected`
and `interval_seconds`. Zero affected targets can be a successful paid attempt
when enemies resist; no eligible target is a rejected, uncharged request.
Server-selected cone targets require native LOS and resistance/recovery checks.
See `docs/CORECU_COMBAT.md` for provisional effect tuning and validation limits.


## Gesture ability catalog (patch 0089)

`weapon.ability_catalog` includes learned, weapon-compatible gesture support rows
with `category: "gesture"`, `activation`, `trigger_description` and
`weapon_requirement`. These are informational choices, available without slot
selection. Warcry, Taunt and Feign Death are currently listed; their existing
native activation routes retain their skill, weapon, state and recovery checks.

`weapon.abilities` contains only equipped targeting specials and the selected
ultimate. Gesture IDs cannot be saved in either selection. Legacy gesture slot
assignments are projected as empty; other slots and the ultimate are preserved.
The four targeting slots and one ultimate limit remain unchanged.


## Brawler targeted melee and buffs (patch 0090)

`/combat/session/melee` accepts optional `ability_id` plus mandatory `target_id`
for `knockdown_strike`, `unarmed_stun`, `unarmed_blind` or `polearm_stun`. These
must be learned, compatible and equipped in a regular targeting slot. Basic
melee requests remain unchanged and cannot select a target. Native validation
retains weapon identity, range/LOS, resource, readiness and cadence checks. A
special is constrained to the named eligible AI; it cannot transfer to a nearer
intervening actor. Shared control availability is projected on AI records as
`melee_control_available` for marker filtering. Native control resistance applies.

`POST /combat/session/brawler_buff` carries the owned session envelope, `shot_id`,
`item_id` and `ability_id` (`center_of_being` or `berserk`). The native player is
the only recipient. No target, cost, duration, multiplier or client effect list
is accepted. Native learned grants, weapon family/certification, state, active
buff, SAC, cooldown and shared cadence gate the request. Unique shot receipts
prevent duplicate spending. `player.brawler_buffs` projects learned/conditions,
active, costs and remaining cooldown; gesture rows show the trigger requirements.
No targeting slot or ultimate selection is involved.

## Advanced-profession ultimates (patch 0091)

Every ultimate must have a native owning advanced profession. The current
registry includes Last Ditch → `combat_smuggler_novice` and Showdown →
`combat_pistol_master`; native grants and weapon restrictions remain required.
Melee ultimate owners are documented with their respective kits below. Basic profession mastery and unrelated
advanced professions do not qualify. Unregistered ultimates are rejected by
loadout validation. Losing the required profession projects a saved ultimate as
empty, removes it from equipped abilities and prevents activation.

Ultimate catalog entries include `required_profession_skill` (native skill ID)
and `profession_requirement` (display name). These are server output, not client
claims accepted by loadout or attack requests. The hologram displays the owning
profession. Four regular slots plus one ultimate per weapon family remain the
limit; an empty ultimate is valid for characters without a qualifying ability.

## Teras Kasi tank abilities (patch 0092)

`POST /combat/session/tka` accepts the owned session envelope, `shot_id`,
`item_id`, `ability_id`, `origin` and `direction`. Allowed IDs are `tka_sweep`,
`tka_half_spin`, `tka_volley`, and `indomitable_focus`. No client target list,
damage, duration or target cap is forwarded. The native server validates skill,
current unarmed weapon identity/certification, player state, finite nearby pose,
SAC, per-ability cooldown, shared attack cadence and duplicate shot receipts.
Area attacks select capped non-pet AI targets server-side with range, cone and
LOS checks. Focus additionally requires the equipped ultimate and Master TKA.

`player.tka` projects learned/conditions, fixed Action/Mind costs, shared recovery,
remaining cooldown and active state; Focus includes remaining active seconds.
Catalog entries use `activation: "tka_gesture"`, `sac_policy: "fixed"` and readable
trigger descriptions. Area entries use `category: "gesture"`; Focus uses
`ultimate: true`, `self_only: true`, and owning skill `combat_unarmed_master`.

The existing `/combat/session/melee` route also accepts `challenging_strike`
with a mandatory bound `target_id` and equipped targeting slot. It uses fixed
SAC and extra aggro, without hard control. Catalog field
`requires_control_available: false` keeps its marker available during control
recovery. The other melee specials still require control availability.

## Swordsman special attacks (patch 0093)

`POST /combat/session/swordsman` uses the owned session envelope, `shot_id`,
`item_id`, `ability_id`, `origin` and `direction`. `rending_cut`,
`disrupting_blow`, `hamstring`, `decisive_strike` and `armour_break` additionally
require a bound `target_id`. `overhead_cleave` and `ground_slam` reject client
`target_id`; their capped target selection is native. No caller-supplied damage,
level, boss flag, target lists, duration or armour values are forwarded.

The server enforces learned Swordsman boxes, certified and intact two-handed
melee equipment, current owned item, target eligibility, Health/boss restrictions,
LOS/range, fixed SAC, cooldown, shared attack recovery and unique shot receipts.
VATS attacks require one of four targeting slots; Armour Break requires the
single ultimate slot and Master Swordsman. Area gestures require no slot.

`player.swordsman` projects per-ability learned/conditions, fixed costs, cooldown
and recovery. Catalog VATS and ultimate entries use `activation: "native_melee"`;
area gestures use `activation: "swordsman_gesture"`, `category: "gesture"` and
trigger descriptions. All use `sac_policy: "fixed"`. The client routes Swordsman
marker attacks through the Swordsman endpoint, while existing melee stays on its
previous route. Melee ultimate activation uses the bound-target route directly.

AI snapshots include `boss`, `effective_max_health` and `fractured_armour`, plus
the existing `level` and current Health. Decisive Strike advertises
`target_health_below: 0.3` and `excludes_bosses: true`. Missing boss metadata hides
its marker; native validation is authoritative even with stale or forged UI data.
An active fracture hides/prevents Armour Break until expiration; it never extends
an existing opening. Disrupting Blow and Hamstring require shared control
availability; Rending Cut, Decisive Strike and Armour Break do not.

## Fencer attacks and ultimate (patch 0094)

`POST /combat/session/fencer` accepts the owned session envelope, `shot_id`,
`item_id`, `ability_id`, finite `origin` and `direction`.
`arterial_cut`, `nerve_strike`, `disorienting_thrust` and `exposing_thrust`
require a bound `target_id` and one of the four equipped targeting slots.
`probing_jabs`, `raking_slash`, `guard_bash` and `flawless_assault` reject
client target IDs. Gestures choose one eligible native AI; the ultimate targets
the player. Client damage, bleed budget, progression, precision, duration and
target lists are never forwarded. The endpoint is exposed through the existing
authenticated remote gateway and shares native duplicate/cadence limits.

Native authority validates the original Fencer skill box, intact certified
one-handed weapon owned by the caller, state, SAC, cooldown, LOS/range and target
control eligibility. Flawless Assault additionally requires Master Fencer and
the equipped one-handed ultimate slot. Gestures need no targeting slot.

`player.fencer` contains learned/conditions, fixed costs, cooldown and recovery
per ability; Flawless Assault also includes active state and remaining seconds.
`player.fencer_precision` reports its native buff. Catalog targeting entries use
`activation: "native_melee"`; gestures and ultimate use `"fencer_gesture"`.
All advertise fixed SAC. Gestures use `category: "gesture"` and trigger text;
the ultimate uses `ultimate: true`, `self_only: true`, owning profession skill
`combat_1hsword_master`, and the supporting-hand two-trigger explanation.
`fencer_progress` and `bleed_budget_fraction` are server projections.

Fencer bleed serializes its custom tick interval and remaining damage budget
inside the native DamageOverTime object. Missing fields keep ordinary DoTs
unchanged. One fixed key per target merges every Fencer's bleed applications,
preserves the next tick and uses the larger remaining/new budget. Immunities,
resistance, absorption, dissipation and native cures remain authoritative.

## Pikeman crowd control (patch 0095)

`POST /combat/session/pikeman` accepts the owned session envelope, `shot_id`,
`item_id`, `ability_id`, finite `origin` and `direction`. `knockdown_strike`,
`polearm_stun`, `pinning_strike` and `disrupting_jab` require a bound `target_id`
and one of the four equipped polearm slots. `overhead_whirl`, `sweeping_trip`,
`driving_jabs` and `whirlwind` reject client target IDs; their capped area target
sets are selected natively. Caller damage, target lists, durations, progression
and control outcomes are never forwarded. Native weapon identity/certification,
training, LOS/range, state, SAC, cooldown, duplicate shots and shared cadence
remain authoritative. Whirlwind requires Master Pikeman and the selected ultimate.

`player.pikeman` projects learned/conditions, fixed Action/Mind cost, cooldown and
shared recovery for each action. Catalog rows add `native_family: "pikeman"`,
fixed SAC and `target_cap`. Targeted rows use `activation: "native_melee"`;
gestures and ultimate use `"pikeman_gesture"`. Gestures use `category: "gesture"`;
Whirlwind has `ultimate: true` and owning skill `combat_polearm_master`.
AI snapshots add `knockdown_available`; Unbalancing Thrust advertises
`requires_knockdown_available` alongside the existing shared-control gate.

Pikeman's advanced knockdown/stun retain Brawler's IDs and cooldown keys. Catalog
composition replaces their existing rows rather than adding duplicates. Requests
for learned Pikeman upgrades on the legacy `/melee` route dispatch to the same
resolver, so switching endpoints cannot obtain another cost, rank or cooldown.
Existing non-Pikeman Brawler actions retain their previous path.

## Force of Will

The existing owned `/combat/session/life` and `/session/life` routes accept
`action: "force_of_will"`. No client health, cooldown, target or training fields
are forwarded. `snapshot.player.force_of_will` carries `learned`,
`conditions_met`, `cooldown_remaining_seconds`, `cooldown_seconds` (600) and
`health_fraction` (0.15). Conditions and cooldown are separate; the client checks
both, and Core3 rechecks all gates under the character lock on activation.

Requires Novice TKA plus `combat_unarmed_accuracy_04`, certified unarmed family,
actual incapacitation and an existing recovery task. Feign death, dead/cloning/
loading, pending transport and pinned HAM deny it. Native command and life route
share one recovery implementation. Only Health is raised, to at least the rounded
up 15% effective maximum; the incap task is cancelled, native posture restored
and the normal revived event emitted. No wound/fatigue/incap-count/threat reset.
The persisted `swgxr_tka.force_of_will_deadline` and existing `tkaForceOfWill`
cooldown both apply. A duplicate request cannot recover twice.

Catalog entry `force_of_will` uses `category: "gesture"`,
`activation: "life_recovery"`, `ultimate: false`, and `self_only: true`.
It is excluded from circle-menu and loadout-slot activation. The client extends
the release-armed offhand-stick recovery hold from one to three seconds; an
acknowledged ordinary recovery can continue during the longer hold. Neither
request changes local life state without a newer native snapshot.

## Player physical accuracy and secondary defenses

Patches `0097-player-physical-accuracy.patch` and
`0098-player-secondary-defense.patch` establish a validated physical contact as
HIT before the ordinary secondary defense stage. A player has no primary innate
hit/miss roll; dodge, block, counter and applicable saber ricochet remain native.
The player contributes zero accuracy rating to the secondary opposed roll, so
changing player accuracy, aim bonuses or accuracy posture modifiers cannot alter
it. Defender ratings, defender posture, Center of Being and native opposed rolls
remain in that stage. NPC/companion attack accuracy retains its original path.

The physical-contact opt-in belongs to server-created attack wrappers, never a
client flag or Lua setting. These wrappers follow target, range, LOS, ownership,
skill, SAC and cooldown validation. Area specials keep bounded server target
selection. Legacy commands, Force and state-only actions remain outside this
physical-weapon path. Native block mitigation and dodge/counter/ricochet handling
run downstream; the existing active physical guard provides its additional
bounded protection. Moving clear of range or trajectory can prevent a contact
before RPG defenses are needed. Armour and status resistance remain separate.

Player accuracy-to-damage and accuracy-to-melee-radius translations remain disabled.
Original grip-scaled distance damage and crouch/prone bonuses are preserved by
patch `0099-client-projectile-contact.patch`, described below.

## Client-authoritative projectile contact

`fire` accepts `two_hands` (boolean) and `firing_posture` (`standing`, `crouched`,
`prone`). The client applies moving spread before sending the launch direction;
its rendered bolt uses exactly that same direction. Core3 captures the authored
weapon near/ideal/far range curve and grip/pose once. Missing fields retain legacy
full-range/standing behavior. Unknown damage or multiplier fields are not forwarded.

On `impact`, Core3 trusts which eligible native target the client reports hitting.
It no longer compares that historical contact with the target's current bounds,
current distance or current LOS. Launch/impact batching under latency no longer
uses server processing intervals as projectile flight time. Owned one-use shot
receipts, finite vectors, eight-second age/expiry bounds, reported direction/travel,
weapon identity and native target eligibility remain enforced. The registered
ability's bound target must match. This is client contact authority, not server
rewind or server simulation of client collision.

Only the confirmed-projectile wrapper bypasses current geometry checks; other
native and melee commands retain them. Native damage, armour, dodge/block/counter/
deflection, state resistance, threat and rewards remain server-owned. Impact returns
`contact_authority: "client"` and `range_damage_multiplier` as diagnostics.

Range scaling is 1.0/1.1 for one/two-handed pistols and 0.3/1.0 for other ranged
weapons. Core3 interpolates its captured curve at reported travel distance,
halves negative modifiers for crouch or clears them for prone, and applies the
result to the native ability multiplier before mitigation. No client damage roll,
modifier or reward is accepted. Movement spread and collision are client-owned.


Marksman VATS additions (patch 0100): `fire.ability_id` accepts
`suppression_fire`, `warning_shot`, `controlled_burst`, and `bleeding_shot`, each
requiring `target_id`. Native launch checks learned skill, weapon family,
certification/condition, equipped slot, native state, costs and cooldown. Actor
snapshots provide `ability_target_available` booleans for these four IDs; controls
also use `melee_control_available`, the existing shared control recovery flag.
Warning includes boss immunity and native attack-delay recovery in eligibility.

Impact remains one consumed registered client contact. Controlled Burst resolves
up to three native subhits against that bound actor with costs paid once;
`mutation.resolved_hits` counts successful command resolutions, including defended
hits that deal no damage. It is diagnostic, never client input. `damage` remains
the aggregate authoritative Health delta. Server ignores supplied hit counts,
costs, cooldowns, damage, bleed budgets and effect lists. No new client authority
over combat resolution is introduced.

## Pistoleer attacks, gestures and Showdown

`POST /combat/session/pistoleer` uses the existing authenticated owned session.
Its payload contains `character_id`, `session_id`, `shot_id`, `item_id`,
`ability_id`, finite three-element `origin` and `direction`, and the normal
optional planet/movement context. `ability_id` must be `fan_shot` or
`run_and_gun`. A supplied `target_id` is rejected, including an empty value.
The new gesture `shot_id` uses the native 8–80 character ASCII alphanumeric,
underscore and hyphen token format.
Client target lists, damage, resource costs, buff durations, hit counts, range,
cone angles and cadence multipliers are not forwarded. Native training,
certification, held usable pistol, player state, resources, cooldown and receipt
checks remain authoritative. Gesture recognition is client-owned.

Fan Shot selects at most five eligible native enemies in a 60-degree muzzle
cone, within the shorter of 12 m and current one-handed pistol range, with LOS.
It is the Pistoleer kit's only damaging AoE. Run and Gun targets self and needs
Pistol Stances II (`combat_pistol_support_02`). Neither gesture needs a targeting
slot or selected ultimate; compatible mixed builds retain both when learned.

`snapshot.player.pistoleer[id]` describes each gesture with `learned`,
`conditions_met`, `cooldown_seconds`, `cooldown_remaining_seconds`, `action_cost`,
`mind_cost` and `interval_seconds`. The `run_and_gun` entry additionally reports
`active`, `active_remaining_seconds`, `duration_seconds` (8),
`ordinary_fire_rate_multiplier` (1.25) and `special_cost_multiplier` (0.75).
These are native output, never accepted claims. Current ordinary pistol cadence
is reflected in `weapon.fire_interval_seconds`; regular single-target pistol
specials expose their current discounted `base_sac`. Fan Shot and ultimates are
excluded. Both stance variants activate this same buff/cooldown.
Run and Gun reports 0.25 s `interval_seconds` for activation recovery; Fan Shot
reports the normal weapon interval with a 1.5 s floor.

`fire.ability_id` additionally accepts `double_tap`, `disarming_shot` and
`showdown`, all requiring a decimal `target_id`. Original native grants gate
Double Tap and Disarming Shot; native `healthShot2` upgrades the existing
`bleeding_shot` rather than exposing a second ID or cooldown. Four selected
targeting slots and one selected ultimate per weapon family remain the limit.
Double Tap resolves two native subhits from one registered contact; Showdown
uses three separately registered physical projectiles.

Every Showdown launch additionally requires `volley_id` (8–80 ASCII letters,
digits, underscores or hyphens) and `volley_index` (integer 0–2, excluding booleans).
Showdown `shot_id` uses the same token format.
For index 0, `volley_id` must equal `shot_id`; later shots have their own unique
`shot_id` and reuse that volley ID. Only Showdown and Rifleman's Flurry Shot
accept these volley fields on `fire`; other actions and abilities reject them.
The native volley ledger, not those client fields, determines
whether costs were already paid, which index is next, whether the 0.25 s spacing
has elapsed, and whether the same bound target, weapon, loadout and valid player
state remain. The sequence has a short expiry. An invalid, duplicate, reordered
or expired continuation never creates a free independent ultimate. Subsequent
physical contact uses the normal `/combat/session/impact` request.
The client waits for the preceding accepted launch receipt and then 0.25 s
before launching a continuation, so network backlog cannot compress native
cadence. Network latency can lengthen or expire the volley.

The first Showdown launch pays 150 Action / 75 Mind and starts the 120 s cooldown.
Each accepted projectile resolves 0.9x damage against the bound target with
normal secondary defenses and armour. Once per volley, the first damaging
contact attempts 30% outgoing-damage suppression for up to 5 s before resistance;
a resisted attempt is still spent. Strongest damage suppression wins. The
server owns this attempt state and ignores client fields such as
`suppression_applied` or `cooldown_paid`. Interruptions and misses do not refund
the activation; Showdown never retargets or adds an area effect.

Catalog `ammo_cost` is presentation/input guidance for the existing client
magazine/reload system: Double Tap 2, Fan Shot 3, Run and Gun 0, and Showdown 1
per launched projectile with 3 required locally before activation. There is no
new native persistent ammunition account or client ammo claim in these requests.
A confirmed failed launch can refund its local reservation; an accepted launch
followed by a missed or failed impact cannot.

## Carbineer controls, gestures and Charge Blast

`POST /combat/session/carbineer` uses the authenticated owned session and accepts
only `full_auto_sweep`, `tactical_brace` or `charge_blast` as `ability_id`. Required
fields are `character_id`, `session_id`, `shot_id`, `item_id`, `ability_id`, finite
three-element `origin` and `direction`, and literal boolean `two_hands: true`.
The token uses the native 8–80 character ASCII alphanumeric, underscore and
hyphen format. Normal optional planet and bounded integer movement revision
context remains. A supplied `target_id` is rejected even when empty; target
lists, damage, costs, control chance, duration, range, cone size, ammunition,
client hit counts and buff claims are not forwarded. Forward Check is absent.

Gesture recognition and grip tracking remain client input. Native checks enforce
learned grants, owned usable certified carbine, player state, resources, cooldown,
receipt reuse and bounded muzzle pose. Charge Blast additionally requires the
selected ultimate; Full Auto Sweep and Tactical Brace require no targeting or
ultimate slot. Their availability carries into combined professions with
Carbineer training. No arbitrary client effect list reaches the native attack.

Full Auto Sweep resolves at most five native eligible living non-pet AI targets
in a 75-degree cone within min(18 m, supported weapon range). Charge Blast
resolves at most six in a 90-degree cone within min(20 m, supported weapon range).
Both use the actual final muzzle, three-dimensional target geometry, native LOS
and nearest-first deterministic selection. They resolve directly from this
intent route, with native per-recipient defenses, damage and resisted controls;
they do not register single-target projectile receipts for subsequent `impact`.
Empty accepted cones still pay costs and cooldown. Tactical Brace is self-only.

`snapshot.player.carbineer[id]` reports `learned`, `conditions_met`,
`cooldown_seconds`, `cooldown_remaining_seconds`, `action_cost`, `mind_cost` and
`interval_seconds`. Tactical Brace additionally exposes `active`,
`active_remaining_seconds`, `duration_seconds` (8) and `control_chance_bonus`
(10 potency before resistance, capped at 95% final chance). These fields are native
output. The buff preserves immunity, recovery, duration and spread. Its activation
recovery is 0.25 s; Full Auto Sweep uses native weapon recovery with a 1.5 s floor
and Charge Blast a 2 s floor. Catalog metadata identifies the two slot-free
gestures with `carbineer_gesture` and Charge Blast with `carbineer_ultimate`.
The chance bonus applies to Carbineer effects and Marksman Suppression Fire and
Warning Shot while using a carbine; legacy Smuggler effect formulas are unchanged.

`fire.ability_id` additionally accepts `crippling_shot`, `wild_shot` and
`charge_shot`, each requiring a decimal `target_id`. Normal grip/posture capture,
loadout, range, state, resource and cooldown checks apply. They use the existing
one-use physical-contact `impact` flow and cannot create cone attacks.
`charge_blast`, `full_auto_sweep` and `tactical_brace` are rejected on `fire`.
Volley fields are rejected on every Carbineer request.

Suppression Fire retains its existing ID, targeting slot and cooldown.
`suppressionFire2` plus Carbineer training independently unlocks it without
Marksman Support; the carbine upgrade reduces enemy accuracy by 25 for up to
6 s before native resistance. Other compatible weapons preserve the Marksman
variant when its Marksman grant is learned. Duplicate source ranks do not create independent slots or cooldowns.
Hard-control attempts and Suppression Fire retain existing shared recovery;
immunities remain and strongest active movement slow wins. Wild Shot's native Stun weakens combat effectiveness and is
not total immobilization.
New Carbineer VATS target availability describes living eligible non-pet AI;
control immunity or recovery withholds the secondary effect without blocking
the damage attack. Existing Suppression Fire keeps its stricter control-target
availability checks.

Full Auto Sweep and Charge Blast expose `ammo_cost: 3`; Tactical Brace exposes
`ammo_cost: 0`. This guides the existing local magazine/reload transaction and
does not add a persistent native ammunition account. Confirmed rejected
activations can restore local reservations; accepted attacks remain spent,
including empty cones. Native Action/Mind costs and cooldown are paid once per
accepted activation; each target receives its own normal defense/effect attempt.

## Rifleman single-target damage and bolting Focus

`POST /combat/session/rifleman` uses the authenticated owned session and accepts
only `rifleman_focus`. Required fields are `character_id`, `session_id`,
`shot_id`, `item_id`, `ability_id`, finite three-element `origin` and `direction`,
and literal boolean `two_hands: true`. The shot token uses 8–80 ASCII letters,
digits, underscores or hyphens. Normal optional planet and bounded integer
movement revision context remain. A supplied `target_id` or volley field is
rejected, including an empty value. Target lists, active/learned claims, damage
multipliers, costs, durations and ammunition claims are not forwarded.

Focus is a self-only buff. The client recognizes the offhand receiver bolting
motion and only sends activation after returning to a supported grip. Native
checks require Novice Rifleman plus Concealment II
(`combat_rifleman_speed_02`), a held owned usable certified rifle, a valid player
state, resources, cooldown and a fresh receipt. This is an explicit SWGXR node
gate; the original profession graph and source grants are unchanged. Focus takes
no targeting or ultimate slot and remains available to combined professions.
No cant/hold alternative activates this gesture.

`snapshot.player.rifleman[id]` reports `learned`, `conditions_met`,
`cooldown_seconds`, `cooldown_remaining_seconds`, `action_cost`, `mind_cost`
and `interval_seconds` for `lethal_shot`, `piercing_shot`, `flurry_shot`,
`surprise_shot`, `sniper_shot` and `rifleman_focus`. Focus additionally reports
`active`, `active_remaining_seconds`, `duration_seconds` (8) and
`damage_multiplier` (1.2). Those fields are native output, never accepted buff
claims. Focus costs 50 Action / 25 Mind, has a 60-second cooldown and multiplies
ordinary rifle fire and compatible regular rifle specials by 1.2; ultimates are
excluded. Activation recovery is 0.25 seconds. Each physical projectile captures
the current Focus multiplier at launch; removing the buff does not rewrite an
already registered shot. Loss of the required rifle, training or valid life
state invalidates the active buff. Catalog activation is `rifleman_gesture` for Focus and
`native_ranged` for Rifleman projectiles.

`fire.ability_id` additionally accepts `piercing_shot`, `flurry_shot`,
`surprise_shot` and `sniper_shot`, each requiring a decimal `target_id`. Sniper
Shot additionally requires literal `two_hands: true`, Master Rifleman, the
original `sniperShot` grant and the selected rifle ultimate. All retain the
existing native-owned skill, certification, loadout, range, player-state,
cost and cooldown checks and normal physical projectile `impact` flow. Focus
is rejected on `fire`, and no new projectile ability is accepted on the gesture
route. Projectiles remain bound to one target; the kit has no area damage.

Head Shot uses the existing `lethal_shot` ID, targeting slot and cooldown.
Novice Rifleman plus `headShot2` independently unlocks the qualified rifle
version without Master Marksman: 4.0x damage, 110 Action / 40 Mind and a
30-second cooldown. `headShot3` raises its multiplier to 4.25x. Other weapon
families retain existing Lethal Shot behavior and training requirements.
Piercing Shot uses `mindShot2` for 2.0x damage and halves the target's current
Kinetic/Energy body resistance for this hit only; no lasting armour debuff or
Mind-pool damage is created. This uses current impact-time resistance after an
existing Fractured Armour effect. It costs 75 Action / 30 Mind with an 18-second
cooldown. Surprise Shot uses `surpriseShot` for 2.0x damage, raised to 3.0x
when the native target is at least 80% of effective maximum Health at impact.
It costs 80 Action / 35 Mind with a 24-second cooldown and needs no stealth state.
Sniper Shot is one 6.0x physical projectile, costs 150 Action / 90 Mind, has a
120-second cooldown and native weapon recovery with a 2.5-second minimum.
Eligible bosses keep ordinary damage resolution; the source incapacitated-target
deathblow behavior is not used.

Flurry Shot uses `flurryShot1` or `flurryShot2` and the same strict three-launch
wire format as Showdown. Each launch supplies a unique `shot_id`, a shared
`volley_id` and integer `volley_index` 0–2, excluding booleans. For index zero,
`volley_id` equals `shot_id`. Both tokens use the 8–80 ASCII token format.
The first accepted launch pays 100 Action / 35 Mind and starts the 18-second
cooldown. Native state binds the volley to its ability, weapon, target and
loadout, admits only the next index, requires at least 0.25 seconds between
launches and expires the sequence after two seconds. Continuations recheck valid
player state; neither a forged payment claim nor Showdown's volley can authorize
a Flurry continuation. The client waits for each preceding accepted launch
receipt and then the spacing interval, so latency can lengthen or expire a
volley. Each accepted projectile resolves its own contact and normal defenses
at 0.8x damage, improved to 0.9x with `flurryShot2`; Flurry has no Showdown
suppression effect. Each launch captures its current learned rank and Focus
multiplier, while requiring the original weapon statistics and continued
training. Retargeting, interruptions and misses do not refund accepted
launches. Subsequent `impact` uses only its normal fields; volley metadata is
rejected there because the native receipt already owns volley identity.

Focus exposes `ammo_cost: 0`; single-shot attacks expose one round. Flurry
requires three rounds available in the existing local magazine system at
activation and spends one per physical launch. Confirmed rejected launches
restore their local reservation; accepted projectiles remain spent even on a
miss. These values do not create a persistent native ammunition account or add
client resource authority.

## Commando equipment delivery

`POST /combat/session/commando` carries the owned session, `shot_id`, `item_id`,
finite `origin`/`direction`, boolean `two_hands` and `ability_id`. Empty ability
means an ordinary cone/beam discharge. `focused_discharge` and `acid_spray`
require one `target_id`; `overdrive` is self-only. Area membership, damage,
certification, training, costs and cooldowns are native decisions. Unknown
abilities and client target lists are not admitted. Rockets register through
`fire` and settle through the existing physical `impact` receipt; world contact
uses `target_id: "0"`. Focused rockets remain bound to their selected enemy.

The seven supported templates expose flat `snapshot.weapon` fields
`native_family: "commando"`, `commando_family`, `class_key`, `delivery`,
`fire_interval_seconds`, `special_interval_seconds`, `max_range_m`,
`projectile_speed`, `cone_angle_degrees`, `beam_radius_m`, `area_radius_m`,
`target_cap`, `area_budget_multiplier`, `charges`, `charge_limited`,
`action_cost`, `mind_cost`, `normalized_damage`, `craft_quality_multiplier`,
`requires_two_hands`, `conditions_met` and `cooldown_remaining_seconds`.
`charges: -1` means a reusable weapon using the existing local magazine path;
the four consumable heavy weapons use native charges and cannot reload them.
`snapshot.player.commando` exposes Focused Discharge, Acid Spray and Overdrive
availability/recovery; Overdrive also exposes its active duration. Slots and
ultimate selection use the heavy-family loadout.

The native packet suppresses inherited heavy-command multipliers and item DoTs.
Physical contact retains native secondary defenses, armor, damage states and
rewards. Area delivery uses at most six eligible enemies, distance/angle falloff
and an aggregate budget of 2.5 direct packets. Cone/beam targeting currently
shares the existing live combat PvE eligibility (hostile AI and lairs).

Player `locomotion.controls` exposes `slow_percent`, `rooted` and
`voluntary_scale`. The source locomotion controller applies it to deliberate
joystick/desktop travel. Tracked head/hand pose and physical room movement are
not animated or repositioned by Commando restraints.

## Squad Leader support and Volley Fire

`POST /combat/session/squadleader` requires the owned character/session,
`shot_id`, equipped `item_id`, positive source `target_id`, and finite
`origin`/`direction`. Accepted ability IDs are `steady_aim`, `rally`, `form_up`,
`boost_morale`, `retreat` and `volley_fire`. The five support targets must be
visible eligible party members within 48 m. Volley targets an eligible enemy
within 64 m and requires Master Squad Leader, the original `volleyFire` grant
and the selected ultimate. Group IDs, recipient lists, damage and durations
supplied by a client cannot authorize effects. Native cooldowns, current
equipment, membership, resources and target legality govern acceptance.

`snapshot.player.squad_leader` contains `group_id`, `passives`, `abilities`,
`targets` and `volley_fire`. Friendly target records contain source position,
height, name and eligibility. Learned support ability records expose native
conditions, costs, duration, range and cooldowns. They are contextual support
options, not four-slot offensive loadout entries. Volley Fire is eligible in
the existing ultimate slot of every weapon family, including unarmed.

Passives expose `damage_bonus`, `action_mind_regen_bonus`, `melee_defense` and
`ranged_defense`. The native group supplies strongest current same-planet
contributions without a distance/cell restriction. Support shouts use nearby
range/LOS and share persistent recipient cooldowns. No party membership or
bonuses are reconstructed by the Python adapter or local client.

Each eligible member's `volley_fire.mark` is either null or its own remaining
charge, with `id`, `target_id`, `position`, `height`, `remaining_seconds`,
`charges: 1` and `per_member: true`. The native cast captures eligible membership
epochs, keeps one active group mark and starts persistent 120-second recipient
recovery. Late joining, leaving/rejoining or another leader cannot create a
second charge. The client draws this local mark through geometry and removes it
on expiry, consumption, loss of authority or membership. It does not broadcast
an authoritative mark to other clients.

A damaging launch may add the paired fields `volley_mark_id` and
`volley_target_id`. Both must be well formed; any ordinary `target_id` must
match the mark target. These identify intent only. Native code checks the
current member's unspent mark, target legality, same planet and the actual
attack's range before reserving one charge. Out-of-range or rejected actions
do not spend it. Caster pose, certification, charges, resource payment and
cadence remain part of the ordinary attack path. Geometry/LOS and avoidance
are bypassed only for the marked hit; the first damage packet receives the
guarantee, while later burst packets retain normal defenses. Armor and separate
status resistance remain. An accepted hit absorbed to zero damage is still a
hit and consumes the mark.

Supported damaging routes are `fire`, `melee`, `commando`, `tka`, `swordsman`,
`fencer`, `pikeman`, `pistoleer` and `carbineer`, excluding their self-buffs.
Scout direct trap/grenade attacks accept the same pair through their own
request contract. Healing, taunts, pure status applications and ongoing damage
ticks cannot consume the guarantee. Showdown/Flurry `volley_id` and
`volley_index` remain separate multi-projectile receipt fields.

Guaranteed ranged attacks resolve their normal native strike from the accepted
launch, returning `volley_consumed`, `volley_mark_id` and `volley_target_id`.
The client treats its remaining projectile as cosmetic and submits no second
impact. Traps and grenades reserve their mark on accepted in-range throwing,
then retain native delay and supplies for one guaranteed primary strike;
movement during that delay does not revoke the accepted range check. Native
reservations and bounded shot receipts prevent repeat consumption. Short-lived
marks may be lost on a server restart; persistent cooldowns remain, rather than
reconstructing free guarantees.

## Bounty Hunter single-target combat

`POST /combat/session/bountyhunter` accepts the owned character/session,
`shot_id`, equipped `item_id`, finite `origin`/`direction`, `two_hands` and
`ability_id`. `underhand_shot` requires two hands and no target; the accepted
receipt contains `armed: true`, `armed_remaining_seconds: 1.5` and `item_id`.
The native session binds the arm to that item. It commits no ammunition or HAM
until a subsequent accepted `fire` with `ability_id: underhand_shot`. That fire
may be targetless; a miss still consumes its opportunity. Equipment/context
changes or expiry invalidate it. An arm acknowledgment cannot authorize a
different client-held item.

`duelist_stance` requires a positive `target_id`, corresponding training and a
compatible weapon. Native aim, range, LOS, costs and persistent cooldowns apply.
The selected enemy remains the sole protection source for the buff's duration.
`snapshot.player.bountyhunter` reports ability availability and cooldowns; the
Underhand row also reports `armed_item_id` and `armed_remaining_seconds`.

The existing `fire` path accepts `eye_shot`, `confusion_shot` and `fast_blast`
with a target. `bleeding_shot` remains the one shared ranked entry. Native skill,
certification, weapon, loadout and target checks remain authoritative. The raw
legacy BH player commands are retired; NPC uses remain available.

Exact `pistol_scatter` shots return a `projectile_profile` with `kind: scatter`,
`pellet_count: 8`, `half_angle_degrees: 4` and `speed: 160`. One shot produces
one impact receipt against one primary target. The impact includes
`pellet_contacts`, one to eight objects with unique integer `pellet_index`
values 0–7, finite `hit_position` and `projectile_age_seconds` within 0–8.
Index zero follows the accepted centre direction; the other seven form the
deterministic ring. The outer impact position/age identify its earliest contact.
Native geometry, target, range, timing and LOS checks bound the accepted damage
to `contact count / 8` of one ordinary shot. Duplicate receipts cannot add damage.

Exact `rifle_lightning` fire may propose `guided_target_id`. Native acceptance
echoes the bound target and a `projectile_profile` with `kind: lightning`,
`speed: 160`, `acquisition_degrees: 5`, `turn_degrees_per_second: 20` and
`max_turn_degrees: 8`. Guidance never switches targets. Client swept collision
and native impact bounds retain obstruction and range checks. These metadata
fields cannot change weapon classification, damage, pellet count or turn limits.

Volley Fire retains one guaranteed damage budget per member. Its accepted
launch resolves the marked attack once; cosmetic scatter pellets or lightning
flight do not submit additional damaging impacts.
