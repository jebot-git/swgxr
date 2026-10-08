> Current target: VR first, standard OpenXR and Godot XR Tools. Quest through
> SteamVR/WiVRn is the initial hardware, with a possible Windows client later.
> Tracking drives head/hands and physical posture; the previous desktop animation
> milestone is retained for asset inspection, not the VR control model.
> All non-headset tests/imports must pass `--xr-mode off`.

# Rough prototype agent workflow

## Intended result

A native Linux Godot client imports assets from the user's original SWG installation media, creates/selects a real persistent Core3 character, then enters a bounded Mos Eisley starport test stage with mouse look, WASD locomotion, gravity, and environmental collision.

This milestone uses local Godot locomotion. It does not implement multiplayer action simulation, NPC AI, authoritative combat, or a Godot dedicated zone server. A separate opt-in [local ranged combat lab](COMBAT.md) now exercises weapons against training targets. Those remain the next architecture milestone; Core3's movement/combat behavior is not a compatibility target.

## Parallel work and handoffs

| Owner | Work | Deliverable | Dependency |
| --- | --- | --- | --- |
| Assets | Extract original media, index TREs, interpret IFF/snapshot/portal/mesh data, convert textures | Local scene manifest, mesh geometry, textures, provenance and compatibility report | User-provided ISOs |
| Backend | Pin/build Core3 + Engine3 in an isolated container, start MariaDB, expose real character operations | Loopback HTTP adapter and persistent local Core3 instance | Available TRE archives |
| Client | Character UI, native C++ GDExtension, first-person controller, collision and diagnostics | Godot project, reproducible native build, and smoke tests | Agreed manifest and HTTP API |
| Integrator | Startup profile, gated starport spawn patch, workflow, launch commands, independent verification | Reproducible steps and evidence | All three handoffs |

Agents own separate directories as specified in AGENTS.md. Communicate schema changes before implementing consumers. Root reviews integration rather than accepting each component in isolation.

## Native client boundary

Use C++ for reusable movement behavior and bulk mesh/collision construction.
Expose these as Godot GDExtension classes so the later headless Godot zone server
can reuse them. Keep prototype menus, HTTP orchestration and test scenarios in
GDScript. Pin the binding source revision and regenerate bindings from the local
engine API; do not rely on an unrelated binary downloaded for another Godot build.
The movement regression and imported-wall test must exercise the native classes.
This establishes a reusable implementation boundary; performance gains require
measurement rather than an assumption that rewriting everything is faster.

## Data contract

- Keep media, extracted TREs, converted geometry/textures, caches, server data, and logs out of Git.
- Asset preparation must use the supplied files; never silently substitute downloaded game data.
- Preserve asset identity and archive precedence. Record missing files and failed conversions.
- The retained starport stage and streamed scenery share one original-cell classifier; full Tatooine terrain streams separately. Keep source coverage and presentation limits explicit.
- Server character IDs cross JSON interfaces as strings so their 64-bit values remain intact.
- Character creation, listing, and entry must come from actual Core3. A separate offline asset-inspection path may exist, visibly labeled.
- Player models retain original skeleton hierarchies, skin weights, morph deltas,
  palette choices, and clothing occlusion zones. Mesh construction runs in the
  native extension; appearance controls and preview orchestration use GDScript.
- Character appearance after entry must come from Core3's replicated character
  and equipment state. A cached creation request cannot stand in for persistence.

## Milestones and gates

1. **Media audit:** inventory archives and report differences from the upstream Core3 TRE profile. Prove the chosen snapshot, starport geometry, interior meshes, and textures exist locally.
2. **Native scene:** import authentic geometry into Godot, render it, ground the player on real geometry, and verify collision against a loaded environmental surface.
3. **Persistent identity:** build/run Core3, create a character through its real creation path, list it in another session, and select/zone it successfully.
4. **Integrated entry:** use the client UI/API to create/select a character and enter the starport stage. Keep creation failures distinct from graphics/asset failures.
5. **Independent QA:** parse/import scripts, run collision and HTTP smoke tests, capture rendered evidence, check logs, verify no original assets are staged in Git, and document exact limitations.

## Character and avatar milestone

The asset owner imports the playable species, customization tables, hair,
starter clothing, and animation data from the active local TRE profile. The
backend owner extends real creation packets and decodes replicated appearance,
equipment, skills, and biography. The client owner implements appearance preview,
creation controls, and the in-world player body, including an inspection camera.

Integration gates are original-asset provenance and valid skin bindings; rendered
preview and morph checks; customized creation followed by independent Core3 entry
and appearance readback; and the existing imported-stair, room collision, and
movement regressions with the avatar attached. Record incomplete material or
animation behavior explicitly instead of claiming original-client fidelity.

## Failure handling

If an archive version is absent, record it and try a bounded configuration using existing files. Changes to Core3 must be narrowly gated for this prototype and stored as replayable patches. If a core startup failure remains, continue independent client/asset work, but never report an offline viewer as completed Core3 integration.

## Next milestone after this prototype

Use a headless Godot zone server for authoritative movement and AI, and a service adapter for Core3's persistent skills, inventory, markets, crafting, and cities. Add input/snapshot networking, reconnect recovery, and uniquely identified reward transactions before introducing action combat.

## Tracked avatar and finger milestone

Core3 appearance now feeds the same original avatar renderer in XR. The native
`SwgTrackedIK` and `SwgFingerRetargeter` own reusable solving; GDScript collects
standard OpenXR poses/actions and manages presentation. No solver writes to the
tracked origin/camera/controllers. First-person head masking partitions source
triangles by original skin weights; observer geometry and customization survive.
Full-body/face AnimationPlayers are disabled while tracking owns the skeleton; masked original clips drive only untracked pelvis, spine and legs for locomotion and physical crouching.

Validate all 20 source rigs for bounded arms, source bone lengths, head alignment,
physical crouch stance and hand/finger input. Hand rigs are sparse: thumb, index,
and ring/shared remaining-finger chains with two joints each. Accept valid runtime
hand skeletons through XRHandTracker; fall back per hand to grip/trigger/touch
poses. Do not equate an Index interaction profile with available skeletal data or
claim five independent fingers from these original meshes. Keep project action
bindings separate from the unmodified pinned XR Tools addon. Automated tests and
GPU captures must use `--xr-mode off`; live Quest/Index validation remains separate.


## Environment restoration milestone

Asset ownership covers Tatooine environment palettes, original audio dependencies,
static interior/child-object geometry, NPC appearances and provenance. Backend
ownership exports deterministic, authored NPC placements from pinned Core3 sources,
with source cells and unresolved dynamic variants recorded. Client ownership keeps
streamed cells and exterior collision membership coherent and supports original
NPC rigs. Integration owns region/day-cycle presentation, bounded audio residency,
baked vertex materials and end-to-end regression evidence.

Gates: source hashes and asset structure validation; all supported NPC templates
loading with original animation; cross-city NPC retirement/reload; streamed interior
entry and unload; imported stairs and grounded XR mock entry; day/night regional
palette and original audio playback tests; desktop rendered interior/exterior evidence.
Never turn these into claims of live headset comfort or exact original rendering.
No gameplay/action menus are part of this milestone. Preserve native OpenXR-neutral
tracking and the existing local Core3 character persistence boundary.

## Authored collision and VR observation correction

1. Retain portal-cell membership across frames. Transition only through finite source
   portal polygons; use a separate conservative seed for loading/teleports. Keep
   source exterior ramps available at entrances. Render the exterior through portal
   openings independently for the headset and spectator cameras.
2. Import POB CELL collision extents as well as parent APPR extents. Preserve FLR
   triangle connectivity, edge flags, portal indices and fallthrough flags. Apply
   the original FLR <=0006 post-load normal reversal, retaining raw source normals
   and a correction marker. Explicit NULL means no static collider.
3. Use native authored support, a capsule support envelope and source edge
   constraints for grounded controller and room-scale movement. Preserve airborne
   motion. Step tolerances must not reject millimetre-scale movement at high
   physics rates. Test complete vertical profiles rather than endpoints alone.
4. Publish streamed collision before activating interior exclusions. Exterior
   terrain remains intact above buried rooms. Use the same clipped AEXC triangles
   for terrain rendering and physics; refine original exclusion boundaries on a
   shared lattice across LODs. Apply interior visual masks per camera.

Turning preferences live in `user://swgxr_vr.cfg`; application UI selects snap or
smooth turning without modifying XR Tools. Stereo rendering uses a dedicated
shared-world viewport. The root window displays a separate mono spectator viewport
with full avatar/head layers, swept-camera collision and a 30 FPS render cap.

Regression evidence is in ignored `runtime/evidence/`: authored collision asset
validation, ground support, portal membership, authored house/world collision,
60/90/120 Hz ground profiles, imported starport stairs, main XR integration,
turning, spectator and two-view portal rendering. All automated tests run with
OpenXR disabled and synthetic tracking; GPU captures do not validate live headset
comfort or runtime submission. Keep the live headset session separate from testing.

The global source regression covers all 160 imported buildings and 3,862 directed
portals, including short movements, wide doorway edges and split-frame crossings.
Full-scene tests additionally traverse the original starport stairs and the reported
house entrance using both controller input and physical room-scale translation.
These are shared algorithms, with no location-specific support planes or building
ID exceptions in movement or terrain code. Rare original wall-base re-entry rules
and the original multi-contact solver are not reproduced exactly; preserve their
source metadata rather than asserting full legacy collision parity.


## Forward+ viability targets and benchmark boundary

The supported presentation target is PC VR using Forward+ on Vulkan. Runtime
policy rejects other GPU renderers/drivers; headless validation remains allowed
with OpenXR disabled. Renderer selection is enforced before launcher service
startup for explicit overrides. Every automated invocation uses
`--xr-mode off --audio-driver Dummy`.

`tools/benchmarks/run_suite.py` runs separate synthetic authority and actual-asset
rendering workloads at 16 players + 16 NPCs, 32 + 24, 64 + 32, and 128 + 64.
These are test loads, not supported population claims. The simulation models
bounded actor movement, pooled projectile sweeps, interest management, serialized
snapshots, latency/loss/reordering and independent instance IDs. It does not
connect to Core3 or real network sockets, and its simple NPC movement is not a
pathfinding benchmark. Headless time measures CPU work in unpaced fixed ticks.
Original-stage collision has a separate native batch-query benchmark.

The rendering fixture loads original local stage, terrain, scenery and character
assets. Optimized effect mode exercises the production native batches and enforced LOD
budgets. `--effects source` retains the costly source playback for comparison;
`--effects surrogate` isolates simpler pooled bolts. Reports include omitted visuals.
Sound and transient source lights are excluded from this fixture. A two-view run
is a synthetic stereo workload using separate viewports, not an OpenXR multiview
or headset test. Reports include CPU/GPU and wall-frame timing where available,
frame-budget misses, scene counts, effects and provenance. Missing timings are
not replaced with invented zero measurements.

```sh
# Functional coverage; short duration never establishes performance qualification.
python3 tools/benchmarks/run_suite.py --quick --output runtime/benchmarks/smoke
# Meaningful duration, one controlled profile or all four default tiers.
python3 tools/benchmarks/run_suite.py --mode simulation --duration 30
python3 tools/benchmarks/run_suite.py --mode render --duration 15 --warmup 5 --views 2 --width 1920 --height 1920 --effects optimized
# For cleaner timing, close competing Godot sessions normally before using this.
python3 tools/benchmarks/run_suite.py --require-idle --views 2 --effects optimized
# Independently checks original geometry across cells and pooled ray throughput.
godot --headless --xr-mode off --audio-driver Dummy --path client --script tests/combat_collision_smoke.gd -- --benchmark
```

