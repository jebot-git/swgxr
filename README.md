# SWGXR rough prototype

VR-first Godot/OpenXR client, chunk-streamed Tatooine and Mos Eisley starport, and a local
Core3/Engine3 character backend. Original SWG media and converted game assets stay
on this machine in ignored directories.

The client creates and selects persistent Core3 characters, then retains a native
connection for inventory, services, resource gathering, crafting and vehicles.
Godot handles tracked movement and environmental collision locally; source poses
are synchronized to Core3. Normal gameplay projects nearby native players,
equipment, creatures, lairs and deployed tools, with a separate head/hand pose
channel. Certified ranged combat uses the same owned native session. Shared
actions come from Core3 confirmations; survey success produces a bounded visible
ground pulse. This remains a prototype, not a demonstrated MMO combat capacity
result. See [session ownership and persistence](server/SESSION_PROTOCOL.md).

Menus, holographic panels and world labels use the CC0 Jupiteroid family, including
matching bold and italic styles. Font provenance and license are in
[the font bundle](client/resources/fonts/README.md). The global theme also reaches
unmodified XR Tools controls.

## Start

The prepared workspace can be launched from this directory:

```sh
./run.sh
```

With the installed remote profile, choose **Create account** or **Sign in**.
For the preconfigured `blux` account, choose **Set password** once to retain its
identity and replace the old access token. Passwords require12–128 characters.
**Remember login** saves a revocable 90-day login token in the game's local
`user://remembered_logins.json` file. Copy this private data file alongside the
server profile and CA to carry the saved login to another installation.
**Forget saved login** revokes it on the server and removes it locally. Passwords
are never saved; short-lived gameplay sessions remain in memory. Character creation
becomes available after sign-in and native Core3 readiness. **Log off** saves the
current source position and interior, closes the character connection, and returns
to character selection. **Quit** saves first when a character is loaded. An
unconfirmed save leaves the menu open for an explicit retry. **Sign out** ends
the session from character selection. See [remote accounts](docs/REMOTE_NETWORKING.md).
The explicit `--local` option selects the trusted loopback development backend.

Character creation dropdowns open inside the menu canvas. Point and trigger to
select; hold trigger and drag the list, or use either joystick while pointing at
the menu, to scroll. The open dropdown takes priority over the page underneath.
Desktop mouse-wheel scrolling is also supported. Changing tabs, closing the menu
or losing focus closes open lists and cancels drag gestures.

Delivery and crafting missions share a parcel handoff. Approach the giving NPC,
press the main-hand trigger, and confirm in the holographic dialogue. Crafting
missions first provide their original schematic and components; build the required
item with a crafting tool. Available parcels appear under **Data** in the datapad
with their original 3D item preview. Point at an entry, hold the main-hand grip and
pull it out, then present it near the receiving NPC's torso and press trigger.
Releasing the grip returns its presentation to the datapad. Pickup, completion
and rewards require Core3 confirmation. Select the mission or parcel in the
datapad and press **Cancel mission** to abort it. Cancellation removes its bound
parcel, issued components and crafted result, including a held presentation;
unrelated inventory items are retained. Older crafting missions created before
mission-item tracking may need cancellation and reacceptance, because old
unmarked items cannot safely be distinguished by template alone.

Voice is the default chat interface, using the native TwoVoIP codec also used by
FPSlop. The palm-facing underside of the offhand forearm has **PROX**, **GROUP**,
**PLANET**, and **FACTION** buttons. Point the main-hand finger and press its
trigger to switch; a visible fingertip cursor marks the selection. Voice controls
and the opposite-arm HAM readout run lengthwise along their source forearm bones,
and follow tracked axial arm roll so turning the forearm reveals them; wrist
flexion does not tilt them away from the arm. Proximity is spatial within64m; other channels are nonspatial.
Group and faction require actual Core3 membership. One channel is heard at a time.
Listening connects on world entry; the microphone starts muted. Choose voice
activity or push-to-talk explicitly, then hold **TALK** for push-to-talk. Menus,
focus/tracking loss, logout and character changes gate audio. Desktop inspection
uses **F12** for controls and **B** for push-to-talk.

