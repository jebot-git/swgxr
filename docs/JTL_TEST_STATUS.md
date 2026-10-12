# Original JtL test scope — 2026-10-10

The test realm enables the ten original Core3 space zones: Corellia, Dantooine,
Dathomir, Endor, Lok, Naboo, Tatooine, Yavin IV, Deep Space and Kessel. Core3's
original spawners and mission observers own NPC traffic, hostile encounters,
combat damage, credit payouts and loot rolls. The account's Luxury Yacht remains
excluded from combat. Use a crafted and outfitted combat hull for combat tests.
Space mining is deferred at the user's request.

The client reconstructs original sky faces, planets, clouds, halos, celestial
layers, stations, landmarks and seeded asteroid fields from the supplied media.
The desktop mirror uses the same sector exterior as the headset. Wrist and
datapad maps use sector coordinates with XZ, XY and ZY projections, nearby ships,
original jump points and native quest waypoints. The navigation panel lists
original hyperspace destinations and exposes native jump/abort commands.

Flight references the pinned original SWG client `ShipDynamicsModel` and
controller sources, recorded with hashes in `server/jtl/flight_reference.json`.
Native ship/component statistics supply speed, acceleration, angular rates and
slide damping. Input is integrated at 50 ms intervals in three dimensions; stale
controls stop after 1.5 seconds. The client smooths confirmed pose corrections and extrapolates native linear and
angular velocity for at most 750 ms. Serialized native requests reuse verified
TLS connections without automatic mutation retries. Ground locomotion rules do not govern flight.
Primary fixed blasters use native projectile collision, capacitor drain, refire,
damage attribution and loot. Missiles, countermeasures and gunner turrets are
not yet exposed by the client. Bolt and hit visuals now use original projectile/CEF/PRT resources, including
animated texture frames. Missile presentation remains simplified; see the
2026-10-12 recording follow-up below for validation limits.

## Pilot missions and ship services

Interact with an original trainer's mesh to enter its original conversation.
The bridge calls the existing Core3 Lua conversation handler and native mission
objects; it does not grant a replacement JSON mission. Active space missions
appear in the datapad, with current-sector mission waypoints on the sector map.
Conversation choices carry a current-screen token and replay-safe request ID.

Test.17 integrates all nine original squadron progression paths through 46
trainer/conversation bindings and 475 mission-leg definitions. Akal Colzet and
the previously missing Imperial, Crimson Phoenix, Vortex and late Havoc paths
use the shared original-source conversion and native quest runtime. Missing
Total Experience narrative strings use functional fallback text. All nine paths
reach mastery in simulated progression checks; native tests cover trainer
bindings, rewards and distinct pickup/delivery docking. Complete gameplay and
balance testing of every mission remains pending. See `docs/PILOT_MISSIONS.md`
in the source repository for conversion provenance and detailed limits.

Craft chassis tokens with the native Shipwright crafting session. Experiment
while points remain, review the result, and finish construction. At a chassis
dealer, select the crafted token, review the original fee and redeem it. Register
the resulting deed to obtain the native owned hull. Original pilot certification
requirements still apply. At a starship terminal, open **Components**, choose an
owned stored ship and install compatible inventory components. Remove an
installed component before replacing it. Luxury Yacht components are fixed: the
interface omits component changes and the native uninstall command rejects them. Original starter/prototype components
are not automatically interchangeable with standard crafted hull components.

## Known asset and presentation limits

