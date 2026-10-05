# Procedural terrain source attribution

`src/swg_terrain*` adapts the terrain evaluator from SWGEmu Core3 commit
403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79 (AGPL-3.0), specifically
MMOCoreORB/src/terrain/{ProceduralTerrainAppearance,MapFractal,PerlinNoise,Random},
layer boundaries, height affectors, Road/HeightData/Segment and height/fractal
filters. Original file authors include Victor and Hakry; the Perlin implementation
also credits Ken Perlin. The license is preserved in TERRAIN_COPYING.

The port removes Engine3 dependencies and parses the original asset rules into
immutable structures once for worker-thread chunk generation. Seed arithmetic
uses int64 intermediates to preserve the original result without signed overflow.
The copied Perlin floating-point rounding and original road smoothing are retained.
No original proprietary client source is included.

Height behavior targets the pinned Core3 evaluator. Original material families,
textures, boundaries, fractal/height filters, environmental IDs, water and exclusion
rules are extracted from user-provided TRN data. Material blending and slope /
direction / shader filtering are reconstructed client presentation: Core3 does not
provide working material rendering. Original base color constants and fractal TGA ramps are applied; detailed shader effects, vegetation
population and complete original renderer behavior are not reproduced.

This native terrain implementation is AGPL-3.0-derived; preserve its source and
license when distributing a combined native module. This is a local prototype,
not an assertion of a permissively licensed clean-room terrain implementation.
