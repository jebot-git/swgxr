# Combat foundation

The prototype has two distinct combat modes. The opt-in **local combat lab**
does not write inventory, condition, wounds, health, ammunition, rewards or combat
results to Core3. It says NON-PERSISTENT on screen and damages its labeled target.

The newer `--live-combat` ranged test holds a persistent native Core3 zone session.
Nearby creatures and lairs, HAM, damage, death and XP are authoritative. Tracked
launches and swept client contacts supply evidence for native validation; the
client never applies local damage to these actors. Live inventory, gathering and
entertainer RPCs remain suspended until they share this persistent connection.
See [WORKFLOW.md](WORKFLOW.md) for the current bridge and validation details.
Earlier milestone notes below describe the local lab and its historical blockers;
statements that persistent native combat is unavailable predate this integration.

## Melee baseline

Grip affects **Power only** for melee. It does not change effective range or the
required recovery separation. Draw one-handed weapons from the dominant hip and two-handed
weapons from over the dominant shoulder using the existing original-derived mounts.
Hold the attacking hand's trigger to be combat ready; release it to be at peace. The first unobstructed target under
the head-bound reticle at the instant the swing qualifies is hit within effective
range. Blade contact and swing direction do not select the victim. Hand positions determine spatial recovery between attacks.
The faint original reticle is a camera child at a fixed three metres, so late head
pose updates cannot leave it shaking at an old world transform. No aiming lag is
introduced; ranged aim remains anchored to the gun. The melee reticle is a reference,
not a lock-on indicator. World collision blocks the targeting ray.

Baseline tuning in `client/combat/balance.json`:

| Class | Stance recovery | Power | Hands |
| --- | ---: | ---: | ---: |
| Knife | 125 | 115 | 1 |
| Sword | 100 | 100 | 1 |
| Baton | 110 | 105 | 1 |
| Heavy axe / maul / cleaver | 75 | 80 | 2 |
| Polearm | 90 | 90 | 2 |

- Required speed is `1.4 m/s × 100 / effective Power`.
- Required separation from the previous attack position is `0.35 m × 100 / Stance recovery`.
- Two hands on a one-handed weapon multiply Power by 1.2. One hand on a
  two-handed weapon multiplies Power by 0.5. Neither changes reach or travel.
- Standing reach uses Core3 maxRange; crouching multiplies reach by 0.75 and
  prone by 0.5. Source range/damage curves scale with that reach. Melee never
  receives the ranged crouch/prone mitigation of negative damage modifiers.
- Original damage spread/type, resistances, armour piercing, wounds,
  certification and condition handling use the shared combat calculation.

`SwgMeleeSwing` measures direct hand separation from its last qualifying attack,
using tracking coordinates relative to head translation to cancel virtual locomotion
and snap turns. The first sample after drawing or enabling seeds that reference.
While combat ready, moving the recovery distance and meeting the Power speed threshold registers an
attack and moves the reference to the current hand position, including on a miss.
Slow withdrawal may prepare an inward swing, but cannot itself attack. Each fast
segment checks its starting and ending distance, so an inward swing from the recovery
boundary qualifies. There is no additional travel charge after rearming. Resting,
trigger presses and circling inside the recovery radius cannot rearm it; continuous
motion can strike again only after covering the required direct separation. Trigger
readiness is a binary hold gate (0.5 threshold), not an attack button: changing it
does not reset the last strike position, and pressing at rest cannot attack. Peace
still tracks hand positions but suppresses attacks immediately.
Tracking loss, focus/menu gating, invalid timing and tracking jumps reset the gate.
Stat/grip threshold changes establish a new reference and cannot spend old movement.
No animation writes controller or HMD poses. The secondary hand stays attached
to a one-handed weapon until support grip is released. Two-handed melee uses its hilt
axis, not a gun's barrel axis, to orient between the two grips.

Twelve explicit Core3 templates are supported: Survival Knife, Stone Knife and its
starter variant, Vibroblade, Sword 01, Stun Baton, Gaderiffi Baton, Vibro Axe, Maul,
Cleaver, Wooden Staff and Vibrolance. Original model geometry, textures and CDF
swing/hit CEF and sound references come from the supplied media. The existing effect
renderer approximations described below still apply; exact original-engine visual
parity is not claimed. Lightsabers are outside this initial weapon set. Unarmed combat is described below.

Test the synthetic lab with:

```sh
./run.sh --offline --combat-lab --combat-sidearm=knife_survival --combat-longarm=2h_sword_maul
```

This defaults to VR/Vulkan. Add `--desktop` for inspection; F5/F6 draw, F7 toggles
support, hold left mouse for combat readiness and press F10 for a synthetic 2 m/s swing. The one-handed maul penalty requires
more speed than that debug gesture; use F7 for the supported grip. The local training
target is placed 2.5 m away when a melee weapon is equipped. For real inventory use
`--combat-items --sidearm-item=<owned-melee-id>` with the usual account/character
arguments. This reads real item statistics; hit results remain non-persistent.

Verification: 121 melee mechanics checks, 12 mocked XR action checks, original-asset
provenance, ranged/posture regressions, and actual-stage movement/stair/collision tests.
A real owned Core3 Survival Knife returned Power 115 and Stance recovery 125 across
fresh logins and entry. Knife/maul desktop captures used Forward+ Vulkan. Camera-anchor tests cover late
head movement and switching back to ranged aim; a Vulkan image comparison measured
zero reticle pixel change after translating and rotating the camera. No live
headset melee validation or full crafting workflow test is claimed.

## Unarmed combat and shared holsters

Melee weapons use the **same body holster code as ranged weapons**: one-handed
weapons use the dominant hip, two-handed weapons use the dominant shoulder reach
socket and the fitted back carry transform. The original skeleton/stow pose remains
the attachment source. No separate melee sockets or mounts are introduced.

With weapons stowed, either hand can punch by swinging while holding its trigger;
each hand owns an independent spatial recovery reference in the same native gate.
The head-bound reticle appears while either empty hand is combat ready. Engaged fingers close
without overriding the tracked hand pose. Drawing a weapon disables both unarmed
gates; stowing or recovering focus seeds fresh positions before another punch. Fists use the
same range/damage curves, world occlusion and crouch/prone reach penalties as melee.
They have no holstered model, ammunition, item wear or two-hand grip bonus.
Original `combat_melee_swing_unarmed.cef` and `combat_melee_hit_unarmed.cef` supply
sound/effect feedback; the supplied default unarmed template has no weapon model.

`server/combat/unarmed_balance.json` holds provisional tuning:

- Power = `100 + 0.1 × Strength + 0.25 × unarmed_damage`.
- Stance recovery = `100 + 0.1 × Quickness + unarmed_speed`.
- Both resolved values are bounded to 25–400. Higher Power reduces the required
  speed; higher Stance recovery reduces the required separation.

Strength and Quickness come from the selected character's replicated base HAM
attributes (not current resource depletion). Skill modifiers are actual replicated
Core3 permanent-plus-bonus totals. Brawler and Teräs Käsi (`combat_unarmed_*`)
contribute their original `unarmed_damage` and `unarmed_speed` modifiers; the client
does not infer bonuses from profession labels or grant skills. For this baseline,
`unarmed_damage` contributes to Power; the damage spread remains the original
unarmed template's 10–50 kinetic damage, with its range modifiers and wounds.

Patch `0017-player-combat-baseline.patch` retains owner-only CREO baseline 4 in the
protocol client. `server/unarmed_protocol.py` decodes it alongside baseline 1 and
returns `weapon_snapshot.unarmed` with source `core3_player_stats`, character ID,
raw player inputs, learned skills, tuning revision and resolved combat profile.
Missing/truncated player baselines fail closed. `/weapons` and `/enter` both expose
this profile, including when no supported weapon item is owned. Manual stat refresh
updates both fists and resets their spatial recovery references.
The explicit offline lab uses a labeled synthetic zero-modifier Power 100 / recovery
100 profile. No persistent unarmed item or replacement character store is created.

The existing combat launch commands enable unarmed too: leave weapons stowed in VR;
in desktop debug use F4 to stow, hold left mouse for readiness and use F10 for a synthetic punch. Both hand controllers
are tested with mocked OpenXR trackers; a Forward+ Vulkan capture verifies visible
closed fists and the head reticle, not live headset rendering. Automated tests cover
29 input/transition checks, real baseline decoding, source Brawler/Teräs Käsi skill
bonuses, ranged regressions and actual-stage integration. A fresh persistent Brawler
returned Strength 600, Quickness 450, unarmed damage 15 and speed 5, yielding Power
163.75 and recovery 150 across fresh logins and entry. Live Teräs Käsi training and
server-authoritative damage remain untested.

## Crafting-driven item profiles

The optional `--combat-items` path uses actual owned Core3 weapons. For example:
`./run.sh --combat-items --account=<account> --enter-character=<name>`.
It selects one supported sidearm and one longarm from that character's inventory;
`--sidearm-item=<object-id>` and `--longarm-item=<object-id>` select specific owned
items. It never substitutes a template weapon for a missing item. The synthetic
`--combat-lab` remains separate and cannot be combined with this option.

Core3 resolves ranged RPM/capacity and melee Stance recovery/Power from raw persisted item values:

- RPM = class/template base RPM × reference attack delay / item attack delay.
- Capacity = round-half-up(base capacity × reference total attack cost / item
  total attack cost), where total cost is health + action + mind.
- Melee Stance recovery uses the same attack-delay multiplier as RPM; Power uses
  the same total-cost multiplier as capacity, without integer rounding. Melee
  profiles expose neither RPM nor capacity.
- Version 2 bounds the RPM multiplier to 0.5–1.5 and capacity to 0.5–2.0.
  Zero total cost reaches the finite capacity cap; negative/non-finite costs and
  non-positive/non-finite delay are rejected.

`server/combat/crafting_balance.json` fixes per-template reference values from the
pinned Core3 defaults. These defaults are not claimed to be average crafted items.
`client/combat/balance.json` retains base RPM/capacity/reload/mode tuning.
`tools/combat/install_crafting_profile.py` generates the C++ reference table and a
combined SHA-256 balance revision. The adapter refuses mismatched revisions.
Change the balance version deliberately when retuning and rebuild Core3.

`server/combat/WeaponCraftingProfile.h` is the shared server calculation. Core3's
weapon attribute path calls it with raw fields after existing resource,
experimentation and component processing. Prototype examination exposes “Rate of
fire (RPM)” and “Capacity (shots)”, or “Stance recovery” and “Power” for melee,
using the same function as finished items.
No extra persistent stats, database migration, replacement crafting algorithm or
reuse of the dormant `roundsused` field is required. Slicing, powerups, combat
skills and the original server's attack timer are excluded from these crafting
multipliers. Existing condition damage remains a separate local combat input.

The authenticated `/weapons` snapshot carries item IDs, certification decisions,
raw crafting inputs, profile/balance versions and resolved stats. Entry returns
the same snapshot. The client uses its resolved combat statistics directly and uses actual item
damage/range/condition fields. “Refresh weapon statistics” refreshes the equipped
items and displays RPM/capacity or Stance recovery/Power changes; it never refills ammo, resets a reload or
rearms a held trigger. Missing/transferred items are disabled on refresh.

This is an item-stat integration, **not an authoritative combat connection**.
Shots, ammunition and damage still run locally, and inventory/stat changes are
received at entry or manual refresh rather than pushed. The client has no complete
crafting workflow yet; its reusable stat preview and the Core3 prototype examine
attributes are ready for that workflow. Factory copies and transfers retain the
existing Core3 storage semantics, but their end-to-end verification is deferred
until the crafting/trading workflow is exercised.

Verification: 3,056 native calculation cases across 28 profiles; client tests for
capacity/RPM refresh, certification and no-refill behavior; actual-stage rig
consumption; real Core3 Marksman item snapshots across fresh logins and a saved server restart. The live
fixture uses starting weapons, not fabricated “crafted” items. Run
`tools/server/weapon_crafting_smoke.py` with the dedicated local
`runtime/server/crafting-fixture.json`; reports live under `runtime/evidence`.

## Run

```sh
./run.sh --offline --combat-lab
./run.sh --offline --combat-lab --dominant-hand=left
./run.sh --offline --combat-lab --combat-longarm=carbine_ee3
```

The launcher exports the selected local Core3 checkout's bounded template catalog
and converts original weapon resources from the supplied active TRE archives.
Defaults are the DL-44 and E-11. Use `--combat-sidearm=<id>` and
`--combat-longarm=<id>` with the IDs in `client/combat/balance.json`.
The offline VR lab also renders an explicitly synthetic human test avatar for
hand and stow-mount inspection. These are test weapons, not inventory grants. The lab explicitly supplies their
required certificates to the local test actor; the normal firing state enforces
all required certificates and tests reject an uncertified actor. No character
skills or novice profession are silently treated as weapon certification.

For desktop regression/inspection, add `--desktop`; F5/F6 draw pistol/longarm,
F7 toggles simulated support grip, F8 cycles modes, F9 starts an early reload,
and left mouse fires. All direct desktop/headless/editor commands require
`--xr-mode off`. Forward+ on Vulkan is the only supported renderer for both PC VR and desktop. OpenGL
is unsupported; automatic OpenGL and D3D12 fallback are disabled.