`setup.sh` installs pinned TwoVoIP binaries and notices; explicit local launch also
starts a loopback voice relay. The VPS relay uses TLS on TCP18444. This is a bounded
prototype: reliable WebSocket transport can stall under packet loss, and ordinary
world native presence refreshes on a5s cadence. It is not an MMO capacity result.
See [voice protocol and limits](server/VOICE_PROTOCOL.md).

The default launch uses standard OpenXR and the Forward+ Vulkan renderer. Select your
OpenXR runtime outside the application and connect the headset first. Quest via
SteamVR or WiVRn is the initial hardware target; XR code has no runtime-specific
branching. A future Windows client will require a Windows native-extension build.

OBS capture is not a client component. The launcher and benchmark runners disable
external OBS OpenXR/Vulkan capture injection before starting Godot. The third-person
desktop spectator is rendered directly by Godot and remains available.

Left stick runs at full deflection (9.36 m/s) and walks at partial deflection;
right stick turns, triggers select pointed controls, and
The controller Menu button opens the menu. Head and controller poses come from tracking; physically
lowering your head changes the collision capsule. The floating menu includes
a virtual keyboard for account/name/biography input. **Turning** selects 30° snap
or smooth rotation, with a saved smooth speed of 30–180°/s (90°/s initially).
Session overrides are `--turn-mode=smooth --turn-speed=90`.
The menu uses direct **Snap** and **Smooth** buttons. After entering your character,
stand upright on a supported floor and choose **Calibrate standing height**. This
saves your real standing eye height; physical crouching then lowers the pelvis
and bends the knees without rescaling the avatar or moving tracked poses.

The desktop window shows a separate third-person camera with the complete avatar,
including head and hair. Its collision-aware view renders at up to 30 FPS at
960×540; the headset retains its own stereo tracked camera.

A simple loading screen covers startup and world entry in both the headset and
desktop mirror. It reports the current loading stage and stays visible until
nearby terrain, scenery, collision and player placement are ready. Head tracking
continues while movement is paused. Loading errors remain visible; press Menu or
Esc to return to the menu.

The saved original SWG avatar is visible in first person with tracked head/arm IK
and input-driven finger poses; XR Tools gloves remain the pre-entry fallback. Desktop body clips and
keyboard posture/emote controls do not drive the VR player.

Hold **grip + trigger on the left hand** for a quarter second to raise the wrist
datapad; release either to close it. Point the other index finger at an entry or
button and squeeze its trigger to select. Keep the finger over the interface and
use that hand’s joystick to scroll or pan; turning remains suppressed until the
stick returns to neutral. The wrist surface follows your view with limited pitch
and no added roll, with an angled information panel alongside it. **Planet map**
expands the screen; click a map point and press **New waypoint**. Without a
selected point it saves your current position; **Use my position** clears a map
selection. The selection survives switching back to the entry list. **Delete entry**
is available for removable player entries; static POIs, learned recipes and
server-managed entries remain protected. The original map provides a planet overview;
zooming does not add detailed city imagery.

With the datapad closed, a compact circular holographic **64 m radar** occupies the
same offhand wrist mount. Contacts rotate with your horizontal head direction:
white for neutral NPCs, yellow for explicitly attackable contacts, red for hostile
contacts, and green for explicitly friendly contacts. NPCs use dots; mobs use
diamonds. Small chevrons indicate contacts more than 3 m above or below you.
Opening the datapad replaces the radar. It hides during menus, loading or tracking
loss and does not capture controls. Current authored ambient NPCs remain neutral;
the radar does not invent live Core3 hostility or mob spawns.

