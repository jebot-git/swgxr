# Persistent gameplay sessions

`POST /session/start` accepts authenticated account, character_id, source position `[x,y,z]` (Y up), heading_radians, building_id and cell_index. It retains an actual Core3 connection without requiring a weapon or enabling combat projection. Repeating start for the same owned gameplay character reuses its session; other character/combat ownership conflicts are rejected without eviction.

`POST /session/update` accepts session_id plus the same pose fields and optional original `vehicle_controls: {held,throttle,steer}`. It returns `source_kind: core3_gameplay_session`, character_id, session_id, session_live, location and `snapshot:{player,vehicles,transport}`. It does not return combat actors. Client updates keep the source connection alive; connection inactivity expires after60seconds. Native vehicle inputs separately expire after0.75seconds. Pause unrelated background requests while driving to keep controls fresh under the shared native command budget.

Services, gathering, crafting, medicine, scouting, inventory reads/mutations, corpse actions, datapad/weapon reads and waypoint mutations reuse this account-owned connection. Source replication refresh explicitly sends current owned baselines/attributes and filters responses by actual native ownership. There is no second login and no synthetic inventory or datapad store. Before a gameplay session exists, the original normal RPC path remains available.

`POST /inventory/status` accepts character_id and optional live_session_id. It returns the existing authoritative core3_inventory schema. When a native transaction already holds the request gate, inventory refresh immediately returns503 backend_busy; the client should preserve its last-confirmed readout while awaiting mutation acknowledgement. This is not a cached-server success and does not authorize another mutation against stale possession state.

`POST /session/logout` accepts character_id, latest source pose/cell/heading, a stable request_id, and optional live_session_id. Native Core3 saves source position before the retained connection closes. Response confirms `saved:true`, `session_closed:true`, and actual `location`. On invalid source-cell rejection the session remains active. Up to16 durable Core3 logout receipts preserve the acknowledged native exit pose on uncertain retries, including after the old connection closes. Seated logout uses the original native vehicle ejection and saves its actual grounded exit position; retrying cannot restore stale seat coordinates. `/enter` returns saved `source_location` and position_space `swg_world`, including original building/cell and world heading. Account authentication logout is a separate gateway operation.

Recorded remote requests during the observed video were individually bounded (median1.27s,max1.66s) but reached45processes/minute, saturating the single native lane. Retained gameplay connections remove those repeated login costs; client background admission still needs a shared budget. Evidence: runtime/evidence/session-20261005/remote-recording-latency.json.

`POST /session/life` accepts session_id and original action `recover` or `medical_transport`, with the same lightweight response. `sequence` carries the native ordering counter; snapshot.player includes authoritative HAM, posture, life state, XP and medical feedback. `/session/update` carries existing transport_ack without projecting combat actors.

The HTTP adapter releases its native transaction gate before encoding or transmitting a completed response. Slow TCP readers therefore cannot hold the native lane. Native mutation serialization and commit semantics remain intact.

## Multiplayer pilot capacity and persistence

The adapter defaults to ten retained native connections, one per account, shared
between gameplay and combat sessions. `SWGXR_MAX_NATIVE_SESSIONS` can set a lower
or higher admission limit from 1 through 16; invalid configuration fails startup.
Patch `0035-multiplayer-session-capacity.patch` raises the independent native
ceiling to 16. Both layers must be deployed before admitting more than four
players. Capacity rejection preserves existing connections. Expired native
processes are reaped before admission. The native 60-second inactivity cleanup
remains enabled; normal clients send movement updates or idle heartbeats.

This limit is an admission bound, not a demonstrated combat performance target.
With patch0038, an owned native start reply advertises
`native_concurrency:engine_cross_lock_v1`. Only those live owned sessions may
run `/session/update` outside the global adapter gate. Older binaries and all
other RPG requests retain the global gate (four waiting requests, three-second
admission deadline). Every account still has a separate bounded IPC gate and
0.275s source command spacing; admission failure preserves its healthy session.
Native Engine cross-locking releases a waiting player's lock while another
command snapshots it. The capability is never learned from client input, and
the HTTP gameplay envelope relays the actual native value. Ten simultaneous
drivers or rapid combat clients remain a separate load target; measure tail
latency and rejected reads before expanding a test.

The durable realm is Core3's MariaDB and BerkeleyDB state, plus the gateway's
account SQLite database. Native connection IDs, IPC files and adapter handles
are temporary and must not be restored as realm state. Clean logout explicitly
saves source location; an adapter or server restart requires a new connection.

Patch `0036-multiplayer-world-snapshot.patch` adds `snapshot.world` to normal
gameplay and combat responses. Its `source_kind` is `core3_world`, `full:true`,
with the native sequence and a 128 m radius. It contains at most 16 nearby online
players and 96 AI/lair actors, nearest first. Objects must share the observer's
original cell, or both be outdoors. `truncated:true` means this bounded view is
incomplete. This conservative cell filter is not a portal visibility graph.

