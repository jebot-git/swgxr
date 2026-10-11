# Global ground PvE and special warnings — staged 2026-10-11

This follows the favorable Mos Eisley prototype feedback. All ten original ground
planets can use `SWGXR_GROUND_ACTIONS=global`; PvP, JtL and player pets retain their
existing systems. No new worlds or remote services were activated by this change.
See [integration and rollback](../server/GROUND_COMBAT_INTEGRATION.md).

## Included behavior

- Native basic and special attack queues feed the action timeline after validation.
  Native RPG resolution remains authoritative; clients report their own contacts.
- Original attack clips hold their first frame through preparation and then play
  fully. Native command speed, reach, cones and area radius inform each warning.
- Special warnings fill progressively in purple and turn red at delivery. Explicit
  single-target Force/state effects also show the existing aim icon near the
  selected player's view. Other players do not inherit that target-bound effect.
- CL-scaled tracking retains the final aim lock. Before lock, all engaged players
  remaining out of useful reach cancel preparation and release native pursuit.
  Sustained escape distance or distance from home invokes native disengagement.
- Herald dialogue from the preceding integration uses the ordinary conversation UI.
  All 58 original herald placements and appearance pools remain included.

## Asset coverage

The prepared catalog has 2,275 templates across 270 families, 4,739 basic animation
bindings and 1,428 special profiles. Command aliases produce 360,747 model/command
bindings across the prepared planet catalogs, with zero conversion failures.
These binding counts include repeated commands/models, not that many distinct clips.

Missing special aliases use the family's base pose with special-specific warning
geometry and timing, and an `animation_fallback` diagnostic. CLL-8 uses its supplied
original firing clip omitted from its LAT. EG-6 and mouse-droid media supply no
attack animation: their original standing clip is explicitly marked as a visual
fallback. Five noncombat appearance templates have no attack profile (two Bomarr
variants, Jabba, Sy Snootles and the shuttle). Proprietary media stays local; the
launcher prepares it from the supplied game data.

## Verification

- Native CoreCU compiled and linked; the complete patch stack through 0141 applies.
- Eight isolated live native checks cover global negotiation outside Mos Eisley,
  basic and targeted/area specials, original special selection, home leash and
  pre-lock cancellation. Fixture placement and attack selection are administrative
  setup, not a physical movement or remote-network test.
- 537 original rig/clip cases across all 270 families passed first-frame hold,
  playback and actor-transform checks using the dummy renderer.
- 353 client warning checks, 49 simulated-latency timeline checks, 45 animation
  cache checks and the original avatar playback regression passed headlessly.
- Python/C++ policy, protocol, dodge and launcher-preparation regression checks
  passed. The native smoke leaves no fixture mobs or temporary screenplay changes.

Exact reports and logs are under `runtime/evidence/global-ground-*`. Final package
manifests record hashes and the source commit. Linux and Windows package preflights
are separate; Windows execution here uses Wine, not a native Windows machine.

Remote deployment, headset inspection, sustained multiplayer capacity, group
balance and authored contact-pose acceptance remain outside these local results.
