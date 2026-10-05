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