Player rows contain native object ID/name, source world position and heading,
building/cell IDs, height, posture, death/incapacitation/combat state, target ID
and HAM. `appearance` contains original body and hair template/customization and
a complete equipped visual array with original slot names. Private inventory,
credits, skills and authentication data are absent. Equipment is capped at 32;
`equipment_complete:false` explicitly identifies overflow. Native AI/lair combat
targets remain separate from peer players; this does not enable PvP contacts.

`world.vehicles` is the existing native nearby vehicle array only, excluding the
observer's private datapad/seat wrapper. `world.deployments` contains at most 64
public tool anchors from the observer and nearby online owners' durable native
gathering ledgers. Entries contain original tool ID/template/customization,
owner ID, source ground position, sampling state and resource name. They do not
settle samples or expose escrow contents. `deployments_truncated` identifies
overflow. `deployment_visibility:"nearby_online_owners"` states the boundary:
offline or distant owners' tools are not a globally indexed world population.
Existing local dropped-item props likewise have no native shared-world store.

The separate `/session/sync` presentation lane overlays fresh, authenticated
tracking onto native visible peer IDs; it does not make movement, damage,
inventory or tracked poses durable realm data. Actual simultaneous native and
client rendering tests are required before claiming visual multiplayer works.

The private owner envelope also includes `snapshot.weapon`, the original native
equipped weapon profile or `null`; a weapon is not required to enter the RPG
session. `/combat/session/fire` and `/combat/session/impact` accept the same owned
gameplay session ID and retain original native readiness, item ownership,
certification, cadence, cost, LOS and target validation. The response remains
`core3_live_combat`; clients can reconcile its owned vitals and world without
starting a second session. Public cues are emitted only for confirmed native
actions, never for an unacknowledged visual projectile or client-reported damage.

Actual local tests: `tools/server/multiplayer_world_smoke.py` checks mutual native
visibility, original equipment, cell filtering, survey cues, deployed tool
anchors and pickup. `tools/server/multiplayer_combat_smoke.py` uses the existing
authorized ranged fixture to verify normal-session damage, peer cues and shared
lair condition. It creates/removes only an ephemeral test lair and grants no
skills or equipment. Both restore original fixture locations and log off; neither
validates live headset rendering or ten-user performance.

### Presentation sync contract

`POST /session/sync` requires the authenticated account's current `character_id`
and `session_id`. It bypasses the serialized native-command lane. Each request
contains an increasing integer `sequence` (at most 2^53), source Y-up `position`,
`heading_radians`, original `building_id` and `cell_index`, optional presentation
`physical_posture` (0–2), and `tracking` entries for `head`, `left_hand`, and
`right_hand`. Each entry has explicit `tracked` validity; valid entries contain
source-space `position` and normalized quaternion `rotation` [x,y,z,w]. Tracking
must remain within 3m of the body, and the body within 32m of its last native
anchor. These are bounded presentation checks, not authoritative movement or
anti-cheat validation. Native heartbeats and gameplay transactions remain required.

The reply echoes owned identity/sequence, `world_revision`, `poses`, `events`,
`event_sequence` and `pose_ttl_ms:750`. Passing the previously received
`world_revision` suppresses an unchanged world payload (`world:null`). A full
payload remains the native interest set; tracked data can never introduce another
player ID. Only same-zone peers in the native visible cells are eligible. Native
anchors expire after 15s; lost or old tracking falls back to native body/animation.
The client requests 10Hz with one request in flight; actual frequency is limited by
round-trip latency. Loading and medical transitions retain the monotonic request
sequence while the native session remains owned.

`event_sequence` is a public-action cursor, independent of pose sequence. Only
successful, non-replayed native transactions emit cues; damage, inventory,
credits and resource contents cannot be submitted through this route. Events are
retained for 5s in a 256-entry ring, with at most 64 returned per request. Survey,
deployment/recovery, accepted shots/contacts and selected life/RPG actions carry
public IDs and locations only. Fire includes the accepted original `weapon_id`;
impact retains that shot's weapon ID, allowing clients to select source effects
from known equipment rather than guessing a weapon. Unknown equipment visuals
are omitted. Native HAM, posture, equipment and actor state remain authoritative.

Normal client ranged combat binds the existing gameplay session and never opens
a second native login. It still requires the original owned/certified weapon,
confirmed launch before contact, native costs/cadence/LOS, and authoritative
target damage. This milestone does not add native melee/unarmed/PvP attacks.
Original avatar construction is cached for repeated appearances; first unique
appearances can still cause a main-thread hitch. Initial peers warm behind the
loading screen. No rendering or headset performance claim follows from protocol
simulation alone.
