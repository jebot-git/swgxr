# VR-first OpenXR client

Godot 4.7.2, standard OpenXR, Forward+ Vulkan renderer, bundled Jolt Physics. Jolt avoids snagging on the imported mesh floor seams observed with the default physics backend. Build the required native extension, then run from repository root:

```bash
./tools/client/build_native.sh
./run.sh
```

The character buttons are enabled only when the local adapter confirms real Core3 readiness. Creating/selecting a character uses Core3. Entry proves Core3 world entry, then renders a local stage; the current native client does **not** maintain a multiplayer zone session or replicate movement.

`Inspect local assets · offline` opens the same imported stage without character creation. It is explicitly labeled offline.

Controls: WASD, mouse look, Shift run, Space jump, Escape menu, R return to the stage entry point. V switches between first and third person; Alt + mouse orbits the third-person camera. First person shows the body with the head hidden. Camera eye level and capsule height follow the original body dimensions and chosen height; hairstyles do not change physical height. The third-person camera stops before environmental walls.

C toggles crouching/kneeling, P toggles prone, and X toggles sitting. The native controller reduces movement speed and capsule height with posture, prevents standing into a ceiling, and disables posture changes while airborne. F1 waves, F2 bows, F3 smiles and F4 blinks when that character has the original clip. The exploration menu also lists the imported body emotes and facial expressions.

The capsule uses original render-triangle collision for structures and source-rule terrain collision outdoors. Tatooine streams around the player; dynamic doors and NPCs remain future work.

## Character creation and avatars

The creator offers the original ten playable species, both sexes, six starting professions, supported original appearance controls, hair/head details, name and biography. The local Core3 adapter supplies original customization variable ranges, palette restrictions and required-hair rules. Creation saves a real Core3 character; entering reloads authoritative body, hair and equipment appearance from Core3 replication.

The preview and player use original imported body, outfit and hair meshes, bone weights, signed morph deltas and source animation clips. Native C++ builds the skinned meshes and morph arrays; Godot's native AnimationPlayer evaluates skeletal tracks. Outfit triangle-zone metadata hides covered body regions. The material shader evaluates imported primary/secondary palettes, texture selectors and original facial texture-renderer layers, including supported beard, brows, makeup, freckles and tattoos. Normal maps and alpha cutouts approximate the original material presentation. Three missing original hair/outfit references are recorded by the importer and unavailable choices are filtered.

`character_animations.py` follows each SAT's body/face LAT bindings and the original ASH state/action references. Gender/mood selectors and source playback scales are retained. Each race exports 18 movement/posture/transition clips and a lazy library of available noncombat emotes and facial clips. The current media genuinely assigns the shared humanoid body graph to playable species; face bindings and skeletons vary by species. Body and face have separate native animation players so expressions can accompany movement.

Actual velocity selects walk/run/directional movement, and actual grounding selects jump/fall/landing. The original jump's root-height curve identifies takeoff, apex and landing phases; upward visual root travel is removed because physics supplies it. There are no standalone noncombat humanoid fall, landing or turn clips in the selected graph: fall/landing use those original jump phases and turning retains the idle pose. This is a new runtime state machine, not a reproduction of combat graphs, priority masks or the original ambient-action scheduler. Missing Ithorian blink/bat-eyes and Sullustan bat-eyes source references are recorded explicitly.

Open the connected creator with `--account=prototype --show-creator`. `--creation-preview=human_female` opens an explicitly local preview; `--creation-options=/absolute/path/options.json` supplies a saved API catalog for repeatable preview tests. `--creation-tab=1` opens appearance controls. Existing character captures support `--third-person`, `--orbit-yaw=radians` and `--pitch=radians`.

## Validation

```bash
# Independent movement/collision regression on synthetic floor and wall
godot --headless --xr-mode off --path client --script res://tests/collision_smoke.gd

# Original imported stage: grounding, lateral movement, collision against an actual wall
godot --headless --xr-mode off --path client -- --smoke-test

# Original cell ownership: exterior hull suppressed inside, true wall retained,
# and exterior render/collision restored outside
godot --headless --xr-mode off --path client --script res://tests/cell_collision_smoke.gd

# Real Core3 HTTP flow: create, list, select, enter, then the same imported-stage test
godot --headless --xr-mode off --path client -- --integration-test

# Native avatar capsule height, eye level, camera modes, orbit and wall clearance
godot --headless --xr-mode off --path client --script res://tests/avatar_camera_smoke.gd

# Native postures, ceiling clearance, crawling and seated movement restrictions
godot --headless --xr-mode off --path client --script res://tests/posture_smoke.gd

# Source clips, runtime state selection, independent face/body and airborne phases
python3 tools/assets/validate_animations.py
godot --headless --xr-mode off --path client --script res://tests/avatar_animation_smoke.gd

# Render original poses under runtime/evidence/animation-poses
godot --xr-mode off --display-driver wayland --path client --script res://tests/avatar_pose_capture.gd

# Actual creator UI signal -> Core3 creation/list/entry -> exact saved appearance
# Creates one persistent character on a unique account, writes creation-flow.json.
godot --headless --xr-mode off --path client --script res://tests/creation_flow_smoke.gd

# Rendered evidence; requires an available Wayland display
godot --xr-mode off --display-driver wayland --path client -- --offline --screenshot=/absolute/path/starport.png
```

`--integration-test` creates one persistent test character. `--character=Name` overrides its generated name. Tests generate a fresh account unless `--account=Name` is supplied, avoiding Core3's per-account creation cooldown. `--evidence=/absolute/path/results.jsonl` appends machine-readable stage/Core3 results. Test failures return nonzero exit status; no mock fallback is used.

Additional options after `--`: `--backend=http://127.0.0.1:18080`, `--stage=/absolute/path/scene.json`, `--position=x,y,z`, `--yaw=radians`. Screenshot capture also works with `--integration-test` and preserves the Core3/local movement label.

For repeatable avatar captures, `--animation=run --animation-time=0.4` holds an original pose after character entry. The standalone pose capture script also accepts `--race=human_female --state=walk,run,sit --time=0.4`.

`--account=Name --enter-character=CharacterName` selects an existing character
through Core3 without creating another character.

The importer preserves POB cells, passable portal polygons, authored CELL collision
meshes and original FLR topology. Membership persists until the player crosses a
finite source portal; projected basement floors cannot capture exterior stairs.
Spawn placement explicitly seeds membership from valid floor support. Collision
is independent of render visibility: source extents use layer 1, terrain layer 2,
and authored solid FLR faces layer 4. Current and nearby portal-adjacent cells
supply collision; an authored NULL extent creates no visual-mesh substitute.
Native `SwgCollisionBuilder.build_cell_extent` clips coarse CMSH closure faces
against finite passable portal apertures, within 10 cm of their planes. This
adapts the original portal-before-extent collision traversal to Godot static
bodies, so a neighboring exterior shell cannot block the capsule before its
center crosses a doorway. Jambs, lintels, floors, unrelated walls and remote
shells retain collision. Both stage and streamed buildings use the same builder.
Exterior rendering is clipped through source portals per view, preserving stairs
outside while hiding exterior hull faces that would cut through occupied rooms.

