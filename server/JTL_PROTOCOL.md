# Noncombat Yacht test protocol

`POST /jtl/<action>` requires an authenticated account, its owned `character_id`, and its current native `session_id` (or `live_session_id`). There is no offline ship store or client-authoritative ship pose. The adapter sends a bounded `jtl` intent through the existing native live session. Responses contain `source_kind: core3_jtl`, `character_id`, `state`, `mutation`, and `live_response` with the original authoritative session envelope.

The initial package enables only `space_tatooine`. Ground APIs retain their ten-planet validation. The first existing/created character by native creation date receives an original Sorosuub Luxury Yacht, backed by an account receipt, native ShipObject, POB cells and ShipControlDevice. Later characters cannot claim it, and deleting the granted ship does not earn a replacement. This is a test grant, not a general ship purchasing or pilot progression system.

| Action | Additional request fields |
| --- | --- |
| `status` | None |
| `crew_prepare` | Nearby original starship `terminal_id`; optional owned `ship_id` |
| `crew_join` | `pilot_id`, native `launch_id`, observed `crew_handshake_id` |
| `crew_remove` | `member_id`, pilot only |
| `crew_cancel` | None |
| `launch` | Original `terminal_id` and prepared `launch_id` |
| `boarding_request` | Nearby `target_ship_id` |
| `boarding_accept`, `boarding_decline` | `requester_id`, receiving pilot only |
| `return_ship` | None; requires the native parked-ship receipt |
| `land`, `leave` | None |
| `station` | `station_id`: `pilot` or `passenger` |
| `control` | Increasing `sequence`; throttle 0–1 and pitch/yaw/roll −1–1 |
| `walk` | Increasing `sequence`, local `position`, original `cell_index` 1–11 |
| `decorate` | `item_id`, `cell_index`, `placement_position`, unit `local_quaternion` XYZW, boolean `suspended` |
| `recover` | `item_id`, `left_hand`, `right_hand` in ship-local coordinates |
| `command` | `command_id`; elevator commands also need original `interaction_id` |

Every action except status/control/walk requires a stable 8–64-character `request_id`. Retries must retain the same intent and ID. Controls and walking use separate increasing sequences. Coordinates are source X, up, Z; client rendering mirrors Z. Ship-local request coordinates are bounded to ±64 m. Native ownership, station, reach, floor, portal and collision checks remain authoritative.

Rejected native JtL intents return HTTP 400 with `ok:false`, the typed JtL snapshot and `live_response`. A guest's old control packet can be rejected after another pilot approves boarding or disconnects; the same response must still move that guest's view to the actual ship or ground destination. Generic transport failures trigger a status refresh before further controls. Public crew appearances are decoded through the same original template/customization path as ground players.

Launch requires the original starship terminal in the same ground cell, within eight metres and line of sight. Selecting a ship opens a second confirmation with a separate Launch button and clickable crew names for removal. A free, tracked, mutually gripped handshake with the preparing pilot enrolls a passenger. The gesture must begin after preparation, following observed separation or grip release; contact lasts at least 250 ms. The adapter binds a consumed proof to that pilot, passenger, launch and request. It cannot authorize party formation or payment. Native code independently rechecks proximity, the current preparation, readiness and capacity. Walking away cancels preparation. Crew formation does not require a party.

No separate authored Yacht passenger maximum exists in the pinned Core3 source. The prototype preserves the original group-launch limit of 20 people including its pilot, reported as `original_group_launch_limit`; this is separate from the 100-decoration limit. Original single-seat fighters take one pilot, and the supported two-seat fighter takes one pilot and one gunner. Original pilot certifications and owned control devices remain required. `Core3.JTL.SwgxrShipTemplates` enables only the eleven small-craft templates with converted original cockpit and exterior assets in `server/jtl_catalog.py`; no extra tester ships or certifications are granted.

Native source component statistics bound speed, acceleration and rotation. Controls supply neither elapsed time nor ship statistics. A stalled connection cannot accumulate catch-up movement. The original Tatooine station remains a navigation landmark; ship collision, station docking, combat missions and space combat are outside this implementation.

