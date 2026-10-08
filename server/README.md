# Local CoreCU adapter

CoreCU preserves pre-CU progression and profession structure while pursuing CU-inspired balance and combat feel. Advanced profession abilities remain provisional skeletons for later definition.

This prototype stores accounts and characters in CoreCU, the local SWGEmu Core3 combat fork. The Python adapter
invokes the pinned upstream `core3client` action framework inside an isolated
Podman container; it does not maintain an imitation character database.

The build produces `corecu` and a `core3` compatibility copy for existing launchers.
Health responses identify `backend_name: CoreCU`; the existing `backend: core3`
tag and database/configuration paths remain compatible. See
[CoreCU combat policy](../docs/CORECU_COMBAT.md) and [fork identity](CORECU.json).

`server/upstream.json` records revisions. `server/patches` contains the complete
source modifications. `tools/configure_core3.py` reapplies those patches and
selects only the locally available TRE archives for a bounded Tatooine profile.

## Startup

Use `./run.sh` from the repository root for the prepared client and services.
For backend-only startup, after the root setup workflow has extracted and
activated the user-provided archives in `runtime/assets/active_tre`:

```sh
tools/server/provision.sh
python3 tools/configure_core3.py
tools/server/start-core3.sh
python3 server/adapter.py
```

Provisioning creates `swgxr-core3-build`, a private container with no published
ports, installs dependencies, and builds Core3 plus Engine3. Host packages are
not modified. The first build uses 12 jobs by default (`SWGXR_BUILD_JOBS`).
The HTTP adapter listens only on `127.0.0.1:18080` and rejects browser Origin
headers. This is a local developer API, not a production authentication service.
Accounts are local aliases; internally generated credentials live in the ignored,
permission-restricted `runtime/server/adapter.secret` file. Preserve that file
with the databases: replacing it changes the generated account passwords.

## API

- `GET /health` verifies actual Core3 login and a zone connection. Inspect
  `core3.ready` and `core3.detail`; HTTP 200 by itself does not mean ready.
- `GET /creation-options` returns all 10 original species / 20 sex variants,
  six starting professions, actual customization paths/ranges/defaults, allowed
  original hairstyles, palette colors and race height bounds.
- `GET /characters?account=prototype` obtains a fresh Core3 character list,
  including actual race and sex decoded from the login template CRC.
- `GET /characters/{id}?account=prototype` selects the owned character through
  Core3 and reads its authoritative appearance, equipped items, skills and biography.
- `POST /characters` accepts `account`, `name`, `species`, `sex`, `profession`,
  `height`, `biography`, `customization`, `hair_template` and `hair_customization`.
  Customization maps use the exact full variable paths from `/creation-options`.
  Legacy `species:"human_male"` also works. The response is obtained through a
  fresh Core3 login and zone selection after creation, rather than echoing inputs.
- `POST /enter` with `{"account":"prototype","character_id":"..."}` validates
  ownership, selects that character in Core3, and waits for its scene. Object IDs
  are JSON strings to preserve 64-bit precision in clients.

`/enter.character` and character detail responses include `appearance` with
actual body and hair customization maps plus their original encoded hex bytes,
height, shared template paths and equipped object IDs/templates/customization.
They are decoded from Core3 scene creation, containment and CREO/TANO baselines;
biography is read with the original object-controller request. `skills` comes
from CREO baseline 1. `profession` is inferred from the six novice skills and is
null when several apply; it does not claim to recover a historical starter choice.
There is no appearance sidecar database. Original empty customization strings
remain empty; renderers use the original asset defaults for omitted variables.

Options use the original ACST IRNG/DEFV range/default registry and CIDM variable
IDs, original PAL color data, `palette_columns.iff` creation color limits,
`hair_assets_skill_mods.iff` availability, and PFDT profession definitions.
Heights use the original shared template range; the neutral UI default is its
midpoint, explicitly labelled as a derived default. Only successfully converted
hairstyles are offered. Core3 applies its original name rules; the local adapter
also bounds input sizes and limits biographies to 4096 characters.

`core3_scene` contains the authoritative entry scene received from Core3.
`position` uses Godot stage coordinates. The adapter then disconnects its Core3
session: movement and environment collision are local Godot prototype behavior.
This is not yet a networked Godot zone simulation or persistent movement bridge.