Terrain interior masks use 25 cm floor/ceiling texels, with 30 cm wall padding
bounded by source cells. Masks apply only to the occupied building and appropriate
camera view; an exterior spectator retains ground above buried rooms. Streamed
regions cannot publish membership or cutouts before their geometry and collision
nodes are installed and synchronized with physics. Unloads restore terrain masks.

`world_stream.gd` streams 256 m static snapshot chunks within 768 m, creates at
most 24 instances/two new shared meshes each frame and activates nearby collision.
It skips retained stage object IDs, streams original interior cells and furnishings,
and registers/unregisters floors with the shared cell classifier. Meshes and collision
shapes are shared; unused meshes are evicted after distant travel. First entry
waits for nearby scenery before enabling exploration.

## Asset contract

The runtime loader reads `../runtime/assets/mos_eisley/scene.json` by default. It uses `meshes` keyed by ID, `surfaces` containing flat vertices/normals/UVs/RGBA vertex colors and indices, relative PNG texture paths, and positioned/quaternion-rotated `instances`. Geometry uses Godot Y-up coordinates (the SWG Z axis is reflected). `spawn`, `spawn_yaw`, `origin`, provenance, and warnings come from the importer. No Godot editor import is needed for user-supplied game data.

The loader retains clockwise render winding and backface culling. Authored collision extents and FLR faces are built separately from the visual LOD meshes. Making exterior hulls double-sided incorrectly exposes their rear surfaces inside the building. Diffuse textures and the original baked vertex colors are displayed without additional dynamic lighting; SWG's original multi-layer shader behavior is approximated. Screenshot-only `--freeze-camera` with `--position`, `--yaw`, and `--pitch` can inspect exterior geometry without implying it has traversable terrain.

## Native code boundary

`native/src/first_person_controller.{h,cpp}` provides the reusable `SwgFirstPersonController` CharacterBody3D class. Capsule/camera setup, mouse look, walking, running, jumping, floor snapping, and reset execute in C++. `scripts/player.gd` is only the scene-facing subclass.

`native/src/swg_mesh_builder.{h,cpp}` provides `SwgMeshBuilder`, validating and converting flat or nested source arrays into ArrayMesh surfaces and shared one-sided triangle collision shapes in C++. Texture/material presentation, UI, HTTP requests, and scene orchestration remain in GDScript. The imported-stage smoke records native class names and checks the actual C++ objects.

`tools/client/build_native.sh` pins godot-cpp `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, installs SCons 4.10.1 in an ignored local Python environment, dumps the installed Godot 4.7 API, and builds only the necessary binding classes. No system packages are installed. The Linux x86_64 shared library uses the system shared C++ runtime. Set `SWG_BUILD_JOBS` to control build parallelism. Generated bindings, API files, object files, and shared libraries remain local build artifacts.

## Native stair stepping

The C++ controller climbs steps up to `max_step_height` (0.35 m by default) without jumping. After normal movement, it checks any blocked horizontal travel and sweeps the full capsule upward, forward by only the remaining travel for that physics tick, and down onto support. A ray checks the actual tread's height and slope, since rounded capsule contact normals at stair edges are not the tread's surface normals. Ceiling clearance, a walkable supporting surface, and the step-height bound are required. Small contact recovery is limited to the controller's collision margin. Ordinary free movement and slopes use Godot's normal movement path.

Regression commands:

```bash
# Four 0.25 m stairs up/down; 0.9 m obstacle and low ceiling remain blocking.
godot --headless --xr-mode off --path client --script res://tests/stair_smoke.gd