## VR interaction

- Squeeze the dominant grip within 22 cm of its hip to draw the sidearm, or over
  that shoulder to draw the longarm. Hold grip to keep it; release returns it to
  its mount. Mounts follow head yaw and physical crouching. Default dominant hand
  is opposite the configured datapad offhand; `--dominant-hand` overrides it.
- Aim the actual held weapon; its handle follows the reachable rendered hand and
  its barrel uses the runtime's OpenXR aim orientation. Raw grip axes are not
  treated as barrel axes. If aim tracking is absent, the pinned XR Tools palm
  correction provides the fallback. The original SWG muzzle hardpoint, reticle
  and projectile share that corrected weapon transform. The trigger uses
  0.75 press / 0.20 release hysteresis.
- Squeeze the support grip within 18 cm of the dominant hand for a pistol, or
  the longarm fore-end. A longarm aims along the tracked hand-to-hand vector.
  A pistol keeps dominant-hand aim; its rendered offhand stays attached even if
  the physical controller moves away. Release, tracking loss, stowing or a
  menu/focus interruption removes the attachment. Longarms retain a 65 cm reach limit.
- Rendered wrists use original `hold_l` / `hold_r` transforms; fallback XR Tools
  gloves use its target-override API. Attached support fingers keep a closed grip.
  Source upper-arm and forearm lengths are hard limits. The old post-IK wrist
  translation override is removed. The weapon and hand stop together at the reach
  limit; a two-hand hold translates the rigid weapon into both arms' shared reach
  volume. It preserves grip spacing, weapon scale and wrist orientation without
  stretching either arm. Original weapon sockets remain attached to both palms.
  The HMD, controllers and collision body retain their tracked/gameplay poses.
  Regression coverage checks 72,609 bone/attachment/scale invariants across human,
  Ithorian and Wookiee rigs, both dominant hands, 0.8/1.7/2.5 m calibrations,
  standing/crouch/prone head heights, one/two-hand pistol/rifle and all 12 melee profiles,
  and extreme controller positions. Maximum measured grip error was below
  0.001 mm. A desktop Vulkan capture checks the original rendered avatar;
  this is not live-headset validation.
- Dominant B/Y cycles only that weapon's supported modes.
- A longarm held one-handed gets **30% of normal range**. With two hands it gets
  normal range. A pistol gets normal range one-handed and **110% with two hands**.
  All three range-curve distances scale with this multiplier; an in-flight shot
  retains the grip state it had at emission.
- Crouching halves negative range-damage modifiers; prone removes them.
  Positive range modifiers and grip-scaled projectile travel remain unchanged.
  These are the original Marksman pose bonuses, independent of skill accuracy.
  Physical XR posture
  uses grounded eye height relative to calibrated standing height (default 1.7 m):
  crouch enters below 78%, leaves above 86%; prone enters below 38%, leaves above
  46%. Low headset height is a proxy, so a very deep crouch can register as prone
  without full-body tracking. Airborne/invalid tracking receives no stance benefit.
  The existing standing-height calibration now also works in the offline combat lab.
  Desktop inspection uses the grounded controller's crouch/prone posture.
- Empty capacity automatically starts a timed power-pack reload/cooldown. The
  duration is a gameplay proposal; physical magazine manipulation is not implemented.
  A fresh trigger release/press is required after drawing, a menu/focus/tracking
  interruption, mode change or reload completion. A stalled frame cannot release
  a backlog of shots. Releasing grip cancels a partial burst.
- The aiming reference uses original `texture/ui_target_aim.dds`, tinted faint
  cyan, with its central cross removed in the shader. It sits exactly **3 m from
  the muzzle**, spans 18 cm and stays centered on the barrel axis. Its broad art
  and missing central cross make it an approximate reference. It does not raycast,
  follow target depth, change on a hit, predict impact or change the shot direction.
  Depth testing remains enabled. The desktop debug centre cross is hidden in the lab.

## Source-derived stow mounts

The source weapon arrangements are `hold_r` (pistol) and `hold_both` (longarm).
They do not define persistent weapon hip/back sockets. As requested, VR mounts
are derived from the original stow poses, rather than labeled as authored sockets:

- Hip: `all_b_cbt_pistol_standing_stow_pistol_holster.ans`, frame 30 at 30 fps,
  `hold_r` relative to `root`, during the hand's holster-contact interval.
- Back: `all_b_int_stow_object_backpack.ans`, frame 50 at 30 fps,
  `hold_l` relative to `spine3`, during the backpack-contact interval. This source
  uses the left hand reaching across the back; its contact lies on the right side.

Each race's original bind/pre/post rotations are retained when sampling. Left
hand dominance mirrors the derived mount across the character's sagittal plane.
The live avatar's final bone transforms drive both socket position and orientation;
weapons retain their original size. No stow clip drives tracked hands. The chosen
contact frames and adapting a generic backpack stow to a rifle are explicit VR
adaptations. Source hashes, skeleton dependencies, model hashes, frame choices and
arrangement descriptors are recorded in the ignored combat asset manifest.

The back-mounted weapon's resting visual now uses a separate carry transform.
Original torso bones and weapon bounds place it behind the torso with 2.5 cm
clearance and its top at the shoulder/neck boundary. The sampled over-shoulder
hand contact remains the grab socket; it no longer positions the resting rifle.
Original weapon scale and orientation remain intact. The human E-11 visual moved
down 33.2 cm; species-specific fits are exported for all 20 player skeletons.
`tests/back_stow_smoke.gd` checks the carry bounds, handedness, height variation,
crouched torso and draw/stow behavior.

The scale audit of `milestone-final-live-mirror.png` found no imported melee
mesh enlargement: the original wooden staff is 2.30 m long, the survival knife
0.303 m and the maul 0.964 m. `tools/combat/validate_assets.py` now compares every
melee vertex directly with the original TRE mesh (only the coordinate-system Z
reflection is allowed). The source client also renders attachments in their own
appearance transform without applying creature appearance scale
(`runtime/research/combat/SkeletalAppearance2.cpp`, attachment render loop).

The old first-frame calibration could shrink the avatar to a 1.20 m eye height
when entering seated/crouched, leaving the source-size staff disproportionately
large. That calibration is not recorded in the supplied live capture, so its
exact value cannot be recovered. Fixed-camera Vulkan reproductions at 1.20/1.70 m
are `runtime/evidence/weapon-scale-{1.2,1.7}.png`; the sideways staff carry also
emphasizes its length. Startup now uses the 1.70 m standing baseline unless an
explicit saved calibration is available. A low first head sample affects posture,
not permanent body scale. The standing-height calibration button still fits the
avatar to the user's measured height, without scaling weapons or the XR world.
`tracked_avatar_smoke.gd` checks low-startup/standing transitions for all 20 races;
`weapon_scale_capture.gd` renders the controlled comparison (desktop only).

