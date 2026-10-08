# Terrain and player navigation

The player moves horizontally over resident terrain height-field triangles. The
terrain supplies foot elevation afterward; it is not a capsule obstacle and has
no generic Godot 45/48-degree walking cutoff. Buildings retain physical capsule
collision, original FLR support and POB cell/portal membership. Head and controller
poses remain tracking-driven.

## Source contract

The audit uses SWG-Source/client-tools revision
`949451032647e45e42c3aaef3f41b132c8af36e3` (local reference under
`runtime/research/swg-collision`) and pinned Core3
`403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79`. Proprietary source and original assets
remain ignored; none is copied into this document or distributed source tree.

| Behavior | Source reference | SWGXR implementation |
| --- | --- | --- |
| Terrain heights | Core3 `terrain/ProceduralTerrainAppearance` and height affectors | Existing native Core3-derived evaluator; independently checked against the native reference executable |
| Leaf tile topology | `ClientProceduralTerrainAppearance_ClientChunk.cpp`, construction triangle indirection; `ShaderSet.cpp`, centre index pattern | Eight triangles around each original tile centre, expressed as alternating quad diagonals; render and physical queries share triangles |
| Horizontal movement, then height | `CollisionWorld.cpp`, `updateStep` | Native height-field follower retains horizontal input distance; source slope policy is the sole terrain speed penalty |
| Passability | `AffectorPassable.cpp`, `affect`/`load_0000`; `CollisionWorld.cpp`, `testPassableTerrain`/`handleTerrainImpassability` | APAS boolean and feather threshold, leaf-tile origin sampling, path checks at no more than 2m, world X/Z sliding; impassability does not remove the terrain surface |
| Terrain exclusion | `AffectorExclude.cpp`, `affect` | Any positive influence excludes terrain; refined exclusion boundaries remain shared by rendering and collision |
| Water support | `TerrainObject.cpp`, `getLogicalHeight`/`isBelowWater` | Maximum of real resident terrain and water minus native swim height; separate swimming/wading state; no invented support when terrain is absent |
| Speed and slope | `PlayerCreatureController.cpp`, `computeTerrainMovementModifier`; `CreatureObject.cpp`, speed/acceleration getters | Native run/walk, acceleration, multiplier, slope, water and cap fields; authored floors bypass terrain penalties; swimming bypasses wading/slope penalty |
| Floor movement | `Footprint.cpp`, `updateHeights`; `FloorMesh.cpp`, `pathWalkCircle` | Finite source support and swept adjacent floor constraints; interiors cannot query exterior terrain |
| Network movement | Core3 `DataTransform`, `DataTransformWithParent`, `PlayerManager::checkSpeedHack` | Normal zone updates, native movement locks/speed checks, floor/water resolution, parent and building permission validation; ordinary submitted poses are not teleports |

Core3's continuous terrain evaluation and the original client's triangulated
surface can differ slightly in Y. Accepted snapshots do not repeatedly snap the
headset to server Y. Explicit native movement rejection restores authoritative
horizontal position/cell and resolves local resident support. Server-directed
travel, medic dragging and vehicle movement retain their own authority and reset
ordinary movement-validation history.

The renderer still uses its existing chunk streaming, materials and render-only
skirts. Exclusion boundaries are refined rather than reproducing the original
renderer’s coarse tile-shaped holes. Those choices do not authorize walking
through excluded or unavailable ground. This is source-aligned navigation with
Godot/Jolt capsule collision and VR tracking, not a claim of a byte-for-byte port
of the original renderer or every FloorLocator internal algorithm.

## Recurring transition defects

Bestine's arrivals ramp exposed a terrain-to-authored-floor handoff bug: the
capsule toe touched the ramp before its centre left terrain, and the terrain
branch suppressed the bounded stair solver. Both controller and room-scale paths
now hand that motion back without consuming it twice.

Departures exposed a coarse original CMSH closure across the open FLR approach.
The shared collision builder follows the portal centreline through original
Crossable floor adjacency to an open terrain edge. Only that finite approach can
extend doorway clearance or lower its bottom to the connected ramp surface.
Closed, WallBase and WallTop edges cannot justify cutting a shell. Below-floor
walls, distant walls, jambs and lintels remain collision geometry. There are no
Bestine-specific object-name exceptions.

A further floor guard treated a disconnected overhead slope's infinite plane as
foot support and created an invisible lateral wall. Boundary constraints now
start from finite footprint contact and follow swept source adjacency.

## Verification

Run headless tests with `--xr-mode off`; these use the dummy renderer and do not
prove headset rendering. Evidence remains in ignored `runtime/evidence`.

- `terrain_source_topology_smoke.gd`: original eight-face fans and independent
  barycentric physical-height checks at positive and negative world locations.