# Original ticket1 staircase: approximately 1 m ascent and descent, without jumping.
godot --headless --xr-mode off --path client --script res://tests/imported_stair_smoke.gd
```

The original staircase test uses the imported `r8_ticket1` mesh, the native controller, and current cell collision ownership. It verifies actual progress to the upper landing and return to the lower floor. Existing floor, wall, sliding, and spawn tests also remain applicable.

## Streamed Tatooine

`terrain_stream.gd` samples the full original 16,384 m map with a persistent worker
and immutable C++ `SwgTerrainEvaluator`. Chunks are 128 m; the nearest 5×5 use
64 subdivisions (2 m) with collision, the middle ring 32, and the outer ring 8.
At most 17×17 chunks are resident. Main-thread installation is limited to one
chunk per frame; worker backpressure bounds completed geometry memory. Old chunks
are retired and changed detail is replaced atomically. Entry waits for nearby
collision. Traversal pauses only if its current fine collision chunk is unavailable.
Render-only 64 m skirts close detail boundaries without making collision walls; an
all-planet edge audit measured a worst fine/coarse gap of 57.806 m. Traversal is
clamped to the original map extent.

Diffuse/normal arrays blend source shader families and original color ramps.
The first variant in each family is currently used; the original random variant
selection, vegetation, sky/weather and exact material effects are not reproduced.
Four source water polygons use original textures and remain visual surfaces only.
Original cell floors mask terrain for interior views, while portal membership selects
authored structure/floor collision inside and adds terrain outdoors. Source AEXC
exclusions refine boundary regions to a common 12.5 cm lattice at every terrain LOD,
then clip triangles against the original rule. Render and physics share those
indices; skirts follow surviving outer edges only. Curves and complex corners
remain bounded polygonal approximations, rather than analytic boundary surfaces.

`--world-position=x,z` sets local exploration to a SWG coordinate, sampling the
source height and waiting for nearby chunks. `--position=x,y,z` remains Godot-local.
`--no-terrain` is a regression/debug option. Neither option updates Core3 position.
See [terrain pipeline and parity](../tools/assets/TERRAIN.md) for the source contract,
reference validation and AGPL attribution. Streaming/physics regression:

```sh
godot --headless --xr-mode off --path client --script res://tests/terrain_stream_smoke.gd
```

## XR Tools integration and target

The primary target is tracked VR through standard OpenXR, initially Quest via
SteamVR or WiVRn on Linux. The rig, action map and menus contain no runtime-specific
code and can carry forward to Windows. Windows still needs its own GDExtension
build/export setup; the current local Core3 provisioning remains Linux-specific.

`tools/client/install_xr_tools.py` pins official Godot XR Tools **4.6.0-dev1**,
commit `ccd795c0d57944f15f4c39d44d284347c74b11fc`, which includes Godot 4.7 fixes.
This is an upstream development release; its plugin.cfg still says 4.5.1. The
lock file records the authoritative tag/commit and separate upstream/project
action-map hashes. The project owns its extra input bindings; reinstalling the
addon preserves them. The MIT addon
is copied unmodified into an ignored directory and installed during setup.
Re-import with `godot --headless --xr-mode off --path client --editor --import --quit`.

The XR Tools StartXR scene initializes the interface, enables stereo rendering,
handles focus and aligns physics with headset refresh. `xr/player_rig.tscn` supplies
an XROrigin3D, tracked XRCamera3D and grip-pose controllers, original XR Tools hands,
left-stick movement (9.36 m/s at full deflection, analog walking at partial
deflection), right-stick 30-degree snap turning and trigger pointers.
`xr_player.gd` adapts the XR Tools physics body to the existing world streamer and
cell ownership. Tracked height drives the capsule; no button crouch or avatar
morph rescales the HMD. Body clips/emotes are bypassed in XR. The original SWG avatar uses tracked head/arm IK and an inferred floor stance;
extra body trackers and full prone interpretation remain future work.
`SwgXRStepSolver` supplies bounded native capsule sweeps for VR stair ascent and
supported descent up to 0.35 m. XR Tools carries the resulting body displacement
to the tracking origin; controller and HMD local poses are left untouched. Walls,
ceiling clearance and unsupported drops remain collision constraints.

A/X toggles the world-space menu. `xr_menu.gd` uses XR Tools viewport surfaces and
virtual keyboard to host the existing character UI; menu surfaces use separate
pointer layers and never become environmental walls. Runtime failure is explicit;
`./run.sh --desktop` deliberately disables OpenXR and selects Compatibility for
legacy inspection. `--offline` selects asset inspection and does not imply desktop.

Always use `--xr-mode off` for tests/imports that must not start a headset session.
A connected runtime is not evidence of application headset rendering. Mocked pose,
pointer/keyboard, original-world and desktop Vulkan tests are separate from a live
headset test. Optional Linux-only read-only diagnostics:

```sh
python3 tools/client/xr_diagnostics.py --report runtime/evidence/xr-diagnostics.json
```

Upstream references: [XR Tools release](https://github.com/GodotVR/godot-xr-tools/releases/tag/4.6.0-dev1),
[Godot OpenXR setup](https://docs.godotengine.org/en/4.7/tutorials/xr/setting_up_xr.html),
[reference spaces and action maps](https://docs.godotengine.org/en/4.7/tutorials/xr/openxr_settings.html).

## Loading and grounded VR entry

One application loading gate keeps body physics and virtual movement disabled
until terrain collision, nearby scenery and cell classification are ready. The
streamer's per-frame readiness check cannot override this gate. Before enabling
VR locomotion, the tracked capsule is initialized and swept downward onto the
actual walkable floor, using interior/exterior collision membership. The grounded
position becomes the reset point. If no safe floor is found, entry stays paused
with an explicit message instead of dropping the player into unloaded space.
Tracking itself remains live during loading.

```sh
godot --headless --xr-mode off --path client --script res://tests/xr_stair_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/xr_imported_stair_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/xr_main_smoke.gd
```

## Tracked original avatar and hands

Core3 character selection now loads the saved original SWG body, clothing, hair
and customization in VR. `tracked_avatar.gd` fits the rendered body to the initial
physical eye height; it never changes the headset/controller transforms, world
scale or collision capsule. Stand normally when entering. The source eye joints
(or Ithorian eye stalks) define the viewpoint. First-person rendering excludes
head/neck triangles on render layer 2; observer cameras can include that layer to
see the complete avatar. XR Tools glove meshes remain available before character
entry and are replaced by the original avatar hands when body tracking is active.

`SwgTrackedIK` provides native two-bone arm IK, source wrist orientation retargeting,
bounded reach and stable elbow poles. It preserves the source forearm twist-bone
hierarchy and ordinary tracked segment lengths. Vehicle controls use the same
solver with a presentation-only reach extension: extra distance is distributed
proportionally across upper arm and forearm, while the hand keeps its size and
the control's orientation. Release, tracking loss and skeleton reconfiguration
restore the original lengths; HMD, controller and physics transforms are never
stretched. The six original vehicle models and all original playable skeletons
are covered by the attachment/IK checks, with a separate desktop Vulkan capture.
Head orientation follows tracking; torso placement
keeps the source eye reference at the HMD. Original SWG walk, run, strafe, backward and crouched-walk clips drive the
untracked pelvis, spine and legs. Source LOCT travel speed controls cadence.
Masked native sampling crossfades states; the spine uses reduced motion and
counters authored pelvis turns to keep tracked shoulders stable. Foot IK preserves
swing height, plants contacts and shortens strides that exceed leg reach. Ground
probes respect interior collision masks. Physical stationary crouching uses a
symmetric IK stance and tracked torso lean instead of the original one-knee kneel.
Legs remain inferred; full prone/body tracking and VR actions are future work. Lost controller tracking selects a safe resting
arm; lost head tracking hides the avatar. Original desktop body/face clips are
suspended during tracked presentation.

Hand poses use grip, trigger and capacitive touch inputs for open hands, grip/fist,
pointing and thumb extension. When a runtime supplies valid `XRHandTracker` joints,
the skeletal input takes priority per hand; controller poses resume on tracking
loss. This accepts both optical and controller-derived OpenXR hand data. Valve
Index scalar bindings alone cannot supply a finger skeleton: skeletal posing
requires the runtime to expose `XR_EXT_hand_tracking`. There is no direct OpenVR
or Oculus SDK dependency. The original rigs have two joints each for thumb,
index and ring/shared remaining fingers; they cannot reproduce five independent
fingers or all three phalanges of a modern tracked-hand skeleton.

The controller frame follows the [OpenXR grip convention](https://registry.khronos.org/OpenXR/specs/1.0-khr/html/xrspec.html#semantic-paths-standard-pose-identifiers).
Skeletal inputs use [Godot XRHandTracker](https://docs.godotengine.org/en/stable/classes/class_xrhandtracker.html).
Automated tests use simulated poses with OpenXR disabled; these are not headset
comfort, live Quest or live Index validation.

```sh
godot --headless --xr-mode off --path client --script res://tests/tracked_ik_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/tracked_hand_input_smoke.gd
```

Additional coverage and rendered evidence:

```sh
godot --headless --xr-mode off --path client --script res://tests/finger_retarget_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/tracked_avatar_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/xr_hand_input_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/tracked_hand_pipeline_smoke.gd
```

Local images are under `runtime/evidence/tracked-avatar-wrapper/`. Restart the
client after rebuilding native code (`tools/client/build_native.sh`) to load the
new solver. The running headset session is not automatically restarted by tests.

Locomotion validation (no headset initialization):

```sh
godot --headless --xr-mode off --path client --script res://tests/body_motion_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/tracked_locomotion_smoke.gd
godot --headless --xr-mode off --path client --script res://tests/tracked_ground_smoke.gd
```

Evidence: `runtime/evidence/tracked-locomotion-smoke.json`,
`runtime/evidence/body-motion-smoke.json`, and rendered pose frames in
`runtime/evidence/tracked-locomotion/`. Cadence is capped at 2.8× source speed;
extreme fast strafing can still slide. Anatomically unreachable hands remain
reach-clamped rather than stretching limbs.


## Original environment presentation

`environment_presentation.gd` reads the original Tatooine environment families,
256-sample palettes, sound definitions and OGG samples. Native terrain AENV rules
select regional ambience and music. Indoor wind is attenuated; nearby original
sound objects and authored NPC droid ambience use bounded spatial playback. Music and ambience have separate menu
volume controls. Day/night ambience blends, regional themes crossfade, and original
sunrise/sunset cues play at cycle transitions.

The default day lasts two hours (a prototype choice; original duration is not
verified). `--day-seconds=120 --time-of-day=0.25` accelerates inspection; phase 0.25
is noon and 0.75 is night. Original sun/moon textures accompany an approximate sky
orbit and procedural stars. Palette row interpretation and sound attenuation are
presentation approximations; weather, exact celestial trajectories and portal
acoustic occlusion are not reproduced.

Materials are unshaded. Original static vertex colors survive; missing vertex
illumination is baked once at mesh construction from a fixed hemisphere, and terrain
and avatar vertices receive fixed irradiance. Day/night changes global palette tints;
interiors retain a warm independent tint. There are no runtime light or shadow nodes
in the world. This is vertex lighting, not a new lightmap/GI or occlusion bake.

`ambient_npcs.gd` streams at most 32 nearby NPCs within 128 metres, loading one per
frame and advancing original animation within 50 metres. The catalog covers 185
source templates and 1,071 authored placements across all seven cities, including
462 interior placements. NPCs retain original rigs, clothing and customizations.
These are local non-interactive presentations of Core3 source placements, without
AI, combat, live server NPC replication or NPC collision. Twenty-one runtime-selected
informant variants are explicitly unresolved. Two absent wearable references and
Luke's Farm `music_event_explore.snd` remain recorded as missing source data.
Four water-container props retain geometry/collision with an untextured material
fallback because their `phong1.sht` owner-supplied shader alias has no static binding.
The Jawa rig's rare 38-influence vertices retain every source influence using an
exact virtual affine skin binding, validated across all 12 original clips.

Rebuild local source datasets without re-extracting mounted server archives:

```sh
python3 tools/server/export_ambient_npcs.py --city all
python3 tools/assets/prepare_environment.py
python3 tools/assets/prepare_npcs.py
python3 tools/assets/validate_environment.py
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/environment_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/ambient_npc_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/world_interior_smoke.gd
```

Evidence lives in `runtime/evidence/environment-*`, `ambient-npc-smoke.json`,
`world-interior-smoke.json` and `virtual-skin-smoke.json`. Desktop day/night captures
and Dummy audio playback checks do not establish live headset performance or
speaker/headphone listening quality. Restart the client to load rebuilt native code.

On the tested Fedora Godot build, some desktop captures stalled during Wayland
display-server shutdown after saving the image and freeing the scene. The stack
trace is `runtime/evidence/environment-shutdown-stack.log`; this was not a
terrain-worker stall. The running headset session was left untouched.

Collision/streaming regressions (append `-- --review-assets` to the cell/world tests before promoting review exports):

```sh
godot --headless --xr-mode off --path client --script tests/portal_membership_smoke.gd
godot --headless --xr-mode off --path client --script tests/authored_world_collision_smoke.gd
godot --headless --xr-mode off --path client --script tests/terrain_exclusion_smoke.gd
godot --headless --xr-mode off --path client --script tests/xr_spectator_smoke.gd
```

The house fixture checks the original exterior ramp above its underground bedroom,
actual doorway transitions, physical floor support, and source NULL collision policy.
The terrain fixture compares five LODs and tests collision 2 cm on either side of
an original exclusion edge. Spectator tests isolate camera ownership, head visibility,
wall clearance and the mono render-rate limit; these do not validate live headset timing.

## Floating datapad, wrist minimap and grounded VR avatar

See the [main controls guide](../README.md) for grip/trigger activation, finger
selection, map scrolling, new waypoints and standing-height calibration.
`xr_datapad.gd` reads finalized avatar poses after IK and uses native
`SwgWristDatapad` for wrist minimap placement, floating view-follow and finite
panel pointing. It sends normal input events into three SubViewports and never
writes tracked head/controller poses. Holding the offhand fist opens the compact
minimap; touch it with the other fingertip to open the datapad. The full datapad
stays open after releasing or lowering the hand; use its Close button to dismiss.
It opens 75cm ahead and slightly below eye level (95cm for the expanded map).
A dead zone includes all three panel edges plus 10 degrees horizontally and
8 degrees vertically. Head roll and small leaning do not move it; larger turns
and walking bring it along with exponential damping. Button and drag captures
freeze following to keep their target still. Reopening recenters at the current
view. The wrist minimap retains its original gesture and mounting behavior.
Pointing follows the visible index fingertip, with optical joints or controller
fallbacks and 1.4m reach across the floating panes. Pointing-hand tracking loss
cancels clicks; only head tracking loss dismisses the full interface. Scrolling
captures the pointing hand's stick until neutral. XRTools' pinned pointers are
restored on closing. `floating_datapad_smoke.gd` checks actual panel corners,
turn/translation dead zones, damping, reopening and tracking with mocked poses.

The left pane displays owner-only Core3 HAM, wounds, battle fatigue, cash/bank,
faction status and standings, per-piece armour protection, residence and bound
cloning location. Point at it and use the stick to scroll. Its holographic bust
uses the current character's original meshes; touching it opens the existing
equipment hologram in its empty-hand browsing mode. Grip an equipped item,
open the backpack with the other hand, and
release the preview inside the bag to request native unequipping. Equipment
stays authoritative until Core3 confirms the transfer; missed drops, tracking
loss and rejected requests retain it. `datapad_equipment_summary_smoke.gd`
exercises this complete UI/gesture/acknowledgement flow with mocked native data.


`SwgCollisionBuilder` handles the gate fix globally; avatar calibration and
pelvis/leg correction use every supported original rig. Ground contact comes
from current source/raycast support in addition to the XRTools floor flag.
Pelvis correction preserves the head and arm targets with spine compensation;
a world-space knee pole prevents deep crouch folding through the floor.
Calibration measures HMD height above the supported floor and is saved in
`user://swgxr_vr.cfg`, without rewriting the OpenXR origin or poses.

