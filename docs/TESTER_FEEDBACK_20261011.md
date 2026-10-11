# Next-release tester feedback patch

Prepared locally; this document does not imply publication, deployment or a
headset test. The previous launcher preparation and cloning entrance fixes remain
included in the next client build.

## Loot interaction

Server-confirmed eligible bodies display the original SWG
`appearance/pt_glowing_imperial_coin.apt`, tinted gold and spinning above the body.
The launcher converts it from the user's own media in the new `loot_marker` step;
source/dependency hashes and failures are recorded in its local catalog.

An empty tracked hand can trigger Loot All directly within 50 cm of the marker,
or aim at it within 2.5 m with a forgiving angular boundary. World collision blocks
selection through walls. No inspect roundtrip precedes coin collection. Coins hide
on confirmed empty/ineligible state; native ownership, capacity and rewards remain
authoritative. Nearby corpse polling is serialized and now uses a three-second
interval. Replicated NPC corpses retain their pose and ownership instead of
receiving a second body mesh.

Harvesting keeps its grip/resource interaction. The above-body region expands to
35 cm beyond the horizontal bounds and 85 cm above the body; resource selection
uses a 14 cm radius. Held buttons and pending requests cannot repeat collection.

## NPC outfit coverage

The reported Mos Eisley Lorne Prestar is `herald_lorne_prestar`, at source
coordinates (3376.1, 5, -4786), rather than the separate quest NPC. The prior city
table export omitted the `heraldList` screenplay. The exporter now includes all
50 literal herald placements across the ten original ground planets. All seven
Tatooine heralds bind to their exact original appearances; Lorne has his original
five-piece `mos_taike_guard_old_outfit`.

This closes the identified herald gap. Arbitrary quest, themepark and procedural
spawners are not covered by static placement matching, so the earlier fix cannot
be described as covering every NPC. Other planets' herald placements were audited;
their complete asset rebuild and live presentation have not been tested here.

## Combat feedback

See [ground integration](../server/GROUND_COMBAT_INTEGRATION.md) for the CL curve,
icon meanings and native weapon synchronization. A stale ambient gun could remain
visible while Core3 selected its secondary/unarmed weapon. The client now displays
the confirmed active weapon on initial snapshots, updates and attack events.
This explains a concrete mismatch in the implementation; the unspecified enemies
from the live report have not been individually reproduced.

## Validation

- 20 Python/native policy tests, including compilation using Core3's C++14 level.
- Native CoreCU build completed and its source/build receipt verified.
- Headless client checks: 157 ground-action checks, 49 action timeline checks,
  17 original animation rigs, 24 source outfit/weapon checks, seven original
  Tatooine heralds, 25 loot input checks, 21 controller checks and all 42 prepared
  Tatooine corpse species. Includes coin wall occlusion, direct pickup, held-input
  suppression, immediate confirmed removal and replicated corpse ownership.
- Desktop Forward+ Vulkan renders inspected for the gold coin and Lorne's outfit.
  These are isolated fixtures; they do not validate a live headset or multiplayer
  group balance. No live realm services were restarted for these checks.

Local evidence: `runtime/evidence/feedback-*.log`,
`runtime/evidence/herald-audit/coverage.json`,
`runtime/evidence/corpse-gathering-preview.png` and
`runtime/evidence/herald-lorne-prestar.png`.