The head-bound targeting reticle disables depth testing and uses render priority
127. It remains visible through scene geometry and characters; shot collision
and line-of-sight rules are unchanged. `tests/aim_reference_capture.gd` verifies
the original reticle against opaque and transparent occluders on Forward+ Vulkan.

## Provisional balance

These are authored starting values, not claims about canonical RPM, original SWG
power-pack capacities or final DPS. Capacity counts emitted projectiles. Burst RPM
is the spacing *within* a burst; EE-3/E-11 bursts have three shots and 0.30 s recovery.
The first mode listed is the initial mode. Individual overrides take precedence.

| Class / examples | Fire modes | RPM | Capacity | Reload / cooldown |
| --- | --- | ---: | ---: | ---: |
| Holdout / CDEF pistol | Semi | 240 | 12 | 1.6 s |
| Service pistol / D18, DH-17 | Semi | 300 | 24 | 1.8 s |
| Heavy pistol / DL-44, metal DL-44, Power 5 | Semi | 180 | 16 | 2.2 s |
| Carbine / E-11, DH-17 | Semi, auto | 450 | 40 | 2.4 s |
| Burst carbine / EE-3 | Burst, semi | 600 | 36 | 2.4 s |
| Service rifle / E-11 | Auto, semi, burst | 360 | 40 | 2.8 s |
| Marksman / DLT-20A | Semi | 90 | 12 | 3.0 s |
| Repeater / T-21 | Auto, semi | 240 | 30 | 4.0 s |
| Bowcaster | Semi | 75 | 6 | 3.2 s |
| Slugthrower / Tusken rifle | Semi | 60 | 8 | 3.5 s |

CDEF carbine and rifle explicitly override their class to semi-auto. Basic service
weapons and precision weapons do not acquire automatic capability merely because
a timer supports it. DH-17 pistol remains semi-auto: the Legends automatic
conversion is a modification, not assumed installed on every instance.