An eligible small ship can request boarding while both ships are stopped within 256 metres. The receiving POB pilot approves or declines. The authority rechecks range, speed, capacity and occupancy when accepting. A POB or gunship cannot board another POB. A multiseat fighter cannot board with an occupied gunner seat; the visitor must be its only occupant. Approval stores the visitor's existing ship in its owned control device and moves its pilot aboard the POB. A temporary datapad action is backed by native parked-ship state, without duplicating a ship or control device. Returning launches that same ship near the POB. Requests do not grant docking authority beyond their original ship, pilots and current sessions.

The pilot command wheel offers front/rear/balanced shields and engine/balanced power. Native learned droid programs remain capability gated; the stock Yacht has no droid interface, so its droid commands are unavailable. Original elevator panels invoke the original native up/down actions. Cockpit boarding and leaving move the player body reference while HMD and controller poses remain tracked.

POB furnishing calls the same native furnishing helper as ground houses. The original Yacht limit is 100 player items. Original item eligibility, capacity, permission, reach, floor snapping, suspension, line of sight, unit rotation, and two-hand recovery rules apply. Original fixed ship fixtures are not player decorations. Ship objects, inventory transfers and decorations persist through Core3.

Ordinary landing returns the ship and crew to the recorded ground launch arrival. Disconnecting passengers are ejected to the ground; disconnecting the captain ejects the whole crew and stores the host ship. Parked visitors keep their original ship in their datapad and lose the temporary return action. Native unload and session-expiry recovery handle abrupt loss; reconnect does not resume flight. The single original `space_tatooine` station serves several ground cities with no unique space-distance city mapping. Disconnect recovery therefore uses its original Mos Eisley landing anchor, resolved to the native interplanetary arrival, as an explicit fallback.

Successful status/control/walk calls can include `presentation` with increasing `sequence`, ship-local `position`, `cell_index`, `heading_radians`, `physical_posture` and head/hand `tracking`. The adapter returns `crew_poses` with a 750 ms lifetime, filtered against the recipient's native ship, cell and crew roster. Tracking cannot add crew, move native bodies, override appearance or authorize ship actions. Rejected tracking does not invalidate an already committed native action. HMD and hand local transforms remain tracking-owned.

Walkable POB interiors render the shared crew. Small-craft rosters and occupied-seat authority are active, but other seated avatars are omitted because distinct original gunner viewpoint/seat anchors have not been sourced. They are not stacked into the pilot cockpit at the same coordinates.

Voice remains available aboard. The native snapshot supplies the actual sector and hull for owners and guests. Sector replaces Planet while in space; proximity requires the same hull and uses its local coordinates. Group voice retains ordinary native party membership. Boarding, return, landing and disconnect invalidate old audio queues and wait for the relay's authoritative context before resuming the selected microphone mode. See [VOICE_PROTOCOL.md](VOICE_PROTOCOL.md) for routing and verification limits.

The staged profile is `corecu-all-planets-jtl-test-12cpu-24gb`. It keeps the ten ground planets, enables only the test space zone, disables its combat spawns, and prepares registration without invitations. Preparing it does not modify the running realm. A current linked native build, actual account/ship persistence checks and live VR validation are still required before release readiness can be claimed.

The profile also sets `Core3.SWGXR.RetailGroundOnly=false`; the earlier prototype flag otherwise skips ShipManager initialization even when JtL is enabled. `tools/configure_core3.py --jtl` sets the same flag. Ground-only profiles retain their original scope.

Flight uses a native 50 ms task and held throttle/pitch/yaw/roll inputs. It integrates three-dimensional ship pose using original engine statistics independently of request arrival cadence. A 1.5-second control lease stops the ship on input loss; disconnected/unpiloted/stored ships cannot continue receiving flight ticks. No ground movement or terrain rules apply to flight. Player walking inside original POB rooms separately uses native character run speed, a bounded two-second distance budget, room connectivity, floor and wall checks.

Rendering ignores duplicate ship snapshots and blends across measured receipt intervals, with at most 350 ms of visual velocity extrapolation. This presentation never moves the physics body or submits ship position. The spectator camera shares the headset camera’s local space environment and restores the ground environment on return. Recovery confirms the current native ship room before transferring a decoration back to inventory.