- `tools/assets/validate_terrain.gd`: 2,249 independent Core3 height samples,
  source water/exclusion, seams and winding.
- `terrain_navigation_policy_smoke.gd`: tile passability, strip crossing, axis
  slide, swimming and wading support.
- `movement_reconciliation_smoke.gd`: explicit rejection versus accepted pose
  and travel ACK, preserved tracking, production logical-water spawn.
- `xr_starport_landing_smoke.gd`: actual streamed Bestine arrivals/departures,
  uphill/downhill, controller/room-scale, tracked pose and cell membership.
- `source_floor_portal_corridor_smoke.gd`: all 15 matching starport placements,
  open versus closed adjacency and retained unrelated walls.
- `source_floor_attachment_smoke.gd`: finite footprint/overhead-floor regression.
- `tools/server/movement_native_smoke.py`: disposable real-Core3 movement,
  saved location, limits, locks, parent validation and Tatooine water.

The catalogue-wide transition audit inventories candidates rather than claiming
every building has been physically traversed. The later authorized VPS migration
enabled the ten original ground planets; space and expansion planets remain out
of scope.

Verified on 2026-10-07: eight actual Bestine landing traversals; 586 shell checks
across 15 starports; 15 floor attachment checks; 29 source movement policy checks;
17 XR passability checks; six floor/terrain/water priority checks; and 19 real
Core3 movement checks passed. Original starport stairs also pass using the actual
native human 5.376m/s movement profile. Independent height comparison retains a
maximum error below 0.00008m across 2,249 samples. The combined verification index
is `runtime/evidence/navigation-verification.json`.

The former VPS received native movement patch 0068 after the local native checks.
Rollback state is `runtime/deploy/pre-movement-20261007T052202Z`; deployment
receipts are under `runtime/deploy/movement-live`. The update preserves realm
state and private configuration; that deployment was Tatooine-only. See
`VPS_DEPLOYMENT.md` for the subsequent ten-ground-planet migration.

## Core5 terrain and service corrections

Placed camps now install the height layers from their original shared template's
`terrainModificationFileName`, following the original client's
`ClientObjectTerrainModificationNotification` add/remove and transform behavior.
`tools/assets/prepare_dynamic_terrain.py` extracts the two authored camp `.lay`
files used by six camp templates, with source hashes. The normal launcher prepares
this catalogue when its Scout/housing inputs change. Unsupported height rules are
recorded as failures rather than replaced by a guessed flat radius. Current player
house templates have no such layer; native footprint placement rules still apply.

The client installs these layers at the native placed object's position and
heading. It replaces the immutable native terrain evaluator, updates the movement
solver's reference, and rebuilds affected streamed terrain chunks. Visuals,
collision, and logical foot support therefore use the same modified surface.
Movement waits for nearby dirty collision chunks; stale worker results cannot
restore the old surface. Removing a camp restores the underlying terrain.
This covers authored height modification, not the original client's flora editing.

### Placement verification, 8 October 2026

`tools/server/structure_placement_native_smoke.py` uses a disposable local Core3
character and the normal preview/place/camp/disband endpoints. Original small
Tatooine house, ore harvester and item factory deeds complete native construction.
Previews create no structure; out-of-range requests are rejected. House and
factory foundation heights match the native maximum over the source footprint;
the ground-snapped ore harvester matches the native center height. None of these
three templates declares a terrain height layer, so the client retains their
original foundation behavior instead of applying camp-style flattening.

All six original camp tiers deploy and disband. Their declared `poi_small.lay`
and `poi_medium.lay` layers level the client terrain. The native harness waits
for actual asynchronous camp destruction, not only disappearance from the area
snapshot, before deploying another camp. Rejections at occupied rural sites
retain Core3's building-proximity restriction. Fixture structures are removed
using the original destruction task, the helper is removed and the session is
saved and closed.

`structure_native_world_smoke.gd` replays the resulting native object rows
through production housing/camp presentation, original geometry and streamed
terrain. It checks native model elevations, source solid/null collision rules,
per-tier modified terrain collision, removal and source restoration. The factory
source has a NULL solid extent and fall-through floor; the replay does not invent
a solid body for it. `dynamic_terrain_smoke.gd` additionally levels a 12.01m
Tatooine height span with every camp tier and checks worker invalidation and
walking support. Rendered evidence and reports are in ignored
`runtime/evidence/structure-placement/`. These are local native and desktop
checks, not live headset validation or a VPS deployment. Factory production,
harvester extraction and a server restart are outside this placement check.

