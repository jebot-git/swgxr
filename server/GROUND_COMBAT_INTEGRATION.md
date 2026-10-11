# Mos Eisley ground PvE integration package

This package implements the first bounded integration stage. It does not enable
the final global Core3-to-CoreCU transition. PvP, pets and JtL are excluded.
The sustained multiplayer/capacity and live-headset suite is explicitly deferred.
Build, policy, protocol, script and geometry checks are separate from that suite.

## Activation and rollback

Install the code overlay over the current matching server/client checkout or
distribution. Preserve existing realm data, media and configuration. Apply the
separate private animation delta using `tools/client/install_ground_actions.py`
first with `--check`, then without it. It verifies hashes and matching skeletons,
adds animation-library entries and copies the new clips/catalog; it never
replaces body geometry. Do not publish the private original-animation archive.
For new asset preparations run `tools/assets/prepare_ground_actions.py` after
normal population export; original supplied TREs remain required.
The launcher now includes this step. Reviewed profile metadata is pinned in
`tools/assets/ground_action_profiles.json`; each locally generated profile must
match it. Optional prepared NPC sets do not change the negotiated revision.
The release includes metadata and conversion code, never original clips.

In the native CoreCU process environment set `SWGXR_GROUND_ACTIONS=mos_eisley`.
The native catalogue defaults to `/workspace/runtime/assets/combat_actions/catalog.json`;
set `SWGXR_GROUND_ACTION_CATALOG` for another installation layout. The local
start script passes the activation variable through Podman. Remote systemd
activation must pass it through `podman exec --env` to the native child, as with
the existing prototype override. This package does not change running services.
Disable that variable to roll back selection to ordinary native AI. Restart
only after graceful native shutdown/save; preserve the existing daily restart.

Both native home/spawn position and current mob position must be inside a
1,500 m circle centered at source X/Z `(3528, -4804)` on Tatooine. Following a
player into this circle does not convert a mob spawned elsewhere. No global
activation value exists in this build. Ordinary spawned mobs are used; no
three-mob fixture, test account authorization or encounter owner is required.

## Attack integration

Native AI retains target selection, threat, pursuit, pathfinding, abilities,
loot, XP, deaths and respawning. Only reviewed `attack`/`defaultattack` execution
is intercepted. Area/cone specials, Force actions, unsupported weapon/animation
profiles and other command-specific abilities retain their native command path.
This avoids bypassing special-command validation or replacing their effects.
Conversion of those abilities requires explicit profiles during the later family
rollout. Native special cooldown bookkeeping remains in the existing AI.

At most one committed attack per mob is held through preparation, original clip
playback and recovery. Movement pauses while committed. Threat-target changes
before commitment cancel preparation; after commitment the aim stays fixed.
Death, stun, knockdown, peace/leashing, weapon changes, cell changes and movement
of the planted body cancel the strike. Target departure does not delete mobs or
an entire party encounter. Subsequent native AI selection can choose another
target. The longer of the action timeline and native weapon/command speed gates
release. Damage is not increased to compensate for slower attack frequency.

Profiles are generated from original rig-bound clips and retain source hashes,
archive names and conversion errors. Humanoid weapon classes and supported
creature rigs have separate profiles. Overlong/ambiguous/unavailable clips stay
on ordinary combat; skipped profiles are recorded. Melee contact timing remains
provisional until the later pose-inspection suite; authored ranged firing markers
are used where present. Supported ranged lanes select the nearest reported contact
once; these are committed line attacks, not a new ballistic projectile simulator.

Protocol and astromech droids use their authored `attack_light_standing` mapping
for basic unarmed attacks. Their humanoid double-jab alias selects heavy clips
lasting 4.33/5.50 seconds and caused 14 omissions in the first preparation pass.
The light clips retain their full 2.87/2.33-second duration and original speed;
no decoder changes, truncation or duration-limit relaxation are involved.

Attack costs are committed once at delivery. Per-victim native outcomes suppress
repeated costs and automatic secondary area expansion only for that exact NPC.
Native armor, secondary defenses and RPG effects remain in CombatManager. The
scoped override cannot apply to another attacker or a player counterattack.

