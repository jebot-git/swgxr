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
