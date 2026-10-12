# Original pilot mission integration

The integration converts the original pilot conversation graphs and mission tables into CoreCU Lua. Trainer sessions are replaced correctly when moving between NPCs, fixing the stale conversation that could leave trainers such as Akal Colzet unresponsive. Native character skills, XP prerequisites, squadron affiliation, quest journals, ship certification, inventory, credits and combat remain authoritative. The existing trainer panel displays these conversations; no separate mission UI or client quest store is introduced.

## Coverage

- Nine squadrons: Storm, Black Epsilon, Imperial Inquisition, CorSec, RSF, Smuggler Alliance, Havoc, Vortex and Crimson Phoenix.
- 46 conversation bindings, including master trainers and the three fuel technicians used by Storm Squadron at Nym's Stronghold. Freelance recruitment still uses the existing faction coordinator.
- 475 mission definitions across 17 objective types, including chained objectives and repeatable duty missions. This count includes individual legs, not 475 independent story assignments.
- Battle, survival and delivery objectives replace upstream Core3's immediate-completion stubs. Completion requires enemy destruction, surviving the transmission period, or docking with the correct recipient. Pickup and delivery require different targets and journal tasks.
- The original Storm transfer authorization can be read and explicitly signed in Oberhaur/Alozen's trainer panel before handover. The signature belongs to the actual inventory object's ID and persists in native quest data.
- Rewards require native completion and a receipt; an inventory-full error leaves the reward claim retryable. Legacy CorSec/RSF/Havoc reward receipts are honored. Existing Havoc transfer state is imported from legacy reward receipts.
- Active objectives restart their current leg after login; earned skills, completed legs and reward receipts remain. Timed work is cancelled during reset.

## Source and Total Experience compatibility

`server/jtl/pilot/sources.lock.json` pins source URLs and SHA-256 hashes to SWG-Source/dsrc commit `e3aac29b55b46fec2ce2b1518db80a8f70d798a5`. Source text, converted Lua and extracted strings remain in ignored local directories. No original media is committed or fetched by these tools.

Later source scripts reference dialogue keys absent from the supplied Total Experience TREs. Existing original strings are retained. Missing options use authored functional labels; missing narrative uses an assignment/status fallback. These are not claimed to reproduce missing original dialogue. The conversion report records missing keys and the media provenance.

Later ace medals absent from the supplied media are excluded. Original credit, component, jacket/helmet and mastery rewards remain. The quest compiler records three table reconciliations: a removed Tatooine Black Sun waypoint, the original matching ship spawner used for Storm's first inspection, and an unregistered optional smuggler kill type omitted from the Imperial master kill list. Other registered targets still satisfy that kill objective.

The compiler preserves parenthesized Java negation, zero-based response arrays and original branch links. Unknown syntax, missing required quest references or unregistered required ship types fail preparation instead of silently completing an objective.

## Preparation

With the supplied TRE set already at `runtime/asset_sources/active_tre`:

```sh
python3 -m venv runtime/pilot-source-venv
runtime/pilot-source-venv/bin/pip install javalang==0.13.0 lupa==2.6
runtime/pilot-source-venv/bin/python tools/space/pilot/prepare.py --fetch
bash tools/server/build.sh
```

`--fetch` retrieves only missing pinned source text. Existing files must match their hashes. Subsequent preparation works without it. `configure_core3.py` installs the prepared bundle. The installer verifies converted program hashes and writes `installed.json`; the native build receipt verifies every installed file. Runtime packaging includes the scripts and conversion/provenance reports. Keep the original ten-sector deployment profile when packaging for the live realm.

## Verification and limits

```sh
runtime/pilot-source-venv/bin/python tools/space/pilot/test_conversion.py
runtime/pilot-source-venv/bin/python tools/space/pilot/test_runtime.py
runtime/pilot-source-venv/bin/python tools/space/pilot/test_objectives.py
runtime/pilot-source-venv/bin/python tools/space/pilot/test_progression.py
python3 tools/space/pilot/native_smoke.py --fixture runtime/server/pilot-combat-fixture.json
python3 tools/space/pilot/native_delivery_smoke.py --port 18088 \
  --fixture runtime/server/pilot-combat-fixture.json \
  --ship-report runtime/evidence/pilot-ship-services-native.json \
  --output runtime/evidence/pilot-native-delivery.json
```

The progression traversal uses actual converted dialogues, with simulated objective success and supplied XP, to reach mastery on all nine paths. It is not evidence of earned XP, real ship damage, flight difficulty or end-to-end playthroughs. The objective harness checks battle losses, survival timing, stale events and distinct delivery targets.

The native smoke test operates only on an explicitly named isolated `invtest` character. It checks trainer access, journal visibility, signing, reward replay and abort/retry. Its injected completion callback is labelled as such. `tools/space/docking_smoke.py` separately exercises native inspection and docking with a genuinely crafted/outfitted ship. The delivery smoke test exercises actual docking at both stops, rejects reuse of the pickup ship, and checks final journal completion. It relocates the original rendezvous near the test ship and disables hostile waves and the follow-on mission; it does not validate travel or combat balance. Tests do not launch the XR client.

