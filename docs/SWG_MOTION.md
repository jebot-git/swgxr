# Native NPC movement and physical contacts

Implemented 2026-10-10. The client follows Core3's native movement endpoints rather
than buffering positions from full RPG snapshots. Core3's
`AiAgentImplementation::broadcastNextPositionUpdate` sends the **next step**, not
necessarily the AI's current simulated position. Discarding these packets was
adding a complete snapshot delivery cycle to NPC presentation.

The approach follows the maintained original-derived
[SWG RemoteCreatureController](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGame/src/shared/controller/RemoteCreatureController.cpp#L361-L557):
per-frame pursuit of the latest goal, slower movement near the goal, acceleration
and deceleration, bounded catch-up, and relocation for large errors. This is an
adaptation for SWGXR, not a claim of exact retail behavior. No extra interpolation
buffer or extrapolation beyond the native endpoint is used. The controller moves
only replicated actor bodies; it never drives the local player's tracked head,
hands or physics body.

## Transport contract

Patch `0135-native-motion-stream.patch` decodes the existing `0x1B24F808` and
`0xC867AB5A` messages in `core3client`, including quarter/eighth-unit coordinates,
parent cell, movement counter, speed and direction. A mutex-protected bounded
cache publishes atomic `motion.json` files every 25 ms, independently of full
native request/reply waits. Destroyed objects are removed, scene changes reset
the cache, counters reject duplicates/reordering and support 32-bit wrap. There
are at most 512 cached entries, retained for three seconds.

`/session/sync` returns an optional `motion` envelope with `source_kind:
core3_motion_v1`, a scene epoch, and visible actor goals. The owned native process,
character, zone, baseline visibility, cell and counter must match. Entries older
than two seconds and files older than 500 ms are ignored. Ground-cell endpoints
are transformed through the baseline's native parent yaw and local/world anchor.
Space ship movement uses its existing dedicated controller.

The envelope only supplies `id`, `cell_id`, `position`, `heading_radians`,
`movement_speed`, `movement_counter`, `sequence` and `age_ms`. It does not update
health, abilities, world membership, RPG snapshot age or native session lifetime.
The local adapter keeps HTTP/1.1 connections open with TCP_NODELAY; idle sockets
time out after 15 seconds and malformed bodies close the connection. The client
spaces sync dispatches using wall-clock time so render stalls cannot cause bursts.
Unsent same-room heartbeats refresh their pose/revision after queued services;
shots, economic actions and transport acknowledgements retain their original
authority and destination.

Full baselines now include movement counter, speed limits and local/cell transform
metadata. Older servers continue through the snapshot goal-pursuit fallback.

A same-counter full snapshot must not replace a next-step goal with the older
server-body position. Newer baselines can update the goal; every baseline can
update health. Death/incapacitation stops movement. Cell transitions reset the
presentation history and reject prior-cell endpoints. Packet loss settles at the
last endpoint; baseline snapshots remain a fallback.

## Hit consistency

The visible actor and its StaticBody collision geometry share one transform.
Projectile contact keeps the identity and world-space contact point from that
presented body. Ordinary projectiles already used client contact authority.
Scatter/lightning now follow that contract too: they no longer re-test the contact
against the target's later server-body sphere. Their existing flight direction,
range, elapsed-time, pellet uniqueness, target binding and native LOS checks remain.
Core3 still owns shot receipts, costs, target eligibility, damage, mitigation,
health and death. No new client damage or health fields are accepted.

## Validation and deployment

Run `tests.test_native_motion`, `tests.test_native_motion_stream`,
`tests.test_multiplayer_sync` and `tests.test_bounty_combat_native` with unittest.
Run `client/tests/npc_motion_smoke.gd` using Godot with `--headless --xr-mode off`.
The latter checks jitter/loss, late and equal-counter baselines, cell/death fences,
and actual physics-ray contact at the displayed transform. Native combat tests
include delayed scatter and lightning contacts after the target has moved.

`client/tests/live_ai_latency_suite.gd` records native goals and displayed motion
in the full production scene against an explicitly selected diagnostic account.
Evidence for this change is under ignored `runtime/evidence/swg-motion-20261010`.
Headless evidence uses the dummy renderer and does not validate headset/GPU output.

Deploy the Core3 server, native bridge, Python adapter and client together for the
full movement stream. A bridge/client update alone cannot provide the new baseline
metadata. The patch was deployed to the authorized test VPS on 2026-10-11, preserving
accounts and the 05:00 UTC restart. Native binary/module hashes and real backend
readiness were verified. The user's VR client was not launched.

The final local 60-second run recorded 2,899 frames, 14 moving actors and 460
movement goals newer than the latest received RPG snapshot, with no failed
requests. Sync requests measured 39 ms median / 77 ms p95; full native updates
measured 279 ms median. The conservative bridge-receipt-to-client age estimate
was 148 ms median / 186 ms p95, so these results do **not** establish sub-100 ms
simulation-to-display latency. See `findings.json` and `final-analytics.json` in
the evidence directory for bounds, intermediate failures and exact results.
