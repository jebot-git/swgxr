# Prototype voice relay

The client uses pinned upstream TwoVoIP (the voice stack used by FPSlop) for microphone/playback and Opus; FPSlop-authored game code is not copied. The separate Python relay forwards opaque encoded frames and never decodes, saves or logs voice content. Remote transport is TLS WebSocket on port18444. No dependency beyond Python's standard library is required.

`python3 server/voice_relay.py --config <gateway-config> --bind 0.0.0.0 --port 18444`

Configuration shares `certificate`, `private_key`, `accounts`, `auth_database` with the HTTPS gateway and adds `voice_secret` (path to at least32 random raw bytes) and `voice_state` (native cache JSON path). The adapter receives matching `SWGXR_VOICE_SECRET` and `SWGXR_VOICE_STATE` environment variables. The relay must be able to read these files and SQLite WAL/SHM. Its SQLite opens are read-only. Native state is atomically published mode0640; a root adapter/blux relay deployment needs an appropriately shared setgid directory. Never expose the private adapter or cache files over HTTP.

Local explicit debug uses `--loopback-debug --bind 127.0.0.1 --port 18084`, accepts unencrypted WS only on loopback, and accepts only locally signed debug tickets. Remote mode rejects those tickets. Default local adapter paths are `runtime/server/voice.secret` and `voice-state.json`; the local secret is created once, never overwritten. Explicit environment secret paths must already exist.

## Control plane

Authenticated `POST /voice/session` accepts `character_id`, optional existing native `session_id`, and the ordinary service position/building/cell fields. Identity is resolved through owned native Core3 state. Its response contains `backend:core3`, `ticket`, `expires_in:30`, `relay_port`, `protocol:swgxr-voice-v1`, `channel:proximity`, granted `channels`, `reasons`, `needs_presence` and `presence_interval:5`, and native `scope`, `zone`, `ship_id`. Scope is `planet` on the ground and `sector` in space; ground `ship_id` is `"0"`. HTTPS overrides the local debug ticket with a session-bound ticket and remote port18444; direct loopback replies use18084. Clients derive the relay host from their configured API host, using the same trusted TLS certificate.

Tickets are HMAC authenticated, one-use and expire after30seconds. They bind account, character, native session, gateway credential hash and auth expiry. Session tokens/passwords never enter relay messages. The relay rechecks logout/expiry/legacy claim status against the auth store at100ms cadence; storage failures close voice. Native session stop removes the published route; the relay closes it on the next state refresh (100 ms cadence). Queued audio is rechecked against fresh state and cannot survive expiry, hull changes or observed credential revocation.

Live native sessions publish identity, position, zone object ID, group ID, actual Rebel/Imperial enrollment, channel scope, hull identity and ground building identity with each existing native snapshot, with a4second freshness limit. Ship heartbeats publish the actual current hull for both owners and guests; fighter cockpit coordinates and POB interior coordinates remain ship-local. A voice request on a live ship reads this native cache and never invokes a ground service refresh or ground recovery. Missing or inconsistent space scope/hull data removes the route. Requests carrying an expired live session ID, or explicit space context without an active native session, are rejected before the legacy ground fallback; voice cannot trigger a ground login/recovery after a ship session disappears. Normal worlds reuse every existing native service observation. If none arrives, `POST /voice/presence` performs a source service refresh at most once per account per5seconds. Normal metadata expires after15seconds. Calls are serialized by the adapter; clients must keep a single request outstanding and suppress redundant heartbeat when a recent service observation exists. This normal-world fallback still performs original one-shot native login on uncached refresh: it is a prototype control-plane cost, not an MMO-scale presence solution. No audio packet initiates a login or native RPC.

## WebSocket `/voice`

First text frame: `{ "type":"hello", "ticket":"..." }`. Server `hello` and subsequent `tuned` messages contain `epoch` (uint32), `channel`, `granted_channels`, `reasons`, `scope`, `zone` and `ship_id`. Tune with `{ "type":"tune", "channel":"proximity|group|planet|sector|faction" }`. Unsupported membership falls back to proximity. Tuning or native membership/zone/hull/building changes increments epoch and invalidates queued audio. The area channel changes automatically between Planet and Sector on ground/space transitions; these remain distinct grants. Already in-flight packets using the immediately previous epoch are silently dropped for 500 ms after a native change, never delivered; other replay/obsolete epoch cases remain rejected. `roster` text messages provide visible peers `{id,name}`.

Client binary: little-endian uint32 epoch, uint32 increasing sequence, then1–400bytes of raw mono Opus (no TwoVoIP framing prefix). Each packet represents20ms at the client's48kHz configuration; relay verifies mono Opus TOC duration without decoding. Server binary: little-endian uint32 receiver epoch, uint32 listener-local per-speaker delivery sequence, uint64 source character ID, float32 source x/y/z, then unchanged raw Opus. Delivery sequences stay monotonic across speaker tuning/reconnects and reset only when the listener's epoch changes. Coordinates are authoritative native Y-up coordinates: ship-local aboard, native ground coordinates otherwise. Proximity clients use the current ship frame aboard; shared channels are non-spatial. Clients discard obsolete epochs and reset per-speaker playback buffers after channel/roster changes.

Proximity requires the same native zone name/object, the same actual hull in space (including guests who are not grouped), and <=64 m distance in its native coordinate frame. Two fighters or POBs with identical local coordinates cannot hear through their hulls. On the ground, native building identity also matches, preventing unrelated interiors with equal local coordinates from mixing; exterior/interior voice is deliberately separated at the building boundary. Different cells within one hull/building may hear each other within the distance limit. Planet is granted only on ground and requires the same native zone. Sector replaces it in space and requires the same native space zone name/object; different hulls in that sector may use Sector. Group remains the same nonzero native party ID across ground planets and space sectors. Boarding never creates group membership. Faction remains galaxy-wide for the same actual Rebel/Imperial enrollment; neutral has no faction channel. Additional instance semantics must be sourced from native instances before being introduced.