The datapad reads real Core3 waypoints, control devices and learned recipes.
Original Tatooine POIs are shared reference entries. No pets or vehicles are
invented when a category is empty; starter possessions depend on Core3’s creation
rules. Waypoint creation uses Core3’s command and verifies persistence through a
fresh login. Offline inspection supports the reference map but cannot save
waypoints. `datapad/offhand="right"` in `user://swgxr_vr.cfg` swaps the hands.
The map includes filterable terminal and trainer POIs. Holding an owned vehicle
deed and pressing trigger registers it through Core3 and adds its control device
to the datapad; ordinary crafting schematics are not vehicle deeds.

Reach your offhand toward its shoulder and squeeze **grip** to take out the
inventory bag. Keep gripping it to display a **4-row × 8-slot** grid of original
3D item appearances. Point and trigger-select an item for its larger preview and
information; use the pointing hand's stick to scroll. The bag uses your equipped
backpack, or the original ranger-NPC backpack when none is equipped. The latter
is a presentation aid, not a granted possession. The bag hangs vertically from
an upper corner in the offhand, with its front facing you; the corner follows
actual source geometry and switches sides with handedness.

Grip an item with the other hand to hold it. Held items use the runtime aim
orientation at the grip position, matching the weapon controller correction.
Releasing that grip while the bag is
open returns it to its slot. Stow the bag by releasing the offhand grip while
keeping the item gripped; releasing the item afterward creates a recoverable
**session-local physical drop**. Grip near the drop to recover it, or aim at it
and squeeze grip from up to **2 metres** away. Distant grabs require a clear line
of sight and a narrow aiming cone. Held/dropped
items retain their Core3 ownership and reserve their existing inventory slots;
they are not transferred into the persistent world. World/character changes clear
these local presentations. **Split stack** performs a real Core3 split for supported
resource containers and factory crates, with server quantity and capacity checks.

While holding equippable gear, press **trigger** to show a local hologram of your
avatar and current equipment. Move the item near a highlighted body slot to see
current and incoming stats in two panels. The main-hand stick pages through all
comparison attributes. Release grip over a compatible slot to equip; the old
item returns to inventory. Core3 requires a free inventory slot before equipping
(and enough room for every displaced piece). Blocked slots show the reason and
keep the item in your hand. Press trigger again to dismiss the hologram.

While holding food, drink or a supported self-use stimpack, a fresh **trigger**
press uses one item/charge through Core3. Native requirements, fullness, existing
effects and medicine cooldowns still apply. Area/ranged/pet or target-only medicine
is explicitly unavailable here. Remaining charges stay held; the last charge
removes the item. Inventory-held weapons reserve trigger for this equipment UI;
after equipping, draw from the normal holster to use combat controls.

Holding a survey tool opens its resource map automatically, with a tilted left
pane showing the selected resource's original container model and Core3 quality
attributes. Point with the other
hand and press **trigger** to select a current planetary resource; use the
main-hand stick while pointing at the panel to scroll the list. Press the holding
hand's **trigger** to survey. The map spans the tool/skill maximum survey width and
shows only returned Core3 concentrations and its highest-concentration waypoint.
That owned resource waypoint can be deleted from the datapad; a later survey
creates a new one when appropriate.
Lower the tool onto supported outdoor ground and release grip to deploy it. Its
original model floats **1.2 m** above the sampling point with a beam to the ground;
the display shows collected resources, the last sampling outcome and the next
cycle. Original skill and density rules still apply: trace amounts can yield
zero units. Grip the floating tool to request recovery; it remains deployed if
Core3 cannot fit the tool and collected resources. Recovery uses the inventory
snapshot from that same native transaction. Unconfirmed requests release the
hand controls and retain their receipt for a safe explicit retry.