`tests/datapad_http_main_smoke.gd` exercises the real application methods and
local adapter using the dedicated backend fixture; it creates persistent test
waypoints. `tests/xr_datapad_smoke.gd` and `tests/wrist_datapad_smoke.gd` cover
pointing, activation, cancellations, scroll capture, expanded map and native
frame-rate invariance. Run all automated checks with `--xr-mode off --audio-driver Dummy`. GPU tests can use `--display-driver wayland --rendering-method forward_plus`; they do not validate live headset comfort.

## Ranged combat lab

Use `./run.sh --offline --combat-lab` from the repository root for the separate,
non-persistent ranged-combat prototype. It uses original local weapon assets,
tracked hip/shoulder grabbing, manual aiming, two-hand support and timed reloads.
See [combat design, controls, balance and verification](../docs/COMBAT.md).

XR and desktop launches both require Forward+ on Vulkan. OpenGL is not a
supported target and automatic OpenGL/D3D12 fallback is disabled. Direct desktop,
render-test and headless commands must still pass `--xr-mode off`.

### Source terrain navigation and Bestine VR fixes (2026-10-07)

[Terrain/navigation source contract](../docs/TERRAIN_NAVIGATION.md) records the
original SWG client and Core3 references, height-field movement, native speed and
water policy, connected floor support, and recurring portal/stair fixes. These
changes apply through shared terrain/collision code, not named-building patches.

