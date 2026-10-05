# Prototype voice relay

The client uses pinned upstream TwoVoIP (the voice stack used by FPSlop) for microphone/playback and Opus; FPSlop-authored game code is not copied. The separate Python relay forwards opaque encoded frames and never decodes, saves or logs voice content. Remote transport is TLS WebSocket on port18444. No dependency beyond Python's standard library is required.

`python3 server/voice_relay.py --config <gateway-config> --bind 0.0.0.0 --port 18444`

Configuration shares `certificate`, `private_key`, `accounts`, `auth_database` with the HTTPS gateway and adds `voice_secret` (path to at least32 random raw bytes) and `voice_state` (native cache JSON path). The adapter receives matching `SWGXR_VOICE_SECRET` and `SWGXR_VOICE_STATE` environment variables. The relay must be able to read these files and SQLite WAL/SHM. Its SQLite opens are read-only. Native state is atomically published mode0640; a root adapter/blux relay deployment needs an appropriately shared setgid directory. Never expose the private adapter or cache files over HTTP.

Local explicit debug uses `--loopback-debug --bind 127.0.0.1 --port 18084`, accepts unencrypted WS only on loopback, and accepts only locally signed debug tickets. Remote mode rejects those tickets. Default local adapter paths are `runtime/server/voice.secret` and `voice-state.json`; the local secret is created once, never overwritten. Explicit environment secret paths must already exist.

## Control plane

Authenticated `POST /voice/session` accepts `character_id`, optional existing native `session_id`, and the ordinary service position/building/cell fields. Identity is resolved through owned native Core3 state. Its response contains `backend:core3`, `ticket`, `expires_in:30`, `relay_port`, `protocol:swgxr-voice-v1`, `channel:proximity`, granted `channels`, `reasons`, `needs_presence` and `presence_interval:5`. HTTPS overrides the local debug ticket with a session-bound ticket and remote port18444; direct loopback replies use18084. Clients derive the relay host from their configured API host, using the same trusted TLS certificate.

Tickets are HMAC authenticated, one-use and expire after30seconds. They bind account, character, native session, gateway credential hash and auth expiry. Session tokens/passwords never enter relay messages. The relay rechecks logout/expiry/legacy claim status against the auth store at100ms cadence; storage failures close voice. Native session stop removes the route immediately.

Live native sessions publish identity, position, zone object ID, group ID and actual Rebel/Imperial enrollment with each existing native snapshot, with a4second freshness limit. Normal worlds reuse every existing native service observation. If none arrives, `POST /voice/presence` performs a source service refresh at most once per account per5seconds. Normal metadata expires after15seconds. Calls are serialized by the adapter; clients must keep a single request outstanding and suppress redundant heartbeat when a recent service observation exists. This normal-world fallback still performs original one-shot native login on uncached refresh: it is a prototype control-plane cost, not an MMO-scale presence solution. No audio packet initiates a login or native RPC.

## WebSocket `/voice`

First text frame: `{ "type":"hello", "ticket":"..." }`. Server `hello` and subsequent `tuned` messages contain `epoch` (uint32), `channel`, `granted_channels` and `reasons`. Tune with `{ "type":"tune", "channel":"proximity|group|planet|faction" }`. Unsupported membership falls back to proximity. Tuning or native membership/zone changes increments epoch and invalidates queued audio. `roster` text messages provide visible peers `{id,name}`.

Client binary: little-endian uint32 epoch, uint32 increasing sequence, then1–400bytes of raw mono Opus (no TwoVoIP framing prefix). Each packet represents20ms at the client's48kHz configuration; relay verifies mono Opus TOC duration without decoding. Server binary: little-endian uint32 receiver epoch, uint32 listener-local per-speaker delivery sequence, uint64 source character ID, float32 source x/y/z, then unchanged raw Opus. Delivery sequences stay monotonic across speaker tuning/reconnects and reset only when the listener's epoch changes. Coordinates are authoritative native Y-up world coordinates. Clients discard obsolete epochs and reset per-speaker playback buffers after channel/roster changes.

Proximity requires the same native zone object and <=64m distance. Planet requires the same zone name and object ID. Group requires the same nonzero native group ID and works across planets. Faction is galaxy-wide for the same actual Rebel/Imperial enrollment; neutral has no faction channel. Current supported scope has no separate instanced-dungeon system: zone-object identity isolates spatial channels. Additional instance semantics must be sourced from native instances before those are introduced.

Limits:32 relay connections; current native live backend separately caps4 native sessions; at most8 active speakers per listener;50 audio packets/second with6packet burst;10 control frames/second;16 queued outgoing frames per listener, audio older250ms discarded,250ms slow-writer deadline;400byte encoded payload;2KiB incoming frame;8KiB handshake;4096 pending used-ticket entries. Overflow/replay/invalid framing closes or drops traffic. A listener's first8 speakers in a1second window are accepted; this is a bounded prototype admission rule. The relay has no mixing, transcoding, TURN, jitter concealment or microphone-device logic. Slow clients lose old queued frames rather than growing memory.

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