The suite writes commands' logs, profile JSON, captures, host metadata and an
aggregate summary under `runtime/benchmarks`. Correctness success is separate
from meeting timing or bandwidth targets. Existing XR clients are never stopped
by a benchmark; concurrent Godot processes are recorded as measurement contention.
The normal suite exits nonzero on correctness/load errors; timing failures remain
reported results suitable for comparing implementations. A 90 Hz render target
means 11.11 ms per frame; simulation uses 60 Hz with a 16.67 ms hard tick budget.

Prototype correction: collision query geometry is independent of the rendering
observer and collider enable flags. Projectiles carry their own portal-cell state;
missing world/terrain coverage is explicitly incomplete rather than an unobstructed
shot. Streaming can retain the union of multiple simulation observers. The existing
single-player movement cell filter remains separate from projectile queries.
Projectile presentation uses bounded native tracer handles and shared MultiMesh
batches; reaching the visual budget does not discard simulated shots or change
their hits. Source-reference playback is excluded from the production path.

Production multiplayer remains a separate milestone: persistent authoritative
sessions, prediction/reconciliation, ownership/version checks and duplicate-safe
Core3 progression transactions are still required. No benchmark creates or alters
user characters, skills, inventory, rewards, markets or cities.

### Local baseline, 2026-10-04

The independent synthetic authority suite passed all correctness checks, with
p99 tick CPU times of 0.132 / 0.378 / 1.099 / 4.397 ms at the four population tiers.
These exclude authored geometry and real networking. The largest tier emits about
2.16 Mbps of uncompressed payload per player; delta snapshots and tighter relevance
need separate evaluation. Original-starport geometry queries passed a 4 ms budget
at 480 sweeps per tick (p99 3.176 ms), measured separately from actor simulation.
Do not add these independent percentiles into a claimed full-server tick result.

Evidence is local in `runtime/evidence/action-simulation-suite.json` and
`runtime/benchmarks/geometry-baseline/`. Preliminary source-particle rendering
missed the 90 Hz budget, while the 16-player no-effects control was substantially
faster. Final rendering qualification remains pending: preview sizing was corrected
after visual review, and further GPU runs stopped when a live XR client started.
The fixture now uses explicit eye resolutions, a fixed preview, and rejects a
crowd outside its camera frustum. Run the documented render command with
`--require-idle` after closing the live client normally. This checks for competing
Godot sessions before each profile; it does not isolate the CPU or GPU from all
other applications. Review notes: `runtime/evidence/viability-render-review.json`.

The upright wrist datapad passed 41 interaction/placement checks, including wrist
roll and vertical screen extension, with a desktop Forward+ capture. These use
mocked tracking and do not establish live headset comfort.

### Native particle comparison, 2026-10-04

The production renderer now uses native batched, source-derived effects with hard
LOD and allocation budgets. These replace the earlier per-particle scene nodes.
The final fixture uses fixed 1600×1600 eye viewports, a 1280×800 preview, the full
crowd in view, five seconds of warmup and 15 seconds of measurement on Intel Arc
A770 / Godot 4.7.2 Forward+ Vulkan. Two separate views are a desktop screening
workload, not an OpenXR runtime measurement. No other Godot session was present at
profile start; general CPU/GPU isolation was not enforced.

| Players + NPCs | Legacy effects p95 frame | Native effects p95 frame | 90 Hz screening target |
| --- | ---: | ---: | --- |
| 16 + 16 | 34.40 ms | 8.79 ms | Met |
| 32 + 24 | Not rerun | 11.94 ms | Missed |
| 64 + 32 | 83.18 ms | 18.32 ms | Missed |
| 128 + 64 | Not rerun | 34.05 ms | Missed |

The 64 + 32 no-effects control measured 17.49 ms p95, so that scene still
misses 11.11 ms even without particles. The native implementation reduces particle
cost substantially; it does not establish 90 Hz support for the larger populations.
Every native profile stayed within the particle, tracer and render-node caps; the
largest reached the 2,048-particle ceiling and intentionally omitted visuals.
Original source playback and the optimized approximation are different visual
workloads by design. Omission counters include repeated visibility decisions,
not counts of distinct events. No gameplay shots were removed by visual limits.

Evidence: `runtime/evidence/particle-implementation-summary.json`,
`runtime/benchmarks/particles-{legacy,optimized,control}/`, and side-by-side
captures under `runtime/evidence/particles/`. Verification passed 40 native LOD
checks, 14 integration checks, 58 ranged-combat checks, 34 mocked-XR combat checks
and 12 actual-stage movement cases. Live headset appearance remains unverified.

### Live VR observation, 2026-10-04

`tools/benchmarks/capture_live_vr.py` collects the running WiVRn performance feed
and Linux process/thread/DRM counters without restarting, injecting into, or
changing the client. It does not add the synthetic crowd to a live session.
Run with the current Godot PID and the runtime pacer ID selected by launch
correlation; the feed does not expose an authoritative PID-to-pacer mapping.

```sh
python3 tools/benchmarks/capture_live_vr.py --pid <godot-pid> --app-id <pacer-id> --duration 60 --output runtime/benchmarks/live-vr
```

The captured live session (Godot PID 683299, correlated pacer 32) completed 1,205
application frames over 59.93 seconds: **20.11 FPS against 72 Hz**. Main-thread CPU
usage averaged 95.19% of one core; total client CPU 107.93%; selected-process DRM
render-engine activity 14.00%; resident memory about 2.03 GiB. These observations
point to a client main-thread bottleneck and do not identify the expensive
script/native subsystem. The headset stream continued delivering about 72 frames/s;
stream delivery does not imply 72 distinct application frames/s.

The runtime's sampled, smoothed frame interval had p95=57.92ms. This is not raw
per-frame p95. Its CPU pacing value is capped at three refresh periods and includes
submission/waiting; GPU-wait time is not the full GPU rendering duration.
Encode-to-display averaged 46.6–48.1 ms per stream, excluding earlier application
work and not equivalent to motion-to-photon latency. No competing benchmark was
launched. Live headset rendering has now been observed through runtime telemetry;
subjective visual quality and comfort were not assessed.

Raw snapshots and process samples: `runtime/benchmarks/live-vr-20261004/samples.jsonl`.
Capture summary: `runtime/benchmarks/live-vr-20261004/summary.json`. Capture validity
and meeting the performance target are separate fields. This live workload is not
directly comparable to the fixed-camera desktop crowd fixture.

### Interior restoration and asynchronous loading, 2026-10-04

The missing cantina furniture was an importer omission: original building
`interiorLayoutFileName` references were not instantiated. Inherited template
properties and the original interior soundscape table were also missing from the
audio export. Conversion now restores 7,114 static decorations across 48 buildings,
including all 258 static Mos Eisley cantina layout entries and both authored sound
objects. The 196 exported soundscape rows select exact POB/cell, building default,
then global default. Adjacent rooms sharing a cue retain playback. SD2D band and
ambience objects remain audible within their owning building; this does not yet
reproduce the original portal acoustics. Music samples respect the music volume bus.

