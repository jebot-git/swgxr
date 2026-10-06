# Scout prototype

`POST /scout/{status,forage,trap,camp,disband,mask_scent,discard_mask_scent,burst_run,holster,return_tool}` uses an authenticated owned Core3 character. Requests carry source X/Y-up/Z position, optional tracked posture, and a bounded unique `request_id` for mutations. Trap/camp/belt actions require an owned item ID; trap and disband also require their native target/terminal IDs. The adapter uses the existing persistent zone session when combat is live, avoiding a second login.

Patch `0025-scout.patch` calls the pinned native commands/components. Core3 owns skills, eligibility, costs, effects, trap uses and delay, camp restrictions/visitors/healing/XP, foraging rolls and area reuse rules. The bounded persistent receipt ledger prevents duplicate mutation requests from consuming resources twice. No local inventory, buff or camp grants are made. Character position is trusted from this loopback prototype, as in gathering/crafting; this is not a public-server anticheat protocol.

Client controls:

- Pump both arms in alternating running strokes to request Burst Run. Six alternating half-strokes require travel and cadence; ordinary locomotion alone is removed from the gesture. The source buff lasts 30 seconds, with the original recovery and scout-adjusted HAM costs. The confirmed native speed multiplier (1.822) applies only to virtual controller movement. Tracking and gravity are unchanged; stale snapshots stop applying the boost.
- Dig with both hands at the streamed terrain surface to forage. Three short strokes trigger one request, latched until the hands leave the ground. Core3 retains the 8.5-second task and standard area limits/reuse timing.
- Grip a trap from inventory or the tool hip slot, make a throw motion, then release. The first eligible creature along the reticle is selected using its original rendered bounds (or original server appearance bounds), with world obstruction checked. An equipped ranged weapon supplies controller aim; otherwise the stabilized head/melee reticle is used. Core3 rechecks the target, range, LOS, skill, uses and cooldown. The original item model follows a presentation arc while the native trap task resolves.
- Trigger a held camp kit to deploy. Approach its original terminal for a holographic owner/time/visitor/abandonment readout and owner-only Disband button. All six original camp CDF layouts supply tents and furnishings; nearby native child objects and campfires use their source templates.
- Select Mask Scent from the empty-hand abilities menu; A activates it. Menus remain attached to the controller during locomotion.

Combat, entertainment and Scout share one ability selection. Replacing an unprimed selection has no cost or cooldown. Replacing a primed selection starts its recovery without firing it or charging attack SAC. Armed Mask Scent cancellation also records its duration-based cooldown in Core3. Source performances with no recovery duration continue to have zero recovery.

The native `SwgScoutLocomotion` GDExtension computes movement modifiers; GDScript connects it to the pinned XR Tools provider chain. Terrain negotiation reduces the frontend's provisional uphill slowdown (up to 50% at a 45-degree uphill slope). Core3's native normalized slope modifier removes that penalty proportionally. Flat/downhill speed is unchanged. Harvesting continues through the existing native corpse-harvesting implementation with `creature_harvesting`; Scout introduces no replacement reward calculation.

Asset preparation: `python tools/scout/prepare_assets.py`. Converted media, source hashes and unsupported conversions stay in ignored `runtime/assets`. Camp CHL2 parsing is bounded to the supplied six layouts; unknown nonzero fields fail export rather than producing guessed geometry.

Validation commands:

```sh
python -m unittest tests.test_scout_protocol
python tools/scout/fixture.py
python tools/scout/smoke.py
python tools/scout/live_smoke.py
python tools/scout/fixture.py --restore
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/scout_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/xr_starport_exit_smoke.gd
godot --xr-mode off --rendering-method forward_plus --rendering-driver vulkan --path client --script res://tests/scout_camp_capture.gd
```

The fixture only grants to its named disposable test account. The capture is desktop Vulkan with mocked tracking, not live headset validation. Gesture thresholds and comfort still need headset testing.


## Bio-engineer DNA sampling

