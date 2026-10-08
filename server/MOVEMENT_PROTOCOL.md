# Native locomotion bridge

Ordinary live, service and Scout pose submissions use `SwgxrMovement`, added by `0068-native-movement.patch`. They update Core3 position/zone membership without teleporting. Native travel, vehicle placement/dismount and medic drag keep their existing transport behavior and explicitly reset the validated position afterward. Starting a live session retains the persisted native location; the supplied start position cannot teleport the character.

The wire coordinate order is `[world X, height, world Y]`. A building/cell submission is converted into the original building-local coordinate system before validation. The native snapshot always reports the actual resulting world position and parent.

`player.locomotion` contains native getters:

- `run_speed`, `walk_speed`, `run_acceleration`, `walk_acceleration` are template values, not pre-multiplied client values.
- `speed_multiplier_base`, `speed_multiplier_mod`, `acceleration_multiplier_base`, `acceleration_multiplier_mod` are separate original modifiers. Posture, private speed/acceleration skill modifiers and Burst Run are already represented; do not apply Burst Run twice.
- `slope_mod_angle_radians`, `slope_mod_percent`, `water_mod_percent`, `swim_height`, `turn_scale`, `current_speed`, `movement_allowed`, `frozen`, `swimming` expose native locomotion state.
- `server_max_speed` is the original server speed-test ceiling before its tolerance: `run_speed * speed_multiplier_mod`. The original Core3 test does not include the base multiplier.

Accepted ordinary movement resolves Core3's terrain/FLO/water floor for the native position. The visual client retains its original terrain triangle floor; it must not continuously snap its feet to the native continuous/cached floor height. Rejected updates contain `mutation.movement_accepted=false`, an `error_code`, and `snapshot.player` with the authoritative position/parent. The client restores that rejected pose. A transport acknowledgment also reports movement not accepted but carries `transport_acknowledged=true` and no error; it is not a rejection.

## Source audit

Pinned Core3: `403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79`. Original client source research: SWG-Source/client-tools `949451032647e45e42c3aaef3f41b132c8af36e3`, recorded in ignored `runtime/research/swg-collision/source-revision.json`.

Source paths below are relative to `vendor/Core3/MMOCoreORB/src/` and refer to this pinned tree plus the existing prototype patches:

| Original source | Rule used by the bridge |
| --- | --- |
| `server/zone/packets/object/transform/Transform.h:126` | Finite positions; outdoor axes within ±8192, parent-local axes within ±1024; posture eligibility at line151. |
| `server/zone/packets/object/DataTransform.h:262` | Posture, frozen, inventory overload, animation movement lock. |
| `server/zone/packets/object/DataTransform.h:314` | Query original world-floor intersections, resolve closest native floor, validate speed, update native speed/swimming/validated position. |
| `server/zone/packets/object/DataTransformWithParent.h:301` | Building entry permission, connected portal cells and intercell floor agreement within0.25m. WALKIN permissions at line406. |
| `server/zone/managers/player/PlayerManagerImplementation.cpp:4100` | Speed measured with server elapsed time; validation window1s. Original tolerance is1.05 plus up to0.05; recent speed reductions receive the original2s change-buffer grace. |
| `server/zone/managers/planet/PlanetManagerImplementation.cpp:1539` | Closest terrain/FLO height by submitted height, then water floor at water height minus swim height if deep enough. |
| `server/zone/managers/player/PlayerManagerImplementation.cpp:3897` | Original swimming state, including checking floor/bridge intersections. |
| `terrain/manager/TerrainManager.cpp:173` | Planet bounds are exclusive at terrain min/max; cached source samples floor coordinates to0.1m. |
| `server/zone/objects/creature/CreatureObjectImplementation.cpp:1900` | Compose posture/private movement and acceleration modifiers; update slope and water properties. |
| `server/zone/objects/creature/CreatureObjectImplementation.cpp:2299` | Terrain negotiation is `min(slope_move,50)/50`; slope angle was converted from template degrees to radians. |

Original client `PlayerCreatureController.cpp:211` computes terrain/water slowdown; solid floors bypass terrain slope slowdown. `CreatureObject.cpp:1755` selects walk or run acceleration at maximum walk speed and multiplies acceleration base/mod; line1799 chooses maximum speed from run/walk. The client agent owns the corresponding client implementation and tests.

The pre-fix bridge teleported every submitted pose and skipped these movement rules. The shared bridge now applies the native policy. It retains VR-specific fine physical deltas rather than imposing the original packet callback's minimum update interval or12.5cm static-update threshold, and derives current speed from accepted displacement/server time rather than trusting a client-declared speed. It does not introduce server wall collision absent from the original: the swept world-wall test in `DataTransform.h:332` is commented out. Original client geometry remains responsible for continuous wall collision.

## Validation

`tools/server/movement_native_smoke.py` creates a disposable native character. Admin setup only positions that fixture and toggles the original frozen state; movement itself uses the production API. It verifies saved-position integrity, native getter projection, accepted normal displacement with a visual/native height discrepancy, native floor/currentSpeed, stable loading state, frozen rejection, original speed rejection with restored validated pose, source terrain bounds, invalid cells, actual Tatooine water/swimming, and indoor parent/bounds/transition checks.

Evidence: ignored `runtime/evidence/movement-native-smoke.json` (19 passed checks). Native build log: `runtime/server/movement-build.log`. This is real local Core3 validation, not a headset rendering or physical-device movement test. No VPS deployment is performed by this test.

## Bounded movement budget (0078)

The HTTP bridge now adds a monotonic per-character distance budget before the
original Core3 speed check. `TIME_VALIDATED` alone cannot apply an arbitrary
position. The allowance stores at most two seconds of native run speed with 10%
speed tolerance, plus a single 0.25m startup allowance. Accepted horizontal path
length, including reversals and individually small steps, spends that shared
allowance. An idle interval is capped; a rejection or duplicate does not create
a new allowance. Rejection preserves the most recently accepted pose and
revision, rather than rewinding to an older periodic Core3 validation anchor.
The original long-window native speed check remains an additional guard.

Comparisons use world-horizontal coordinates even across cell parents. Native
floor selection, portal connectivity, permissions, water and movement locks are
retained. Height-only client/native support differences do not count as physical
locomotion. Actual native ground teleports rebase the budget; client movement
never invokes that rebase. Session end clears its budget entry.

`player.locomotion.movement_revision` changes on accepted horizontal/parent
movement and authorized rebases. Clients may attach the last observed
`movement_revision` at the top level of a live request. It is scoped to that
owner and request; only a movement-bearing operation checks it. A mismatch
returns `native_movement_stale_revision` before changing pose. The field is not
inserted into stored action payloads or their idempotency fingerprints. Completed
receipt replays return before pose validation and do not repeat movement or
charges. Older callers without this optional field still use the distance budget.

Every shared movement-policy error uses the `native_movement_` prefix. Ordinary
`/session/update` and movement-bearing service failures retain the owned native
`live_response` inside HTTP400, with `mutation.movement_accepted=false`, current
snapshot, session identity and server sequence. Failure does not approve the
requested service action. Corpse interactions no longer temporarily assign an
unvalidated position; corpse and resource-gathering actions use this same policy.
Medical commands continue to use the current native position independently of
stale pose fields.

`tests/movement_budget.cpp` exercises the pure policy with explicit fake clock
values. `tools/server/movement_budget_native_smoke.py` exercises actual local
native requests and disposable fixtures; its report records completion rather
than treating source inspection as a runtime pass.