Carried instruments require native equipment in the weapon slot before music
selection and performance gestures become available. Inventory-held inspection
does not equip or start music. The bag's **Equipped items** view supports grip
retrieval or **Return to inventory**; Core3 confirms removal and stops music
before the item appears in the bag or hand. Nearby playable placed instruments
can be selected from the performance menu and remain at their world location.
The entertainer controller resumes with the live session. A suspended controller cannot
anchor a hand to its stale instrument pose. The immediate Bestine appearance
warning was a duplicated Transport Shuttle actor: ServiceWorld already owns its
complete original model. Generic actor rendering defers only for a matching,
fully loaded service actor; genuinely missing appearances still report failures.

## Basic melee and action feedback

The ordinary gameplay combat bridge sends qualified melee swings and punches to the owned native session. A head-aimed 30-degree cone selects one nearby native PvE target; native equipment, range, LOS, HAM and shared attack timing still decide whether it lands. Default unarmed combat is available when the server reports its unarmed weapon equipped. Advanced melee profession abilities remain provisional.

Swing/fire pulses are followed by a stronger pulse on a confirmed hit. Physical guards pulse on confirmed blocks. Successful inventory, crafting, gathering, medic, Scout, service, vehicle and entertainer actions use a short pulse on the interacting tracked hand. Polling and rejected actions stay silent; feedback requires XR focus and tracking. Headless checks exercise receipts and filtering, not controller hardware.

Brawler taunt: with Novice Brawler and the native taunt ability learned, hold grip to clench a free hand, keep trigger released, and tap the chest twice while aiming the head reticle. Either repeat one fist or alternate hands. Pull back between taps; simply holding a boxing guard does not taunt. The closest eligible enemy under the reticle is challenged, with native range, line of sight, success chance and recovery. Menus, occupied hands and lost tracking block the gesture. A confirmed taunt gives a short haptic on the completing hand.

### Slicing and creature interaction refinements

The original slicing knife can use its native weapon slot or tool hip slot. A
separate tracked knife presentation allows an inventory target to remain in the
other hand. Either hand can retrieve the backpack from the offhand shoulder; the
opposite hand can then retrieve an item. Native slicing acceptance freezes only
the target beneath the puzzle.

Minimap dots and native actor nametags share observer-specific relationship
colors: neutral white, attackable yellow, friendly green, hostile red. Holding a
free gripping hand near the chin for 0.65 seconds while looking at a visible
creature invokes native Inspect Creature. Its returned details retain Core3
creature-knowledge requirements; client gestures do not grant knowledge.

The fist gesture opens the minimap; touching its surface with a fingertip opens
the datapad. Enlarged datapad panels individually face the viewer, and distant
finger pointing uses the currently rendered fingertip rather than a cached ray.

Crafting lists use native tool compatibility and categories. Leaving one schematic
selected for a second loads its recipe; changing selection cancels the pending
load. The preview includes the description, and original spice appearances are
prepared by the asset pipeline. Area Track uses larger controls, full-width
scroll hitboxes and a central search status while retaining its native search
delay. These changes have headless/mock regression coverage, not headset proof.

The login panel and surrounding sky now use static neutral white stars on black,
with varied point brightness/size and no colored haze or shimmer. Headless menu
and original login audio checks pass. The revised shaders still need visual
review on a GPU: the current sandbox cannot access the desktop display or a
render device. Live VR remains closed pending the user's next launch approval.


### Parties

Bump a free fist with another player: hold grip and trigger on either tracked
hand while the fists meet. Both players' fresh contact is verified by the
authenticated presence service before Core3 creates or joins the party. Bumping
any member can join their party. Native rules choose the initial leader, giving
a Squad Leader priority, otherwise using combat level. Separate or release the
fist before another deliberate bump. Wallet handshakes, held props, drawn weapons
and active interfaces do not supply party proof; a holstered weapon frees its
hand. Confirmed formation/joining shows a short notice.

**Leave Party** remains in the existing armed/unarmed circle and entertainer
circle for every profession. It uses native group removal and does not consume
an armed combat ability. `tests/party_bump_smoke.gd` covers both tracked hands,
wallet exclusion, receipt suppression, native acknowledgement and circle access
with mocked tracking/transport; it does not validate headset interaction.

### Mask Scent gesture

With both hands free, rub an open hand back and forth along the opposite
forearm as if applying lotion. Either arm works; three strokes of roughly
9 cm over at least 0.65 seconds activate the learned Mask Scent ability.
Release grip/trigger on the rubbing hand. No circle selection is required;
the existing circle/A activation remains available. Move hands clear of the
forearms for 0.35 seconds before repeating.

The recognizer follows the original avatar's IK forearm, allows controller
clearance, and ignores brief touches, hand-to-hand rubbing and small jitter.
Held tools/weapons, interfaces, performance, vehicle controls, lost tracking
and unavailable gameplay input block it. Core3 retains skill, cost and cooldown
authority; the gesture does not replace another prepared ability.

`tests/mask_scent_gesture_smoke.gd` covers both arms, 45–120 Hz, locomotion/turning,
negative motions, release/tracking behavior and production controller routing
with mocked tracking and transport. It does not validate live headset ergonomics.

Validation (2026-10-08): clean headless editor import; 36 Mask Scent checks,
19 Scout checks, 50 combat-input checks and 30 gesture-arbitration checks passed
with `--xr-mode off` and the dummy renderer. No live VR launch was performed.

### Entertainer flourish gesture

Clap once in front of your torso while dancing or playing an instrument to
request a random learned flourish through the existing native ability path.
Separate hands by about 32 cm, then bring both inward with palms facing each
other; registration occurs at about 16 cm, allowing controller clearance.
Hands must separate again for another clap. A remains available.