A complete gameplay pass of every mission in every sector, multiplayer objective ownership and balance remains separate from source conversion and these regressions. Native damage/hate tuning continues to use CoreCU ship templates; original script damage multipliers are not all represented by upstream Lua APIs. Missing narrative fallback wording should receive editorial review in the tester pass.

## Local integration evidence (2026-10-11)

- Conversation/compiler/runtime/objective regressions: 11 tests passed.
- Existing docking/protocol/deployment regressions: 17 tests passed.
- All nine converted squadron paths reached mastery in the simulated progression traversal.
- Native trainer integration: 100 checks passed across all 46 NPC bindings, including signing, reward replay and stale conversation tokens.
- Native inspection/docking regression: 14 checks passed with a crafted and outfitted Z-95.
- Native two-stop delivery: 13 checks passed, including distinct pickup/delivery targets and completion through the real `SHIPDOCKED` observer.

Reports are under ignored `runtime/evidence/`: `pilot-progression.json`, `pilot-native-integration.json`, `pilot-integration-docking.json` and `pilot-native-delivery.json`. These results are from the isolated local CoreCU test instance. They do not establish a live-realm deployment or a full gameplay pass of all missions.

## Waypoint audit (2026-10-12, pending release)

Audited all 475 converted mission definitions and their 1,496 navigation points.
The native journal exports active waypoints only for the player's current sector,
with XYZ in the same Y-up coordinate convention as ship positions. The client
puts these on its sector map and wrist map; it does not currently provide a
cockpit waypoint bearing/distance marker.

Five defects were found and corrected locally:

- The sector-map ship arrow read `orientation`, although native snapshots supply
  `quaternion`, leaving the arrow fixed while the ship turned.
- Upstream `SpacePatrolScreenplay` removed the last waypoint without completing
  the journal. The converted quest wrapper now completes an in-order final
  arrival, preserving the native completion/follow-on handling. This affects
  `corellia_privateer_tier3_3_a`, `corellia_privateer_tier4_1a` and
  `tat_priv_quest_trans`. Akal's second-point encounter trigger is unchanged.
- The quest wrapper cancelled the pending encounter when completing a
  point-triggered patrol. It now preserves that already-scheduled start on
  successful completion; failure/abort still cancels it. The Akal regression
  executes completion with actual cancellation semantics, not just scheduling.
- Hyperspace map points used the original table's XYZ directly, but Core3's
  arrival task applies XZY. Preparation now matches the native arrival frame;
  all 32 navigation entries across the ten sectors were regenerated and checked
  against the supplied hyperspace table. Mission buildout positions are unchanged.
- The delivery runtime used the initial quest sector for every rendezvous.
  `tatooine_rebel_tier3_3` crosses Lok to Dathomir,
  `tatooine_rebel_tier4_2_a` crosses Dathomir to Yavin, and
  `tatooine_privateer_tier4_1a` crosses Lok to Dantooine. Each stop now uses its
  original `zoneName` for waypoint and ship creation. After pickup, the mission
  waits for the destination sector instead of spawning there in the old sector
  or failing the required zone transition.

Regression commands:

```sh
runtime/pilot-source-venv/bin/python tools/space/pilot/test_waypoints.py
godot --headless --xr-mode off --path client --script res://tests/jtl_waypoints_smoke.gd
python tools/space/pilot/native_delivery_smoke.py --cross-sector --port 18088 \
  --fixture runtime/server/pilot-combat-fixture.json \
  --ship-report runtime/evidence/pilot-ship-services-native.json \
  --output runtime/evidence/jtl-waypoints-native-hyperspace.json
```

The six Lua regression tests exercise actual patrol/objective code with modeled
engine calls, including all three original cross-sector deliveries, all three
final-point patrols, Akal waypoint order, and delivery cleanup. They are not live
flight tests. The headless map test checks eight projection, heading and marker
replacement conditions; it does not validate GPU/headset rendering. Existing
JTL client regression: 70 checks passed. Pilot compiler/runtime suite: 22 tests
passed; JTL protocol/sector-asset suite: 16 tests passed.

The separate native same-sector delivery run passed 20 checks with a genuinely
crafted Z-95, original target templates, real docking, exact XYZ readback,
localized labels, replacement and completion cleanup. Its original rendezvous
are relocated near the fixture and hostile waves are disabled. Reports are
`runtime/evidence/jtl-waypoints-source-audit.json` and
`runtime/evidence/jtl-waypoints-native-delivery.json`.

The native cross-sector run passed 24 checks: real pickup docking, native
hyperspace from Tatooine to Naboo, arrival within the original 100 m per-axis
random offset of the corrected map point, destination waypoint/target creation,
real delivery docking and final waypoint removal. The recipient was placed
200 m above the Royal Way arrival for a clear approach; original docking
collision checks remained enabled. A prior obstructed approach was rejected
by that guard and retained separately as evidence, not counted as a completion.
The isolated server enabled both space sectors for this test. No live-realm
mutation or headset launch was performed. Evidence:
`runtime/evidence/jtl-waypoints-native-hyperspace.json`.

These are pending source/data changes after test.20, not a deployed waypoint
patch. Complete route playthroughs across all 475 missions remain untested.