`/enter.combat_snapshot` now also decodes the selected creature's original HAM,
wounds, shock wounds, posture and target/weapon IDs. It explicitly reports
`live:false`: it does not turn the short entry session into ongoing combat.
Patch `0018-combat-target-baselines.patch` captures CREO/TANO baseline 6 for this
readback; the running `core3client` must be rebuilt to supply it. With an older
binary the observation is marked incomplete and no HAM values are invented.
`python3 tools/server/combat_protocol_smoke.py` checks the wire layouts, all nine
attributes, ordered list updates, posture-driven incap/death state, lair condition,
truncation rejection, 64-bit IDs and an archived actual Core3 baseline.

`python3 tools/server/export_combat_population.py` indexes the source Tatooine
regions, lair registrations, mobile definitions and appearance dependencies.
This is asset preparation, not a live population or an alternate spawn engine.
For bounded initial conversion:

```sh
python3 tools/server/export_combat_population.py --group tatooine_mos_eisley_easy_newbie --out runtime/assets/combat_population/mos_eisley_easy
python3 tools/assets/prepare_npcs.py --placements runtime/assets/combat_population/mos_eisley_easy/appearance_requests.json --out runtime/assets/combat_population/mos_eisley_easy
```

`python3 tools/server/simulate_combat_approach.py` runs a controlled, source-derived
approach experiment for a kreetle and CDEF-rifle desert demon marksman against
standing, retreating and strafing players. It outputs JSON, CSV traces and a PNG
under `runtime/evidence/ai-approach`. This does not execute Core3's behavior tree,
combat queue, pathfinder or damage system. See the assumptions in `report.json`.

The tested final profile selects all 51 archives in the pinned Core3 pre-CU
configuration. They come from the original three discs, Jump to Lightspeed, and
the five Total Experience discs. Seven later/CU archives are excluded by the
asset allowlist. Original extracted files are preserved; `active_tre` contains
traceable links. See `runtime/server/media-profile.json` for the exact selection.

Only Tatooine is enabled. Space initialization is deliberately disabled. The
spawn patch sends new characters directly to the Mos Eisley starport coordinates
in the Core3 world. Compatibility patches support older slot definitions, locate
resource-table fields by name, and guard unavailable snapshot objects and
container components. Client-side patches await authenticated zone permissions
and record the actual scene identity/coordinates. They do not implement a new
movement protocol. Further client patches capture appearance and biography over
existing messages. A narrow Core3 fix escapes signed customization low bytes
correctly (for example female chest morph `-1`), preserving roundtrip decoding.

Core3's resource, market, and city managers initialize in this configuration.
Their broader RPG workflows have **not** been functionally validated. The proved
scope is character creation, fresh listing, selection, Tatooine entry, and disk
persistence, followed by local Godot locomotion/collision.

Run `python3 tools/server/smoke.py` for live create/list/enter validation. The
report is written to `runtime/server/smoke-report.json`. It fails visibly when
Core3 is unavailable and never substitutes offline data.

Run `python3 tools/server/appearance_smoke.py` for a real customized Twi’lek
Medic creation, subsequent independent logins, skill/body/hair/biography readback,
and equipment verification. This creates a test character; use `--account` and
`--expect-id` to recheck the same ID. No server restart is needed for that test.

Observed proof files:

- `runtime/server/appearance-roundtrip.json`: customized Twi’lek female Medic,
  signed `-1` chest morph, skin/hair colors, height, biography and actual clothing
  retained across separate creation, detail and entry protocol sessions.
- `runtime/server/appearance-first-disk-persistence.json`: the first customized
  character retained its body/hair bytes, skills and biography through a full
  graceful Core3 process restart.
- `runtime/server/creation-catalog-validation.json`: all 20 race defaults/ranges,
  signed/escaped wire endpoints and invalid input rejection checks.

- `runtime/server/smoke-created-character.json`: initial real Core3 creation.
- `runtime/server/smoke-persistence-tavren.json`: exact character ID retained
  through graceful database save and full server-process restart.
- `runtime/server/smoke-persistence-godot.json`: the character originally created
  through Godot also retained its exact ID and re-entered after that restart.

For a repeat persistence check without silently creating a replacement:

```sh
python3 tools/server/smoke.py --account viability --name Tavren \
  --expect-id 281474993517524 --report smoke-persistence-tavren.json
```

## Persistence and shutdown

MariaDB lives in `runtime/server/mysql`; Core3's Berkeley DB files live in
`vendor/Core3/MMOCoreORB/bin/databases`. Preserve both when rebuilding. Never use
Core3's `clean` command for a server whose characters should be retained.

`tools/server/stop-core3.sh` requests Core3's graceful `exit` through its console
FIFO so state can be saved. The container and MariaDB remain running. Check
`runtime/server/core3-console.log` for completion before stopping the container.

Core3/Engine3 retain their upstream licenses. Keep source patches and notices
with any distribution; user-owned game assets are never bundled here.

## Datapad and waypoints

`GET /datapad?account=...&character_id=...` reads the selected character's actual
Core3 datapad container, PLAY8 waypoints and PLAY9 learned draft schematics.
`/enter` also returns this object as `datapad`. IDs remain strings. Entry
categories are `waypoints`, `data`, `vehicles`, `pets`, and `schematics`.
Learned recipes identify themselves as `core3_player_schematic_list`; these are
not physical manufacturing schematic objects. Unknown display names fall back
to a readable template filename, retaining the original template and StringId.

`POST /waypoints` accepts `{account, character_id, name, planet:"tatooine",
position:{x,y,z}}` in canonical SWG world coordinates, with Y as elevation.
The adapter sends Core3's ordinary `requestwaypointatposition` command and only
reports success after another authenticated session receives the newly created
persistent waypoint. Returned positions are `[x,y,z]` arrays. Names currently
support 1–64 printable ASCII characters. Reads have a 30-second protocol bound;
creation has a 45-second total protocol bound. A failed confirmation asks the
client to refresh before retrying because the command might already have saved.
There is no local waypoint database and no automatic mutation retry.

The observed new Artisan has 30 learned recipes and, after the initial grant
runs, an actual helper R2 pet control device. The starting X31 vehicle deed is
in inventory; it is not presented as a redeemed vehicle in the datapad.
Waypoints are initially empty. Grants always come from actual Core3 readback.

Run `python3 tools/server/datapad_smoke.py` to create a dedicated test character,
create one waypoint, verify it across fresh login and entry, and reject invalid
coordinates. `--fixture runtime/server/datapad-fixture.json` reuses only that
explicit diagnostic fixture and adds one waypoint. Evidence is written to
`runtime/evidence/datapad-http-smoke.json`. These checks do not restart Core3;
fresh-session persistence is verified, not a new server-restart test.


### Weapon profiles and datapad deletion

`GET /weapons?account=<account>&character_id=<id>` reads owned weapon attributes
through an authenticated Core3 session. `/enter.weapon_snapshot` has the same
schema: `profile_version`, `balance_revision`, `weapons`, and
`unsupported_item_ids`. Supported weapon records carry a string `item_id`,
`source_kind: core3_weapon_instance`, resolved `rpm`/`capacity` for ranged or
`kind: melee` with `stance_recovery`/`power`, `crafting_raw`,
`crafting_modifiers`, `condition` and the actual certification decision. Unsupported
weapons are listed explicitly. Ownership, missing replies and stale build/balance
revisions fail closed. Combat remains local; this endpoint does not authorize
persistent damage or ammunition writes. See `docs/COMBAT.md` for conversion rules.

`POST /datapad/delete` accepts `{account, character_id, entry_id}`. A fresh owned
datapad read must mark the entry `deletable`; the adapter then sends the normal
`serverdestroyobject` command with the scoped `swgxr_datapad` argument. Core3 checks
live ownership/container membership, static/mission restrictions, special
waypoint type and its existing destruction permissions. Learned recipes and local
POIs are never targets. Protected or active control devices may reject deletion.
A subsequent authenticated login must prove removal before success is returned.
Deletion capabilities are refreshed by `GET /datapad`; initial `/enter` entries
default to protected until this owner-only attribute read completes.
No local database or optimistic permanent UI removal is used.

The UI's waypoint target is set only by a map click, not by automatically selecting
an existing list entry. The selected target survives switching between map/list.
“Use my position” clears it, restoring player-position creation. Map clicks use
terrain elevation when saved; the player's position retains its actual elevation.
The detail pane enables deletion only for server-authorized removable entries.

