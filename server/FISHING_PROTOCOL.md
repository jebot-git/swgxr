# Gesture float fishing

Fishing uses original Core3 fishing poles, bait, water checks, rod quality,
vegetation/density, fishing states, seven-second events, mishaps and rewards.
`0048-gesture-fishing.patch` adds authenticated presentation commands through the
existing `/services/fishing_*` bridge. No client-created catches or local inventory.

## Controls

Take a fishing pole from inventory and keep gripping it. It uses its original
full-size appearance, with the source grip at the object origin and shaft aligned
to the runtime-neutral controller aim. Taking it equips the actual pole through
the existing native equipment transaction, including displacement/capacity rules.

The idle rod shows a filtered, paged grid of original 3D bait models and a
holographic bait cube. Grip a bait model with the free hand, drag it into the cube
and release. Releasing elsewhere or losing tracking cancels without a request.
The native pole receives the actual bait stack. Replacing bait returns the old
stack first, preserving freshness. Bait cannot be changed during an attempt.
Use the free-hand stick to page the bait tray; that stick is captured while open.

Hold the rod trigger, swing back then forward, and release to cast. A plain click
cannot cast. Hand motion determines heading and distance (2.1–10 m); looking around
or artificial locomotion cannot supply cast power. Core3 validates the water,
terrain, line of sight and original fishing state restrictions.

The original float bobs, nibbles and dips with the native state. Lift quickly or
tug sideways to request the corresponding original fishing action. Once hooked,
grip beside the rod's reel and circle the free hand to wind. The native server
consumes these actions on its clock. Holding still never reels automatically in
VR. Fish jumps are not imported. A caught fish or original junk reward remains in
the owner-only native fishing marker until a trigger click collects it; inventory
capacity applies. Releasing/stowing the rod cancels fishing without resetting bait.

## Timeout and authority

The original freshness rules remain unchanged: `fishingProceed` has its original
5-in-101 chance per applicable event to increase freshness damage. Freshness 6 is
Soggy; before a catch, values above 6 retain the original `random(15) < freshness`
chance to toss the bait and end fishing. This is a probabilistic timeout, not an
invented fixed deadline. `loseBait` retains native stack decrement/reset behavior.
Waiting without gestures or status polling does not pause the server clock.

Actions: `status`, `open`, `bait`, `cast`, `action`, `stop`, `stow`, `collect`, all
prefixed `fishing_`. Each takes the owned `rod_id`; mutations require a stable
`request_id`. Bait takes `bait_id`, cast takes source `cast_position`, and gesture
input takes `session_id` for that cast plus `gesture` 1=up, 2=right, 3=left, 4=reel.
The live transport identity remains separate as `live_session_id`. A bounded
native receipt ledger makes exact mutation replay idempotent. The client does not
queue late gestures, automatically retry a mutation, or set freshness/quality/loot.

The original desktop fishing path is unchanged. Native VR reeling schedules its
next event with no implicit action, and reaching landing distance retains the
session until native success, instead of cancelling it before reward generation.
Original player death/combat/movement observers still end invalid sessions.

## Reuse and validation

Inspected `/home/blux/raifslop`, origin `https://github.com/jebot-git/raifslop`, commit
`a2912dfdd254fc9dc5cdeac497d83e58cad4d7c0`. `cast_motion.gd` and `reel_tracker.gd`
are adapted directly; tracking rejection and rod-pull thresholds derive from
`cast_pose_sampler.gd` and `fight_input.gd`. No raifslop art, species, catch economy,
fish jumps or indefinite fishing-session rules are imported. Source hashes are
recorded in `runtime/evidence/fishing.json`; original SWG asset provenance is in
`runtime/assets/inventory/catalog.json`. The launcher prepares missing rod, float
and four original bait appearances without granting any items.

Tests cover casts at 72/90/120 Hz, no-motion inputs, cranking, tracking loss,
discontinuities, bait drag cancellation, request identity, ownership response
checks, original model scale, inventory/crafting/pet regressions and patch replay.
A C++ harness compiles the actual native `continueFishing`/`fishingProceed` bodies
with deterministic test doubles to check soggy-bait termination, idle scheduling,
VR reel gating, legacy automatic retrieval and catch completion. This is not a
full Core3 build or a running-server test.

Full native compilation/deployment remains blocked by Podman's read-only
`/run/user/1000/libpod` configuration and missing host Lua/Berkeley DB headers.
A desktop Forward+ Vulkan capture was attempted but neither X11 nor Wayland was
accessible. Headless tests use `--xr-mode off` and the dummy renderer. No GPU,
live VR, end-to-end server fishing or deployment success is claimed. No planets
or new fishing water were deployed; live-test Tatooine scope is unchanged.