All 58 supplied Total Experience TREs lack these original resources (see [media scope audit](https://github.com/jebot-git/swgxr/blob/main/docs/MEDIA_SCOPE.md)):

- `object/static/space/asteroid/shared_asteroid_molten_mammoth_01.iff`
- `object/static/space/asteroid/shared_asteroid_molten_mammoth_02.iff`
- `appearance/corellian_corvette_pob.pob`

The missing Dathomir asteroid variants are omitted and the affected corvette
interior appearance has no converted hull. Source hashes and exact failures are
retained in the private catalogs. No replacement proprietary assets were fetched.
The original Dantooine asteroid-style spelling error and Endor malformed field
vector are recorded by the converter. Other conversion errors remain failures.

Nebula gas quads now use original textures, field positions, radii and density
rules; their deterministic random placement differs from the original client
RNG. Distant particle appearances and hyperspace use bounded GPU playback of
original particle data and textures. Planet UV orientation, moon tiling, surface
rotation and halo angle units follow the original renderer. Nebula lightning and
sound, exact planet detail-shader blending and radial asteroid animation remain
presentation gaps. Hyperspace retains the tracked camera rather than applying
the original third-person camera and camera shake. Sector reconstruction is therefore
a limited test implementation, not complete original-client visual parity.
Sky cube seams may be visible. The asset closure conservatively retains catalog
alternatives and their dependencies, including those needed by these pending
presentation paths; raw TREs and standalone developer outputs are excluded.

## Validation boundaries

Tests use an isolated account whose name starts with `invtest`. Fixture scripts
provision crafting ingredients, skills, money and standard component loot solely
to that account. The Z-95 chassis itself comes from a native crafting job; the
dealer consumes that token and the original deed creates the owned ship.
Crafting experimentation and replay protection, original trainer enlistment,
redemption fees, and install/remove/reinstall passed live native tests.

The combat fixture positions an original hostile NPC ahead of that crafted ship
and repairs only the fixture's own hull. Projectile collision, damage, threat,
NPC destruction and loot remain native. This validates the transaction path; it
does not establish encounter balance or ordinary pilot difficulty. Live combat
exposed an original octree bounding-center error that omitted nearby objects in
translated octants; the corrected native method is checked across 4,096 cells.

All ten sector captures use desktop Forward+ Vulkan. Script, input and movement
smoke tests use the dummy renderer with XR disabled. Neither validates a live
headset or native Windows Vulkan/OpenXR rendering. Actual headset and physical
microphone selection checks remain separate from these automated checks.

Station communications use the native station conversation handlers, including
original range checks, landing-port choices and repair fees. The selected port
supplies both planet and coordinates; no client Tatooine fallback is used. The
command wheel and datapad no longer expose the emergency return shortcut. Hyperspace phase
receipts come from Core3's actual task; the client presents calculation, countdown,
entry and arrival. Original cockpit particles and audio are converted from
`scene/hyperspace.iff`. Headset tests remain suspended; desktop Vulkan captures
and headless tests do not establish headset rendering or comfort.

## Navigation update evidence

The isolated native yacht reached its component limit of 47.04 m/s and travelled
182.19 metres in 6.59 seconds. Losing input stopped it after the 1.5-second lease.
The original Tatooine station conversation completed a Mos Eisley landing and
stored the ship. A subsequent jump reached Naboo and reported calculation,
orientation, countdown, travel, arrival and idle from the native task.

The original-source comparison is pinned and hashed in
`server/jtl/flight_reference.json`. `PlayerShipController` and
`ShipDynamicsModel` inform three-dimensional flight; `SpaceEnvironment` and
`PlanetAppearance` supply sector transforms, UVs, parallax and layer settings;
`ClientNebula` supplies field population rules; and `HyperspaceIoWin` plus the
supplied `scene/hyperspace.iff` define cockpit entry/exit presentation. Core3
remains authoritative for component statistics, conversation landing and jump
timing. Original nebula shader references distinguish additive gas from alpha
clouds; treating both as alpha previously produced black quads.

The 60 Hz presentation regression preserves constant flight speed across 5 Hz
native receipts. TLS reuse passed real HTTPClient/certificate verification tests.
These checks address known stalls and correction spikes; they do not establish
that all network rubberbanding or headset control issues are resolved.

## Presentation follow-up (test.6)

The private presentation archive adds original chair poses for all 20 race/sex
combinations, ship CDF engine bindings, POB interior ambience, source environment
entry music and original space-combat music. Eleven unresolved CDF references
(including duplicate references) remain recorded in the audio conversion audit;
no replacement media is supplied. Blank original music fields remain blank.
Ground ambience is stopped while aboard and restored on return.

Hyperspace follows the centre-eye pose, uses a shared billboard orientation for
both eyes and respects original additive material flags. The desktop Vulkan
capture verifies shader compilation and removes the opaque square found during
review. This is not a live stereo/headset verification. Synthetic avatar tests
check seated pelvis anchoring and bent legs for all 20 bodies while preserving
head, controller and physics transforms.

Native bazaar scope filtering supports this terminal, current planet, galaxy and
searchable player vendors. Static NPC suppression now recognizes each original
spawn's full appearance pool, including stationary citizens and GCW alternatives.
Exact placement and alternate-template cell identity are still required; native
visual readiness controls fallback suppression. The cross-planet synthetic suite
passes 5,846 checks.

The remote voice relay had been stopped during maintenance. It was restarted;
starting the gateway now also pulls in the relay. Two isolated accounts passed
39 live TLS/WSS/Opus checks without activating a microphone. Physical microphone
and live headset tests remain suspended.


## Sector rendering audit (test.7)

The original client reference paths, revision and SHA-256 hashes are recorded in
`server/jtl/sector_rendering_reference.json`. The audit compared SpaceEnvironment,
SkyBox6SidedAppearance, StarAppearance, PlanetAppearance, ClientAsteroidManager,
AsteroidGenerationManager and the nebula generation/rendering sources against
all ten converted sector manifests. Positions use original XYZ with a reflected
Z axis in Godot. Stations and landmarks retain Core3 coordinates; authored terrain
files supply background positions, sizes, orientations and lighting.

Sky faces now use a hardware cubemap with filtering across adjacent faces. Small
original bottom-face textures are expanded to the largest supplied face size;
the original artwork is retained. Stars use the source count-seeded ran1 stream,
first-row colour ramp and randomized alpha. Planet parallax includes the camera
offset from the ship, preserving the source 100/sector-width background scale.
Both authored parallel lights illuminate planets and static sector meshes; cloud
shells also render beyond the solid planet silhouette.

Asteroid visibility follows distance to the field edge and the original ordered
prefix, including the source's removal hysteresis. Grouped meshes no longer
vanish together based on their MultiMesh origin. Nebulae skip zero density, use
90% of the authored generation radius, minimum quad spacing, four corner colours,
source light darkening and paired X/Y-constrained facing quads with angular alpha
fading. Distant mesh appearances are now instantiated as well as particles.

This remains a translation into Godot rather than a complete port of SWG's
renderer. Remaining differences include original planet detail shader stages,
asteroid spin and proximity-driven radial debris, and nebula lightning. Stars use
a fixed angular raster rather than two-pixel points; nebula random placement uses
a deterministic client stream rather than SWG's global RNG. Mesh materials retain
the converted diffuse/vertex-colour representation. The two missing molten
mammoth asteroid templates remain missing source media, not replaced assets.

Validation: 205 sector-rule checks with the dummy renderer and desktop Forward+
Vulkan captures of all ten sectors. These checks do not validate headset stereo.
VR launches remain suspended.

## Explicit JtL targeting (local integration, 2026-10-11)

Ship selection is now a persistent native pilot/ship target. Dominant-hand A/X
selects the looked-at ship; the other A/X cycles hostile contacts. Dominant-hand
B/Y cycles available subsystems; the other B/Y fires an acquired missile.
Ship commands → Targeting provides previous/next selection, clear, named paged
subsystems (including whole ship), launcher selection, inspection and docking
commands. Physical HOTAS buttons are configurable and saved in Flight Controls.
Selection never rotates the HMD or redirects fixed guns.

The HUD separates target brackets, ship-forward gun reticle and projectile-speed
lead. Lead smoothing applies to the predicted offset, not ship steering.
Core3 validates target identity, same-sector distance, targetable components and
missile eligibility. Protected/destroyed components are shown unavailable;
a destroyed selected component does not silently switch selection to hull.
Native shields, component damage, inspection observers and quest logic remain
authoritative. Mission docking is now granted for the exact NPC selected by an
active native inspection/rescue objective (task 2). Inspection must complete
before an inspection mission grants access. Ordinary pilots cannot dock with
arbitrary targets; changed, failed or completed objectives revoke permission.
Native approach obstruction checks and docking completion observers remain in
use. Undock permits the active pilot to cancel while in ordinary peace/seated
states, which the original client-only undock table rejected on the server.

The XR projectile no-subsystem byte is 255, not reactor slot 0. A requested
component applies only to the selected victim, so intervening ships do not inherit
that component request. Collision candidates refresh on native projectile batches
and are no longer truncated to the AI's 32-contact view. The AI view remains
bounded. This does not change the separate ground hit protocol.

Missile acquisition uses original ammunition cone/time plus launcher range,
requires fresh flight control, and resets on loss of eligibility or changed
ship/component/launcher. Launch checks native ammunition, recharge and capacitor,
and uses native guided ShipMissile simulation. Retry receipts prevent double
consumption. The existing outfitting interface exposes compatible ammunition
loading for empty missile launchers; it calls the native loader. Its obsolete
fltmaxammo-only check now uses the ammunition item's actual count (original
templates also use the ammo attribute). Missile presentation consumes native
position/termination receipts, with bounded smoothing and expiry.

Original-derived client reference paths and hashes are recorded in
server/jtl/targeting_reference.json. Later client enum slot numbers are deliberately
not copied: this Core3 revision places weapons at slot 12.

Validation passed: full native build and build receipt, 30 protocol/policy tests,
10 native flight/crew/transaction/spatial regression tests, Godot import and
headless targeting/effects smoke, and 70 synthetic flight/interior checks on
the original yacht geometry. The isolated crafted Z-95 / original NPC test passed
17 targeting, subsystem, inspection, lock-loss and missile-ammunition checks;
9 further live checks verified fixed-gun damage, destruction, native kill loot
and payout after the no-subsystem change. NPCs were repositioned and the fixture
hull repaired for deterministic targeting; these are not free-flight balance or
remote latency tests. Validation artifacts are local under
runtime/evidence/jtl-targeting-*.
The client smoke uses the dummy renderer with XR off; it does not validate headset
stereo or controller ergonomics. These changes are included in the test.16
release package; deployment evidence is recorded separately.

## Pose-controlled virtual HOTAS (2026-10-11)

Virtual HOTAS now uses the selected dominant controller as a steering gesture:
hold its grip-pose up axis upright for 200 ms, then tilt to pitch/roll or twist
to yaw. The off-hand controller engages throttle when held sideways for 200 ms;
28 cm of forward/backward travel spans full throttle. Both gestures use the
cockpit frame and have separate entry/release thresholds. Leaving the throttle
pose holds its setting and permits repositioning without a jump. Tracking loss,
UI focus, stale state and mode/hand changes clear gesture capture and thrust.
No authored grab handles, thumbstick axes or grip holds are needed in this mode.
Existing button commands remain available. Physical HOTAS and stick mode remain
separate choices. Tracked head, hands and body are never driven by this input.

Validation: 36 gesture checks, including both dominant hands, a rotated cockpit,
axis signs, release/reacquisition, ignored grip/stick values and tracking loss;
70 original-yacht integration checks. Both ran headless with XR off and the dummy
renderer. Controller ergonomics and live headset behavior remain unvalidated.


## Flight and spacecraft patch — test.21 (2026-10-12)

The enabled hull set expands to 45 templates including the existing Yacht. See
[the complete player spacecraft inventory](https://github.com/jebot-git/swgxr/blob/main/docs/PLAYER_SPACECRAFT.md) (also bundled in `engine/docs/`). These changes
are included in test.21, following test.20.

The TIE desktop camera anchor placed the eye 32 cm behind and 23 cm above the
yoke grips. VR frame alignment adds 23 cm rearward and 20 cm upward clearance;
tracked poses stay untouched, and approved Z-95/X-wing stick placement is retained.
A terminal JTL session-conflict response now stops polling, freezes extrapolation,
drops queued actions and opens normal reconnect handling. Reconnection clears
old scene/revision state before admitting a fresh owned snapshot. The retained
recording-session network ring contains only the subsequent 409 status failures;
it does not establish why the original owned session ended.

Cockpit waypoints follow the original SwgCuiAllTargetsSpace active-waypoint,
colour, ship-distance and 50 m suppression rules. The XR adaptation adds bounded
edge arrows for objectives outside the forward view. Markers survive long range
without far-plane clipping and clear on objective changes, landing or session
loss. This complements the native mission/map waypoint corrections already
recorded in PILOT_MISSIONS.md.

Foraging now accepts distance-based out-and-back strokes on all three axes at
controller heights up to 55 cm, with a 4-second stroke-gap allowance. Either
tracked hand can dig while the other is untracked. Near-ground dirt feedback is
retained, action dispatch still waits for native availability, and unavailable
states no longer permanently latch a gesture. Native costs and cooldowns remain
unchanged. Slow/fast synthetic traces span 0.35–4 Hz; headset gesture reliability
still requires physical testing.


## jtl2.mp4 follow-up — 2026-10-12, local integration

The recording ends with hull **0/800** while still in the cockpit. Earlier engine
failure at 774/800 was a separate component-disable state. The retained client
network ring contained successful responses, rather than the earlier session
conflicts. This patch is local and has not superseded the published test.21.

- Native `DestroyShipTask` iteration 1 returned without rescheduling the final
  storage/ejection stage. It now runs that stage after the five-second destruction
  effect and uses the exact control-device landing point. The isolated test also
  caught unsigned underflow in the original random landing offset; recovery uses
  `getStoredPosition(false)`, as the existing launch flow already does. The hull
  remains owned and damaged; normal native storage returns the crew to ground.
  Zero hull stops flight integration and primary/secondary weapon delivery.
- Space audio passed scene-local positions into the global spatial mixer. The
  cockpit scene is at Y=10000, so the distance gate rejected nearby shots/hits.
  Positions now include the scene's global transform. Original engine ENGS banks
  resolve from chassis/component attachment tables, including damage bands; root
  INTS booster audio follows the native booster-active flag. These are distinct
  loops with the original volume, interpolation and semitone-pitch parameters.
- Original native quest system messages, music and NPC taunts are bridged as
  owner-only, bounded, expiring receipts. Existing STF strings/parameters supply
  the text. The cockpit shows deduplicated nonmodal messages and NPC sender names.
  Existing station reply conversations remain unchanged. This adds no invented
  voiced dialogue or alternate mission state machine.
- Seventeen original projectile entries and four shield/armor/component/chassis
  hit effects now select their original CEF/PRT textures, curves and colours.
  GPU playback handles source texture-sheet animation and projectile alignment;
  reusable curve textures are cached. EMTR 0014 decoding follows the original
  source's shared prefix, retaining extension bytes. Nested particle attachments,
  CEF camera shake/lights and missile models are not claimed complete; the HMD is
  never driven by an effect.

Original implementation references and SHA-256 values are recorded in
`server/jtl/presentation_reference.json`. Converted user media remains ignored.
The space audio catalog now contains 63 sounds. Its 11 pre-existing missing CDF
records belong to NPC transport/escape-pod templates; they remain reported in
conversion failures, rather than silently replaced. Combat effect conversion has
no missing dependencies in the supplied media.

Validation evidence is in `runtime/evidence/jtl2-20261012/`: native build, Python
protocol tests, the 74-check client smoke, receipt/coordinate/expiry effects test,
and the combat-audio/communications test. The latter decodes an original sample
and verifies admission to the spatial mixer with a listener at Y=10000; dummy
audio does not prove headset audibility. `original-effects.png` is a Forward+
Vulkan capture on Intel Arc A770, with XR disabled. It is GPU evidence, not a
headset test.

`tools/space/destruction_smoke.py` uses an isolated invtest account and an already
natively crafted Z-95. It invokes the real destruction task directly, checks
original mission/NPC communications, automatic return to Tatooine and continued
hull ownership, and restores temporary Lua fixture code. This tests the recovery
path; it is not a new prolonged combat or lethal-damage test. The final probe
passed all 9 checks and returned to ground in 10.13 seconds, including the
fixture task's four-second scheduling delay. The next release
must include native patch 0153, the adapter/client changes and the revised local
media preparation recipe. Existing launcher recipe hashing invalidates changed
conversion inputs; proprietary assets are not shipped in public patch bundles.