Patch `0045-bioengineer-sampling.patch` extends the same authenticated outdoor
profession transport with `/scout/sample_dna` and `/scout/discard_sample_dna`.
Sampling requests contain the native `target_id`, source-coordinate
`hand_position`, player position and mutation `request_id`. Python rejects
nonfinite poses, invalid identities and hands farther than 3.5 m from the player.
Core3 independently checks the hand against original appearance bounds, same
zone/cell, visibility and the original creature/skill requirements. The existing
receipt ledger handles identical request replay. Position/tracking claims remain
trusted prototype input, as with the other VR interactions.

The native snapshot exposes `sample_dna_available`, `sample_dna_pending`,
`sample_dna_cooldown`, `sample_dna_recovery`, and per-target `dna_eligible`.
Eligibility comes from Bio-Engineer Novice and native command/creature rules.
These fields do not grant a profession or a DNA sample. The bridge calls the
original `SampleDNACommand`, verifies that its pending task started, and leaves
Mind expenditure, timing, success/quality rolls, XP, sample creation and possible
creature aggression/death to `SampleDnaTask`. Its ordinary approximately
11-second sequence also supplies the initial ability recovery and primed-selection
discard cooldown. It does not replace the native task with a timer reward.

Select **Sample DNA** in the dominant-hand ability wheel, with a weapon or empty
hands, then press **A** to prime it. Move either available hand over a visible,
eligible creature and click that hand's trigger. Contact uses the current
rendered creature bounds with an 18 cm margin and a world-obstruction check;
aiming the reticle at a distant creature is insufficient. A valid request consumes
the prime. Neither hand needs to stay held on the creature once the original
sampling task has started. Routine HAM updates preserve the contact prime;
tracking loss disarms it. The selected icon uses the original `sampledna` art.

The sampling trigger remains reserved until released, preventing a shot or
punch from the same click. Held triggers, tracking reacquisition, busy requests,
stale eligibility and occupied offhands cannot cause deferred sampling. Replacing
a primed ability uses the existing shared selection/cooldown rules. No client HAM
or inventory reward is fabricated. Inventory polling reflects the native result.

Validation: `tests.test_bioengineer_sampling`, `tests.test_scout_protocol`,
`bioengineer_sampling_smoke.gd`, `scout_smoke.gd`,
`profession_combat_smoke.gd` and `profession_xr_input_smoke.gd` pass with
`--headless --xr-mode off` (dummy renderer, mocked tracking/backend). The new
Core3 patch replays against all predecessors. Original icon provenance is in
`runtime/combat/abilities/catalog.json`; results and exact limits are recorded in
`runtime/evidence/bioengineer-sampling.json`.

Not deployed or validated in a live headset. Full native compilation and actual
sampling/reward checks remain blocked by Podman access to read-only
`/run/user/1000/libpod`; the host lacks Lua/Berkeley DB development headers.
The broader HTTP-based `live_main_smoke.gd` also cannot bind a loopback socket in
this sandbox; its isolated HAM checks can run without that transport fixture.