Use **Tool slot** on the survey panel (or trigger while holding another tool) to
open the equipment hologram. Release the tool at the offhand-hip marker to reserve
that single tool slot. Draw it with a fresh **grip from either hand**, including
the offhand, near that hip; handedness swaps the hip location. The tool stays in
the hand that retrieved it. While holding a survey tool, the free hand can pull
out the backpack. The open inventory temporarily replaces the survey panes;
closing the bag restores them.
Returning a hip-held tool into the open bag checks inventory capacity. Crafting
tools use this slot and open the artisan interface described below.

With an empty main hand just above a corpse, press a fresh **trigger** to inspect
it. Cyan holographic resource containers appear above the original corpse model.
Move the hand to a resource and squeeze a fresh **grip** to request its native
harvest. A second fresh **trigger** over the corpse requests all available credits
and items. Native eligibility, yield and capacity failures remain visible; the
client does not invent rewards. Menu/tracking loss cancels these interfaces safely.

For automatic preparation of all current item appearances before entry, launch
with your account and character name:

```sh
./run.sh --account=prototype --enter-character=YourCharacter
```

The launcher reads that character's real inventory and prepares missing local
models. Unsupported original appearances remain explicitly marked **NO MODEL**;
they do not receive replacement art. Equipped supported weapons work without
`--combat-items`; their local combat dependencies are prepared when absent.

The bounded live ranged test uses `--live-combat` (which implies `--combat-items`).
It holds a persistent authenticated Core3 zone session: nearby creatures/lairs,
retaliation, HAM, damage and deaths come from Core3. The client supplies tracked
launch poses and projectile contacts; native validation decides the result.
Inventory, datapad, gathering and entertainer operations are suspended while
this session owns the character. Basic ranged attacks are supported; translated
local active abilities are disabled. Closing the client stops its zone session
and leaves Core3 and the loopback adapter running.

Use `./run.sh --desktop` for the retained desktop inspection mode.

Wait for `LOCAL CORE3 · Connected`, open character creation, choose species,
sex, appearance, starting profession, and name, then create the character.
Select it and click **Enter Mos Eisley**. The account field is a local developer
alias; reusing it retrieves its persistent characters. This prototype is not a
public authentication service. Core3 applies its normal name and creation limits.

In desktop inspection mode, move with **WASD**, look with the **mouse**, run with **Shift**, and use
**Space** for a cosmetic jump or knockdown recovery. Jump raises the view without lifting the
collision body. Open the menu with **Esc**, and reset to the entry point with **R**.
In VR, click the **offhand stick** to jump/recover; the weapon-hand stick selects abilities.
During an entertainer performance, press **A** to request a random learned flourish.
Jump remains available for its normal cosmetic jump and knockdown recovery.

Artisan crafting uses the owned tool from the bag or tool hip slot. Trigger opens
usable schematics and a filtered grid of original 3D ingredient models. The
main-hand joystick scrolls the recipe list without requiring pointer hover;
tilted side panes show the original preview and ingredients. Grip-drag
ingredients into the holographic cubes and trigger advances assembly. At a compatible station, grip-turn the spaced experimentation knobs
and drag the source color sliders, then trigger starts crafting. **Stowing before
the timer starts refunds all resources and components**, including after assembly.
Running tools reserve output slots and show countdowns. See
[the crafting protocol](server/CRAFTING_PROTOCOL.md) for scope and validation.

Recovery follows physical standing/kneeling posture. Going prone clears knockdown, and a prone
player cannot be knocked down. The weapon wrist shows HAM bars with gray wound blockers.
The datapad **Skills** tab browses original profession trees, prerequisites, costs and observed
learned boxes; it does not train skills. Combat posture recovery remains local prediction pending
a continuous Core3 combat connection.
Use **V** to switch between first-person exploration and the avatar inspection
camera. The player body uses the original locally imported SWG meshes and skin
bindings, with appearance and equipped clothing read back from Core3.
Hold **Alt** while moving the mouse in third-person view to orbit the camera.