Limits: connected population has no default fixed ceiling; `SWGXR_MAX_VOICE_CLIENTS` can configure a relay admission limit. The atomic native state file has an 8 MiB parsing budget; at most8 active speakers per listener;50 audio packets/second with6packet burst;10 control frames/second;16 queued outgoing frames per listener, with oldest audio evicted before any control/context acknowledgment. Audio is dropped if all slots contain controls; an additional control closes the unresponsive connection safely instead of losing context. Queued audio is bound to the exact source connection generation, and a replaced socket cannot emit or inherit old queued frames even when numeric epochs coincide. Audio older250ms is discarded;250ms slow-writer deadline;400byte encoded payload;2KiB incoming frame;8KiB handshake;4096 pending used-ticket entries. Overflow/replay/invalid framing closes or drops traffic. A listener's first8 speakers in a1second window are accepted; this is a bounded prototype admission rule. The relay has no mixing, transcoding, TURN, jitter concealment or microphone-device logic. Slow clients lose old queued frames rather than growing memory.

## Evidence

`tests/test_voice_relay.py` uses three real TLS WebSocket clients with synthetic native metadata and synthetic mono20ms Opus-shaped packets. It validates routing, membership changes, channel selection, one-use tickets, spoofing/replay/rate rejection, logout/stale-source disconnect and codec/epoch bounds. `tests/test_voice_policy.py` checks source partitioning,64m boundary, signed ticket failures, missing source membership,8speaker and16queue caps. Gateway tests verify voice ticket identity and auth-session binding. These are transport/control tests, not microphone or decoded-audio tests.

`tools/server/voice_smoke.py` separately verifies actual normal and persistent Core3 source membership and cache behavior using existing isolated test accounts. Neither suite launches VR.

### Deployed verification (2026-10-04)

The Ubuntu VPS runs Core3 patch0032 and the TLS relay. Actual Godot WSS testing
with two existing isolated test characters passed20 checks: ticket admission,
14 delivered real Opus frames, nonzero decoded PCM, proximity/planetary isolation,
and refusal of group/faction access for solo neutral characters. The native
multiplayer persistence regression passed30 checks. Core3 was left running.
Evidence: `runtime/evidence/voice/vps-voice-godot.json`,
`vps-two-client-regression.json`, `vps-runtime-audit.json` and
`deploy-verification.json`.

Local tests cover157 native codec checks,35 mocked wrist UI checks,26 controller
lifecycle checks and10 relay/policy TLS tests. Group/faction positive routing is
covered with synthetic membership; the remote native characters were solo and
neutral. Desktop Forward+ Vulkan captures cover both wrist sides. These results
do not validate microphone hardware, live headset audio, WAN loss latency, or
MMO concurrency. Headset testing remains suspended.

### Channel lifecycle verification (2026-10-05)

The deployed relay passed 37 Godot WSS checks with two isolated `voicetest_*`
native characters: delayed admission, proximity/planet channel switching,
roster joins/removals, denied group/faction selection, disconnect/reconnect,
rejoining and audio delivery after reconnect. Eighteen real Opus frames arrived
and decoded to nonzero PCM, with no unexpected disconnects. These accounts are
separate from the concurrently used multiplayer regression accounts. The probe
accepts their private profiles through `--profile1` and `--profile2`; it never
creates characters or opens a microphone.

This found a client admission bug: enabling Godot's automatic heartbeat before
authentication could send a ping before the required hello when the engine had
already been running for five seconds. `voice_transport.gd` now enables the
heartbeat only after admission. The probe explicitly waits beyond that interval
before connecting and also reconnects the same transport instance. No deployed
server restart or configuration change was needed.

Thirteen local TLS relay/policy tests also pass, including roster cleanup,
replacement sockets, source expiry and auth logout. The actual local Core3
membership smoke passes 12 checks plus four native session-envelope checks;
the mocked client lifecycle suite passes 26. Positive group/faction routing is
tested with synthetic membership, while the deployed characters are solo and
neutral. This does not validate headset microphones or acoustic playback.

Evidence: `runtime/evidence/voice/verified-voice-godot.json`,
`runtime/evidence/voice/verification-20261005.json`, and
`runtime/logs/voice-verification-*.log`.


## Crew/sector verification (2026-10-10)

`python3 -m unittest tests.test_voice_policy tests.test_voice_space` passes 24 tests without sockets, executing the actual relay routing, tuning, queue delivery, expiry and credential-revocation logic with isolated writers. Coverage includes POB guests without party membership, identical local origins in different fighters, sector/planet grants, cross-sector party/faction traffic, malformed native scope, stale native sessions, ground building isolation, hull-change epochs, three-speaker authorized bursts preserving the context acknowledgment, bounded all-control overflow, replacement-socket generation fences and queued audio cancellation. The native snapshot fixture separately verifies actual hull/cell and scope metadata.

The nine existing TLS WebSocket integration tests were attempted, but all are blocked during socket creation by this session sandbox (`PermissionError: [Errno 1] Operation not permitted` on 127.0.0.1). They did not execute their relay assertions and are not reported as passing. No deployed-server connectivity, TLS admission, headset microphone capture or acoustic playback was validated for this change. Historical evidence above remains historical. Evidence: `runtime/evidence/voice/crew-sector-validation.json`.