The recording also showed persistent movement rejection during house placement.
The rejected service path previously discarded the owned authoritative snapshot,
allowing the client and server positions to diverge. Patch 0076 marks movement
rejections on all native verbs; the adapter retains the correction in HTTP 400
responses. The global client API consumer applies only explicitly rejected,
owned, current-session snapshots through normal sequence validation. It does not
retry or approve the failed placement. The short placement notice expires;
native city, terrain, water, deed, range and zoning restrictions remain enforced.

The new dynamic terrain regression exercises real Tatooine/camp layers, physics
height, removal, worker invalidation and the existing movement solver. Housing
tests also cover transient movement notices without hiding native placement
restrictions. On 8 October the unrestricted build resolved a crafting snapshot
weak-reference compile error and the knife template's missing native player-race
equipment permissions. The linked server passes 30 Core5 native integration
checks and 19 native movement checks. The actual loopback HTTP correction path
also passes nine headless checks. Evidence is under
`runtime/evidence/core5-release`; deployment receipts are separate under
`runtime/deploy/core5-live`. These checks do not validate live VR or every native
housing placement restriction.

The live regression also restored instrument processing after session startup
and removed duplicate generic rendering of a shuttle already represented by its
complete original service appearance. Background native reads now share the
same fair admission budget during live combat, including Image Designer status.
Ordinary movement polls yield an eligible waiting service a scheduling turn;
otherwise a network round trip longer than the poll interval could starve all
later service controllers. The in-memory performance bus is excluded from native
request accounting. A real loopback HTTP regression with slow responses verifies
continued movement, service and entertainer polling with one optional native
request in flight.
Explicit unstarted busy replies use bounded command retries or a fresh movement
pose; ambiguous failures and the four-second stale-session timeout still stop
the session. The polling regression passes 19 checks with mocked HTTP responses.


## Movement hardening after the 8 October live probe

The authenticated Zevrion probe reproduced two independent faults: an ordinary
`/session/update` rejection lost its authoritative correction envelope, and a
following request inside Core3's one-second speed-check interval could temporarily
apply an excessive position. The probe accepted a 500m displacement through a
service request before restoring the prior validated position. Original evidence
is under `runtime/evidence/simulated-zevrion`, records 084, 086 and 090.

The native bridge now checks one shared per-character movement budget before
applying a submitted pose or performing a movement-bearing interaction. It charges
cumulative horizontal path distance using monotonic server time and native speed,
with a 0.25m initial allowance, 10% speed tolerance and at most two seconds of
stored movement. Rejected or duplicate packets cannot reset the budget or grant a
fresh distance tolerance. Ordinary elapsed time still accrues up to the cap.
Core3's original speed/state checks remain an additional guard; its subsecond
`TIME_VALIDATED` result alone cannot authorize a teleport.

Exterior and cell positions are compared in world-horizontal coordinates. Native
portal, permission, floor and movement-lock checks remain in place. Authorized
native teleports explicitly rebase the budget. Actual accepted horizontal/cell
changes and rebases advance a movement revision; unchanged poses and height-only
support differences do not. Queued requests capture this revision before waiting
for transport, preventing an older pose from undoing newer accepted movement.
Native request scope carries the revision separately from gameplay receipt
fingerprints, and existing action receipts are checked before movement validation.

Ordinary updates and service failures preserve the owned correction envelope,
including pose, cell, session and ordered server sequence. The client applies each
current correction once, discards stale combat input, and sends a fresh heartbeat
even when stationary. Duplicate or older corrections do not rewind the player or
close the session. Corrections do not automatically replay failed gameplay actions.
Corpse and gathering interactions also validate submitted movement before effects.

The terrain contract remains horizontal movement followed by resident terrain,
water or original FLR foot support. Corrections move the player origin and resolve
local support while leaving tracked head/hand transforms intact. This change does
not introduce terrain capsule blockers or change the repaired starport ramps.

Validation uses a pure C++ clock-controlled policy test, mocked HTTP client
recovery tests, actual native Core3 fixtures, and original-stage Bestine ramp
traversals. Evidence is recorded under `runtime/evidence/movement-budget`,
`runtime/evidence/movement-native-smoke.json`, and
`runtime/evidence/xr-bestine-landings.json`. Local desktop/headless checks do not
validate headset behavior. The live VPS has not received this change; a live VR
launch still requires the user's approval.

The accompanying character-summary fixture verifies native HAM, credits,
faction standings, unset home references, and armour equip/unequip updates.
Its optional house registration currently fails to enter the admin-spawned
building (`declaration_failed_4_parent_0`); available/removed residence resolution
is therefore explicitly skipped, not counted as a passing native check.
Available home display has Python/UI coverage, and both home references use the
original native character-sheet getters. Bound-clone registration was not
performed on the disposable character.
