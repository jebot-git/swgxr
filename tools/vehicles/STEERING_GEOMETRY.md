# Original steering art

`prepare_assets.py` exports all six source saddle models and their steering
triangle selections. `validate_steering.py` checks the three newly separated
models against source topology, hashes, attachment seams and rider grip points.
`client/tests/vehicle_handlebar_assets_smoke.gd` checks the actual Godot mesh
partition without losing source triangles, materials, vertices or UVs. Normal
comparison allows the mesh renderer's normal-packing round trip (0.0003).

The speederbike uses eight complete position-welded components: both original
grips, levers, stems and cable parts, totaling 430 triangles on surface 1.
The swoop uses six original index-connected groups totaling 132 triangles on
surface 0. Its bar joins the stationary body at six duplicated source positions;
partitioning follows the authored normal/index seams, without generating faces.
The Flash Speeder uses 24 source index groups totaling 72 driver-wheel triangles
on surface 1. Ten steering-column triangles stay stationary. X31, X34 and AV21
retain their existing detached wheel selections.

No saddle provides a steering bone, steering hardpoint or original steering
animation. Moving these original triangles is a local VR interaction extension.
The pivot remains the midpoint of the original human rider hold sockets. Bikes
rotate around Godot Y so opposite grips move fore/aft; landspeeders use Z.
The source attachment seams therefore move as rigid pieces, not as an original
articulated mechanical assembly. Every original triangle remains in exactly one
of the stationary or moving meshes; no replacement handlebars are invented.

Closest original selected-vertex distances to rider sockets are 8.2/8.7 mm for
the speederbike and 9.6/27.2 mm for the swoop. Flash's corresponding nearest-vertex
distances are 77.5/52.4 mm. These are vertex-distance upper bounds, not measured
hand-to-triangle surface gaps. This change preserves the source rider sockets
instead of silently inventing a different riding pose.

Use `--xr-mode off` for all test modes. A headless run uses the dummy renderer
and verifies geometry/math only. `--capture` requires supported Forward+ Vulkan
and a working display; it writes neutral and ±0.4-radian views of each model.
Neither test mode validates a live headset or deploys changes to the live server.