Creation supports the ten original playable species with male/female variants,
original body/face controls and palette limits, available hairstyles, six starting
professions, and a biography. A live preview uses the imported body, hair, and
profession outfit. Original body and facial clips play through separate native
animation players; first-person view hides the head while retaining the body.
Desktop-only controls: **C** to crouch, **P** to go prone, **X** to sit, **F1/F2** to wave/bow,
and **F3/F4** to smile/blink. More source emotes are in the exploration menu.

The movement state machine covers directional walking/running, crouching,
crawling, sitting, jump/fall/landing phases and body/facial actions. Layered original
beards, brows, makeup, freckles, tattoos, age maps and texture patterns are supported.
This is a new interaction runtime; original combat graphs and exact material effects
are outside this milestone. Missing source references remain in the asset reports.

```sh
./run.sh --offline                  # VR asset inspection, no Core3 session
./run.sh --desktop --offline        # Desktop asset inspection, OpenXR disabled
tools/server/stop-core3.sh          # Graceful save and exit; leaves MariaDB up
```

The complete 16,384-metre Tatooine terrain is evaluated from original source rules
in C++ and streamed in 128-metre chunks, with 2-metre collision detail near the
player and coarser distant meshes. Source roads, terrain colors, cave exclusions
and four water regions are retained. Static snapshot scenery streams separately.
Original building interiors, floor cells, furnishings and static collision now stream
with scenery. Authored non-interactive NPCs play original idle/mood animations;
regional ambience, music and a configurable day/night cycle use local source assets.
Original named-cell interior layouts now supply 7,114 static decorations across
48 buildings, including all 258 static entries in the Mos Eisley cantina. Interior
soundscape selection uses the original cell/building table; cantina ambience and
the authored band recording continue across its adjacent rooms. World geometry,
texture decoding, collision-query preparation and Ogg decoding use bounded
background workers; scene installation and GPU uploads remain on the main thread.
See [interior import details](tools/assets/README.md#original-interior-layouts-and-soundscapes)
for regeneration and audited unsupported source entries.
World materials retain original vertex colors and baked vertex irradiance without
real-time lights or shadows. Water is visual only, doors are static, and procedural
vegetation, effects, weather and full original visibility optimization remain pending.

For development travel, start at SWG x/z coordinates after real character entry:

```sh
./run.sh --account=prototype --enter-character=Jebot --world-position=3300,-4600
```

This changes only local exploration; it does not move the Core3 character.

Grounded VR movement follows original FLR support ramps and connectivity, with
native capsule support and bounded step sweeps for controller and physical motion.
Cell membership persists until movement crosses an actual portal; projected
basement floors cannot capture a player standing outside. Static collision uses
authored appearance and POB cell extents, scoped to the current cell and nearby
doorways. Explicit source NULL extents do not become visible-mesh colliders.

Exterior building surfaces are clipped through source portal openings separately
for the headset and spectator. Exit stairs remain visible through their doorway.
Interior terrain cutouts activate after building collision is resident and only
for an interior view; outside terrain retains its rendering and collision.
The renderer bounds portal traversal to 32 visible openings and 16 cells per path,
and preserves exterior visibility if that budget is exceeded.

## Prepare from the supplied media

Host prerequisites: Linux x86-64, Godot 4.7 with Jolt (tested with 4.7.2), Python 3 with Pillow,
Podman, Git, 7-Zip, CMake and a C/C++ build toolchain for the small extraction
utility. Core3 builds in a Debian container using Clang 19; MariaDB and its
dependencies stay inside that container. Provisioning needs network access for
open-source code and build packages. It downloads no replacement game assets.

The client uses a C++ GDExtension for the first-person controller and bulk mesh
and collision construction, including weighted avatar meshes and relative morphs.
The terrain evaluator derives from pinned Core3 AGPL source; see
[terrain attribution](client/native/TERRAIN_SOURCE.md) and its included license.
Menus and HTTP orchestration remain in GDScript.
`tools/client/build_native.sh` builds the extension against the installed Godot
API using pinned bindings and SCons in a local Python virtual environment.
Rebuild it after changing native sources or the engine version. These native
classes can also be used by a future headless Godot server.

```sh
./setup.sh                          # Finds the three supplied ISO files here
# Or: ./setup.sh /path/disc1.iso /path/disc2.iso /path/disc3.iso
./run.sh
```

The initial Core3 build is substantial; it defaults to 12 parallel jobs. Set
`SWGXR_BUILD_JOBS` to lower that on a smaller machine. Do not re-extract TRE files
while Core3 is reading them. Setup checks for an active server before extraction.

The supplied March 2004 media contains 30 TRE archives through patch 07. The
Jump to Lightspeed BIN/CUE adds eight archives, including `data_sku1_00..05` and
`patch_11_00..01`. The five Total Experience discs supply the remaining 13 archives
expected by Core3's pre-CU profile. Setup extracts each media set separately and
builds an active directory with traceable links to 51 selected archives. Later
Combat Upgrade archives on those discs are excluded. The
bounded ground-only profile records the selected and missing archives
in `runtime/server/media-profile.json`. Source revisions are pinned in
[server/upstream.json](server/upstream.json), and compatibility changes are stored
in [server/patches](server/patches). `tools/configure_core3.py` reapplies them and
generates the local Tatooine configuration.

## Checks and evidence

```sh
python3 tools/assets/validate_stage.py
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/xr_rig_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/xr_menu_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/xr_main_smoke.gd
python3 tools/assets/validate_characters.py
python3 tools/assets/validate_animations.py
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/terrain_stream_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/avatar_mesh_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/collision_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client -- --smoke-test
python3 tools/server/smoke.py
python3 tools/server/appearance_smoke.py
godot --headless --xr-mode off --audio-driver Dummy --path client -- --integration-test
```

The backend and integration tests create real persistent test characters. Their
success requires a working Core3 login, creation, fresh character listing, and
world entry; there is no fake backend fallback. The stage test checks grounding,
movement, and collision against an imported wall.
The appearance smoke checks a customized Twi'lek Medic through distinct logins,
including signed body morphs, hair values, biography, skills, and equipment.

Verified in this workspace: native character creation → fresh Core3 listing →
confirmed world entry → rendered starport → grounding and imported-wall collision.
Two characters retained their exact IDs and could enter again after a graceful
Core3 save and full process restart. The final selected archive list has no
missing entries from the pinned Core3 profile.

The persistent starport stage contains 17 cells, 120 shared meshes, 428 placed instances,
and 173 textures. The world snapshot covers 14,455 objects and 16,294 placed mesh instances indexed
into 272 chunks, with 1,036 shared meshes and 1,959 interior cells. Terrain height validation compares 2,249 points
against the pinned Core3 implementation, with maximum error under 0.00008 m.
Local evidence:

- [Streamed Mos Eisley terrain and scenery](runtime/evidence/tatooine-mos-eisley.png)
- [Streamed Mos Espa](runtime/evidence/tatooine-mos-espa.png)
- [Terrain streaming and physics validation](runtime/terrain/streaming-physics.json)
- [Full animation asset validation](runtime/evidence/animation-validation.json)
- [Core3 character inside the starport](runtime/evidence/starport-core3-final.png)
- [Final native integration results](runtime/evidence/integration-final.jsonl)
- [Character persistence after restart](runtime/server/smoke-persistence-godot.json)
- [Jebot with his Core3 clothing in the starport](runtime/evidence/jebot-avatar-starport.png)
- [Character appearance controls](runtime/evidence/creation-appearance-final.png)
- [Customized character appearance roundtrip](runtime/server/appearance-roundtrip.json)
- [Character geometry, animation, and provenance validation](runtime/evidence/character-assets-validation.json)
- [Creation and avatar milestone verification](runtime/evidence/avatar-milestone-validation.json)

Asset provenance and SHA-256 hashes live under `runtime/assets/`; server smoke
results and startup logs live under `runtime/server/`. These generated artifacts
and all proprietary data are excluded from Git.

Preserve `runtime/server/adapter.secret`, `runtime/server/mysql`, and
`vendor/Core3/MMOCoreORB/bin/databases` together to retain account access and
characters. Core3 listens inside an isolated container without published ports;
the adapter binds to `127.0.0.1:18080`.

See [agent workflow](docs/WORKFLOW.md), [asset pipeline](tools/assets/README.md),
[backend API and persistence](server/README.md), and [client options](client/README.md).

### Gate, avatar and wrist interaction regression checks

Run automated clients with OpenXR disabled so an active headset session is not
interrupted. Current checks include actual source main-gate colliders (all three
starport gates, both directions, joystick and room scale), finite aperture cuts
that preserve walls/jambs/floors, all 20 avatar rigs with deep physical crouch,
and real XRTools pointer events into the menu. These are mocked tracking tests;
live headset comfort, readability and hand alignment still require a headset run.

```sh
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/xr_starport_exit_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/tracked_calibration_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/xr_menu_pointer_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/wrist_datapad_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/xr_datapad_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/radar_contacts_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/wrist_radar_smoke.gd
python3 tools/assets/validate_datapad.py
```

A running client retains its old scripts and native library. Restart it normally
to use updated collision, calibration and datapad behavior.


Forward+ on Vulkan is the only supported GPU renderer. The launcher rejects
unsupported overrides, and the application verifies the active backend. PC VR
through SteamVR/WiVRn is the target; standalone headsets are excluded. Run
`python3 tools/benchmarks/run_suite.py --quick` for the viability benchmark smoke
suite. See [benchmark targets and limitations](docs/WORKFLOW.md#forward-viability-targets-and-benchmark-boundary)
for full-duration and synthetic stereo workloads. Benchmark success is not a
supported MMO population claim.

The wrist datapad now rises vertically above its wrist hinge, independent of
palm roll, with its lower edge attached to the wrist. View following retains the
25-degree pitch limit and adds no roll relative to this upright origin.

Combat effects now default to a native batched renderer using original textures
and source-derived colors, including the bright tracer core. Enforced 20/50/100 m
LOD tiers and shared particle/tracer budgets bound presentation independently of
projectile collision. See [particle limits](docs/COMBAT.md#enforced-particle-limits)
for exact caps and validation. The benchmark defaults to `--effects optimized`;
legacy source playback is an explicit `--effects source` comparison mode.

The [melee baseline](docs/COMBAT.md#melee-baseline) adds physical swings with spatial
recovery between attacks, head-bound targeting and crafting-driven Stance
recovery/Power. Melee grip
changes Power only; crouching and prone reduce reach. Original melee models and
swing/hit audio are imported from the supplied assets. Combat results remain local.

Scout VR controls and native authority are documented in [SCOUT_PROTOCOL.md](server/SCOUT_PROTOCOL.md). Scout keeps native harvesting and terrain-negotiation modifiers, camp deployment/terminal management, traps from inventory or the tool hip slot, ground-digging foraging, and empty-hand Mask Scent selection/A activation. Alternating running-in-place arm strokes request native Burst Run. Ability menus follow the controller, and all professions share one selection with recovery applied when an armed ability is replaced. Scout gesture/headless checks, native fixture tests and desktop Vulkan camp captures are separate from live headset validation.

The basic Medic VR focus now has an independent offhand healing wheel and
reticle. Point at the first eligible recipient (including your own body), then
press the offhand trigger. Healing leaves locomotion available. Native area stims
show a ground perimeter, while recipients see restrained local healing/damage
pulses. See `server/README.md` under “Basic Medic and recipient feedback” for
controls, native requirements, validation and current drag limitations.

Vehicles can be called from the datapad’s Vehicles tab. Touch the driver or
passenger seat and squeeze that hand’s trigger to board; the jump control
(offhand stick click) dismounts. Grip either bike handle and twist forward/back
for throttle/brake/reverse, moving the handlebars to steer. Landspeeders use
main-hand joystick forward/back for throttle, braking and reverse while gripping
the yoke. Steering follows hand movement around the wheel. Avatar hands stay on
the grabbed yoke; original X31, X34 and AV21 yoke geometry rotates locally. The
Flash steering mesh remains static because it is joined to the dashboard stem.
Tracked controller poses remain unchanged. One free hand remains usable by the driver; both
passenger hands remain free. Both-hand contact/grip stores a parked, empty owned
vehicle. The datapad also offers **Recall** for a nearby parked, empty vehicle.
Owned follower droids have **Call/Recall** controls; touching a droid with both
hands and gripping recalls it through Core3. Native range, line of sight, combat
and ownership checks apply, and removal waits for confirmed native state.
Dead and incapacitated occupants are ejected; losing the driver stops
motion. Details and reproduction commands are in `server/README.md` under
“VR vehicles”. Vehicle-frame smoothing preserves direct head tracking; completed
Vulkan frame tests and native Core3 checks are distinct from live headset testing.

## Recording follow-up: core1.mp4

Confirmed inventory remains browsable during tool recovery and refresh; pending
mutations still lock changes. Survey maps omit navigation POIs. Recipe selection
waits for an in-flight crafting status read instead of discarding the click.
Mission lists support trigger clicks, hand drag and the pointing hand's joystick;
held grip does not suppress trigger selection. The pointer follows the rendered
fingertip, including source skeleton scale, rather than the controller origin.

Wallet/tool/weapon grab zones follow headset translation and horizontal facing.
Head pitch, head roll and avatar arm movement do not tilt these zones. The wallet stays behind, the tool uses the offhand hip, and the weapon uses
the dominant hip. Changing handedness swaps the two hips. Visual equipment keeps
its original bone mounts independently of these forgiving reach targets.

Vehicle calls retain the original native connection throughout the delayed spawn.
Datapad vehicle entries render the original resolved vehicle model; unknown device
templates do not invent a replacement. Optional status reads share a fair budget
and yield to user actions and seated vehicle controls. Live VR tests remain paused;
headless and desktop Vulkan evidence do not establish headset usability.

## Recording follow-up: core2.mp4

The common rendered-finger pointer keeps its last extended aim in wrist space
while trigger pressure curls the index finger. The visible beam still starts at
the rendered fingertip; moving the wrist continues to aim and drag normally.
All diegetic interfaces use the same ray contract. Logoff defers destruction of
objects still executing a callback. Multiplayer source coordinates now read
the production stage loader's origin report rather than an undefined property.

Mission terminals use their original screen anchors, select the nearest aimed
screen and reject back-face interaction. Native offers with an empty type are
excluded after terminal refresh. Artisan survey missions use the original
resource-family, density and distance requirements and original rewards;
explorer hunting and reconnaissance retain their original objectives.

Static foliage honors the original effect's alpha-test flag, including opaque
sort buckets. The launcher refreshes cached material metadata and verifies the
original vehicle catalog. Geometry, collision and source textures are retained.
VPS packaging and startup require the six supported vehicle descriptors.

Exterior doorway repair is limited to actual authored cell shells. Source-sized
bounds and at least 90% aperture coverage identify nearby closure sheets, including
layered/slanted shells. Interior walls, props, floors, jambs and distant shell
faces remain protected. The theatre entrance shown at 8:06 passes real native
locomotion in both directions; eleven affected source portals pass capsule
sweeps. More distant university/combat-guild/alternate-starport candidates are
recorded for separate investigation, not cut by widening the safety bound.

Evidence is under ignored `runtime/evidence/core2/`: original Core3 objective
transactions, actual-stage collision, mocked tracking and desktop Forward+ Vulkan
rendering are recorded separately. No live headset validation is claimed.