`client/tests/datapad_http_main_smoke.gd` verifies create/delete/fresh-login readback
through real main UI handlers on its dedicated fixture. The UI smoke exercises
actual click events, fallback, selection persistence, busy gating and protected
entry rejection. Desktop capture tests require Forward+ Vulkan and `--xr-mode off`.

Melee profiles use balance version 2 and patch `0016-melee-crafting-profile.patch`.
Attack-delay crafting improvements drive Stance recovery; attack-cost improvements
drive Power with the existing bounded conversion. `python3 tools/server/melee_weapon_smoke.py`
reads the existing diagnostic Artisan fixture and verifies its actual owned knife
across fresh logins and entry. It does not modify crafted stats or apply combat damage.

`weapon_snapshot.unarmed` (also in `GET /weapons`) resolves Strength, Quickness and
actual `unarmed_damage`/`unarmed_speed` totals from selected-player CREO baselines
1/4. Patch `0017-player-combat-baseline.patch` requires rebuilding core3client.
No new server database fields or synthetic item are used. Conversion tuning lives
in `server/combat/unarmed_balance.json`; missing player baselines fail closed.
`python3 tools/server/unarmed_smoke.py` creates/reuses a dedicated Brawler fixture
and verifies actual player stats across fresh sessions and entry.

Profession translation adds `profession` modifiers and the eligible `abilities`
list to each weapon/unarmed profile. `player_combat` carries observed current HAM
from CREO6 and remains explicitly `local_prediction_only`. Missing current HAM
disables ability priming; base HAM is never substituted. Class cooldown progression
uses learned skill boxes, independently from transient accuracy/speed totals.
Original command damage and SAC multipliers are parsed from the pinned Lua source.
The source aliases, provisional coefficients and authority limits are documented
in [COMBAT.md](../docs/COMBAT.md#profession-translation-and-primed-master-abilities).
`python3 tools/server/profession_smoke.py` checks the translation and creates an
explicit synthetic frontend test fixture; it grants nothing in Core3.

Scout commands, native receipts, gesture controls and the persistent live-session bridge are described in [SCOUT_PROTOCOL.md](SCOUT_PROTOCOL.md). Rebuild Core3 after applying `0025-scout.patch`.

## Basic Medic and recipient feedback

`POST /medic/{status,provision,select,heal,holster,return_tool,drag}` operates on an
owned native character. A live account must supply its existing `session_id`;
no second login is opened. The focus uses the original medikit inventory object,
rendered in VR with the original generic stimpack model. Provisioning is an
idempotent, once-per-character starter focus for a learned Medic and requires
inventory capacity. It does not provide consumable medicine.

Heal Damage, Heal Wound, Tend Damage, Tend Wound, First Aid and Quick Heal retain
the source learned abilities, medicine requirements, HAM/wound costs, range,
medical environment checks and pending treatment recovery. Diagnose is excluded.
The selected medical command is saved separately in native player screenplay
data. Healing never teleports to an old request position, captures locomotion or
waits for a character animation. Ordinary live movement continues during healing
and recovery. Primary weapon abilities remain independent.

`state.abilities` includes native `range_m`, `area_radius_m`, `medicine_id` and
remaining `cooldown_seconds`. Area radius is from the stim selected by the source
HealDamage command; single-target treatments report zero. The client selects the
first eligible, injured/wounded/bleeding player along its independent stimpack
reticle, respects world occlusion and source range, and submits an explicit
`target_id`. Missing a recipient does not silently self-heal. Aim at your own
body for self-treatment. The thin area perimeter follows available ground around
the selected recipient, without drawing across unsupported ledges.

Native medical scopes record actual positive healing/wound changes for every
recipient, including AoE recipients. Native damage records exclude self-paid HAM
costs by object identity. Owner snapshots expose bounded presentation sequence
counters; they cannot apply damage, healing or rewards. Initial, duplicate and
stale events are suppressed by the client. The local view uses a short soft
peripheral pulse with a clear center: cyan-green healing and muted red damage,
with no shake, blur or full-screen flash. Captures use Forward+ Vulkan; headless
checks use the dummy renderer with XR off.

Offhand grip retrieves a hip medical focus. A focus picked from the bag with the
main hand can be handed to the offhand by gripping near it after closing the bag.
Offhand stick click opens/closes the independent wheel when no weapon is held;
offhand trigger activates its selected heal. Stowing preserves selection.

Dragging uses native `science_medic_injury_speed_02`, two hand contacts against
posed original avatar bones, fresh patient tracking, native incapacitation and
eligibility, bounded hand displacement, source floor/collision queries, and a
short exclusive lease. Crossing arms cancels the lease and rejects further grabs
while crossed. Releasing either grip, tracking loss or recovery stops dragging.
The current native drag movement path supports outdoor ground; indoor drag
floor/cell transitions reject safely. No animation drives tracked controllers.

Reproduction and evidence:

- `python tools/medic/prepare_assets.py`: supplied-media models/icons and hash catalogs.
- `tools/medic/update_patch.py`: patch `0027-medic.patch`, separate from terminal work.
- `python -m unittest tests.test_medic_protocol`: protocol rejection checks.
- `godot --headless --xr-mode off --path client --script res://tests/medic_smoke.gd`.
- `tools/medic/fixture.py`, then `tools/medic/live_smoke.py`, then fixture `--restore`:
  strictly scoped disposable native accounts; real healing, supply consumption,
  movement during recovery, both-party feedback, drag displacement/cancellation
  and the original 15 m area stim. Fixture restoration removes only its own Lua block.
- `runtime/evidence/medic-core3.json`, `medic-client.json`, and
  `medic-{neutral,heal,damage}-vulkan.png`.
- Actual starport XR movement: 12 cases pass in `runtime/logs/medic-xr-starport.log`;
  full mocked XR entry also passes. The older desktop `--smoke-test` still fails
  its infinite-wall clearance assertion after selecting a small terminal as its
  obstacle (`runtime/logs/medic-stage-movement.log`); that test was not changed.

No live headset validation is claimed.

## VR vehicles

`0030-vr-vehicles.patch` adds a native vehicle facade to the existing authenticated
live session. `POST /vehicles/{status,call,board,dismount,store}` requires that
session and its owned character. Legacy live updates carry bounded
`vehicle_controls: {held, throttle, steer}`. Prepared patch
`0058-client-vehicle-motion.patch` advertises `driver_motion: "client_pose"`
and accepts the owned driver's collision-resolved `vehicle_id`, `position`,
`heading_radians`, and `speed`, while retaining native seat ownership, condition,
and speed limits. The client switches only after this capability is advertised;
older servers retain their legacy control integration. The new Core3 patch now
compiles and passes 14 running local Core3 checks, including passenger replication,
rejected foreign/speed/boundary inputs, stale stopping and legacy controls
(`python3 tools/vehicles/client_motion_smoke.py`). The Tatooine-only VPS deployment
and authenticated HTTPS capability/session checks passed on 2026-10-05; VR testing
was skipped at the user's request. Snapshots contain nearby vehicles, persistent native control
devices, seat occupants, source movement statistics, and forced-exit revisions.
The adapter never owns a parallel vehicle inventory.

Calling/storage use original `VehicleControlDevice` operations, including the
source outside/at-peace restrictions and wilderness call delay. Only owners can
drive or store; nonhostile players can use an empty passenger seat. The VR seat
reservation replaces legacy single-rider containment so passengers and tools
work without imposing mount animation or command restrictions on tracked arms.
Native condition/decay, run/walk speed, acceleration and turn rate persist.
Reverse uses native walk speed. In legacy mode, input release/staleness brakes;
native source terrain, world boundaries and hull-corner collision sweeps constrain
movement. With the negotiated client-pose mode, local resident terrain and source
solid hull sweeps resolve driver motion, without delayed server control echoes. Shuttle
boarding requires dismounting first. Vehicle-shot origin validation allows a
bounded speed-dependent presentation delay, without increasing weapon range.

Driver/passenger positions come from supplied-media saddle art: the invisible
`pv_*` skeleton alone is not a vehicle model. The importer follows original
logical saddle/appearance/rider-pose tables, preserves meters, extracts the
`player` hardpoint, and derives control contacts from original human rider hand
poses. Six supported templates are Speederbike, Swoop, Flash, X31, X34 and AV21.
Flash is a landspeeder despite its internal `speederbike_flash` template name.
Pre-CU source tables contain one rider. The second visible landspeeder cockpit
seat is a labelled VR extension mirrored from the original driver hardpoint;
single-seat bikes do not gain invented passenger seats. No original assets are
committed. Hashes and conversion failures stay in ignored
`runtime/assets/vehicles/catalog.json`.

The body and pelvis remain attached to the seat. Only the XR origin follows the
vehicle: local tracked head/controller transforms are untouched. A native
critically damped vehicle-frame filter bounds correction acceleration. The
rendered vehicle, seat, body and camera use the same render-frame pose; a fixed
seat-local origin prevents cumulative transform drift. Riding does not falsely
count the low seat-relative head height as crouching/prone combat bonuses.
Driver grips bind the corresponding original left/right model contacts regardless
of controller reach. Landspeeder push/pull along model Z controls throttle/brake;
the original wheel-plane arc steers vehicle yaw without lateral strafing. Bikes
retain wrist-twist throttle and their original handlebar geometry pivots around
model UP, moving opposing grips fore/aft. All six source steering assemblies move.
Controls retain their state while either grip is held, including hand transfers.
Both released grips restore neutral. Tracking/focus loss suspends output and
preserves the latched visual pose; reacquisition rebases without an input jump.
A valid physical release still detaches while a menu blocks driving. Only avatar
hand bones snap to the source contacts; HMD/controller tracking stays untouched.
Driver controls reserve only the gripping hand, preserving the existing weapon,
medical focus and inventory interactions in free hands. Jump dismount takes
priority over the offhand medical wheel while seated.

Native DEAD and INCAPACITATED both release the reservation and place the occupant
on supported ground without changing HAM or life state. Ejection is reconciled
on the next live vehicle update/snapshot; the driver’s motion stops, while a
conscious other occupant remains seated. Missing vehicles, ownership changes
and disconnected riders also release reservations. Forced-exit revisions ensure
clients apply each authoritative relocation once. Source animations only pose
the untracked rider body; bounded arm IK remains active.

Validation/reproduction:

- `python tools/vehicles/prepare_assets.py` imports source art/poses and provenance.
- `tools/client/build_native.sh`, `python tools/vehicles/update_patch.py`, and
  `tools/server/build.sh` rebuild native controls, the patch and Core3.
- `python -m unittest discover -s tests -p 'test_vehicles_protocol.py'`: 5 tests.
- `godot --headless --xr-mode off --path client --script res://tests/vehicles_smoke.gd`:
  20 control/protocol-integration/synthetic jitter checks. The simulated 90 Hz,
  delayed-snapshot case reduces speed variation by about 87%; it is not an HMD test.
- `vehicles_xr_smoke.gd` uses the real XR rig and source rider avatar with mocked
  tracking/network data. `-- --driver` checks a single driving grip. Headless uses
  the dummy renderer. For desktop GPU evidence, explicitly use `--xr-mode off
  --rendering-method forward_plus --rendering-driver vulkan` and `-- --capture
  --driver`. It checks completed render frames, fixed seat/pelvis alignment,
  direct head tracking, locomotion lock and deduplicated forced ejection.
- `python tools/vehicles/fixture.py`, `python tools/vehicles/live_smoke.py`, and
  `python tools/vehicles/life_smoke.py` use only isolated `invtestvehicle*`
  characters. 23 actual-Core3 ownership/seat/movement/storage checks and 12
  ejection checks pass. Life checks set controlled native life postures; they
  test ejection, not damage/knockout/death-rule calculations. Run fixture
  `--restore` afterward to remove only this feature’s marked Lua block.
- Evidence: `runtime/evidence/vehicles-{core3,ejection-core3,client}.json`,
  `vehicles-xr-driver-{mocked,vulkan}.json`, and `vehicles-driver-*-vulkan.png`.
  Completed Vulkan frames keep seat/camera and pelvis alignment below 0.01 mm.
- All 12 actual-stage starport XR movement cases and full mocked XR entry pass
  (`runtime/logs/vehicles-xr-stage.log`, `vehicles-xr-main.log`).

Forward+ Vulkan is the supported render target. No live headset comfort or
live-controller driving validation is claimed. Original engine audio/effect
playback and vehicle customization are not part of this baseline.
