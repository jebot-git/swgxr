# Cloning-centre entrance collision

The Mos Eisley entrance was blocked by the original exterior CMSH collision
shell. Its face slopes about 27 degrees from vertical through the authored POB
opening. The client only subtracted doorway apertures from faces aligned within
about 18 degrees of the portal normal, leaving this sloped sheet solid. The same
geometry occurs in all 19 city cloning-centre placements across three building families.

`SwgCollisionBuilder` now accepts steep exterior closure sheets (up to 45 degrees
from the portal normal). The broader angle requires a connected, open authored
FLR approach. Candidate sheets must cover at least 90% of the portal aperture
and remain within the existing finite approach limits. Subtraction retains the
portal width and lintel; it cannot extend below the supported approach floor.
Interior cells keep the original angle tolerance. No source assets change.

Validation uses the original converted assets and Godot native capsule physics:

- `cloning_entrance_smoke.gd`: all 35 facilities across the ten ground worlds,
  identified by their building templates, including 19 city centres and 16
  smaller house/outpost facilities. Five lateral routes in both directions
  produce 350 sweeps at authored floor height, including raised doorsteps.
  The 19 affected city centres also receive 38 adjacent wall/lintel checks and
  38 missing-floor/disabled-portal controls.
- `cloning_stage_walk_smoke.gd`: production XR locomotion with mocked controller
  input in streamed Mos Eisley; walks into the foyer and back outside, remains
  grounded, and preserves the head tracking transform.
- Existing original starport corridor, authored stair movement, cell collision
  and source-floor regressions guard the shared collision builder.

Run tests with `godot --headless --xr-mode off --path client --script tests/<name>.gd`.
Evidence is written under ignored `runtime/evidence`. Dummy-renderer and mocked
tracking results do not validate headset rendering. This is a client fix and
requires an updated native library on both Linux and Windows; server changes or
original-media reconversion are unnecessary.