Two world workers perform chunk parsing/filtering, geometry packing, texture decode
and mip generation, and native combat BVH/floor-support preparation. Completed
native regions transfer ownership on the main thread. Scene nodes, physics objects,
GPU uploads and region publication remain on the main thread, following
[Godot's thread-safety constraints](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html).
Authored collision and physics synchronization precede region publication and
terrain cutouts. Generation tokens reject stale chunk/publication results after
travel. Worker shutdown joins outstanding work.

Queues are bounded at 64 descriptors per world job kind; at most two mesh results
are prepared/in flight. Mesh/image results are limited to 64 MiB each and input
files to 32 MiB. Unreferenced geometry has a 64-mesh/128-MiB warm-cache limit;
actively resident geometry is not capped by that eviction budget. Main-thread
installation uses a cooperative 3 ms budget and one mesh upload per frame, so a
single upload or physics call can exceed it. Audio separately uses two decode
workers, 32 pending requests and a 32-stream/64-MiB compressed-data cache; active
players retain their own resources. These limits do not cap total client memory.

The actual cantina fixture loads five chunks, 3,268 instances and all 258 expected
decorations, checks the two authored audio players, verifies band continuity in
the adjacent alcove, then checks that cantina cues leave residency outdoors:

```sh
godot --headless --path client --xr-mode off --audio-driver Dummy --script tests/cantina_integration.gd
godot --path client --xr-mode off --audio-driver Dummy --display-driver wayland --rendering-method forward_plus --rendering-driver vulkan --script tests/cantina_integration.gd -- --capture --output=res://../runtime/evidence/cantina-render.json
```

With restored assets in both runs, the synchronous observer request took 126.18 ms;
the threaded version took 0.45 ms. Moving decoding alone left a 50.32 ms publication
spike; native preparation/adoption reduced the measured publication peak to 2.68 ms.
Headless loading-loop p95 changed from 11.58 to 7.03 ms, maximum from 54.75 to
7.36 ms. Spreading installation increased readiness time from 2.47 to 4.51 seconds.
Initial manifest configuration remains synchronous (about 58 ms). These are local
headless loading observations, not headset FPS or full-application frame budgets;
the combined fixture does not include every live rendering subscriber.

Comparison evidence: `runtime/evidence/cantina-before-threading.json`,
`cantina-threaded.json`, and `cantina-publish-adopt.json`. Provenance and conversion
checks are in `runtime/evidence/interior-assets-validation.json`. All 90 exported
sound definitions decoded in `environment-async-smoke.log`. Dummy audio checks
playback state, not audibility. Unsupported content outside the cantina remains
audited: 276 wholly unsupported layout placements, nine omitted component children
and one missing unrelated music cue. See `tools/assets/README.md` for refresh commands.

Final regressions passed all 12 actual-stage starport movement cases, combat
collision and multi-observer residency, full world streaming/unloading, geometry
and baked-color parity, native floor adoption/removal, same-key cancellation,
queue/result/cache limits and shutdown during active work. Logs:
`runtime/evidence/final-world_stream_smoke.log`, `final-world_threading_smoke.log`,
`threaded-xr_starport_exit_smoke.log`, `threaded-combat_collision_smoke.log` and
`threaded-combat_residency_smoke.log`. The desktop Forward+ Vulkan cantina fixture
also passed (`cantina-render.json`); `cantina-interior-1.png` shows the restored
furniture and bar fittings. These captures do not validate headset appearance.
The final capture fixture checks actual FLR support beneath its observer and uses
verified walkable camera positions; an earlier camera inside a bar interstice
exposed exterior roof backfaces. Original mesh parity and the camera diagnosis
are recorded in `runtime/evidence/cantina-capture-geometry-diagnosis.json`.

### Initial loading presentation

`client/scripts/loading_screen.gd` covers the desktop/spectator with an opaque
CanvasLayer and the headset with an isolated render layer, dark surround and
camera-attached status panel. The exact prior headset cull mask is restored on
completion. Camera tracking is unchanged, and geometry near the headset cannot
show through. Main entry yields a rendered frame before synchronous preparation,
reports real phases rather than estimated percentages, and retains the existing
movement gate until terrain, scenery, collision synchronization and spawn placement
complete. Required world/terrain failures remain visible and keep movement paused;
Menu/Esc returns to the menu. Original asset errors are not converted into success.

The lifecycle fixture checks actual-stage entry and a deliberately missing world
manifest. Its desktop Vulkan variant also places a bright object 0.5 m in front of
the camera to verify it is hidden by the headset presentation. Captures:
`runtime/evidence/loading-desktop.png` and `loading-head-view.png`. The latter is a
desktop camera exercising the headset presentation, not a live OpenXR capture.
The mocked-XR main fixture separately distinguishes covered spawn repositioning
from visible falling and checks post-entry grounding and the missing-floor gate.

```sh
godot --headless --path client --xr-mode off --audio-driver Dummy --script tests/loading_screen_smoke.gd
godot --path client --xr-mode off --audio-driver Dummy --display-driver wayland --rendering-method forward_plus --rendering-driver vulkan --script tests/loading_screen_smoke.gd -- --capture
```

### Global instance-uniform capacity

Restored interior furnishings exposed Godot's default global shader buffer limit
in the full client, especially when nearby NPC avatar parts were added. In the
running Godot commit `ed1daf0bf`, Forward+ reserves **16 slots per geometry
instance using any instance uniform**; each slot is 16 bytes. Our two static
instance parameters therefore reserve 256 bytes together, rather than two floats.
The existing portal-building and indoor-lighting parameters remain intact.
See the [allocator and buffer construction](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/material_storage.cpp),
[value/usage structures](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/material_storage.h),
and [16-slot instance limit](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/shader_language.h).

`rendering/limits/global_shader_variables/buffer_size=524288` is a **slot count**.
With the current seven global slots, capacity is
`floor((524288 - 7) / 16) = 32767` geometry instances, versus 4095 at the
[65536-slot default](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-global-shader-variables-buffer-size).
The reservation costs 8 MiB GPU storage, 8 MiB CPU values and 2 MiB CPU usage metadata,
plus 513 dirty-region bytes and allocator/hash overhead: approximately 18 MiB total,
an increase of 15.75 MiB over the default. It does not multiply by eye count for a
shared scene.

The conservative asset audit counts all 23,408 Tatooine world mesh records,
428 retained-stage records and 4,096 additional actor/transient **geometry instance**
blocks: 27,932 blocks, leaving 4,835 spare. This deliberately double-counts retained
objects normally filtered by the streamer; it is uniform storage headroom, not a
claim that the full planet should render concurrently or that 32767 draw calls
meet the frame target. Existing streaming, NPC, particle and LOD limits remain.

```sh
godot --headless --path client --xr-mode off --audio-driver Dummy --script tests/shader_instance_budget_smoke.gd
```

`runtime/evidence/shader-instance-budget.json` records the source URLs, active
setting, global-slot calculation and current asset counts. This headless audit
does not test GPU allocation; the full-entry Forward+ Vulkan run must additionally
finish without `global_shader_parameters_instance_allocate` errors.

The final full application entry completed cleanly on Forward+ Vulkan after this
correction (`runtime/evidence/loading-full-entry.log`, exit 0), with source
decorations and NPCs visible in `loading-complete-world.png`. Loading lifecycle
validation passed 13 checks. The final mocked-XR run observed 789 covered loading
frames with physics disabled, no uncovered vertical drop and about 2 mm of
post-entry settling (`xr-main-loading-smoke.log`). Initial NPC residency now
finishes before the loading cover is dismissed. Live headset comfort and audio
audibility remain unverified for these changes.

### Equipped NPCs and fixed-client live profiling, 2026-10-04

The cantina's apparently unskinned band members were missing Core3-authored
outfits. Their original body weights, skeletons and clips were valid. The general
export now includes seven outfit variants (38 clothing/hair entries and four
instruments) and deterministic original primary weapons for 445 eligible NPC
placements. Three probot intrinsic weapons are excluded. Outfit/weapon identity,
original CDF clothing, customizations, arrangements and provenance remain in the
local manifests. This is ambient presentation, not live Core3 equipment state.
Two pre-existing missing wearables remain audited: the Valarian leader's hat and
Desert Demon gloves.

Rigid equipment uses source-driven `BoneAttachment3D` children, shared resources,
bounded caches and NPC residency cleanup, without gameplay colliders or animation
overrides. Asset validation, all five band appearances, their four instruments,
and all 18 selected weapon templates passed. The back-rifle carry and reticle
corrections are described in `COMBAT.md`. The actual Forward+ occlusion fixture
passed with both opaque and transparent foreground geometry.

The fixed client was relaunched into live WiVRn OpenXR at the cantina (PID 717733,
launch-correlated pacer 34), using Forward+ Vulkan and the third-person mirror.
`runtime/evidence/npc-fixed-live-mirror.png` shows clothed band members with
instruments and the lowered back rifle. This is a live desktop spectator capture,
not a recording of the headset's stereo images. The session is explicitly offline
asset inspection with the combat lab; it does not benchmark a connected Core3
server, network combat, or a synthetic MMO crowd.

The opt-in `--runtime-profile=/absolute/output/directory` diagnostic waits for
world readiness, warms up for 10 seconds, profiles scripts for 20 seconds, stops
that profiler, settles for 5 seconds, then records a 70-second baseline. It writes
bounded raw process-callback intervals and one-second engine/scene monitor samples.
The external 60-second WiVRn/process capture runs within that baseline. Profiling
ends automatically and leaves the client running. Parse its stdout with:

```sh
python3 tools/benchmarks/summarize_script_profile.py <client.log> --output <script-profile-summary.json>
```

The completed run is `runtime/benchmarks/live-vr-fixed-20261004T113133Z/`:

| Measurement | Result |
| --- | ---: |
| Completed application frames / observation | 1,381 / 59.94 s |
| Application FPS / runtime target | **23.04 / 72 Hz — target missed** |
| Raw process-callback interval mean / p95 / p99 | 43.33 / 47.26 / 51.77 ms |
| Main thread / whole process CPU, one-core basis | 94.44% / 105.86% |
| Selected-process GPU render-engine busy | 15.38% |
| Mean resident memory | 1,860 MiB |
| Mean draw calls / rendered objects / primitives | 1,885 / 4,848 / 1.19 million |
| Mean engine physics monitor | 1.76 ms |

CPU saturation with low measured GPU activity strongly indicates a main-thread
bottleneck. The following priorities distinguish measurements from hypotheses:

1. **Native scene/render work is the leading unproven cause.** Draw calls ranged
   from 1,450 to 3,980 across all viewports. Resident scenery included 3,638 world
   mesh instances, 2,402 interior instances and 289 terrain chunks. Exterior shell
   portal clipping happens in the fragment shader, so it does not remove CPU draw
   submission. At 23 FPS, the spectator's 30 Hz request limit also permits another
   view every application frame. Measure native rendering and compare a fixed
   scene with the spectator disabled before choosing batching/culling changes.
2. **Native animation/skeleton work needs separate measurement.** Approximately
   32 NPCs remained animated. Body/face animation eligibility is distance-based;
   it does not suspend all hidden actors. Native AnimationPlayer/Skeleton work
   is not fully attributed by the GDScript profiler. Isolate it with a controlled
   frozen-animation comparison while retaining the same meshes and camera.
3. **NPC construction is a measured hitch source.** Eleven actors were configured
   during the script window: 0.356 seconds inclusive, about 32 ms per actor.
   Fourteen JSON reads cost 0.092 seconds; 275 clip builds cost 0.127 seconds
   inclusive. These nested costs must not be added together. Shared decoded data,
   shared animation resources and bounded installation are justified follow-ups;
   construction alone does not explain sustained 43 ms frames.
4. **Physics is smaller than the frame gap.** The smoothed monitor averaged
   1.76 ms per physics step (maximum sampled 2.75 ms), with 60 Hz physics and
   multiple steps per rendered frame. Zero active rigid bodies does not exclude
   character queries. World streaming had no active workers, pending instances
   or installation work throughout all 69 baseline snapshots, so it was not the
   sustained cause in this capture.

The GDScript output reports 1.869 seconds of accounted time in its 20-second
window, but inherited `super` calls appear charged to both the wrapper and base
method. In particular, `xr_player._physics_process` only wraps the base call and
a height guard; its reported self time is not an isolated locomotion hotspot.
Do not treat the sum as an exact exclusive CPU total. The one-frame-per-second
script samples were typically about 3 ms. Native stack sampling was unavailable;
the rendering-versus-animation ranking remains a hypothesis, not a causal result.

`summary.json` contains the external counters; `engine/report.json` contains raw
callback intervals and scene samples; `script-profile-summary.json` contains the
function rankings. Raw callback intervals include pacing/stalls, not GPU duration
or headset presentation timing. Engine monitors are smoothed; draw counters cover
all viewports. The user moved within the cantina while XR remained focused, so
neither this run nor its profiled/baseline phases form a fixed-workload A/B test.
The prior 22.46 FPS session used different scene activity and cannot establish a
performance improvement from these fixes.

Startup logged one rejected unsafe-ground entry before the successful scene
entry. The subsequent measured session remained on the cantina floor; this run
does not establish that initial grounding is fixed. Unsupported Pico/Vive action
paths and existing script/Jolt warnings are retained in `client.log` rather than
reported as a clean startup.

### Portal visibility and animation optimisation milestone

The default client now uses native conservative portal visibility to suppress
resident interior meshes before rendering. Unknown cells, incomplete graphs and
traversal overflow remain visible. Queries union the OpenXR runtime's eye poses
and projections with the active spectator; desktop inspection uses its camera.
Portal cones retain a 25 cm margin and recently visible cells remain eligible for
200 ms. Exterior-shell fragment clipping remains the correctness fallback.
Visibility never changes authored collision, source floor support, soundscape
residency or backend state.

Ambient NPCs additionally use conservative body/equipment bounds against the
active view frusta. Hidden actors suspend body/face evaluation while retaining
logical animation time. Before revealing an actor, the current phases, skeleton,
virtual skin and rigid equipment are updated. The tracked player is excluded.
The existing 50 m animation distance still applies independently. Bounds use
original mesh extents plus a generous motion margin; they are not a full baked
envelope of every possible future action.

Compiled original `Animation` resources are shared across compatible actors;
each actor retains its own library, player, skeleton and playback state. Cache
identity includes clip contents/provenance, target skeleton and root-motion policy.
The LRU retains at most 256 clips and 500,000 track keys; resources still referenced
by resident actors survive eviction. This is an in-memory compiled-resource cache,
not GPU animation baking or a persistent binary conversion cache.

Independent diagnostics are `--no-portal-culling`, `--no-animation-cache` and
`--no-hidden-animation`. Disabling portal culling restores mesh visibility while
retaining visibility queries for the independent suspension comparison.
`--no-spectator` disables the additional desktop view in a live XR diagnostic.
Defaults preserve the requested third-person mirror.

The fixed cantina comparison launches a fresh process for each configuration,
loads the actual application/world/NPC assets, fixes the camera at two viewpoints,
and records intervals, draw calls and subsystem counts. It refuses GPU timings
when another Godot process is present. Headless mode is functional coverage only.

```sh
python3 tools/benchmarks/compare_cantina.py --headless --variants baseline,combined --duration .3 --warmup .2 --output runtime/benchmarks/cantina-smoke
python3 tools/benchmarks/compare_cantina.py --duration 10 --warmup 3 --output runtime/benchmarks/cantina-comparison
```

The [pinned NGE source comparison](NGE_OPTIMIZATION_COMPARISON.md) documents
portal/DPVS visibility, shared animation templates, lazy bone evaluation and
character budgets. Full hidden-actor suspension is an explicit SWGXR policy,
not a claim that the inspected NGE client used the same implementation.

Validation passed 45 cache/suspension checks, 498 authored directed doorway
checks, all 12 actual starport gate cases, imported stair ascent/descent,
original animation and outfit/equipment regressions, and tracked avatars across
all 20 player races. The headless full-app comparison passed both feature-off and
combined configurations; those dummy-renderer timings are not GPU evidence.

The isolated Forward+ Vulkan comparison is in
`runtime/benchmarks/cantina-milestone-20261004/summary.json`: fresh processes,
1280×800 mono viewport, three seconds settling and ten seconds measured per view,
no other Godot process during measured frames. This is one ordered comparison
round, not repeated statistical qualification. Visibility queries remain enabled
even in the feature-off control to support independent switches; that control is
not an old client binary. Results:

| Configuration | Band p95 ms | Bar p95 ms | Band / bar draw calls |
| --- | ---: | ---: | ---: |
| Features off | 8.287 | 8.288 | 1291 / 1025 |
| Portal culling only | 6.449 | 7.360 | 842 / 839 |
| Compiled clip cache only | 7.944 | 7.703 | 1291 / 1025 |
| Hidden animation suspension only | 6.956 | 6.619 | 1291 / 1025 |
| Combined | **5.414** | **6.400** | **842 / 839** |

Combined p95 improved 34.7%/22.8% for the two fixed views, with 34.8%/18.1%
fewer draw calls. The full scene retained 32 NPCs but evaluated 11/22 in those
views; 1,882 of 4,066 managed static mesh instances were hidden. Three incomplete
building graphs remained fail-open. Cache counters reported 730 hits and 129
misses. Cache-only steady-state differences are small and potentially ordinary
run variation; its intended benefit is avoiding repeated compilation. The
separate original 18-clip fixture measured approximately 18.7 ms cold versus
12.4 ms shared-cache lookup, including content hashing, rather than a zero-cost
warm path. This cache does not eliminate other actor-construction costs.

Rendered `0-{baseline,portal_only,combined}-{band,bar}.png` captures retain the
visible furnishings, doorways and equipped actors. These observations validate
the desktop scene and measurable work reduction, not a 72 Hz headset result,
all possible head movements, or an MMO population capacity.

The first connected OpenXR validation (`cantina-milestone-20261004/live/`)
exposed a tracking-gate defect: all culling queries failed open despite a focused,
moving headset. Its 26.06 FPS observation therefore does **not** validate active
VR culling. In the installed Godot source, `OpenXRInterface::get_tracking_status`
returns a member that is not updated by that interface; actual head tracking is
published separately through the head tracker pose. Culling now uses that pose's
tracking validity/confidence and finite transforms, retaining fail-open behavior
on real tracking loss. Diagnostic status includes the current culling state so
this condition is visible before a benchmark finishes. See the pinned
[OpenXR interface](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/openxr/openxr_interface.cpp)
and [member declaration](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/openxr/openxr_interface.h).

Final live validation is `cantina-milestone-20261004/live-tracking-fix/` (PID
729539, launch-correlated pacer 37). All 69 baseline snapshots had valid runtime
eye projections plus the spectator (three views), with 1,812–2,145 resident mesh
instances hidden. Culling updates averaged 0.782 ms in the one-second snapshots.
No script errors occurred. The user traversed from the starport toward the
cantina during measurement; active NPC animations ranged from zero to 29.
The live mirror is `runtime/evidence/milestone-final-live-mirror.png`.

The unprofiled external observation completed **22.75 FPS against 72 Hz**, with
95.19% of one core on the main thread and 14.78% selected-process GPU render-engine
activity. Raw engine callback p95 was 48.64 ms (p99 81.34 ms); these include
traversal/loading and are not headset presentation percentiles. The performance
target remains unmet. This moving, connected session is neither the fixed
desktop workload nor a controlled before/after live comparison, so no live FPS
gain or regression is attributed to the milestone. Culling is now verified active
in OpenXR; the remaining main-thread cost still requires native profiling.

### Controlled live XR bottleneck suite (2026-10-04)

`client/diagnostics/xr_bottleneck_suite.gd` is an opt-in same-process diagnostic,
enabled with `--xr-bottleneck-suite=/absolute/output/directory` as a client argument.
After world readiness it runs 10 seconds of warmup and six conditions: baseline,
spectator rendering disabled, NPC animation/manager frozen, half internal headset
resolution per axis, scene drawing hidden, and restored baseline. Each has a
2-second notice, 3-second settling interval and 20-second measurement. Physical
tracking remains live; locomotion/combat/datapad inputs are gated. Escape or the
controller menu button cancels and restores settings. Completion and node removal
also restore settings. The 31-check headless lifecycle smoke passed, as did script
import with `--xr-mode off`; these checks do not validate headset rendering.

Engine evidence includes raw callback intervals, asynchronous CPU/GPU render
timings for each viewport, focus, pose drift, NPC activity, world loading and portal
visibility. Save WiVRn's performance feed as `runtime-before.json` before launching,
then run `tools/benchmarks/capture_xr_suite.py --pid PID --output DIRECTORY` to collect
passive runtime delivery and `/proc` CPU/DRM counters. The collector requires all six
phases and successful completion. `tools/benchmarks/summarize_xr_suite.py DIRECTORY`
combines the evidence without treating callback intervals as presentation timings.
The WiVRn collector is external instrumentation; the client remains standard OpenXR.

Two connected Forward+ Vulkan cantina runs used the same client and spawn with a
72 Hz Quest session on Intel Arc A770. Evidence directories:

- `runtime/benchmarks/xr-bottleneck-20261004-141426/` (PID 734312, pacer 38).
- `runtime/benchmarks/xr-bottleneck-no-obsmirror-20261004-142006/` (PID 736379, pacer 39).

| Condition | Original environment completed FPS | OBS OpenXR mirror disabled FPS | Clean-run main CPU, % of one core |
| --- | ---: | ---: | ---: |
| Baseline | 24.03 | 71.52 | 75.57 |
| Spectator disabled | 25.62 | 71.72 | 69.00 |
| NPC animation/manager frozen | 24.83 | 71.78 | 67.70 |
| Half internal resolution per axis | 23.81 | 71.59 | 74.93 |
| Scene hidden, spectator disabled | 28.55 | 71.82 | 38.60 |
| Restored baseline | 24.08 | 71.29 | 75.41 |

The original baseline averaged only 2.52 ms of headset GPU rendering while whole
callbacks averaged about 42 ms. Half resolution reduced headset GPU time to 1.53 ms
without improving FPS. Even four-draw-call dark frames delivered only 28.55 FPS.
The scene-hidden condition retains simulation, physics, audio and XR submission;
it is not a pure compositor benchmark. Disabling the spectator retains conservative
portal visibility for its camera, isolating its render/update cost.

Source verification confirms internal scaling applies to Forward+ stereo buffers:
[viewport forwarding](https://github.com/godotengine/godot/blob/ed1daf0bf/scene/main/viewport.cpp#L5065),
[internal size calculation](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_viewport.cpp#L233),
and [buffer allocation](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L292).
The XR swapchain/output remains full resolution; allocated GPU dimensions were not
independently captured.

Two separate 20-second native main-thread profiles, after the measured phases,
identified the dominant cost. Of 3,214 baseline user-cycle samples, 62.51% landed
in libc's memory-copy implementation and 64.19% of sampled stacks included the
external `XR_APILAYER_NOVENDOR_OBSMirror` layer (`copyEye`, `FrameWriter::publish`,
`releaseImage`). After disabling only that OpenXR layer, it was absent from maps
and samples; libc leaf share fell to 5.19% across 2,447 samples. The separate Vulkan
OBS layer remained loaded during this comparison, so the intervention was specific.
These percentages are CPU sample shares, not wall-time shares; inclusive stacks
overlap and must not be summed. Kernel cycles, blocked time and existing sibling
threads are excluded. Unwind error rates were 0.2% and 0.7% respectively.

Reusable native tools are `collect_native_cpu.py --pid PID --output DIRECTORY
--seconds 20` and `summarize_native_cpu.py DIRECTORY`, under `tools/benchmarks`.
They use installed `eu-stackprof`, ELF symbols and mini-debug data; they do not stop
the client, install packages, or change system profiling permissions. Run profiling
after timing trials. The collector sends its termination signal only to the profiler.

Both live suites retained focus, valid runtime eye projections and three conservative
visibility views; no script errors occurred, and both restored controls/settings.
World streaming was settled. Within measured baseline phases, one-second snapshots
showed at most 1.6/2.4 degrees of head rotation and 0.4/1.7 cm of translation. The
two launches were not pixel-identical: average total draws were 1,813 versus 1,518,
and active NPC body players 16 versus 17. Therefore this is strong attribution of
the dominant capture cost, not a precise matched-scene speedup estimate. Restored
baselines reproduced each run's result. The clean callback p95 remained 15.55 ms;
71–72 completed FPS in this stationary scene does not establish every-frame 72 Hz,
traversal performance, combat headroom, or MMO population capacity.

Residual CPU costs are distributed across Godot rendering, Intel Vulkan submission,
and scripting/string/dictionary operations. Prioritize reducing material surfaces
and draw submission, then spectator update frequency and NPC update/animation work.
GPU resolution reduction is a poor first optimization for this workload. No engine
render-thread change was needed or enabled.

At the user's request, the testing-only OBSMirror installation was removed: the
OpenXR library and implicit-layer manifest, OBS-side `openxr-vulkan-mirror` module,
its module registry/scene entries (including the scene backup), and six stale frame
files totaling 335,301,408 bytes. WiVRn was restarted to unload existing mappings
from tracking/WayVR processes. A subsequent readable-process map scan found no
OBSMirror mappings. Unrelated OBS components remain installed. Removal evidence is
`runtime/evidence/obs-mirror-removal/`.

`tools/client/launch_environment.py` now disables both known external OBS capture
layers before Godot starts; `run.sh` and the automated rendering/simulation runners
use this environment. No client OBS dependency was found. The built-in Godot
third-person spectator is independent and remains enabled. Direct developer Godot
invocations bypass the launcher, so use the same environment helper for bespoke
captures. The removed OpenXR plugin can no longer inject via its deleted manifest.

### Passive offhand wrist radar (2026-10-04)

`xr_datapad.gd` now shows a 14 cm circular holographic radar above the same dorsal
wrist hinge while the datapad is closed. Both use the existing native constrained
wrist follower. Opening the datapad hides the radar and disables its viewport;
closing it restores the radar. World/loading/menu/focus gates apply to both.
Passive radar requires head and offhand tracking, independent of dominant-hand
tracking. It does not capture controller input or modify tracking/physics poses.
The datapad's existing grip/trigger opening, pointer and stick capture are preserved.

`wrist_radar.gd` draws a heading-up 64 m horizontal circle, self arrow, heading/range
labels, white neutral NPC dots, and mob diamonds. Explicit attackable, hostile and
friendly relations use yellow, red and green. DatapadSans is reused. A small elevation
chevron marks contacts more than 3 m above/below the player. The display is unshaded,
transparent and casts no shadows. Its 256×256 viewport updates once per refresh at
5 Hz, retains at most 128 nearest contacts, and does no queries/redraws while hidden.
There is no animated scan, light, continuous extra viewport pass or OBS dependency.

The original's default 64 m range and camera-yaw rotation are documented in
[SwgCuiGroundRadar](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiGroundRadar.cpp#L204).
The palette follows
[CuiGameColorManager](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientUserInterface/src/shared/core/CuiGameColorManager.cpp#L142).
This prototype uses a strict horizontal radius with elevation cues: it does not
copy the original's broader 3D candidate tests or 15 m different-cell interior
height rejection described in
[BlipPane](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiGroundRadar_BlipPane.cpp#L293).

`radar_contacts.gd` indexes authored Tatooine inhabitants into 64 m spatial tiles,
independently of the 32-avatar rendering cap, portal hiding and animation budgets.
Loaded avatar positions override their authored positions. The current placements
are local noninteractive presentation and have no per-player hostility information,
so they remain neutral white even if their source faction/weapon appears hostile.
This change does not create mob spawns or a live Core3 NPC subscription.

Moving gameplay/replicated NPCs and mobs can join `swg_radar_contacts` and implement
`get_radar_contact()` returning `{id, position: Vector3, kind: "npc"|"mob",
relation: "neutral"|"attackable"|"hostile"|"friendly", alive?, radar_visible?}`.
IDs deduplicate static contacts; explicit dead/ineligible contacts suppress their
authored entry. Unknown relations become neutral; non-creature kinds are excluded.
Source movement rebuilds the index. Main's callback is gated by world readiness.

Validation: 17 provider checks (including the actual cantina source query), 22
radar/visibility/input lifecycle checks and 41 existing datapad integration checks
passed. The cantina query returned 57 contacts, visiting 94 of 1,071 indexed
placements. A separate Forward+ Vulkan desktop render passed 23 checks and was
visually inspected; see `runtime/evidence/wrist-radar-preview.png` and
`wrist-radar-render.json`. The preview uses synthetic contacts to expose all palette
states; the source query is independently validated against actual placements.
All mocked/headless/desktop runs use `--xr-mode off`. Live headset placement remains
unvalidated while the Quest is disconnected; no headset performance claim is made.

### Inventory assets and session-local handling

`setup.sh` now prepares the original inventory catalog from Core3's source starter
item candidates, validates it, and prepares the combat assets used by supported
inventory-held weapons. Steam Audio remains pinned through its existing installer.
These catalogs are presentation/reference data, never an ownership database.

`./run.sh --account=ACCOUNT --enter-character=NAME` waits for real Core3 readiness,
resolves the named character through that account's `/characters` response, and
reads `/inventory` before starting Godot. The authoritative snapshot is saved in
ignored `runtime/server/inventory-snapshots/` with an immutable content-hash name.
The launcher prepares missing item/shared-template mappings and model files;
an already prepared selection skips conversion. Starter definition changes and a
missing generic bag also trigger preparation. Existing combat catalogs/assets and
Steam Audio installation are reused, including launches without `--combat-items`.
An interactive launch without a selected name prepares starter candidates only.

Additional inventory snapshots can be prepared explicitly:

```sh
python3 tools/assets/prepare_inventory.py --snapshot PATH_TO_CORE3_INVENTORY_JSON
python3 tools/assets/validate_inventory.py --snapshot PATH_TO_CORE3_INVENTORY_JSON
```

`--template object/.../item.iff` prepares another original item; `--refresh`
reconverts existing entries after archive changes. The version-1 manifest indexes
server templates and actual shared-template aliases, retains exact model bounds,
original appearances/meshes/materials and source hashes, and reports unsupported
models explicitly. It never labels substitute geometry as original. The source
backpack fallback is proven against the original ranger trainer CDF wearable.

The offhand shoulder/grip gesture opens the held bag and its 4×8 visible grid.
Point/trigger selects; the pointing stick scrolls. Main-hand grip takes an item;
releasing it while the bag is open returns it. Releasing offhand grip stows the
bag while preserving a gripped item. Releasing that item afterward creates a
bounded recoverable local physics proxy, using the same original fitted model.
The original inventory slot stays reserved: there is no Core3 world-drop or
ownership-transfer claim, no JSON persistence, and at most 32 local drops.
Recovery removes a proxy only after the hand presentation succeeds. World or
character changes clear proxies; Core3 remains the source of possessions.

Stack splitting is a separate authoritative operation for supported resource
containers and factory crates. Core3 validates the amount, ownership, type and
container capacity; the adapter reads a fresh snapshot to verify the new object
and conserved quantity. A held/dropped item must be recovered before splitting.
Unsupported use-count items are not treated as arbitrarily divisible stacks.

The inventory UI shares meshes/materials in a 64-entry cache and renders at most
32 slot models plus one selected preview. Closed model viewports stop rendering;
slot/preview model viewports redraw only when their contents change. Ordinary
items support inspection and local holding/dropping. The equipment/consumption
milestone below adds authoritative equip and supported consumable actions.
Crafting and deed activation are outside these inventory interactions.
Reopening the bag, tracking loss, menus or combat cancellation restore/return the
held presentation safely. Reserved IDs cannot also be drawn from weapon holsters.
A refreshed server snapshot removes local proxies whose ownership disappeared.

Backend patch `0019-authoritative-inventory.patch` adds bounded authenticated inventory
reads and original resource/factory-crate splitting. The adapter verifies each
successful split with a separate authenticated Core3 login. No mutation is
retried automatically. Snapshot bounds are 256 items and depth 8; exceeded bounds
fail explicitly instead of silently truncating possessions. Core3 ancestor volume
checks apply even when the immediate backpack has free space.

Validation for this milestone:

- 45 inventory interaction checks using original models and mocked tracking;
  47 checks in a separately inspected desktop Forward+ Vulkan render.
- 27 main-orchestration checks against real Core3: hold, stow, supported weapon
  handoff, duplicate-holster prevention, local drop/recovery, focus cancellation,
  ownership reconciliation and unchanged persistent possessions.
- Existing XR combat (34), datapad (41), radar (22) regression checks passed.
- Original-item physics drop settled on an imported SWG interior FLR; recovery,
  duplicate rejection, missing-model rejection and 32-proxy cap passed.
- Six backend decoder checks plus real ownership rejection, resource quantity
  conservation (20 → 17 + 3), fresh-login and Core3-restart persistence passed.
  An 80/80 root rejected a split inside a backpack with 49 free immediate slots.
  The existing player's six items remained unchanged. Factory-crate splitting
  compiles and uses original Core3 code, but live manufacturing was not exercised.

Evidence lives in ignored `runtime/evidence/`: `inventory-live-preview.png`,
`xr-inventory-smoke.json`, `xr-inventory-render.json`, `inventory-main-smoke.json`,
`local-inventory-drops-smoke.json`, `inventory-core3-final.json`,
`inventory-assets-validation.json`, `inventory-launcher-checks.json` and
`inventory-launcher-live.json`. Asset validation covers all six current inventory
appearances; the initial optional worn `shirt_s14` OPST limitation was subsequently resolved
by the equipment milestone's original owner-race skin material binding.

Run the relevant client checks with XR explicitly disabled:

```sh
godot --headless --path client --xr-mode off --script res://tests/xr_inventory_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/inventory_main_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/local_inventory_drops_smoke.gd
```

The main HTTP check requires the local `runtime/server/unarmed-fixture.json`
character and a ready Core3 adapter. Headless checks use the dummy renderer;
desktop Vulkan captures do not validate live XR. The Quest was disconnected at
final verification, so shoulder reach comfort, stereo readability and headset
interaction/performance remain live-test items.


### Equipment hologram and native consumable actions

A fresh main-hand trigger press while holding equippable inventory gear opens a
local 54 cm hologram of the current original avatar and equipment. It shares
immutable mesh resources but owns a frozen skeleton/material presentation; it is
not a replicated actor, has no collision/AI and never animates the tracked player.
Source slot arrangements supply up to32 bounded proximity markers. The compatible
arrangement highlights green; blocked arrangements highlight red and explain why.
The two tilted panels compare matched source examine attributes and bonuses, with
main-stick paging so later bonus rows are not discarded. Empty slots and items
with no source bonus are presented without fabricated statistics. Trigger again
closes the hologram. Active metadata refresh preserves its world position while
rebuilding only when the original appearance/equipment or held record changes.

Release grip on a highlighted compatible arrangement requests
`POST /inventory/equip {account,character_id,item_id,arrangement}`. Core3 validates
ownership, original species/slot/state restrictions, and preexisting root inventory
space before moving gear. A net-zero swap still requires a free slot. Multi-slot
arrangements reserve room for every distinct displaced object; displaced items
return to root inventory. Original transfer callbacks apply/remove equipment
bonuses. Failed validation retains the held item. Transfer rollback is implemented,
but unexpected transfer-failure rollback was not fault-injected in this milestone.

A fresh trigger with a supported consumable invokes
`POST /inventory/consume {account,character_id,item_id}`. Food/drink use the original
Core3 consumable callback, retaining native fullness, species and existing-effect
rules. Ordinary non-area, non-ranged self-use StimPacks invoke original `healdamage`
with this exact item, retaining native damage, healing ability, mind cost and
treatment-cooldown checks. Target-only, area/ranged, pet/droid and other specialized
medicine remains explicitly unsupported. One successful press consumes one item
or charge; held charges reconcile to the returned object and the last charge
clears its presentation. Pending/rejected actions never auto-repeat while the
trigger stays down. Core3 remains authoritative for the item's native use effects;
these operations do not turn the local combat prototype into server-authoritative
combat.

Patch `0020-authoritative-equipment-consumption.patch` extends `/inventory` with
full current equipment, source arrangements, availability/reasons, decoded dye
customization, race, consumable eligibility and native player stat snapshots.
Successful mutations return a fresh authenticated snapshot. On failure, main makes
one read-only refresh to reconcile an ambiguous result; it never retries a POST.
Confirmed native HAM costs/benefits apply once as a delta to existing local combat
prediction, preserving previously spent local pools instead of refilling them on
ordinary snapshot refresh. Equipped weapon profiles/bonuses then refresh from
Core3. Inventory-held equippables reserve trigger for the hologram; only confirmed
equipped weapons receive ordinary holster permissions.

`avatar.refresh_equipment()` rebuilds original clothing/body-occlusion meshes and
rigid attachments while preserving the existing skeleton, animation players,
tracking pose, hair, height and calibration. Equipment imports now include
race-specific original skinned variants and owner-bound OPST skin materials.
The launcher prepares variants from the selected snapshot's race. Final local
catalog:28 ready original previews,10 human-male equipment variants,265 audited
source hashes and zero conversion failures for the test selection. Other races
are prepared as selected; a missing variant is reported explicitly.

Validation:

- 48 equipment interaction checks and45 inventory regression checks passed using
  mocked tracking. The separately inspected actual-equipment Forward+ Vulkan
  capture passed51 checks (`equipment-hologram-live-preview.png`).
- 18 main mutation lifecycle checks covered rejection, malformed/wrong-character
  replies, pending locks, remaining charges and precise native stat deltas.
- 16 main HTTP/gesture checks on a disposable Core3 character exercised trigger →
  hologram → release onto actual shirt slot → persistent equip, then trigger →
  native food consumption. The original live avatar skeleton/pose survived the
  equipment replacement; the displaced item returned to inventory.
- Native tests verified dye preservation; flightsuit displacement of3 worn items
  across7 source slots; backpack equip;80/80 rejection of both empty-slot equip and
  net-zero swap;79/80 rejection where3 items would be displaced; real food bonuses;
  real stim healing with10→9 charges, native mind cost and cooldown rejection;
  ownership/state rejection; and persistence after a Core3 restart. The user's
  character inventory was unchanged; all mutations used disposable fixtures.
- Existing XR combat34, datapad41, and avatar mesh, animation, first-person
  partition/tracking and NPC outfit regression checks passed. No GPU or live XR
  validation is attributed to dummy-renderer checks.

Evidence: `equipment-hologram-smoke.json`, `equipment-hologram-render.json`,
`equipment-actions-main-smoke.json`, `equipment-main-http-smoke.json`,
`avatar-equipment-smoke.json`, `equipment-core3-smoke.json`,
`equipment-core3-capacity.json`, `equipment-core3-final.json` under ignored
`runtime/evidence/`. The hologram capture uses actual Core3 equipment and source
attributes; the separate synthetic comparison preview is labeled as such.
Live headset comfort/readability and gestures remain unvalidated while the Quest
is disconnected.

```sh
godot --headless --path client --xr-mode off --script res://tests/equipment_hologram_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/equipment_actions_main_smoke.gd
# Mutates only runtime/server/equipment-fixture.json's disposable character:
godot --headless --path client --xr-mode off --script res://tests/equipment_main_http_smoke.gd
```

## Resource gathering and native corpse interactions

The client orchestrates gathering through `resource_gathering.gd` and
`corpse_gathering_controller.gd`. Core3 patches 0021/0022 own the tools, resource
identity, skills, yields, XP, harvested flags, loot rights and inventory transfers.
`/gathering` reads current planetary resources for the held tool. The map uses the
source survey grid's **full width**, not a radius; highest positive concentration
creates/updates the native resource-survey waypoint. Crafting is outside this step.

A deployed tool moves into an owner-restricted persistent Core3 escrow container.
PlayerObject screenplay data records its sampling position, generation, resource
spawn anchor, accumulated quantity, next cycle and recent mutation receipts. The
original resource spawn remains anchored through expiry. The client posts original
SWG `[x,y,z]` coordinates with Y up; stage transforms and the mirrored local Z are
applied at the boundary. Deployment requires loaded outdoor source terrain/FLR
support, a supported footprint and a reachable tracked hand. Ground validation is
client-side in this prototype. Collection additionally checks native owner and
2.5m proximity to the submitted player position; local movement remains client
reported, as for the custom locomotion prototype.

The visible source model floats 1.2m above the unchanged sampling position. A
six-sided cyan unshaded beam joins it to that position, without lights, particles,
shadows or locomotion collision. Pickup uses the floating model's bounds. Confirmed
counts appear above it. Missing/unloaded support hides the presentation while
retaining server ownership/state. At most32 nearby tools within64m render; labels
end at8m. These are rendering budgets; Core3 separately allows one deployment per
native survey tool type per character, across planets, with a defensive16-record
protocol bound. Patch0087 caps each new buffer at one native100000-unit resource
stack. Full/expired tools reserve their type until recovered. Old duplicate tools
pause safely and old excess output remains recoverable.

Sampling copies the pinned Core3 baseline density/skill/sample-rate/sample-size
and XP formulas: first result after3s, then25s cycles. Persistence uses lazy
settlement on reads/actions, including elapsed offline/restart time, stopping at
resource expiry or full storage. Each request processes at most1024 cycles; excess work remains
pending instead of being discarded. This custom unattended sampler intentionally
omits the original kneeling/mind-cost, gambling/rich-node and radioactive-wound
mechanics. Skill modifiers are checkpointed between settled intervals. Recovery
preflights the tool and every required native resource stack (including compatible
existing-stack merges); failure leaves the entire deployment recoverable.

One tool can be reserved at the offhand hip. Drawing is a local presentation of
that same escrowed object, so it requires no spare inventory slot and creates no
second item. Returning it to the bag or displacing a previous hip tool checks
inventory capacity. Synthetic equipment UI markers never become fake native
arrangement indexes.

Corpse discovery projects actual nearby dead Core3 creatures. Empty-hand trigger
inspects; a fresh grip on a holographic resource requests native harvesting; a
second fresh trigger over the corpse requests all personal loot and credits.
The backend temporarily projects the player to its submitted local position under
lock for original range/rights/skill checks, then restores the Core3 position.
Native harvesting chooses and consumes a real carcass resource according to
original yield and harvested-state rules. Loot preflights all transfers before
committing credits. Group-distribution loot is outside this initial implementation.
Local combat training targets are not Core3 corpses and cannot generate persistent
rewards. The future combat entity bridge must provide real death/loot authority.

The corpse importer derives42 source mobile templates from95 harvestable Tatooine
animal definitions. It freezes original `loop_incapacitated` animation data using
original inverse binds/weights (22 unique models,245 original TRE hashes), rather
than claiming a separate death clip. Source meshes keep their meter scale and
customization. Unsupported appearances are reported, never replaced with invented
art. Corpse presentation retains canonical records and renders at most32 within64m.
Use `tools/assets/prepare_corpses.py --planet tatooine` for reproducible preparation
or `--snapshot FILE` for an actual native corpse query. Original data stays ignored.

Mutation requests carry stable unique IDs; ambiguous responses cause read-only
reconciliation, never automatic repeat mutations. Receipts cover the most recent32
operations per character. The Core3 object database and screenplay receipt writes
are not one crash-atomic transaction; tested graceful restart persistence should
not be represented as arbitrary power-loss transaction safety.

Verification commands (headless uses the dummy renderer; no GPU/XR claim):

```sh
godot --headless --path client --xr-mode off --script res://tests/survey_tool_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/deployed_resource_tools_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/gathering_actions_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/corpse_gathering_smoke.gd
godot --headless --path client --xr-mode off --script res://tests/corpse_controller_smoke.gd
# Explicitly mutates only the disposable runtime/server/gathering-fixture.json:
godot --headless --path client --xr-mode off --script res://tests/gathering_main_http_smoke.gd
# Requires a fresh controlled native corpse on runtime/server/corpse-fixture.json:
godot --headless --path client --xr-mode off --script res://tests/corpse_main_http_smoke.gd
```

Desktop Forward+ Vulkan fixtures are `survey-tool-preview.png`,
`corpse-gathering-preview.png` and `gathering-world-vulkan.png` under ignored
`runtime/evidence/`. Their synthetic counts/rewards are explicitly separate from
native HTTP evidence; they do not validate live headset interaction. The world
capture rendered successfully but required termination during teardown.

The main gathering HTTP fixture passed12 checks through the production main
orchestration: source tool → fresh trigger survey → native deployment over an
actual outdoor starport FLR → original model hovering1.2m above support → main
pickup provider → native collection back into the hand. Separate native tests
verified source waypoint, buffer/escrow persistence across graceful Core3 restart,
materialization of178 units into real resource containers, full-inventory and
out-of-range rejection, stale deployment rejection and idempotent collection.
Mocked input/lifecycle tests also cover stale same-ID re-grabs, session changes,
malformed replies, pending locks and fresh edges after corpse requests.
The existing actual-stage XR main regression and29 unarmed-input checks passed
with mocked tracking, including intentional missing-floor spawn rejection.

Corpse backend fixtures use real source Creature objects explicitly put into DEAD
state, with controlled native loot ownership/items/credits; they do not validate
a native combat kill/death pipeline. The earlier Lua damage fixture expired in10s
because it lacked native damage credit; no production corpse lifetime was changed.

The controlled native corpse regression passed: exact2-unit meat yield and49 scout
XP;123 fixture credits plus the original Wild Snaff item; full-inventory, range,
invalid-ID and already-harvested rejection; and same-request replay without a
second grant. The main client HTTP/gesture fixture separately passed10 checks:
trigger inspection, original resource holograms, grip harvest matching the native
quantity, then second-trigger loot-all. Earlier fixtures shared one spawn point;
the client test isolates its exact native corpse identity for deterministic hand
selection. It does not claim to test overlapping-corpse target selection.
Evidence: `corpse-core3-smoke.json`, `corpse-main-http-smoke.json`,
`gathering-core3-smoke.json` and `gathering-main-http-smoke.json` under ignored
`runtime/evidence/`. Backend wire details and source-policy limits are documented
in [server/GATHERING_PROTOCOL.md](../server/GATHERING_PROTOCOL.md).

Selected-character launch preparation now queries native gathering state as well
as inventory, so tools held in hip/deployment escrow retain original appearances
after restart. Those records are nested appearance inputs in an immutable snapshot;
they are not inserted into the character's inventory list.


### Persistent native ranged combat test

`--live-combat` is a separate bounded Core3 session mode. The launcher implies
`--combat-items` and rejects offline/local-lab combinations. Main completes
entry, datapad and inventory reads, reserves the character against legacy RPCs,
drains existing requests, then opens the persistent native zone connection.
Legacy character/inventory/gathering/entertainer operations stay suspended until
that session closes; reconnecting the same account otherwise evicts it.
Closing the client stops only its owned live session. Core3 and the loopback
adapter remain running for subsequent tests.

`client/combat/live_world.gd` requests complete native snapshots at up to 5 Hz with bounds
of96 actors,64 outstanding shots and128 queued commands. A four-second update
loss, malformed identity/vitals or truncated population disarms combat and removes
collision projections. An appearance failure is isolated to that entity: available
original body/clothing remains visible with its missing-component report; a fully
unavailable appearance keeps its native identity and diagnostic label without an
invented mesh or collider, and cannot accept projectile contacts. Original live
skeletons supply idle/walk/run; confirmed native death selects the original
corpse pose. These actors never own HP, AI or death decisions.

Tracked muzzle launches register an immutable shot identity before contacts are
submitted. Native launch validates the owned equipped certified weapon and
cadence and commits HAM cost; native contact validates the shot and target before
calling the original attack path. Native targetID remains zero to prevent player
auto-attack recovery from creating unsolicited additional shots. Creature threat,
retaliation and original damage/death processing remain native. The client disables
its translated active abilities, predicted HAM costs and predicted weapon wear.
Compact primary HAM/wounds snapshots replace predictions exactly, including
regeneration; native incapacitation/death gates movement and firing without
moving the HMD or controllers.

This is an outdoor basic-ranged test bridge, not a general MMO entity replication
protocol. Movement inputs remain prototype client supplied. Corpse harvesting and
inventory management are implemented through separate one-shot RPCs and are
intentionally unavailable during this session until they share its connection.
Native replication and local client collision tests are separate from live HMD
rendering evidence. Optional `--live-combat-status=/absolute/path.json` records
bounded live client state; `--runtime-profile=/absolute/directory` records runtime
and XR focus samples alongside live combat counters.


Live verification for the dedicated Master Marksman/FWG5 character recorded
native lair condition damage, worrt HAM damage/death, pistol/general XP and a
10-second living-target window without player auto-fire. The passive worrt
moved away from the player during that interval; retaliatory damage was not
observed and is not claimed. Native LOS is called by the attack path, but an
actual blocked-LOS firing case remains outside the outdoor fixture evidence.
Client smoke evidence separately covers22 entity/shot projection checks and72
main integration/authoritative-HAM/session-lifecycle checks using mocked HTTP;
those are not live headset validation.


The first rendered live launch uncovered two gaps that mocked tests could not:
random surrounding native spawns required additional lair/humanoid appearances,
and an unseen hostile could damage the character while failed loading left the
native character present. Exact original-asset coverage now spans the source
Tatooine groups and existing ambient NPC catalogs; missing-media failures remain
explicit. The persistent client defers original scene-ready activation until the
Godot world is loaded and initial XR focus exists. Native readiness is monotonic
for that session, so losing focus after activation cannot enable protection.
The controlled worrt fixture now uses source player3790,5,-4780 and lair3810,5,-4780
inside the city no-spawn region. Actual streamed-stage collision checks establish
clear ground,3m clearance and a clear firing line there (`live-site-ground.json`).


Live native NPCs are reconciled against authored ambient placements only when
both exact template and source coordinates match within0.25m. One-to-one stable
bindings suppress duplicate local presentation and radar contacts; they persist
through death/removal for the session and restore on session stop. Other ambient
NPCs remain intact. Original incapacitated clips retain dressed humanoid clothing
when there is no frozen animal-corpse mesh. Appearance reports distinguish complete,
partial and unavailable actors in diagnostic state and visible notices.


Tracked held weapons and the original dominant-hand hold bone share one solved
rigid grip target. Reach projection runs after the current body pose; no independent
weapon interpolation or controller overwrite can separate the gun from the hand.
Body displacement is sampled on the physics clock to avoid render-rate velocity
aliasing. Tracking remains unchanged. `xr_weapon_pose_smoke.gd` covers locomotion,
origin turns, physical crouching and unreachable source-arm targets.
Remote live NPCs use the visible world layer for every mesh surface, including
head triangles that are hidden only on the first-person player avatar.

Accepted projectile discharges play the original fire effect before collision
preflight. An obstructed muzzle or incomplete streamed collision still rejects
flight/contact as appropriate, but does not silently suppress the sound.
Projectile diagnostics record incomplete-query reasons. The HAM panel remains
12cm clear of the tracked wrist, with rolled-hand placement covered by regression.
Headless pose, mesh and HUD tests do not establish live headset visual quality.


World projectile coverage uses bounded source-index tiles, independently of
object bounding boxes. A tile is complete only after every source chunk with
geometry overlapping it has published its collision snapshot. Empty indexed
ground is therefore traversable by projectiles; pending or evicted overlapping
geometry invalidates the proof. Original terrain coverage, portal membership,
unknown-shape rejection and native authority remain in effect.
`live_stage_projectile_smoke.gd` exercises the actual streamed test site and
original worrt collider through swept projectile contact, with no server mutation.


Native physical-impact bounds use the original appearance bounding sphere,
including its authored center, target rotation and creature scale. This handles
LOD/component appearances such as the dead-log lair, whose original geometry
extends beyond the previous origin-based guard. Invalid or missing bounds use a
bounded fallback; shot ownership, direction, range, time and native LOS still apply.
No recurring per-actor bounds telemetry is added to the snapshot.

The persistent adapter spaces native commands by at least 275 ms and waits
1.05 seconds after zone initialization. Core3 otherwise silently drops commands
above its original five-per-second limit. Updates and combat share this budget,
so the client polling target is not a guaranteed snapshot rate. Mutations are
never replayed. Actual native verification covers original outer-edge damage,
rotated bounds, outside-bound rejection and sustained mixed update/fire/impact
traffic (`live-impact-native-bounds.json`). This pacing is for the bounded test
bridge; it is not a production MMO replication transport.

Live screenshot regressions (2026-10-05): static material coverage now follows
the original effect's base pass. An alpha-tested secondary specular pass must
not cut holes through an opaque base. Schema 3 refreshes the existing local
material metadata; geometry and collision remain unchanged. Production Vulkan
captures cover foliage alongside opaque architecture and original vehicle art.

Body grab zones now follow headset facing yaw, including room-scale translation,
while ignoring head pitch and roll. Handedness still swaps tool and weapon sides.
Idle offhand proximity cannot reserve the weapon hand. Wallet and backpack grabs
arbitrate actual ownership in the same frame. Backpack panels attach to the
original bag's top/front geometry and remain upright when the controller rolls.

Landspeeder steering uses tracked hand movement around the wheel, with a shared
two-hand translation cancelling out of steering. Wheel push/pull controls
throttle independently; wrist roll alone cannot steer. Vehicle prediction follows
the turn between server snapshots. Datapad refreshes retain the authoritative
control-device-to-mobile association used by original 3D previews.

Terminal activation tests the physical screen plane and viewer facing, allowing
bounded fingertip contact behind the offset hologram plane. Approaching and
aiming at a closed terminal no longer draws a guiding line. Trigger activation
and the opened interface's finger pointer, click dot and drag behavior remain.

Captured starport NPC records show some ordinary NPC origins up to one metre
below reconstructed terrain, while fresh server snapshots still show AI moving.
Presentation floor support reconciles positive penetration up to 1.5 m only for
nonattackable, standing outdoor humanoids. It preserves native records and actor
roots, excludes attackable actors, interiors and other postures, and caches
unchanged positions rather than casting rays each frame. The exact screenshot
scientist was already grounded in the later remote capture; a different captured
commoner reproduces and verifies the one-metre burial correction.

Current evidence is under `runtime/evidence/live-regressions`,
`runtime/evidence/headset-grab`, and `runtime/evidence/alpha-grounding-regression`.
All headless and desktop checks use `--xr-mode off`. Mocked tracking and desktop
Vulkan captures do not establish live headset validation; VR tests remain paused.


Imperial-area source-floor audit (2026-10-05): ambient NPC placement now queries
original FLR support in its exact authored cell instead of raycasting against
arbitrary static props. Desks, decorations, roofs and floors in other cells cannot
be selected merely because a visibility-dependent collision ray hits them first.
Exterior placements choose nearby authored platform support or terrain, retain
seated source poses, and preserve explicitly elevated placements beyond the old
two-metre downward support reach. This applies to noninteractive ambient art;
it does not relocate authoritative attackable Core3 actors or alter hit mapping.

The actual recruitment building (1280129, cells 2 and 3) passes 17 source-stage
checks, including injected table colliders, original floor elevation and seated
exceptions. A recorded elite sandtrooper's native elevation agrees with its
original raised platform within 0.005 m; its exact bound weapon/appearance variant
also passes idle, walking and running foot-height checks. The reported live
Imperial airwalking has not yet been reproduced by these samples. Do not describe
this ambient fix as confirmation that every moving live Imperial case is resolved.
Evidence and a Forward+ Vulkan recruitment-room capture are under
`runtime/evidence/npc-floating/`. Terminal interactions retain 62 mocked checks;
the full original ambient streaming check passes with 32 resident skeletons,
original equipment and no errors. No live VR testing was performed.

## Core3 recording interaction corrections (2026-10-05)

`Downloads/core3.mp4` was inspected using 64 timestamped frames across its
21-minute duration and the correlated client log. Review evidence is under
`runtime/evidence/core3-review/`; the recording shows tracking filters at
230–250 seconds, missing performance options and an expired-session message
from about 330 seconds, vehicle grip problems at 690–950 seconds, and steep
exterior terrain at 1010–1270 seconds.

Recognized profession gestures now reserve the datapad chord until release.
Performance priming survives ordinary HAM replication; learned command matching
handles Core3's mixed-case names, and a completed gesture can wait behind a
background status request without being silently discarded. Dancing is prop-free:
select a learned dance, spread both arms at chest height with open palms facing
down, then make repeated waves or circles. The ribbon is no longer a performance
prop. Previously provisioned native items are not silently deleted by this code
change.

Area Track status updates clear both the drawn panel and XR input pending state.
Mask Scent has one hand-anchored badge; lost hand tracking hides it instead of
moving it into the head view. Text-only native pet training options no longer
abort radial-page construction because they lack an icon name.

Vehicle grips remain latched until release rather than expiring with reach or
snapshot age. The later physical-control revision also removes seated-driver
grab proximity: each hand attaches to its corresponding model grip, even from a
distant or crossed controller pose. Vehicle-only IK permits visual arm extension
to keep the original hold socket attached; releasing restores ordinary reach
limits. HMD, controller and physics-body transforms are unchanged by attachment.

Landspeeder throttle uses physical model-forward push/backward pull, independently
of wheel rotation; bike throttle retains wrist twist. Joysticks do not drive.
Control positions survive one-hand release, hand transfers and tracking
suspension, and reset only after both grips are released. Suspension stops drive
output while retaining the visible control position. Swoop/speederbike handlebars
pivot around model up, so opposite grips move fore/aft. All six original steering
meshes now move locally; source seams partition existing triangles without
replacement geometry. `vehicle-rigid-attachment.json` records 132 original-model
attachment checks; `vehicle-handlebar-assets.json` and
`vehicle-handlebar-mesh-smoke.json` record topology, source hashes and geometry
validation. These checks are headless, not headset/GPU observations.

Patch `0058-client-vehicle-motion.patch` adds negotiated local
driver motion: the client resolves controls, collision and terrain height, while
Core3 validates the owned ride and publishes its pose/properties. Current servers
without `driver_motion=client_pose` retain the legacy motion protocol. The patch
has protocol and client tests. The resumed build passed after Podman became
accessible, and 14 running local Core3 checks now verify accepted poses, passenger
replication, ownership/speed/world-boundary rejection, stale stopping and legacy
controls. The probe restores its dedicated fixture poses and releases seats.
Evidence: `runtime/evidence/vehicle-client-motion-native.json`. The user restored
SSH access and authorized server-only deployment. The Tatooine VPS now runs the
verified binary; HTTPS checks confirm the new capability and a retained native
session. No VR test was launched.

Terrain following uses actual resident terrain triangles, Core3 Scout slope
modifiers, and swept building collisions. Missing terrain and explicitly denied
surfaces remain unsupported. The bridge currently provides no per-position
Core3 passability query, so this is imported-terrain support, not a claim of
server-authoritative walkability. Evidence includes 55°, 70° and 82° slope tests
at 60/120 Hz, wall/hole controls, and an actual imported Tatooine triangle in
chunk `(4096,-4608)` with a 50.387° slope.

The presentation hub now removes stale visible presence after 15 seconds while
retaining an account-bound session for up to one hour of inactivity. This lets
initial loading exceed 15 seconds without destroying the token; a new character
entry still revokes the old token. Native performance resumes only after a fresh
Core3 observation. This server-side correction is included in the deployed update.

The native client library and targeted headless regressions were rebuilt with
`--xr-mode off`. Mocked XR inputs and dummy rendering do not establish live
headset validation. No new live test was launched for these corrections.

Resume validation (2026-10-05): the native build completed and the deployment,
vehicle protocol, launcher and session-retention suite passed 51 tests. A five-file
delta bundle is staged under ignored `runtime/deploy/vehicle-live/`; it includes
Core3/core3client and three changed adapter modules, without planet configuration
or player data. The installer retains the Tatooine-only guard and graceful save,
persistent backup and configuration-hash checks. Deployment passed; four files
changed, while the included core3client binary already matched. All services are
active, player counts and private configuration are preserved, and the daily
05:00 UTC restart remains enabled. The dedicated HTTPS test character entered
Tatooine, read its inventory and new vehicle capability, retained its native
session, and saved/logout successfully. Evidence: `runtime/evidence/vehicle-live-https.json`
and `runtime/deploy/vehicle-live/applied.json`.
WiVRn reports a connected Quest Pro, but no project XR launch or headset rendering
validation was performed during this resume.


## core4 recording corrections (2026-10-06)

Reviewed all 192 seconds of `/home/blux/Downloads/core4.mp4` using timestamped
frames. The bazaar sequence shows the projected finger beam and backpack access
problem. No crafting-station sequence was found in this clip; the reported
stick-click failure was independently confirmed in the input handlers.

The free-hand stick now confirms highlighted crafting and terminal rows, with
both crafting-tool hand assignments covered. Consumed UI clicks cannot also jump.
Bazaar/vendor browsing permits shoulder-backpack access and temporarily yields
input while retaining terminal context. Nested pointer ownership prevents either
panel from restoring the stock beam before the other closes. Terminal interaction
keeps its contact dot without drawing a beam. Item-drop sale proposals still use
the existing native commerce path.

Original vehicle engine and droid sound bindings now feed the shared spatial
mixer independently of weapon equipment. Original idle, movement, start/stop and
observed droid damage effects are connected. See `tools/assets/README.md` for
source limitations and the remaining unwired event types.

Evidence is under ignored `runtime/evidence/core4-review/`: recording hash and
48 timestamped frames, `ui.json` (24 checks), `audio.json` (18 checks with real
Ogg decode and nonzero mixer capture), and regression logs. Crafting (40),
hologram navigation (16), service controller (59), backpack (49), vendor commerce
(23), and slider regressions passed. Terminal interaction (62), vehicle controls and
weapon spatial-audio (12) regressions also passed. The asset audit verified 2,977
source hashes and 115 converted Ogg files. Editor import was clean. Tests used
`--xr-mode off` with dummy rendering; UI tracking and commerce responses were
mocked. Audio capture verifies mixed output, not headset listening. No live VR
test or server deployment was performed for these client corrections.

## Image framing and medical focus controls — 2026-10-08

Image Design now accepts a held two-hand thumb/index frame near eye level (0.8 s),
using optical joint geometry or a controller grip/index/thumb approximation.
It opens the existing recipient selector; native skill checks and recipient
consent remain in the established flow. Pet and droid command menus intentionally
remain unchanged, as requested.

The medical focus uses tap/release for Tend Damage and a 0.65 s trigger hold for
Quick Heal, without requiring circle selection. Holding never fires Tend Damage
first. Explicit First Aid selection retains its short-trigger fallback. Treatment
selects the native ability and rechecks the same aimed recipient after the reply;
focus loss, stowing, session/world changes and changed aim cancel pending use.
Medical supplies continue through their existing item-specific treatment path.

Validation: 951 checks passed across image_frame_smoke (40),
medical_focus_trigger_smoke (27), medic_smoke (35), bandage_gesture_smoke (14),
gesture_arbitration_smoke (30), entertainer_smoke (749),
entertainer_extension_smoke (32), and flourish_clap_smoke (24).
All used `godot --headless --xr-mode off --audio-driver Dummy --path client
--script res://tests/<name>.gd` with mocked tracking/native transport and the dummy
renderer. No GPU/headset validation or live VR launch was performed. Evidence is
in ignored `runtime/evidence/*_smoke-current.log`, `image-frame.json`, and
`medical-focus-trigger.json`. Native code and backend balance were unchanged.

## Local target-point combat abilities — 2026-10-08

Ranged ability activation now uses a real-time, player-local anatomical overlay:
weapon-hand stick click acquires the aimed native creature, and firing at a point
requests that point's ability on the same actor. Head/Concussion, heart/Lethal,
pelvis/Low Blow and knees/Restraining points follow posed source bones or source
bounds on one target-depth plane. Scenery and shot-path checks hide obstructed
points; materials retain depth testing. Eligibility checks cover native grants,
state, SAC, cooldown, certification, weapon condition, capacity/reload and range.
The overlay neither changes time nor replicates to other clients.

Last Ditch uses a physical two-hand weapon hold and a fresh both-trigger chord.
A 120 ms tolerance accommodates uneven trigger edges without a preceding ordinary
shot. Held triggers cannot repeat the ultimate; separating the support hand after
activation cannot fabricate an ordinary trigger edge. No native advanced melee
specials were introduced; the existing explicit melee profession lab remains.

Patch 0085 adds native range/state/ultimate metadata and optional target binding
on ranged fire. The current client always binds specials. Core3 checks the chosen
actor before spending resources, stores it on the shot, and rejects another actor
at impact. The normal projectile, LOS, cadence, ownership and damage path remains.
The adapter validates/forwards the source target ID; client launch routing no
longer reads a selected/primed ranged ability. Confirmed rejected launches release
the local cooldown reservation from the current native snapshot.

Validation: 320 checks passed across target_abilities_smoke (84),
gameplay_combat_smoke (53), profession_combat_smoke (29), ranged_combat_smoke (62),
xr_combat_input_smoke (50), world_combat_coverage_smoke (12), and live_combat_smoke
(30). combat_collision_smoke also passed. These used the dummy renderer,
`--headless --xr-mode off --audio-driver Dummy`, mocked tracking/native transport,
and local original assets. Three Python Smuggler transport tests passed. The
complete patch stack applied, and the local Core3 executable linked successfully
in the existing build container; a fresh build receipt was recorded.

Desktop Forward+ Vulkan rendering on Intel Arc A770 was inspected in
`runtime/evidence/target-abilities-vulkan.png` (original avatar, mocked combat
state, XR disabled). No live server encounter or headset launch was performed;
this is not live VR validation, and the update has not been deployed.

Separate existing regression: xr_main_smoke passed its ordinary stage entry,
collision, movement, tracking and bounds checks, but failed its two missing-floor
assertions. The same two failures reproduced in an isolated client using the
pre-change ranged rig and combat bridges. See `target-xr_main_smoke.log` and
`target-xr-main-baseline.log`; this is not a passing full-stage regression claim.


## 2026-10-08 — Linux and Windows testing launcher preparation

Prepared Python 3.10+/Tk source bootstraps for Linux x86_64 and Windows x86_64
under `runtime/releases/testing-launcher/`, with SHA256SUMS. Linux uses launch.sh;
Windows uses launch.cmd. Both contain only launcher code, public origin/CA and
instructions. The client build remains a subsequent task; no client payload or
live server update was published, and no VR client was started.

Launcher host checks, user installation defaults, file locking and atomic writes
now support both systems. Releases declare their platform and require the
appropriate engine/godot or engine/godot.exe. New bootstraps use independent
`testing-linux-x86-64` / `testing-windows-x86-64` channels, compatible with the
existing gateway route validator. The legacy Linux `testing` channel remains
supported. A missing channel explains that its client build is not published yet.
The Linux publisher accepts prepared Windows payloads; Windows engine/native
extension assembly and native validation remain part of the later client build.

Validation: 75 tests passed across test_launcher_platform, test_client_launcher,
test_account_auth, test_remote_gateway and test_remote_auth. These include local
TLS, invitation/account flows, both target manifests, archive isolation,
independent publication sequences, platform mismatch rejection, interrupted
updates, cross-process installation locks and session-file cleanup. Child game
processes were mocked. Evidence: runtime/evidence/testing-launcher-tests.log.
The packaged Linux launcher window was opened, inspected and closed without
logging in or starting a download/game; screenshot:
runtime/evidence/testing-launcher-linux.png. Native Windows startup, Windows
locking and headset behavior have not been exercised on Windows hardware.

## 2026-10-08 — Weapon-family combat loadouts

Implemented four combat slots plus one ultimate per weapon family. Physical
right-stick click while the equipment hologram is active switches to an ability
grid on the left, details on the right, and four slots above the original avatar.
Grip-drag equips, swaps, or clears regular slots; trigger-click selects/clears the
separate ultimate row. Confirmed slots connect to original body anchors. The
pointing hand follows weapon-handedness; the opening click remains physical right.
The editor consumes equipment/combat inputs, requires fresh input edges, cancels
on tracking loss and weapon changes, and retains drags through changing cooldown,
state and Last Ditch multiplier observations. Dropped-outside drags do not save.

Patch 0086 stores per-character/per-family selections on the Core3 PlayerObject.
The existing authenticated live session accepts bounded revision-checked loadout
proposals for the actual equipped item. The native catalog separates all learned
compatible choices from equipped abilities; both native fire and client targeting
reject unequipped abilities. Ultimates cannot occupy regular slots, duplicates
are rejected, and editing never resets cooldowns or spends SAC. Initial family
loadouts are empty. Melee families have slots but no invented native specials.
UI confirmation is driven by the native snapshot, not local preference files.

Validation: 400 client checks passed: combat_loadout 27, equipment_hologram 48,
target_abilities 86, gameplay_combat 58, xr_inventory 49, inventory_hand_pose 50,
profession_combat 29, equipment_actions_main 23, live_combat 30. These ran with
`--headless --xr-mode off --audio-driver Dummy`; combat transport and tracking
were mocked. 46 Python protocol/account/TLS tests passed. The shared native
loadout policy passed 15 C++ assertions; the full patch stack applies, Core3
linked successfully, and the native build receipt was recorded and verified.
The existing live Smuggler/slicing test fixtures now explicitly equip abilities;
those live combat fixtures were not run.

Desktop Forward+ Vulkan output using original avatar assets and mocked native
loadout state was visually inspected at
`runtime/evidence/combat-loadout-vulkan.png` (Intel Arc A770). The capture uses
`--xr-mode off`. No headset or live combat launch, client release publication, or
server deployment occurred. Native persistence and gestures still require a live
validation pass after the launch hold is lifted.

Separate broader-check limitation: inventory_main_smoke made read-only local
Core3 inventory/weapon requests and its 27 assertions reported success, but an
asynchronous script error called missing Player.get_camera() in that test's
mock player during main.sync_inventory_equipment. It is excluded from the 400
passing checks. Evidence: runtime/evidence/loadout-inventory_main_smoke.log.

## 2026-10-08 — Live deployment and outdated-client launcher smoke

Deployed the prepared current native build and gateway to `87.106.27.237` after
graceful save, consistent persistent-state backups and verified delta transfer.
The 35-file package changed 34 files. Post-deployment checks confirmed native
readiness, unchanged account/character counts and private configuration, ten
original ground planets and the 05:00 UTC restart timer. See VPS_DEPLOYMENT.md
and `runtime/deploy/combat-loadouts-live/` for hashes, backup path and receipts.

Added explicit `--desktop` mode to both launcher bootstraps. Its button reads
Play desktop (test), and it starts the client with `--xr-mode off --desktop`.
The default remains Play VR. Rebuilt both platform archives and SHA256SUMS;
24 launcher unit tests pass (`runtime/evidence/launcher-smoke-preflight-tests.log`).

The extracted Linux bootstrap passed 19 end-to-end checks against an isolated
local TLS gateway using the deployed gateway implementation. A real outdated
smoke-v1 installation updated to smoke-v2, fetching only 3,684 bytes in three
blobs while reusing the unchanged 131 MiB Godot engine. The update added and
removed files, retained the old release, and launched the real updated Godot
client with an authenticated temporary connection profile. Forward+ Vulkan ran
on Intel Arc A770, OpenXR stayed off, the process exited successfully and its
session profile was deleted. Evidence and inspected screenshot:
`runtime/deploy/launcher-local-smoke/{result.json,launcher-after-update.png}`.
This tiny smoke project does not enter a character or validate headset gameplay.

Two attempts against the live gateway failed at sign-in before any download;
their temporary accounts, patch channel and gateway configuration were cleaned
up successfully. A subsequent harness adds a verified TLS readiness check after
the gateway restart and safe exception diagnostics. Local success does not
establish a passing live launcher test. That retry was stopped at the unanswered
secure sudo credential prompt, before temporary setup began. A final authenticated
TLS health check confirmed native readiness, and the daily restart timer remained
active/enabled for 05:00 UTC. Native Windows execution remains
unvalidated; the production client payload is still a separate pending build.

## Survey tool persistence and storage limit — 2026-10-08

Patch0087 enforces one placed native survey tool category per character across
planets. Different item IDs, resource selections and tool variants cannot bypass
that reservation. A recovered tool frees its category. Native escrow, spawn
anchors and screenplay checkpoints continue to account for offline time; output
now stops at `ResourceContainer::MAXSIZE` (100000 units), with the final sample,
resource depletion and XP limited to accepted units. The client shows capacity
and a full-storage state without a misleading sample countdown.

Validation: linked CoreCU build and matching native receipt; complete patch-stack
reconstruction; deterministic C++ settlement tests (offline serialized state,
cadence, expiry, bounded catch-up, exact final unit, XP, full-storage no-op and
legacy excess preservation); ten Python policy/transport/inventory tests; Godot
headless deployed-tool presentation, actual-stage source locomotion (29 checks)
and actual Tatooine terrain-follow regression. These use the dummy renderer with
OpenXR disabled and do not validate GPU or headset rendering.

`runtime/evidence/survey-limits-native.json` records actual local native duplicate
rejection, independent tool types, logout persistence, offline cycles, controlled
near-full buffers, capped output/XP, recovery and redeployment. Near-full quantities
and productive sampling checkpoints are deliberately seeded on a disposable test
character, not represented as days of natural production.
`runtime/evidence/survey-restart-persistence.json` confirms the original tool IDs,
resource anchors and coordinates survive graceful server restart, offline cycles
accrue and both tools remain recoverable. The initial90-second shutdown wait
expired while the native process was still closing after its shutdown-complete
log; it subsequently exited without force, and readback passed after restart.
The optional restart smoke now permits240 seconds for full process exit before
starting another database writer. The subsequent user-authorized deployment passed live audit and authenticated HTTPS survey-limit verification; see `docs/VPS_DEPLOYMENT.md` (Persistent survey limits).