The E-11's canonical role is documented in the [official Databank](https://www.starwars.com/databank/e-11-blaster-rifle).
Its [canonical automatic setting](https://starwars.fandom.com/wiki/E-11_medium_blaster_rifle)
supports the automatic proposal. The [EE-3 Legends entry](https://starwars.fandom.com/wiki/EE-3_carbine_rifle/Legends)
describes three-shot burst behavior in Battlefront II. The
[DH-17 Legends entry](https://starwars.fandom.com/wiki/DH-17_blaster_pistol/Legends)
distinguishes an automatic conversion from the base pistol. The
[T-21 Legends entry](https://starwars.fandom.com/wiki/T-21_light_repeating_blaster/Legends)
describes squad-support use and power/overheating constraints; this prototype gives
it slow, capacity-limited automatic fire, not unlimited crew-served sustained fire.
Other class assignments are conservative gameplay inferences pending weapon-by-weapon
tuning. Canon and Legends portrayals are reference constraints, not one numerical spec.

## Statistics and authority boundary

`tools/combat/export_catalog.py` is a strict read-only exporter. The ignored
`runtime/assets/combat/catalog.json` records each Core3 Lua path, SHA-256 and checkout
revision. It rejects missing explicit fields rather than guessing template
inheritance. `attackSpeed`, speed modifiers and old DPS do not drive the simulation.
Only the bounded allowlist is supported. Commando's seven certified weapon
profiles now have dedicated cone, beam or rocket delivery; supported grenades
use the trap-style physical throw path. Shotgun pellets and other unsupported
weapons remain outside that allowlist. The Commando attacks do not use ordinary
blaster-bolt simulation for cones or beams.

`weapon_state.gd.configure(profile, owned_certificates, item_condition)` is the
consumer interface. A profile combines an authored class with the following
unmodified fields under `core3`:

- `damageType` (lowercase name), `minDamage`, `maxDamage`, `woundsRatio` (percent),
  `armorPiercing` (0–3), and `certificationsRequired` (all-of names).
- `pointBlankRange`, `idealRange`, `maxRange`, and the corresponding
  `pointBlankAccuracy`, `idealAccuracy`, `maxRangeAccuracy` values.
- Instance condition is separate: `maxCondition` and `conditionDamage`. The lab
  starts a clearly synthetic full-condition 1000-point instance and wears 0.05
  points per emitted shot. It survives stowing/reloading within that lab session;
  changing/reentering the session resets it. This is not persisted Core3 condition.

Core3's source range values are **accuracy modifiers**, not an existing damage
curve. Manual VR aiming removes the accuracy roll. This implementation explicitly
repurposes their piecewise interpolation as `max(0, 1 + modifier / 100)` damage
multiplier. It retains the three original points and values; this is a deliberate
VR adaptation, not a claim of unchanged Core3 semantics.

Per hit: uniform min/max damage roll × range multiplier × Core3 condition damage
multiplier × AP/rating multiplier × matching resistance. Core3 condition damage
reduction starts after 75% condition damage (`TangibleObject.idl`); the prototype
blocks completely broken weapons. The AP factor is `1.25^(AP-rating)` above the
armour tier, or `0.5^(rating-AP)` below it, following Core3 `CombatManager.cpp`.
Resistance is a percentage selected by damage type. A separate wound roll uses
`woundsRatio/100`; zero damage cannot wound. The local target accumulates hit,
damage and wound counters. Wound severity, body locations, death, armour wear,
server-side random rolls and reward transactions are not implemented.

Projectiles sweep each traveled segment against structures, terrain, authored
floors and training targets, clamp that segment to remaining range, and despawn
on the first hit or when range is exhausted. A grip-to-muzzle sweep prevents
spawning through a thin wall. The player body is excluded. There is no hitscan
fallback and armour piercing does not mean wall penetration.

A production adapter must supply **owned item instances**, actual crafted stats,
condition and actual granted certification names, then validate shots/hits on an
authoritative session and persist resulting RPG changes. Template defaults are
never labeled as a character's actual weapon inventory. No HTTP combat endpoint
or server-side patch is claimed by this change.

## Original media and rendering limits

`tools/combat/prepare_assets.py` reuses the existing local TRE/static-mesh decoders
without modifying them. It follows shared-template inheritance, selects the
original highest-detail mesh, retains its original texture pixels, obtains
`muzzle` from MESH/LOD hardpoints, and resolves the original
`datatables/weapon/weapon.iff` effect ID/index. For example, the supplied DL-44
actually maps to the DH-17 firing CEF; the importer respects that mapping.

The current export includes 28 weapons, 23 unique meshes, 27 CEF definitions,
13 PRT definitions and 27 sound definitions, with zero conversion failures.
Sounds are decoded into PCM WAV without lossy re-encoding, pitch substitution
or synthesised replacement sounds. Source hashes and archive names are recorded
for every dependency. All original and converted content stays in ignored
`runtime/assets/combat`; no replacement proprietary assets are downloaded.

Runtime combat presentation uses a separate native batched particle renderer.
It retains original user-provided textures, sampled source colors and proportions,
and additive/alpha material families. Emission, motion and lifetime are simplified
and bounded for VR. Legacy source-curve playback remains available only as an
explicit benchmark/reference mode. This is a visual adaptation, not a claim of
pixel-identical legacy playback. Missing original assets are not replaced by
unrelated textures.

Distance and view culling are evaluated from the gameplay eye, with a conservative
margin for stereo views. LOD limits apply to active effects as well as new bursts;
culled transient effects do not accumulate an emission backlog. Tracer presentation
is independent of authoritative projectile movement and collision. Dynamic flash
lights and camera shake are omitted. The tracking system retains control of the
head pose. Source audio remains separate from the visual batch budget.

### Enforced particle limits

`optimized_particles.gd` compiles 13 locally extracted programs into 23 compact
styles at startup. `SwgParticleBatch` performs particle updates and submits
MultiMesh buffers in C++; there are no per-particle meshes or per-projectile
visual nodes. All emitters sharing a World3D share one budget, including the HMD
and desktop mirror. Shader billboards use each eye's view; culling follows the HMD.

| Eye distance | Presentation |
| --- | --- |
| Up to 20 m | Main source layer and at most one secondary layer |
| 20–50 m | One-third burst density; smoke already culled at 20 m |
| 50–100 m | One primary impact particle; half the tracers; no muzzle or secondary layers |
| Beyond 100 m | No particle or tracer rendering |

These are hard maximum ranges. Source-specific shorter limits still apply.
Active particles moving into a stricter tier are thinned or retired immediately.
Frustum culling has a 15-degree angular guard and emitter-radius margin; particles
within 2 m bypass frustum rejection to protect nearby hand effects. The far limit
still applies. Offscreen transient bursts are discarded. Logical tracer handles
remain bounded and can become visible when they enter the view. The analytical
white-hot bolt core uses source emitter colors in the existing textured quad.

Hard ceilings are 2,048 transient particles, 512 logical tracers, 512 rendered
instances per style, and 48 styles/materials/batches. Burst admission and tracer
creation each have a separate 96-event frame budget. Culled bursts do not consume
the visible burst budget. Missing resources and invalid requests are rejected;
source caches are bounded. Counters report budget, distance, frustum and LOD
omissions. Visual limits never change collision, damage or projectile lifetime.
Audio stays in the separate spatial-audio system.

`tests/particle_lod_smoke.gd` checks the budgets, tier boundaries, active culling,
handle reuse, pause expiry and offscreen-storm admission. The style capture fixture
is `tests/particle_visual_capture.gd`. Run both with OpenXR disabled; the capture
also requires desktop Forward+ Vulkan. The rendering suite defaults to
`--effects optimized`; use `--effects source` for the legacy reference.

Format layouts were checked against SWG-Source client-tools revision
`949451032647e45e42c3aaef3f41b132c8af36e3` (ParticleEmitterDescription,
ParticleDescriptionQuad, ParticleTexture, ClientEffectTemplate, WaveForm and
ColorRamp). Research copies are ignored under `runtime/research/combat`.

## Weapon audio

Weapon feedback now uses the original CEF sound references and locally decoded SWG
samples through `audio/spatial_audio.gd`. The previous path created ordinary
Godot 3D players without a shared voice budget or binaural rendering. Steam Audio
is now the default for combat: CPU HRTF gives headphone direction cues that follow
the actual HMD, independent of the desktop spectator camera. Music and ambience
keep their existing Godot paths.

The integration adapts [FPSloppa's audio implementation](https://github.com/jebot-git/FPSloppa/tree/8fbf5c829d356226065868189c615b72c3bc1646/deathmatch/audio)
with the owner's permission. Local and fetched remote audio revisions matched.
`client/steam-audio.lock.json` pins the patched Godot Steam Audio 0.3.1 addon and
Steam Audio SDK 4.8.0 binaries, patches and license notices by SHA-256. The installer
accepts `--source-repo /path/to/FPSloppa` or retrieves the same pinned files from
GitHub. No FPSloppa game media is used. Only Linux x86-64 is installed/tested today.
The upstream [Godot integration](https://github.com/stechyo/godot-steam-audio)
is alpha; retaining a fallback and the FPSloppa source-lifetime, gain and shutdown
fixes is part of the integration decision.

There are at most 32 active voices, with lower-priority impacts retired first.
Original sample variants, pitch and source gain are preserved. Source distances
feed reference-distance attenuation without applying Godot's distance/pan twice.
The effects bus has a limiter; a shared, subtle reverb responds to nearby walls.
Ten-Hz obstruction probes use the view-independent combat collision service to
muffle occluded shots. Full Steam Audio geometry/reflection simulation is disabled
until its CPU cost and streamed-stage integration have been evaluated. Steam Audio
therefore improves spatial playback without claiming acoustically exact simulation
or identical output to the original game's mixer. Use `--spatial-audio=stereo` to
compare standard Godot playback; missing native classes select it automatically.

## Tracked posture and weapon alignment

Weapon translation comes from the controller grip pose and barrel orientation
from the runtime aim pose, with the XR Tools palm correction as a missing-aim
fallback. Avatar source hand hardpoints and fallback gloves consume this same
weapon pose. This avoids applying the controller correction twice. The reticle
lies on the resulting barrel axis.

Grounded headset height selects standing, crouched or prone motion with hysteresis.
Prone now selects the original prone/crawl clips and preserves their torso lean
and knee directions. Crouching moves the inferred pelvis rearward and bends knees
forward; floor constraints and blend resets prevent reversed knees at transitions.
Head, controller and physics-body poses remain tracking/gameplay driven. Without
body trackers this is inferred posture, not measured pelvis or leg movement.
`tracked_posture_smoke.gd` covers 20 source avatars, crouch/prone/crawl transitions,
knee direction, floor clearance, and unchanged tracked head and physics transforms.

## Verification

```sh
python3 tools/client/install_steam_audio.py
godot --headless --xr-mode off --audio-driver Dummy --path client --editor --import --quit
python3 tools/combat/export_catalog.py
python3 tools/combat/prepare_assets.py
python3 tools/combat/validate_assets.py
godot --headless --xr-mode off --audio-driver Dummy --path client \
  --script res://tests/ranged_combat_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client \
  --script res://tests/xr_combat_input_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client \
  --script res://tests/combat_posture_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client \
  --script res://tests/xr_imported_stair_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client \
  --script res://tests/xr_main_smoke.gd
godot --xr-mode off --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan --path client \
  --script res://tests/ranged_combat_capture.gd
```

`weapon_audio_smoke.gd` runs with `--headless --xr-mode off --audio-driver PulseAudio`.
It exercises a real, muted output mixer: binaural direction under head rotation,
near-source gain versus the Godot fallback, original CDEF sample identity,
occlusion, listener motion, the 32-voice cap and repeated native source teardown.
Its report is `runtime/evidence/weapon-audio-smoke.json`; this is not subjective
headset listening verification.

`runtime/evidence/ranged-combat-smoke.json` records firing rates at 60/90/120 Hz,
semi/burst/auto, capacity/reload, certificates, condition, damage spread, resistance,
AP, wounds, range, both holsters, two-hand support, loss of tracking, unchanged
head/body transforms, broad fixed-distance reticle, swept thin-target hits,
range expiry, muzzle obstruction and actual imported-stage collision.
`xr-combat-input-smoke.json` additionally checks actual XRController3D action reads
with mocked left-dominant trackers, focus gates, mode switching and pose loss,
source avatar and fallback-glove attachment/release, distinct grip/aim poses,
rotated XR origins, missing-aim fallback, offhand movement while latched,
physical posture classification and animated source-derived mounts. Its `--capture`
option produces `combat-cdef-avatar-grip.png` and `combat-source-stow-mounts.png`
using desktop Forward+ Vulkan; these are not live headset verification.
`combat-posture-smoke.json` covers independent posture/grip combinations,
positive/negative range curves, projectile expiry and immutable shot snapshots.
`combat-assets-validation.json` verifies source hashes, exact imported Core3 fields,
source texture pixel equality and audio decodes. `combat-original-dl44.png`,
`combat-original-e11.png` and `combat-original-muzzle-flash.png` are actual-stage
**desktop Vulkan captures**, not live-headset proof. Native movement and the pinned
XR Tools addon were not changed.

## Live population/combat follow-up — incomplete

The October 4 population request requires a persistent authenticated zone session.
The current adapter still disconnects after entry and the Godot population is
static ambient presentation. No live lairs, HAM damage or delayed NPC attacks are
claimed by the preparatory changes below.

Implemented preparation:

- `server/combat_protocol.py` decodes authoritative CREO3/6 HAM, maximum HAM,
  wounds, shock wounds, target/weapon IDs and posture, plus TANO condition for
  lairs. Life state follows Core3 posture, never a guessed zero-health rule.
  Attribute deltas reject missing/reordered counters and apply transactionally.
- `/enter.combat_snapshot` exposes the entry observation with `live:false`.
  Patch 0018 adds baseline 6 capture. Eight offline protocol tests pass, including
  an archived real baseline; this is not live combat testing.
- Source population dependency export resolves 61 Tatooine groups, 206 lair
  templates, 245 mobiles and 264 appearance alternatives. The Mos Eisley beginner
  group's 14 original appearances converted successfully, with no conversion
  failures. Original bytes and generated assets remain under ignored `runtime/`.
- Creature locomotion now follows each original graph's root standing selector
  (`loop_stand` rather than the humanoid `loop_standing`). The fastest authored
  gait supplies running, including the eopie's gallop. Explicit humanoid sideways,
  backward and crouched clips are restricted to the original humanoid LATs.
  Headless playback passes all 42 idle/walk/run checks across the 14 appearances;
  this validates asset loading and bone motion, not live AI or GPU rendering.
  Reproduce with `godot --headless --xr-mode off --path client --script
  res://tests/combat_population_assets_smoke.gd`.

Core3 already owns wilderness spawn definitions. Mos Eisley's city circle has
`NOSPAWNAREA`; its beginner and surrounding regions provide the wilderness
groups. Spawning local copies would not restore Core3 lair state, babies,
defenders, reinforcements, nest damage or respawn behavior.

Integration boundaries identified in the pinned source:

- Keep player movement synchronized in source world/cell coordinates while the
  authenticated zone session stays connected; consume create/destroy, transforms
  and ordered state deltas under a session epoch. Disconnection must disable
  combat and clear replicated targets.
- Resolve player weapon contacts against live object IDs. Core3 must validate
  ownership, certification, condition, cadence/recovery, range, line of sight and
  target eligibility; client-supplied damage/HAM/wound values are not authoritative.
- Retain Core3 `CombatManager::calculatePoolsToDamage`, `applyDamage`, wound and
  observer paths. Creature `inflictDamage` and PlayerManager destruction handlers
  own incapacitation, recovery, deathblows, death, loot/XP and persistence.
  In this revision three player incapacitations within the retained 600-second
  window kill the player; this is not a client timer to duplicate.
- NPC AI retains target selection, movement speeds, weapon choice and the combat
  queue. Separate attack launch from impact before the existing immediate damage
  path. Store immutable launch aim, range, weapon/command and an attack ID; sweep
  a finite projectile or resolve the delayed melee volume against current target
  positions. Only a validated impact enters damage once. Missing a shot must not
  re-aim toward the target or charge the queue/cost a second time.

Build/live-test blocker: the current managed sandbox denies Podman access with
`chmod /run/user/1000/libpod: read-only file system`; the local HTTP adapter is
also unreachable from this runtime. The patch stack reapplies cleanly, but patch
0018 has not been rebuilt into `core3client`. Persistent zone transport, live
mob/nest rendering, authoritative hit submission, NPC launch/impact separation,
and actual queue/AI/HAM/death tests remain required. Existing local training-target
damage remains explicitly local.

## Controlled approach simulation

`tools/server/simulate_combat_approach.py` runs the pinned FOLLOWING branch's
movement arithmetic on level, unobstructed ground with a direct path, a human
target, full-health upright mobs, and no evade/flee/posture/weapon changes. It
records source hashes and fails if key source expressions drift. Core3's
`SMAT`/`LSAT` server appearance handlers return null, so the selected actors'
`getTemplateRadius()` padding is zero; `collisionRadius` is a different field.
This is a Python numeric model, not execution of Core3 or the Godot client.

Six 60-second runs started 40 m apart, with standing, 1 m/s retreating, and 1 m/s
strafing players. Combat-distance bounds are sampled over the final 10 seconds:

| Mob / player motion | Source run speed | First arrival within preferred range | Combat distance |
| --- | ---: | ---: | ---: |
| Kreetle / standing | 7.25 m/s | 5.2 s | 3.06 m |
| Kreetle / retreating | 7.25 m/s | 5.6 s | 2.39–5.38 m |
| Kreetle / strafing | 7.25 m/s | 5.2 s | 2.45–5.35 m |
| CDEF-rifle marksman / standing | 6.00 m/s | 4.4 s | 13.60 m |
| CDEF-rifle marksman / retreating | 6.00 m/s | 5.2 s | 12.80–15.19 m |
| CDEF-rifle marksman / strafing | 6.00 m/s | 4.4 s | 12.77–15.16 m |

The kreetle's original intrinsic weapon has 5 m ideal/maximum range. The marksman's
chosen source CDEF rifle has 15 m ideal and 64 m maximum range, so all these rifle
runs begin inside attack range. Range eligibility does not imply a queued or
landed hit. Melee range eligibility during the final retreat window was 86.7%.

The source computes displacement budget from run speed before adjusting
`currentSpeed`, and clamps travel using a difference of squared distances.
The simulation intentionally preserves both behaviors: the latter permits a
full movement step inside preferred range. Approximately 400 ms movement updates
produce visible stop/catch-up cycles in raw server positions. These are candidates
for live validation, not evidence that Godot's rendered movement will have the
same visible stepping. Random ranged kneeling/prone/evasion and actual terrain
pathfinding can materially change the result and remain untested.

Evidence: `runtime/evidence/ai-approach/report.json`, six CSV traces, and
`runtime/evidence/ai-approach/approach.png`. Reproduce with
`python3 tools/server/simulate_combat_approach.py`.

## Profession translation and primed master abilities

`server/profession_protocol.py` translates owner-only CREO4 skill modifier totals
and CREO1 learned skills into a separate `profession` field on weapon snapshots.
Crafted item stats remain unchanged. The provisional coefficients live in
`server/combat/profession_balance.json`:

| Original class modifier | Frontend effect |
| --- | --- |
| Melee accuracy | Source metadata only; no player contact-radius bonus |
| Melee speed | +1% Stance recovery per point; shorter qualifying recovery travel |
| Ranged accuracy | Source metadata only; no player damage or hit-roll bonus |
| Ranged speed | +1% RoF and capacity recovery rate per point |

Source accuracy is reported for the equipped weapon's class but has no player
hit, damage or contact-radius effect. Speed translations remain independent.
The old widened-query geometry helper can still be exercised by explicit lab
fixtures; player weapon snapshots always emit zero accuracy-derived radius.
Existing unarmed STR/QUI/Teras Kasi damage/speed translation remains in place;
its speed modifier is not applied a second time.

Only two active frontend abilities are exposed, gated by actual basic mastery
and weapon certification. The pinned Core3 commands and original string tables
do not contain the requested names. The provisional naming/source mapping is:

| Frontend ability / weapon | Original command | Damage multiplier | SAC multipliers H/A/M |
| --- | --- | ---: | --- |
| Lethal Shot / ranged | overChargeShot2 | 3.75 | 1 / 1 / 1 |
| Melee Assault / one-handed | melee1hLunge2 | 3.0 | 0.625 / 0.625 / 1.5 |
| Melee Assault / two-handed | melee2hLunge2 | 1.0 | 1.5 / 0.625 / 0.625 |
| Melee Assault / polearm | polearmLunge2 | 2.0 | 0.625 / 1.5 / 0.625 |
| Melee Assault / unarmed | unarmedLunge2 | 3.0 | 1.5 / 1.5 / 1.5 |

The exporter reads these numbers from the pinned Lua commands and retains their
hashes. SAC uses actual item attack costs (template costs only in the explicit
lab), multiplied by the command costs and then Core3's current STR/QUI/FOC cost
adjustment: `max(0, base * (1 - (attribute - 300) / 1200))`. Each pool must exceed
the adjusted floating cost; spending truncates to integer damage as Core3 does.
Incomplete current-HAM observations disable priming. The added knockdown chance
is provisionally 25% on a damaging hit, independent of original lunge state
chance; actual NPC resistance/recovery and persistent knockdown remain Core3
integration work. Original special-command range and speed multipliers do not
override the new physical attack mechanics.

Base cooldown is 30 seconds. Progress in the equipped class reduces it linearly
to 15 seconds: four basic branch boxes, specialist novice, sixteen specialist
boxes and specialist master form 22 steps. Mastery of that specialist class is
full progression. General basic mastery alone invents no branch progress.
Master Pistoleer gives no rifle bonus without rifle progression. Cooldowns are
shared per ability across all weapons and both fists, start on attack launch,
and survive stowing, switching and stat refresh. Already-launched attacks retain
their captured modifiers even when equipment changes. A miss still spends SAC
and starts cooldown. Only the next attack receives the prime, including in auto
or burst mode. A primed attack with insufficient HAM cannot spend ammo or fire.

Click the dominant-hand stick to open/close the small holographic radial menu.
After a neutral stick sample, deflect the stick to select; selection closes the
menu. The chosen original SWG command icon appears above the weapon (or fist).
Right-controller A toggles priming and brightens the icon; X retains access to
the system menu with either dominant hand. The menu blocks attacks and captures
its stick until neutral after closing, preventing an accidental turn or move.
Tracking loss, focus/menu blocking and stowing clear the prime. Desktop debug:
F11 opens/closes, Up selects, F12 primes.

Reproduce the bounded synthetic profession lab with:

```sh
python3 tools/server/profession_smoke.py
python3 tools/combat/prepare_abilities.py
./run.sh --offline --desktop --combat-lab --combat-profession-lab
```

The launch wrapper prepares icons and the explicitly synthetic skill fixture.
No skills or items are granted to a real character. Original icon crops and
their source hashes stay in ignored `runtime/assets/combat/abilities/`.

Verification: 182 source/translation checks, 31 ability/cost/collision checks,
20 mocked XR input checks across both handedness settings, and existing ranged,
melee, posture, crafting and actual-stage entry harness regressions. All headless
Godot tests used `--xr-mode off`; reports are in
`runtime/evidence/professions/`. Desktop Vulkan UI capture could not initialize
X11 or Wayland in this managed session, so neither rendered UI nor live headset
appearance is validated. The reproducible capture harness is
`client/tests/profession_ui_capture.gd`.

## Wrist HAM, profession trees and cosmetic jump/recovery

The dominant weapon wrist now carries three small holographic H/A/M bars.
Their colored segments are current HAM divided by maximum HAM; gray right-hand
segments block wound capacity. Empty space between them represents ordinary
damage. Wound amounts appear beside the bars. Missing current/maximum/wound
observations display an unknown indicator instead of invented full health.
The readout shares the ability-cost prediction model across fists and weapons,
follows the rendered held grip after arm limits, and remains available with an
empty weapon hand. The entry decoder supplies all nine current/max/wound slots;
the display selects health/action/mind at indices 0/3/6.

The datapad Skills tab reads the supplied `skills.iff`, `skl_n.stf` and
`skl_d.stf`: 49 visible professions and 858 boxes. It retains recursive parent
relationships, prerequisite counts, exclusions, XP/credit/skill-point costs,
modifiers and certificates. Learned boxes come from the selected creature's
CREO1 skills, with missing replication explicitly shown as unknown. Training
is not implemented. The profession selector is embedded and scrollable inside
the wrist viewport; trigger selection opens the existing detached details panel.
One malformed original Commando modifier is recorded in the catalog warnings
and omitted from parsed modifiers rather than repaired by guessing.

Click the offhand stick for jump/recovery (Space in desktop inspection). The
weapon-hand stick remains reserved for abilities; desktop ability priming uses
F12 so P can remain prone. `SwgViewPosture` owns presentation timing and recovery
state, while the existing native/XR Tools locomotion retains collision and
gravity. Jump uses the original `all_b_loc_standing_jump_up.ans` root-Y curve:
3.1 seconds, about 0.516 m peak rise, including anticipation/landing movement.
It has no upward impulse and cannot lift the collision body over an obstacle.
The camera offset stops short of solid ceilings. Raw HMD/controller transforms
remain unchanged; the XR origin receives the cosmetic displacement while the
top-level physics body stays grounded.

Knockdown lowers the view smoothly toward 0.35 m above the body base and plays
the original face-up downed pose on untracked avatar joints. Combat and stick
movement are blocked while down. Jump emits a recovery request for standing or
kneeling based on physical head height; prone posture clears knockdown without
a button, and already-prone players reject knockdown. Presentation offsets are
removed before collision processing and excluded from physical posture
classification, preventing false prone recovery. Saved standing-height
calibration applies to recovery thresholds. Spawn reset clears view offsets and
movement locks. Incapacitation/death observations cannot be cleared with jump.

The current bridge supplies entry observations and then disconnects. Recovery
requests therefore use explicit local success prediction; the model also
supports pending/rejected recovery for a future authoritative transport. This
does not send Core3 posture commands, implement live incoming damage updates,
or bypass persistent incapacitation/death rules. `receive_combat_knockdown()`
is the frontend event hook, and `recovery_requested(posture, automatic)` is the
outbound hook. Continuous Core3 combat integration remains outstanding.

Prepare original local assets with `tools/assets/prepare_professions.py` and
`tools/combat/prepare_player_feedback.py`; the launcher prepares missing outputs.
Outputs stay under ignored `runtime/` with source hashes, including downed
animation clips for all 20 original player rigs.

Validation: `tests.test_player_feedback_protocol` (5 source/protocol tests),
`player_feedback_smoke.gd` (30 checks), `player_feedback_xr_smoke.gd` (21 checks),
and actual SubViewport trigger selection in `xr_datapad_smoke.gd` (45 checks).
The tracked posture sweep now includes original jump/downed/recovery poses
across all 20 body rigs (1,080 checks). Existing profession input/combat,
72,609 weapon/arm-limit checks, desktop posture clearance, and both desktop/XR
original ticket-hall stair movement tests pass. These Godot runs used
`--headless --xr-mode off` and the dummy renderer, not live headset or GPU
validation. The environment still blocks Podman at `/run/user/1000/libpod`
and cannot initialize the desktop X11/Wayland display for Vulkan capture.

Authority limitation: these are frontend translations and local attack
predictions. Entry and `/weapons` now include `player_combat` with observed
current HAM and an explicit `local_prediction_only` marker. This does not create
a persistent zone connection or mutate server HAM, NPC posture, skills or
cooldowns. Patch 0018/current baseline 6 is required to observe current pools;
without it ability priming fails closed. The earlier live-combat blocker remains.

## Physical accuracy in native sessions

Squad Leader's Volley Fire is an explicit exception to physical contact and
avoidance below: an owned native mark guarantees one in-range direct hit per
eligible party member. It preserves normal damage, armor, costs and separate
status resistance. See [Squad Leader support](ABILITY_ACTIVATION.md#squad-leader-support).

The final `0097` + `0098` policy bypasses only the innate player hit/miss roll.
Validated projectile and melee contacts proceed through normal dodge, block,
counter and applicable deflection. Player accuracy stats do not modify that
secondary contest; NPC and companion attacks keep native accuracy. CoB and
defensive progression remain effective. Active physical guard and moving clear
of range/trajectory provide additional defenses. Armour, damage variation and
status resistance remain separate.

Player skill accuracy no longer adds damage or widens melee contacts, including
cached profiles. Original grip/range and crouch/prone damage bonuses remain.
Aim cannot provide a player hit-chance buff; enemy accuracy penalties remain useful.

## Client projectile contacts and moving fire

Patch `0099-client-projectile-contact.patch` makes the client authoritative for
ranged projectile contact and Core3 authoritative for its outcome. The client
sweeps the actual rendered world, applies movement spread to the bolt, and sends
its contact against the registered shot. Core3 consumes that receipt once and
resolves target eligibility, damage, armour, normal dodge/block/counter/deflection,
status effects, threat and rewards. It does not re-test the target's later position
or current LOS/range against a contact observed earlier by the client. Receipt
ownership, age, reported trajectory/travel bounds and weapon identity still apply.
Server receipt-processing time no longer substitutes for reported flight age.
Existing melee/area target selection is unchanged by this projectile patch.

Launch captures `two_hands` and `firing_posture`. Long weapons retain 30% range
one-handed and full range two-handed; pistols retain full range one-handed and
110% two-handed. These scales apply to all three distance-curve points. Crouch
halves negative range-damage modifiers and prone removes them; positive modifiers
are unchanged. Core3 derives the multiplier from its captured weapon values and
reported contact distance, never a supplied damage number. Later grip/pose changes
cannot change an in-flight shot. Skill accuracy still adds no player damage.

Movement spread uses horizontal locomotion velocity and roomscale head movement;
vertical crouching, tracking loss and recenter jumps do not create extra spread.
The cone half-angle scales from zero above a 0.15 m/s dead zone to its cap at
5 m/s. Initial tunable caps are 0 degrees for pistols (including heavy pistols),
1.2 for carbines, 4 for rifles and other supported longarms, and 6 for heavy/repeater
classes. Uniform solid-angle sampling changes the actual emitted trajectory,
after target-marker aiming and before both registration and local flight.
Weapon/HMD/controller transforms remain untouched. Unsupported heavy projectile
types are not enabled by defining their movement penalty. This adds movement
spread, not a new recoil simulation.