Bio-Engineer training, genetic crafting and crafted creature-deed activation are
covered in [CRAFTING_PROTOCOL.md](CRAFTING_PROTOCOL.md#bio-engineer).

## Ranger kit use, rescue and area tracking

Patch `0053-ranger.patch` adds `/scout/ranger_status`, `/scout/conceal`,
`/scout/rescue` and `/scout/area_track`. These actions require an owned retained
native gameplay session. They use source position, zone and building/cell context;
Ranger status, kit application and rescue support interiors, while original area
tracking is outdoors only. Each mutation has a stable `request_id`. Changing
tracked pose, hand or posture during a retry does not repeat the mutation; changing
its item, target or tracking type with that key is rejected.

- `conceal` takes the exact owned `item_id`; omit `target_id` for self. Applying to
  another player requires `target_id` and finite source `hand_position`, physical
  reach, original body touch, same cell/zone and LOS. Kits are exposed with
  `tool_kind: "camouflage"`. Only the selected kit loses one actual native charge.
  Original planet restriction, nearby hostile check, scent-mask exclusion and
  cooldown remain authoritative. Already-concealed targets are rejected without
  toggling protection off or consuming a charge.
- `rescue` takes the enemy NPC/creature `target_id`, not the endangered groupmate.
  Original learned ability, group membership, enemy defender and native taunt
  probability apply. This gesture prototype additionally bounds targeting to 32 m
  with same cell/zone and LOS. `mutation.rescued` distinguishes actual native
  taunt/highest-threat success from an accepted failed roll.
- `area_track` takes an unlocked `track_type` (`animal`, `npc` or `player`). The
  original command, selection callback and six-second `AreaTrackTask` perform the
  scan. Movement beyond 1 m or combat interrupts it. `state.ranger.tracking` reports
  pending/succeeded/failed and bounded original results: names, plus direction and
  integer distance only when the corresponding original skills permit them.
  Exact object positions/IDs are not disclosed by tracking. `total_results` counts
  original qualifying results; `truncated` indicates that only the first 256 are
  returned, preserving original order and skill gates.

`state.ranger` also provides current camouflage/rescue modifiers, available
commands and tracking types, active conceal power/duration/planet, owned kit uses,
and bounded nearby handover/rescue candidates. The original 18 Ranger trainer
boxes are included in the source trainer catalogue.

The all-profession kit requirement deliberately changes the original zero-skill
case: buff power is `max(5, caster camouflage / 2)` and duration is 40 times that
power, giving an untrained user 200 seconds. Existing Ranger scaling is preserved.
Native AI still adds half the recipient's own camouflage; an untrained recipient
of a Ranger's kit therefore has less protection than that Ranger. Conceal remains
probabilistic against hostile NPCs/creatures and retains original droid/pet
exceptions. It is not invisibility or a PvP targeting restriction.

The native AI detection cache now validates the active buff and its planet before
using a successful result and keys that result to the buff's application time.
Expiry/reapplication cannot reuse a prior cast's decision. Deferred camouflage
success/failure tasks also verify that they still refer to the original buff
before changing it or awarding XP.

`tools/server/ranger_smoke.py` uses fresh `invtestranger` fixtures. Source kits,
advanced prerequisite skills and isolated source NPCs are labelled administrator
setup, not earned progression. The trusted screenplay-only `setBuffDuration(crc,
duration)` binding delegates to the original Buff renewal/event operation for
accelerated expiry regression. The similarly bounded trusted `setUseCount` binding
initializes diagnostic kit charges because uncrafted source templates start at
zero uses. Neither exposes a player/HTTP administration route.

A retained ConcealBuff from another planet is reported inactive. Using a valid
kit on the current planet replaces that stale buff only after ownership, kit
planet, target reach/LOS, command state, cooldown and hostile-proximity checks
pass. An active same-planet buff is retained and rejects another kit without
consuming it. The original zone component only clears the MASKSCENT state, so
this replacement avoids trapping the kit-only interface behind a foreign buff.

Native validation uses a controlled original awareness prospect: trusted
`setWatchObject` selects the isolated test player; original range, LOS, camouflage
and aggro behavior decide whether to attack. The comparison verifies acquisition
before protection, concealment during protection and acquisition after original
buff expiration. It does not claim autonomous random prospect selection. The
queued CamoTask replacement guard is source-reviewed; a deterministic concurrent
stale-task race was not exercised by the native fixture.

The final native evidence is `runtime/evidence/ranger-native.json`: 50 checks,
including natural 200-second untrained expiry, controlled native AI acquisition,
actual Rescue threat transfer and asynchronous skill-gated tracking.
`tools/server/ranger_zone_smoke.py` appends cross-zone stale-buff replacement,
final-charge object destruction, receipt replay and exact truncation-count checks
to an already passing full fixture report. Its zone changes and one-charge setup
are explicitly administrator prerequisites, not shuttle-travel validation.