The recognizer reads actual controller poses even when instrument visuals
constrain the rendered hands. Idle/expired performance, open interfaces,
lost tracking/focus, one-handed taps and held contact do not trigger it.
Native costs and recovery remain authoritative.

Validation (2026-10-08): clean headless editor import, 24 clap recognizer/routing
checks, 749 entertainer checks and 30 gesture-arbitration checks passed with
`--xr-mode off` and the dummy renderer. Live headset ergonomics are untested.

First Aid also uses a bandaging motion: with free hands, wrap an open hand around a nearby bleeding player's forearm or your opposite forearm, roughly four-fifths of a turn over at least 0.6 seconds. Move away to rearm. It shares native First Aid costs and recovery; the medical focus remains an alternative. Health is now the survival pool, with Action/Mind reserved for resources; see [the first CU medical balance pass](../docs/CORECU_COMBAT.md).

Health Wound Medpacks are held inventory items: touch yourself or a nearby patient with the pack and trigger. The exact pack supplies one charge on confirmed native success. Diagnose and separate Heal/Tend Wound selections are retired. Only Health can receive player wounds; obsolete wound supplies and recipes are removed. See the [medical dependency audit](../docs/CORECU_COMBAT.md).

Medical inventory supplies now include stims, ranged/area stims, antidotes, fire blankets, state cures, Doctor enhancements and resuscitation kits. Hold a supply against an eligible patient and trigger; ranged stims also support aiming. The native server chooses the treatment from the exact item, pays resources, and consumes one charge on success. With the Doctor tool, aim and tap/release for Tend Damage, double-tap within 0.30 seconds for learned Heal Mind, or hold for 0.65 seconds for Quick Heal. Single tap waits for the double-tap window; a double tap or hold fires only its own action. Selecting First Aid retains its single-tap fallback. Heal Mind needs no selection and transfers the healer's Mind to another friendly player or organic pet, paying the actual restored amount plus Action and leaving at least one Mind. Keep the same tool and patient through the input; changing either, losing tracking or entering medical VATS cancels the sequence. Food/drink now use bounded CU-inspired bonuses and a shared restoration cooldown; see [balance details](../docs/CORECU_COMBAT.md).

Doctor adds resuscitation-kit pad presses, fire-blanket sweeps and friendly
condition targeting. Friendly VATS requires the Doctor tool held: click its
stick while aiming at a friendly patient, then aim at a condition marker and
squeeze/release its trigger. The matching state pack must be in accessible
inventory. Stowing or losing tracking clears the selection; release both
triggers before weapon combat resumes. Held supply contact/trigger application
remains available. Doctor has no ultimate.

Combat Medic uses the same held Doctor tool against hostile targets. Click its
stick to acquire a target, then squeeze/release the Poison, Area Poison, Disease
or Area Disease marker. Each marker names the exact compatible pack and shows
its charges and area radius. Pack selection uses the strongest available pack
that can reach that target; losing it, changing allegiance or losing tracking
cancels an armed delivery. Both effects have one shared channel per target,
bounded potency/duration and shared offensive recovery. Area delivery affects
at most six enemies; area healing affects at most five patients. Combat Medic's
trained debuff potency leads the combat professions while remaining subject to
resistance and immunity. No Combat Medic ultimate is enabled.

