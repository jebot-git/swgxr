# Herald integration for the next release

Heralds use the existing NPC dialogue panel and wave-to-talk interaction. The
server executes the original single-destination, multiple-destination and custom
Tatooine conversation handlers. Original text, replies, waypoint destinations and
credit costs remain owned by those handlers. Accepted replies refresh the datapad.

Replies carry the current native screen token and option index. The server checks
range, cell, line of sight and player/NPC availability before advancing a screen;
stale replies are rejected. Existing durable service receipts prevent a retried
request from executing its handler twice. The client does not deduct credits or
create destination waypoints optimistically.

## Appearance coverage

The exporter includes 50 `heraldList` and eight `multiDestHeraldList` placements:
Tatooine 9, Corellia 7, Naboo 10, Rori 5, Talus 5, Dantooine 4, Dathomir 7,
Endor 3, Lok 4 and Yavin 4 4. These are native screenplay spawns, not additional
client spawns. Lorne Prestar retains his original five-piece outfit.

Heralds can wander. Native snapshots expose their home position so exact source
placement matching still works for a player who arrives after the NPC moves.
The client continues rendering the NPC at its current position.

The launcher prepares every original template in the heralds' appearance pools,
including all 120 commoner variants. Live presentation uses the appearance
selected by the native server. Original media stays in ignored local directories;
source hashes and conversion failures remain in the generated catalogs. Existing
launcher pipeline fingerprinting invalidates caches when this converter changes.

## Verification

- Python tests cover both literal placement tables, public route exposure,
  conversation token/option validation and original text localization.
- Headless dialogue checks exercise the existing panel, native option indices,
  pending input suppression and ignoring replies after the panel closes.
- The isolated local native client discovers and approaches the wandering Lorne,
  opens original dialogue, rejects a stale reply, accepts and replays a choice,
  and reads the original Fort Tusken waypoint from the persistent datapad.
- Headless appearance checks exercise all 58 placements and their original
  appearance pools through ordinary multiplayer and the legacy combat projection.

Headless checks use the dummy renderer. This is not headset validation. The paid
and multiple-destination handlers are connected to their original implementation;
the local native scenario above exercises the free single-destination flow.

Evidence is stored under `runtime/evidence/herald-*`. Client and server packages
are staged for the next release. No public release, remote service restart or
live headset launch is part of this integration.