## Transport and client behavior

Protocol 2 negotiates an exact generated catalogue revision. Unsupported clients
retain ordinary mob combat. The server keeps expiring native-session capabilities;
clients cannot set damage, another player's victim ID or global activation.
Eligible nearby players in the same zone/cell are snapshotted per attack, without
explicit encounter enrollment. Pets/NPC-vs-NPC keep their existing native path.

Preparation/final state is published repeatedly and recoverable in native batch
replies. Monotonic attack state revisions supersede per-client transport cache
sequence numbers. Up to 32 acknowledgements/receipts share one existing owned
native transaction, preserving the account command budget. Client contact batches
receive priority behind an in-flight operation. The native client's action-reply
wait is bounded to 10 ms to limit missed-notification stalls; this is not a claim
that the measured remote latency target has already been met.

Four timestamps estimate server-clock offset while excluding native processing
time. The lowest-delay estimate anchors each new attack; existing countdowns do
not jump when another clock sample arrives. A client acknowledges final aim only
when its world is ready, XR focus is valid and the actor's original animation is
available. It first acknowledges the warning; the server must receive that at
least 100 ms before aim lock (600 ms before delivery for these profiles). Final
aim acknowledgement must arrive before delivery minus 50 ms. A missing/late acknowledgement or missing valid contact coverage waives
that victim's hit and records an outcome; it never produces an unseen fallback
hit. This deliberately replaces the old fixture's native fallback policy.

A contact includes a bounded sample position and coverage interval. Native active
window LOS, current session/zone/cell, proximity, revision and geometry checks
bound accepted hits. Exact duplicate reports are idempotent; contradictory ones
cannot replace an accepted result. This remains client-authoritative contact:
a modified client reporting dishonest misses is not solved by identity checks.
Waived and reported outcomes are exposed in bounded native batch diagnostics.

Telegraph geometry remains a horizontal footprint. Its subdivided vertices sample
the outdoor native heightmap for drawing, without changing range or countdown.
Interior vertices use floor collision in the active cell. The full outline stays
visible while area fills to delivery. Original animation/audio timing remains
separate from native damage confirmation. No player tracking node is animated.

## CL tracking and presentation feedback (2026-10-11)

The server scales preparation steering by `min(3, 0.5 + (max(1, CL)-1)/60)`.
CL 1/31/91/151 therefore permits at most 6/12/24/36 degrees per second and
1/2/4/6 metres per second of lateral target correction. Both limits apply;
the stricter one wins. The 100 ms steering tick cap, warning acknowledgements,
final 500 ms aim lock and native target/aggro selection remain unchanged.
This is initial tuning for group testing, not validated tank/healer balance.

Protocol 2 events additionally expose `enemy_cl`, `tracking_degrees_per_second`,
`tracking_metres_per_second` and `weapon_template`. These are server-derived
presentation/diagnostic fields, not new client authority. Existing clients ignore
them. The template identifies the strike's captured native weapon; native weapon
changes still cancel the strike. Pistol/rifle/carbine profiles remain ranged.

The client shows the existing SWG target-aim icon for the selected victim (amber
during correction, white after lock) and the animal-attack icon in red for any
eligible player inside the lane. The old overhead warning text is removed.
Native weapon snapshots and strike events replace stale source-placement guns,
including hiding a gun when the native AI changes to unarmed combat. Original
instruments and other decorative attachments are preserved. Unprepared original
weapon art is reported explicitly, without a substitute gun.

## Evidence and deferred acceptance

Focused evidence is under `runtime/action-prototype/ground-*.log`; native build
receipts and package hashes identify the compiled sources. No new live remote,
capacity or headset result is implied by these checks. Later tests must cover
normal spawned mobs, ability preservation, loot/death/respawn, crowd warnings,
interiors/slopes, reliable lock delivery, sustained load and original contact poses.
Only favorable results authorize the subsequent global per-family transition.