Doctor direct-heal training reaches +30% for ordinary stims/Tend and +15% for
Quick Heal; wound treatment retains its +50% specialty. Crafted stim tiers A–E
have distinct potency ranges and cost 6% base Action/8% base Mind on successful
Heal Damage. Inspect a pack for its native healing preview. Each patient can
have one general preparation (Vitality, Endurance or Metabolic) and one
poison/disease prophylaxis. Preparations do not refill current resources. See
[Doctor policy](../docs/CORECU_COMBAT.md#doctor-preparations-and-care-2026-10-09)
for tier bands, costs and the bounded resistance rules.

Companion medical supplies: hold a pet stim or droid repair/reconstruction kit, touch the corresponding creature/droid model and trigger. The server applies the current Health-only treatment and shared recovery rules; ordinary organic medicine cannot repair droids.

Image Design starts by holding two opposing thumb/index L shapes as a frame near eye level for 0.8 seconds. Either diagonal works. With optical tracking, extend thumb/index and curl the other fingers; with controllers, hold grip, lift thumb/index off their controls, and orient the grips as opposite frame corners. Both hands must be free. The frame opens the existing recipient selector, preserving native permissions and recipient consent. Lower or open the frame to rearm; losing tracking/focus cannot repeat a completed hold. Circle-menu access remains. Pet/droid commands intentionally remain in their circle menu.

`tests/image_frame_smoke.gd` and `tests/medical_focus_trigger_smoke.gd` cover mocked input, frame-rate variation, one-shot activation, interruption, permissions, and production routing. Run headless with `--xr-mode off`; these checks use the dummy renderer and do not validate live headset behavior.

Ranged combat abilities now use player-local target markers instead of circle
selection and A-to-prime. Click the weapon-hand stick while aiming at an eligible
creature, then shoot the desired marker: head/Concussion, heart/Lethal Shot,
pelvis/Low Blow, knees/Restraining Shot. A second click on that creature closes
the overlay; clicking a different creature changes targets. Markers follow posed
bones or source bounds, share a world-space plane at target depth, and use normal
depth testing plus scenery/shot-path occlusion. Unavailable abilities disappear.
Last Ditch uses both triggers with both hands physically at the weapon; both
triggers must be released to rearm. The native server still owns cost, cooldown,
range, skill, weapon restrictions, impact and damage. No pause or slowdown occurs.

Validation: `tests/target_abilities_smoke.gd` covers geometry, occlusion, availability,
trigger timing and production weapon routing; `tests/gameplay_combat_smoke.gd`
covers explicit ability/target transport. `tests/target_abilities_capture.gd`
renders original assets with mocked state using desktop Forward+ Vulkan and XR off.

### Weapon-family ability equipment

Open the equipment hologram, then click the physical right joystick to switch to
the loadout editor. Four combat slots sit above the avatar; the left pane holds a
paged ability grid with a separate ultimate row, and the right pane explains the
pointed-at ability. Grip-drag regular abilities to slots, swap occupied slots by
dragging, or return them to the grid to clear. Trigger-click an ultimate to select
it (click again to clear). Click the right stick again to return to equipment.

The current native weapon snapshot supplies the family, learned compatible
catalog and saved 4+1 selection. Changes wait for Core3 confirmation. Confirmed
slots draw lines to source-avatar body anchors; tracking loss, stale weapon
changes and invalid drops cancel drag state. Combat is captured while editing.
The same family shares selections across weapon instances; other families retain
independent Core3 selections. No client file grants or persists RPG abilities.
Empty native melee catalogs are displayed explicitly. Run
`combat_loadout_smoke.gd` with the dummy renderer and `--xr-mode off`; the optional
`combat_loadout_capture.gd` uses desktop Forward+ Vulkan and mocked native state.

Commando's seven supported special weapons use native cone/beam discharges or
physical rockets. Grenades share the trap grip/throw/hip interaction, with
original models and native fuse timing. Focused Discharge and Acid Spray use
VATS; Master Overdrive uses the supported two-trigger ultimate chord. Source
particles remain bounded approximations, with no camera shake. Cryoban/Glop
control voluntary movement while preserving tracked head and room movement.

Squad Leader friendly VATS exposes all five learned group shouts with any
weapon, outside offensive slots. Volley Fire is a selectable any-weapon
ultimate; each member sees and consumes their own native mark. Its large local
reticle remains visible through geometry, and guaranteed cosmetic projectiles
cannot submit another impact. See [support controls](../docs/ABILITY_ACTIVATION.md#squad-leader-support).

PvE bounty missions reuse terminal, NPC, inventory, datapad and waypoint controls.
Trigger a held seeker to search/track; trigger a held Arakyd probe and select a
native search planet. Core3 supplies eligibility, charges, progress and discovery.
See [bounty controls](../docs/ABILITY_ACTIVATION.md#pve-bounty-hunting).

BH combat adds Eye/Torso/Confusion VATS choices, Underhand and Duelist gestures,
Fast Blast, physical scatter pellets and limited lightning guidance. Headless
checks cover moving targets, obstruction, ordinary lair contacts and the shared
native pellet coordinate convention. See
[combat controls](../docs/ABILITY_ACTIVATION.md#bounty-hunter-combat); these are
mocked-tracking checks, not live headset validation.

### Nearby NPC greeting (unreleased)

Look toward an interactable NPC within 3 metres, raise either empty hand near
shoulder/face height, release grip and trigger, and wave side to side. A deliberate
wave with three direction reversals within about 1.8 seconds opens the same panel
as pointing and selecting. Arm movement and raised wrist rotation both work.
Lower the hand before greeting again; there is also a two-second cooldown.

This applies to the existing trainer, delivery, recruiter, broker/informant,
pilot-trainer, chassis-dealer and creature-vendor service records. It initiates
interaction only: purchases, training, travel and dialogue choices still require
their usual confirmation. Look more directly at the desired NPC if several are
close together. Waving at scenery or NPCs without an available interaction does
not invent a dialogue.

Discovery freshness, native room membership, stage collision coverage and line
of sight gate selection. Occupied hands, other interfaces, tracking/focus loss,
small tremor, a single reach and large pose discontinuities cannot complete a
wave. A completed gesture stays latched through lost tracking or closing the
panel until the hand is lowered. Head and controller poses remain tracking-owned.

`npc_wave_smoke.gd` covers 44 synthetic gesture, selection and real service-panel
routing checks with mocked native requests. Existing service UI, coordinator,
gesture arbitration and settings checks also pass. Tests use the dummy renderer
with `--xr-mode off`; no headset behavior is claimed. The change is prepared
locally for the next release, with no release or remote deployment performed.

Prepared mail, interaction and junk-appearance update (2026-10-11):

The datapad footer opens native persistent mail; an unread envelope appears in
its minimap's lower-right corner. Inbox paging, reply, deletion and saving native
waypoint attachments share the existing XR menu surface. Background unread polls
do not interrupt typing. Bank terminals expose Pay with recipient entry and a
review of the native bank fee before sending. The tenkeyless keyboard uses the
same holographic theme and sends keys only to the focused menu field. Standard
scroll containers, item lists, rich text and text editors support pointer drag
scrolling, with clicks deferred until release so a drag does not activate a row.

Survey probes are available from the mail panel and from the held original item.
They consume the selected native survey tool and one probe use, retain the native
quality-based 15–60 minute delay, and deliver the original resource report by
mail. Restart recovery retains the full epoch-millisecond request time.

Herald triggers now open the original greeting immediately; wave/trigger picking
uses the visible replicated NPC position and a five-metre interaction reach.
Loot markers are capped at 1.2 metres above the corpse root and removed after a
confirmed empty loot result, including protection against stale corpse snapshots.

Launcher preparation now includes all ground loot definitions and follows native
shared-template inheritance. Ledger and Damaged Datapad load original models;
all 42 generic junk definitions pass original-appearance, geometry, texture and
hash checks. Of 2,084 loot references, 10 remaining non-junk conversions record
explicit failures (four source mappings/media, five Twi'lek owner-shader hats and
a lightsaber-blade appearance). They are not replaced with invented meshes.

Validation evidence is under ignored runtime/evidence: mail-native-smoke.json,
ground-damage-native.json, mail-ui-smoke.json, junk-appearance-validation.json and
mail-keyboard-preview.png. The 900-second native survey report arrived after a
server restart with unread status and original Naboo resource results intact
(probe-report-delivery.json). UI tests use the dummy renderer; the UI preview uses
desktop Vulkan Forward+. Neither validates live headset behavior. These changes
are prepared locally for the next release; the Downloads client and remote realm
were not patched or restarted for this work.


Rodian Mabari clothing and NPC/forage interaction corrections (prepared locally)
-----------------------------------------------------------------------------
The installed human-only equipment selection omitted Rodian male Mabari
Armorweave boots, although their original appearance was present. The launcher
recipe now prepares registered clothing and armor against all twenty original
player rigs after character animation preparation. Native `playerRaces`
inheritance limits applicable pairs; source body bones, rest poses, owner
materials and hashes are retained. An unchanged verified variant is reusable on
subsequent preparation runs. Twi'lek hats resolve their original lekku/skull
owner shaders instead of failing the body-only alias resolver. No replacement
art or proprietary media is committed.

Preparation produced 8,520 applicable wearable variants from 803 registrations
across twenty rigs. The complete inventory audit validates 8,605 equipment
models, including previously prepared weapons, without integrity errors. All six
Mabari pieces pass on fourteen native-allowed rigs; the 197-check clothing test
also samples 26 Rodian clothing families. Original species and Imperial faction
equipment restrictions remain authoritative. Missing artwork adds no new equip
restriction. The five previously failing Twi'lek owner-shader hats now convert.

Coverage is not complete: supplied media lacks `bodysuit_s07_f.sat` and
`earring_s05.apt` (36 applicable variants), besides abstract base registrations.
Rigid Rodian earring/ring attachment also remains unresolved: conversion of a
preview does not establish an original equipped hardpoint. These are recorded
separately in `runtime/evidence/player-equipment-audit.json` and
`player-clothing-smoke.json`, not replaced with invented meshes. Desktop Vulkan
`rodian-mabari-preview.png` visibly confirms the boots and full armor.

NPC clicks target an upright body volume from any side, regardless of heading
or screen metadata. Creature vendors use the same NPC classification as waves;
terrain presentation offsets move the interaction point with the visible actor.
Waves can use an unobstructed torso sample if the head sample is obscured.
Collision and native range/cell checks still apply.

Forage uses three deliberate scoops with both hands near the floor. Controller
origins can remain 15–20 cm above it; a scoop rises at least 8 cm, and hands may
stay within 45 cm during the gesture. The ground query includes the locomotion
floor layers and excludes the player body. A completed gesture survives a brief
background status request, expires after two seconds, and cancels on lost
tracking or an unavailable interaction. Native CoreCU still determines skill,
posture, location, cooldown and reward eligibility.

Regression entry points: `player_clothing_smoke.gd`, `player_clothing_preview.gd`,
`npc_wave_smoke.gd`, `npc_visibility_smoke.gd`, `services_controller_smoke.gd`,
`scout_smoke.gd`, `tools/assets/audit_player_equipment.py`, and
`tools/assets/test_inventory_cache.py`. The before-preparation clothing test
reproduces missing Rodian Mabari appearances. Headless gesture tests use synthetic
tracking, not a headset. These changes are staged for a future release; they do
not update the running Downloads client or live realm.

Held-weapon readout (prepared locally)
-------------------------------------
Ranged weapons carry a capacity bar and firing-mode light on the rear of the
original mesh, tilted upward 30 degrees. Single fire is blue, automatic fire is
steady red, and burst fire uses three red flashes. The bar tracks remaining
shots; consumable weapons track observed native charges independently of crafted
magazine statistics. Holstered weapons and melee weapons hide this display.
The old held labels, weapon statistics and buff text are removed. Inventory and
crafting statistics remain available. The display does not change grip pose,
muzzle direction, collision bounds or controller tracking.

`weapon_readout_smoke.gd` covers capacity, empty/refill, native charges, modes,
holstering and unchanged weapon geometry. `weapon_readout_preview.gd` captures
the original pistol, carbine and rifle in standalone desktop Vulkan Forward+;
this does not validate headset readability. XR input and Commando, Rifleman and
Carbineer routing regressions pass with the new display.

Bestine decoration and roaming-citizen corrections (prepared locally)
-------------------------------------------------------------------
Inspection of `Downloads/rec.mp4` identified overlapping consoles in Bestine's
association hall. Native housing snapshots include authored public-building
furniture; housing presentation rendered it again without the static building's
rotation. The world stream now exposes object ownership and building orientation.
Housing skips those objects, removes duplicates when a chunk arrives late, and
uses the original building basis for genuinely dynamic furniture in public
buildings. Player furniture remains interactive. Service presentation also uses
the shared NPC classification, avoiding a second frozen pilot-trainer mesh.

Passive roaming citizens sample their original cell floor at their current
interpolated position. Exterior approach floors supplement terrain support.
Corrections are bounded to 1.5 metres and retain native position, cell ownership
and server navigation; missing cells do not borrow an unrelated floor. Combat
actors, sitting/dead/incapacitated actors and nonhumanoid rigs are excluded.
This corrects visible floor following, not horizontal server pathfinding.

`actor_floor_projection_smoke.gd` passes 31 checks, including real Bestine
interior and exterior slopes, ascent/descent, missing cells and combat exclusion.
Housing, streamed-world ownership/unload, NPC motion and interaction regressions
pass. Standalone Vulkan `bestine_decor_preview.gd` reproduces the old two-copy
console with `-- --before`; the fixed capture has one original instance. Images
are under `runtime/evidence/rec-inspection/bestine-{before,after}.png`. These
captures do not connect to the server or validate live headset behavior.

Original pilot trainer/progression inspection
--------------------------------------------
The filmed trainer is Lt. Akal Colzet. His Core3 mobile has an empty
`conversationTemplate`, and `StormSquadronScreenplay:start()` is empty. The
existing native conversation bridge correctly requires a real screenplay;
changing NPC facing or exposing a generic dialogue cannot supply this progression.
Eight map-marked pilot trainers have no conversation: Akal Colzet, Barn Sinkko,
Da'la Socuna, Denner, Dravis, Hakassha Sireen, Shamdon Kree and V3-FX.

The pinned [original Akal conversation](https://github.com/SWG-Source/dsrc/blob/e3aac29b55b46fec2ce2b1518db80a8f70d798a5/sku.0/sys.server/compiled/game/script/conversation/tatooine_imperial_trainer_1.java)
contains enlistment, novice skill and eligible starter-ship grants, then:

1. Patrol `tatooine_imperial_1`, splitting into a three-pirate surprise attack.
2. Destroy four pirates in `tatooine_imperial_2`.
3. Patrol `tatooine_imperial_3`, splitting into a freighter escort.
4. Assassinate the pirate leader in `tatooine_imperial_4`.

Reward-received flags unlock the next mission, independently of victory flags;
failed/aborted missions can be retried. Rewards, faction standing, training,
repeatable destroy/escort duties and authorization to transfer to the next
trainer belong to persisted server progression. Original `faceTo` calls turn
the NPC after interaction; they are not a player approach-angle requirement.

Five original Storm conversations and eight Akal mission tables were inspected.
Their pinned hashes and comparison with Core3 and supplied dialogue can be
rechecked using `python3 tools/space/audit_pilot_progression.py` after placing the
recorded reference corpus in ignored `runtime/reference/pilot-progression`.
The audit is read-only and records `playable_progression_validated: false`.
The later source references 70 Akal dialogue keys absent from the supplied
Total Experience STF; the other four conversations also differ. A compatible
port must reconcile those branches, implement quest/skill/reward persistence
through Core3's existing space quest handlers, and validate the mission chain,
relog recovery and duplicate-reward protection. Server mission tables are not
missing client media. Akal's full conversation/progression is not implemented
by this client patch.

Datapad layout update (2026-10-13):

The main floating datapad is square (36 cm, 900 × 900 pixels). Opening the
planet or sector map expands it to 70 cm and 1260 × 1260 pixels; returning to
entries restores the compact square. Hold the pointing trigger and drag the
description text to scroll, or use the stick. Captured pointer motion also
reaches the existing map/list drag handlers. Tracking loss cancels a pending
drag without replaying a click. The detached side panes retain their size.

Validation: 63 production SubViewport input checks, 98 mocked view-follow
checks, and the datapad UI smoke pass with the dummy renderer and XR off.
These checks do not validate live headset rendering.

Published as [test.23](https://github.com/jebot-git/swgxr/releases/tag/v2026.10.13-test.23)
from source commit `6cf7a77`. Linux and Windows packaged preflights passed (Windows
through Wine), all 18 test.14–22 incremental bundles reconstructed the target
manifests, and all 24 uploaded asset sizes and SHA-256 digests matched. Launcher
discovery selects test.23 with nine patches per platform. Release evidence is in
`runtime/releases/test23-20261013/`. No server changes or live client launch were
performed.
