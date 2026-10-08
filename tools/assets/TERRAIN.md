# Original Tatooine terrain pipeline

`prepare_terrain.py` reads the active original-media TRE allowlist and writes
`runtime/assets/terrain/tatooine.json`, the original TRN for independent checks,
and converted local textures. It covers the full source extent, -8192 to +8192
metres in both ground axes. No proprietary terrain data is checked in.

```sh
python3 tools/assets/prepare_terrain.py
./tools/client/build_native.sh
godot --headless --xr-mode off --path client --script ../tools/assets/validate_terrain.gd
```

The 257 original layers contain 43 fractal families, 15 ground shader families,
17 environment families, 12 road affectors, four local water polygons, and cave
exclusions. All height constants/fractals/terraces, road segment heights,
rectangle/circle/polygon/polyline boundaries, their feathering, layer ordering,
and height/fractal filters are evaluated natively. Original material families,
texture variants, eight constant color rules and 49 fractal color rules use
14 original TGA color ramps. Shader texture dependencies and source hashes are
recorded in the manifest. Flora rules and seeds are preserved/inventoried but
procedural flora is not populated by this evaluator.

`SwgTerrainEvaluator.configure(manifest)` creates immutable internal rules. Do not
reconfigure an instance while workers use it; configure is deliberately one-shot.
`sample_height(x,z)` returns the absolute SWG height. `sample(x,z)` adds shader
weights, color tint, environment ID, source exclusion and water table data.
`build_chunk(min_x,min_z,size,resolution)` is safe for concurrent read-only workers;
resolution means cells per edge. Returned vertices are Godot chunk-local
`(dx, absolute_SWG_height, -dz)`. Place the chunk at
`(min_x-scene_origin.x, -scene_origin.y, scene_origin.z-min_z)`.

Chunk data includes `vertices`, `normals`, `uvs` (global SWG metres), `indices`,
`shader_ids` (four floats per vertex), `shader_weights` and `tints`
(PackedColorArray), plus source heights and excluded cell count. Normals use
constant global +/-1m samples, so equal positions on adjacent chunks match.
Indices use Godot clockwise winding, independently compared with PlaneMesh.
Adjacent sample quads alternate diagonals to form the original client's
eight-triangle leaf-tile fans. Refined boundary vertices stay on those same
planes; rendering and resident collision use identical indices.
Source cave exclusions remove both render/collision triangles at the chosen
mesh resolution. Interior source floor masks are handled separately by the
terrain context/presentation pipeline; there is no invented world-wide flat floor.

For independent height parity, `tools/terrain/build_reference.sh` builds a small
read-only executable against the pinned actual Core3 terrain library. It opens
only the original TRN and no character database. Give it SWG x/z coordinate pairs
on stdin. The native validator consumes `runtime/terrain/reference-heights.tsv`
and `road-reference.tsv` if present; its report explicitly counts compared points.
Current evidence is `runtime/terrain/native-validation.json`: 2,249 independent
reference samples, including 1,395 road samples, maximum difference below 0.00008m;
chunk seams, material normalization, source water, exclusions and winding pass.
Two 128m/64-cell chunks plus one coarse chunk take about 84ms on this machine.

Height parity targets the pinned Core3 evaluator, not a claim of recovered
proprietary client source. Core3's direction/slope/shader filters do not implement
height filtering; this behavior is retained for exact server height parity.
Client material filters and blending are reconstructed from the source rules.
Original rendering, detailed shader effects, all texture variation behavior,
vegetation populations, weather and sky transitions are not reproduced here.
Object placement terrain modifiers must be explicitly referenced by their shared
templates: the context audit found none among 415 Tatooine snapshot buildings,
so unrelated .LAY files are not silently applied.

The native algorithm derives from AGPL-3.0 Core3 source. Its source attribution
and complete license are in `client/native/TERRAIN_SOURCE.md` and `TERRAIN_COPYING`.

See [player terrain navigation](../../docs/TERRAIN_NAVIGATION.md) for the original
client's height-field, slope, passability, water and floor-transition contract.
