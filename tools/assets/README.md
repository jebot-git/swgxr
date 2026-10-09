# Local SWG asset preparation

This pipeline reads the user's original installation images. It downloads no game assets and stores all original/converted data under ignored `runtime/` paths. The generated stage is a real mesh reconstruction of Mos Eisley's starport and static objects within 180 metres, using the original world snapshot. The separate terrain/world pipeline now extends this to full Tatooine; original material effects remain approximate.

## Local layout and private archive

| Directory | Contents |
| --- | --- |
| `runtime/assets/` | Converted runtime assets, grouped by gameplay system and ground planet; combat and entertainment catalogs live here too |
| `runtime/asset_sources/media/{base,jtl,tte}/` | Original user-supplied installation images |
| `runtime/asset_sources/extracted/{base,jtl,tte}/` | Media extractions, original TRE copies and media hash inventories |
| `runtime/asset_sources/active_tre/` | The 51 allowlisted source archives, with relative links to the retained originals |
| `runtime/asset_reports/` | Audits, extraction logs, migration journal and original metadata retained for rollback |
| `runtime/asset_work/` | Old export experiments, diagnostic captures and build/test scratch files |
| `runtime/asset_archives/` | Private verified ZIP64 bundles, SHA256 files, manifests and verification receipts |

For portable testers, build a runtime-only archive:

```sh
python3 tools/assets/bundle_assets.py --profile client-runtime --output runtime/asset_archives/test-runtime-data-20261010.zip
```

This selects the transitive converted-data dependencies of the client source and
explicit dynamic loaders. It retains conditional catalog alternatives and embedded
source hashes/conversion limitations, while excluding original TREs and binary source exports, server-only
catalogs, standalone development reports and unreferenced conversion outputs.
The adjacent `.selection.json` records roots, client source hashes and excluded
paths. Selection is conservative static reachability, not a claim that every
retained asset appears during a play session. Identical files at different required
paths remain separate; deduplication would require a separate archive/layout change.
The existing `swgxr-assets-v2` client importer supports this profile unchanged.
Put the unextracted ZIP in the client `data/` folder and run `import-data.sh` or
`import-data.cmd`. Keep exactly one ZIP there. Switching from a full archive
requires a fresh client directory; do not overlay an existing import receipt.

For source/development backup, the default full profile remains available:

`python3 tools/assets/bundle_assets.py --output runtime/asset_archives/SWGXR-assets.zip`
bundles every converted runtime file and the complete required TRE set, with
conversion limitations and source provenance retained. It excludes installation
images, duplicate extractions, scratch work, credentials and databases. TRE links
are materialized as regular files for Windows extraction. Every archive asset is
read back and checked against its SHA256 before the final ZIP is published.

Extract into an empty workspace/staging folder and run the included
`python restore_asset_paths.py --root <workspace>` (Python 3.11+) to verify the extracted files
and rebase recorded absolute JSON paths. The archive contains assets, not the
Godot executable or game code; use the matching client with this asset layout.
Keep the archive private and ignored by Git. The local cleanup preserves original
media and old work; it does not delete source extractions or conversion failures.

## Reproduce

Requires Python 3 with Pillow, 7-Zip, and unshield. The optional bootstrap downloads/builds a pinned open-source extraction utility; it does not download game data.

```sh
python3 tools/assets/extract_media.py --bootstrap-unshield
# Optional expansion media: always extract into its own cabinet directory.
python3 tools/assets/extract_media.py --output-root runtime/asset_sources/extracted/jtl "runtime/asset_sources/media/jtl/Star Wars Galaxies - Jump to Lightspeed (USA).cue"
# Optional Total Experience set: separate cabinets again.
python3 tools/assets/extract_media.py --output-root runtime/asset_sources/extracted/tte runtime/asset_sources/media/tte/SWG_TTE_CD{1,2,3,4,5}.ISO
python3 tools/assets/activate_archives.py --audit-only
python3 tools/assets/activate_archives.py
python3 tools/assets/prepare_stage.py --tre-dir runtime/asset_sources/active_tre
python3 tools/assets/validate_stage.py
```

BIN/CUE support is limited to a single MODE1/2352 track at INDEX01 00:00:00; sector headers are verified and the user image is never modified. CUE extraction requires an explicit `--output-root` so its InstallShield `data1.cab` cannot overwrite base-media cabinets.

`activate_archives.py` creates relative symlinks into `runtime/asset_sources/active_tre`, fails on duplicate archive names with different hashes, and writes source provenance. Run activation while Core3 is stopped. It auto-detects the isolated JTL and TTE directories, supports base media alone, and filters every source with the checked-in 51-name Core3 pre-CU allowlist in `archive_policy.py`. All 38 repeated archive names on TTE were hash-identical to the earlier media. Thirteen missing pre-CU archives were added; seven unrelated/later CU archives were excluded. `--supplement DIR` accepts another explicit source; conflicting duplicate names fail rather than replacing an earlier archive. `--audit-only` checks without changing active links. The stage converter prefers this active set by default; its validator follows the manifest's recorded TRE directory.

Explicit ISO paths can follow `extract_media.py`; `prepare_stage.py --tre-dir PATH` accepts a local installed game's TRE directory instead. Archive precedence exactly follows the pinned Core3 51-file list in `archive_policy.py`, including the interleaving of SKU1 data/patch archives. It does not infer arbitrary custom `live.cfg` configurations.

Outputs:

- `runtime/asset_sources/extracted/base/tre/SWG_Files/`: 30 original TRE files from the three supplied CDs.
- `runtime/asset_sources/extracted/jtl/tre/JTL_Files/`: eight expansion TREs from the supplied JTL BIN/CUE.
- `runtime/asset_sources/active_tre/`: 51 relative archive links and `provenance.json` (30 with base media, 38 with base+JTL, 51 with TTE supplement).
- `runtime/asset_sources/extracted/tte/tre/Star_Wars_files/`: 58 original TTE archives retained locally; only 51 pre-CU names are eligible for activation.
- `runtime/asset_sources/extracted/tte/media_inventory.json`: five TTE ISO and 58 archive hashes.
- `runtime/asset_sources/extracted/jtl/media_inventory.json`: expansion BIN/CUE and archive hashes.
- `runtime/asset_sources/extracted/base/media_inventory.json`: media and extracted archive SHA-256 hashes.
- `runtime/assets/mos_eisley/scene.json`: Godot-ready static meshes, instances, spawn, provenance.
- `runtime/assets/mos_eisley/textures/`: locally converted PNG textures.
- `runtime/assets/mos_eisley/source/`: original Tatooine terrain rules, starport terrain layer, POB and 17 floor files preserved with source provenance; the separate terrain evaluator now reconstructs planet heights and materials.
- `runtime/assets/mos_eisley/conversion_report.json`: selected snapshot nodes and explicit conversion failures.

The March 2004 base installation contains patch_00 through patch_07. The October 2004 JTL image adds data_sku1_00 through 05 and patch_11_00/01. The subsequently supplied April 2005 Total Experience media fills all 13 missing expected archives, yielding the complete 51-file pre-CU set. Its patch 15/CU archives and data_skuja_00 remain excluded. JTL updates slot definitions from version 0005 / 62 records to 0006 / 84 records; the final pre-CU patch set has 85 records, adds skill/creation data, and updates the Tatooine snapshot. The final 51-archive stage has 120 meshes, 428 instances, 165,061 rendered triangles and 173 textures. All 17 starport cells and 774 source dependencies validate. Actual starport geometry and materials are unchanged from the base media. Modern Core3 compatibility is assessed independently.

`python3 tools/assets/audit_formats.py` performs a read-only slot/schema audit and inventories critical resource forms in `runtime/asset_reports/retail-format-audit.json`.

## Scene contract

`scene.json` has `schema_version: 1`, `origin`, `spawn`, `spawn_yaw`, `meshes`, `instances`, `warnings`, `statistics`, and `provenance`.

`origin` is the original SWG X/elevation/Z coordinate `[3618.98388671875, 5, -4801.0859375]`, from snapshot object 1106368. Geometry and instance positions mirror original Z into Godot Y-up coordinates. Positions are relative to origin. Rotations are Godot `[x,y,z,w]` quaternions; `spawn_yaw` is radians.

Each mesh has `surfaces`, each with flat `vertices`/`normals` xyz arrays, `uv` xy pairs, triangle `indices`, optional `colors` rgba float values, and a `texture` path relative to the manifest directory. Indices have Godot clockwise front-face winding. Each instance has `mesh` (mesh-map key), `position`, `quaternion`, `object_id`, and `source_template`.

The 17 original portalized starport cells are loaded together at their actual relative coordinates, including the exterior and actual interior floors/walls. The importer exports original authored collision extents and complete FLR support data separately from the render triangles; explicit NULL declarations have no blocking collider, while missing or unsupported declarations retain a reported visual-mesh fallback. The spawn is in foyer4 at local Godot `[-60, 2, 10]`, yaw `0`, verified against the actual floor and walls. No substitute terrain plane or proxy building geometry is introduced.

## Portal-cell ownership

The manifest additionally preserves the original starport's `cells` map, keyed by `building_object_id:cell_index`. Each cell includes its name, `is_exterior`, scene-local floor vertices/triangle indices, geometry bounds, and original portal polygons with adjacent-cell keys. All 17 starport mesh instances carry matching `cell_id`, `cell_name`, `building_object_id`, and `is_exterior` fields.

This ownership is essential: the exterior r0 hull intentionally overlaps interior room space. When all cells were flattened, moving left from spawn crossed an exterior wall triangle after 1.269 metres despite the actual foyer wall being 9.067 metres away. Backface culling alone hid the plane from one side but did not prevent it appearing and colliding after the player crossed it. Original floor support and portal connectivity identify cell ownership. Hiding an entire exterior hull is insufficient: the medium-house r0 also contains the exit stairs above a basement. Runtime support selection must prefer the nearby exterior stair floor over a buried room and retain exterior support geometry at doorways. This is a cell visibility/collision issue, not terrain or an incorrect world transform. Terrain comes from the separate original-rule evaluator, with source-floor masks inside the retained starport.

Known classification checks: spawn `[-60,0.64,10]` and the reported overlap location `[-62.9,0.64,12.7]` lie in foyer4; `[-60.4,1.2,21]` lies on the ticket1 stair/ramp floor. `[-85,0.1,1.6]` is outside every interior floor. The runtime currently uses room ownership rather than complete portal clipping; an exterior view through a doorway still requires the later portal-aware rendering work.

## Static-stage converter boundaries

Supported: TRE v5/zlib, nested IFF, snapshot placement, template inheritance, APT, static MESH v4/v5, closest LOD, POB cell geometry, base diffuse shader textures, vertex colors. Shader animations use the first texture frame. A bounded set of nearby original static buildings and props is included.

The bounded stage importer omits five creatures and two particle effects explicitly. The character pipeline supplies skeletal avatars, while the terrain and world pipelines below supply outdoor terrain and snapshot exteriors. Original portal occlusion, dynamic doors, particle effects, lights, and exact shader behavior remain incomplete. Authored collision extent and FLR graph export are now supported.

The converter derives data from TRE records on demand, checks decompressed sizes, and records every loaded dependency's archive, size, and SHA-256. `media_inventory.json` records full original media/archive hashes. All converted proprietary art remains local and must not be committed or redistributed with the code.

## Format references

Implementation was informed by public format readers and verified against the supplied files:

- SWGEmu Core3 snapshot parser: `vendor/Core3/MMOCoreORB/src/templates/snapshot/WorldSnapshotNode.h` and `WorldSnapshotIff.cpp`.
- [io_scene_swg](https://github.com/nostyleguy/io_scene_swg_msh), MIT, Nick Rafalski; inspected revision `cdb1cdbbe172a7d46740762f92de855dc60920c7` for MESH/POB/vertex-format structure. The converter does not import Blender or vendor this add-on.
- [Swg.Explorer](https://github.com/wverkley/Swg.Explorer), inspected revision `671fe8041038fc83687868fe6cfb5a3e9483c1e3`, for TRE layout.
- [unshield](https://github.com/twogood/unshield), pinned bootstrap revision `cbed3d19ef9cdf4e5fb86b9d65e48f1bf8d539db`, for extraction of InstallShield cabinets. Its own license accompanies the local checkout.

## Authentic playable characters

`python3 tools/assets/prepare_characters.py` reads the active, local 51-TRE set
and writes ignored `runtime/assets/characters/catalog.json`. Defaults include all
20 species/sex variants, every available original hairstyle, original default
and six profession outfit tables. Original SAT/LAT/ASH animation references
are resolved by `character_animations.py`; body and face clips retain source
selector decisions and explicit coverage limitations. For a quick subset use
`--races human_male human_female --hair-limit 3`; `--hair-limit 0` disables hair
conversion and the default `-1` selects all. Run
`python3 tools/assets/validate_characters.py` afterwards.

Body, hair and clothing model JSON share the race's merged body/face skeleton.
SKT bone names determine global mesh joint indices. Each surface has eight joint
indices/weights per vertex, original UV/normals, sparse MGN morphs expanded to
relative arrays, and source occlusion zones per triangle. Clothing `occludes`
zones suppress matching lower-layer body/clothing triangles. `skin_body.sht`
material references resolve against that race's actual body shader. Clothing
appearance siblings select source male/female and Wookiee/Ithorian meshes when
present. This is local conversion of supplied assets, never replacement models.

The catalog retains the original character customization table rows, height
bounds, all source hairstyle names, private/shared palette paths, palette colors,
and conversion availability. Face skin palette metadata is recovered from the
MGN's texture-renderer reference. All seven referenced original facial renderers
are decoded, including authored beard, eyebrow, makeup, lip, freckle, tattoo and
skin-highlight layers. Their available controls are enabled only when the
corresponding source operation is supported by the runtime shader.
Three original references are absent from this media set: human female hair33,
Rodian female hair11 and Ithorian male jacket16. They are reported explicitly;
all twenty body meshes are available.

Animation data exports named `animations` clips and a lazy `animation_library`,
each clip containing `fps`,
`length`, source ANS filename and per-bone `rotations` / `positions` key lists.
The first component is time in seconds. Rotation components are Godot xyzw;
positions are absolute local bone positions. Original KFAT/CKAT integer frame
indices, separate translation channels and compressed quaternion windows are
decoded. Local rotations compose `RPST * animation * BPRO * RPRE`; translations
add the bind translation. SWG Z is mirrored consistently for skeleton, mesh,
morph and animation. Original locomotion root-motion chunks are deliberately
not applied because the gameplay controller owns movement. Source selectors,
state/action coverage and unavailable references are recorded in `animation_graph`.

Format references include the public MIT
[io_scene_swg importer](https://github.com/nostyleguy/io_scene_swg_msh) by Nick Rafalski
(SKT/MGN and ANS format notes) and the public
[SWG toolkit animation format documentation](https://github.com/kennethlong/swg-toolkit/blob/main/docs/02-formats/skeletons-and-animation.md)
for CKAT packing. The parser implementation here is independent; no original
client implementation is bundled or required. The upstream MIT notice is
retained in `THIRD_PARTY_io_scene_swg.txt` for reference.

Character transparency comes from the original effect implementation's `ALPH`
sort bucket or its first `PASS/0009` alpha-test flag. Surface `alpha_source`
records this evidence. The client currently approximates these materials with
alpha scissoring, which removes rectangular Wookiee fur/hair cards without
mistaking opaque textures' specular alpha channels for transparency; original
multipass blending is not reproduced.


## Facial texture renderers and character color masks

`facial_materials.py` exports the original BTRT layer draw order and vertex/UV
rectangles, SSTC fixed textures, SST1 style selectors and STFP palette factors.
The seven referenced recipes use only supported copy and alpha-blend operations;
unknown commands fail conversion explicitly. `TX1D` selectors export original
age/wrinkle maps and species pattern variants. Surface metadata also retains
MAIN/HUEB/NRML/CNRM bindings, secondary-palette alpha masks and normal encoding.

`client/scripts/avatar_materials.gd` resolves customization values with original
private/shared paths and passes textures/colors to the native Godot spatial
shader `client/shaders/avatar_material.gdshader`. That shader evaluates up to six
source layers in their authored rectangles. It handles the separate transparency
and hue masks of Wookiee fur, both original palette colors, ordinary and compressed
normal maps, and the original surface alpha classification. Colors, textures and
geometry are source assets; no generated or replacement overlays are used.
Lighting is Godot lighting; original environment/specular multipass behavior and
soft transparent fur blending remain approximations.

Run `python3 tools/assets/validate_facial_materials.py` for the reachable asset
and selector checks. Run `godot --path client --xr-mode off --rendering-method forward_plus --rendering-driver vulkan
--script res://tests/facial_material_smoke.gd` on a graphical display for real
human/Zabrak/Twi'lek/Wookiee source-material comparisons. Both animation players
are paused during each comparison, so changed pixels measure customization
rather than motion. Evidence is written to ignored `runtime/evidence/facial/`.

## Full Tatooine terrain and world snapshot

```sh
python3 tools/assets/prepare_terrain.py
python3 tools/assets/prepare_terrain_context.py
python3 tools/assets/prepare_world.py
```

Terrain manifests and converted textures live in `runtime/assets/terrain`; the
native evaluator samples the full original PTAT rule tree on demand. The context
pass audits all 415 source buildings for explicit terrain modifications and masks
the retained starport interior with its original FLR floor triangles. See
[TERRAIN.md](TERRAIN.md) for source rules, material limits, parity checks and license.

`runtime/assets/tatooine_world/world.json` indexes the original static snapshot
into 256 m chunks with shared per-mesh JSON and textures. POB interior data is
preserved for later streaming, while this milestone loads exteriors beyond the
retained starport. NPCs, particles and sound simulation are excluded and recorded.
All source data and converted output remain ignored, including provenance hashes.

## Full Tatooine static snapshot

`python3 tools/assets/prepare_world.py` converts every static, building and
tangible placement, including hierarchy-owned interior furnishings, in the original `snapshot/tatooine.ws` into ignored
`runtime/assets/tatooine_world/world.json`. It leaves the verified Mos Eisley
stage unchanged. `--chunk-size` defaults to 256 metres; `--tre-dir`, `--out` and
`--stage` select explicit local inputs/outputs. Run
`python3 tools/assets/validate_world.py` for geometry/placement/provenance checks.

The prepared snapshot contains 14,455 placed objects and 16,294 mesh instances,
using 1,036 shared meshes in 272 chunks. All 1,959 POB cells retain original floor
triangles, portal neighbors and exterior/interior ownership. CMPA components
are resolved and their authored matrices baked into reusable meshes, including
Jabba's palace, the Lucky Despot, Fort Tusken and garages. The converter records hashes for every original dependency. Original static shaders use diffuse textures and
source alpha classification; animated displays currently use their first frame.

The 260 excluded snapshot placements include sound emitters, particle effects
and skinned/animated appearances. These are individually listed in
`conversion_report.json`; no replacement objects are generated. Four water containers (objects 4925785, 1493863, 5285750 and 5285751)
share `appearance/mesh/con_gen_inorganic_water_l0.msh`. Its first surface
(44 triangles) references `shader/phong1.sht`, an `OPST0000` object-material
alias named `body`, rather than a textureless material. No owner binding was
found in their static templates/appearance; geometry and collision remain
available with an untextured fallback. See the local
`runtime/evidence/world-material-limitations.json` for exact placements. One original wall (1525427) has source elevation 3,093,066 metres. Its
unaltered source placement is recorded under `source_elevation_outliers` so it
cannot be mistaken for a conversion transform error.

The world manifest maps mesh IDs to individual JSON paths and bounds, and chunk
keys to JSON paths/bounds/counts. Positions use the same starport origin and
mirrored SWG Z as the existing stage. Textures are relative to the world root.
`existing_stage_object_ids` describes possible overlap; the streamer actually
uses the retained stage's instance IDs to avoid duplicate render/collision.

`client/scripts/world_stream.gd` exposes `configure(manifest_path, existing_stage)`
and `update_observer(scene_local_position)`, plus its `report` dictionary. It
streams exterior buildings/props by observer distance, constructs meshes/shapes
through native `SwgMeshBuilder`, enables nearby collision, unloads distant chunks
and evicts unused mesh resources. Every interior furnishing stays in its owning building chunk, even if its
position crosses a chunk boundary. The runtime uses the original floor/portal
cell ownership to stream interiors and suppress the exterior shell from inside.

`godot --headless --xr-mode off --path client --script res://tests/world_stream_smoke.gd` checks
actual streamed geometry collision, existing-stage deduplication, distant-city
loading, chunk removal and the bounded mesh cache. Terrain comes from the
separate original-terrain evaluator; this converter does not synthesize ground.

### Original locomotion cadence audit

Character ANS decoding retains `source_speed_mps` from the original `LOCT`
chunk, `source_cycle_displacement` in Godot coordinates, and the ANS SHA-256.
These describe authored visual cadence; they never move the gameplay body or
XR origin. The tracked lower-body sampler scales cadence against measured
velocity and avatar visual scale. Source walk/run speeds are approximately
1.549/5.132 m/s, with 1.1/0.733 second cycles. Directional and crouched walking
use their own source values.

`python3 tools/assets/audit_locomotion.py` verifies the LOCT average speed
against source displacement/duration and samples reconstructed ankle, toe,
head and root heights for all 20 source skeletons. Its ignored JSON evidence
includes source hashes and original footstep markers. The original `crouch`
clip is one-knee kneeling; VR stationary physical crouching instead uses the
standing source pose with tracked height and leg IK. Crouched locomotion uses
the original crouched walk clip. No independent leg tracking is claimed.

## Ambient NPCs and source environment

Generate reproducible Core3 city placements with
`python3 tools/server/export_ambient_npcs.py --city all`, then export their exact
original appearances with `python3 tools/assets/prepare_npcs.py`. The ignored
`runtime/assets/ambient_npcs/catalog.json` uses the existing Avatar catalog
schema keyed by source template plus resolved outfit/weapon variant. Each NPC resolves its actual shared
mobile template, SAT skeleton/body, original LAT idle/mood clip, CDF `CSSI`
customizations and **all** `MESH` records in every `WEAR` block, retaining each
block's `WCSI` colors. No generic player character replaces a missing NPC.
Unsupported mood names and missing wearable files remain explicit. Placements
are deterministic Core3 source selections, not live server NPC replication.

Core3 `outfit` definitions are preserved independently of the NPC's CDF.
`core3_outfit` records the source group, deterministic variant, object templates,
customizations, file hashes and line numbers. `source_primary_weapon` retains the
first source-authored primary weapon candidate and explicitly labels it ambient
presentation, not live equipped state. `appearance_id` includes the outfit and
selected weapon, preventing different equipment sets on the same body from
sharing a descriptor. Primary/secondary weapon state is not simulated; intrinsic
droid, creature, unarmed and vehicle weapon objects are excluded.

`prepare_npcs.py --refresh-outfits` incrementally updates equipment using existing
body/CDF data. Original CDF clothing remains intact; additional original skinned
wearables/hair enter `default_outfit` with their exact customization values.
Rigid equipment enters `rigid_equipment` separately, with a converted static
model, the source arrangement slot matching an actual skeleton bone, and an
explicit row-major 3×4 local transform. Instrument appearances contain no grip
hardpoints: their original object origins bind directly to animated `hold_r`.
No guessed grip offset or collider is generated. An explicit outfit item takes
precedence over a primary weapon requesting the same bone.

The current local data exports all 42 items in seven outfits: 38 clothing/hair
items and four band instruments. Another 445 placements receive supported
original primary-weapon visuals through 69 equipment variants; three intrinsic
probot weapons are excluded. There are 21 shared rigid models across the band
instruments and primary weapons. All new outfit/equipment conversions succeed.
Two pre-existing CDF wearable references remain missing in the supplied active
archives and stay in `catalog.failures` (a Valarian leader hat and Desert Demon
gloves). Run `python3 tools/assets/validate_npc_outfits.py` to verify all source
hashes, CDF preservation, customization, mesh weights and authored attachment
slots. `outfit_report.json` records per-variant coverage and any unsupported items.

Jawa source geometry contains six vertices with 38 influences: one dominant
weight and an identical baseline on every other joint. Their skinning can be
represented exactly by two weighted matrices, the dominant joint and a virtual
uniform average of the 38 original skin matrices. `virtual_skin_bones` records
this runtime requirement; `virtual_skin_audit` retains the original positions
and complete normalized influence lists. Other dense patterns are rejected;
this conversion never silently prunes weights.

`python3 tools/assets/prepare_environment.py` exports ignored
`runtime/assets/tatooine_environment/environment.json`: 17 original Tatooine
families, all 85 source weather rows, 256-sample sky/lighting ramps, celestial
shader references, geographic source rules, sound definitions, original audio
converted to Ogg, 112 hierarchy-transformed snapshot sound emitters, and 17
original NPC `ASND` emitters at their authored Core3 placements. Run this
export after `export_ambient_npcs.py --city all`; only continuous/random ambient
CDF `ASND` references are used, not combat or triggered voice events. The
first/night/sunrise/sunset music and ambient selections come directly from the
original environment datatable. One source reference,
`sound/music_event_explore.snd`, is absent from the supplied archive set and is
recorded instead of replaced.

Source sound loop counts, delay ranges, fade ranges and volume ranges are
retained along with the numeric template bytes. The prototype 3D distance
policy and two-hour day duration are explicitly labeled implementation choices.
Likewise, mapping the first two color-ramp rows to ambient/direct presentation
colors is unverified; every raw RGBA row is retained for later refinement.
Gradient sky colors come directly from the original texture. Original vertex
colors exist on 371 of 1,036 static meshes (509,796 of 854,799 vertices); they
must not be described as a complete original baked-lightmap solution. Runtime
lighting may precompute fixed shading and blend day/night tint without dynamic
light sources or shadows, as requested.

`python3 tools/assets/validate_environment.py` verifies source hashes, all
lighting/sample references and the decoded Ogg streams using ffprobe.


## Authored collision and floor schema

Stage and world schema version 2 share `StaticAssets.place`, so retained buildings
and streamed instances have identical transforms and POB ownership. The retained
medium house 1280129 and hospital 9655494 now keep all their cells, including r0.
The 428 retained instances match the corresponding world instances exactly.

`collisions[collision_id]` records the owning source appearance, status
(`authored`, `null`, `missing`, `unsupported`), explicit fallback policy, and an
instance-local Godot extent tree. Supported source extent types are EXBX boxes,
EXSP spheres, XCYL cylinders, CMSH triangle meshes, CMPT components, CPST unions,
and DTAL coarse/detail groups. Detail groups preserve the coarse first child;
consumers should use remaining detailed children for blocking when present.
Component transforms are explicit row-major 3x4 Godot matrices, with translation
in elements 3/7/11. Cylinders use an authored base and extend along positive Y.
Each placement has `collision_id` and `collision_owner`; only the owner creates
an authored collider when several visual parts share the same extent. POB CELL0005 owns a separate collision extent after its DATA record; the importer
exports this tier as `source.pob#cell:index` and assigns it to that cell’s visual
parts. All eight supplied cases with both an authored cell extent and authored
APPR extent contain identical geometry. NULL is preserved as NULL with
`fallback: none`; only missing or unsupported declarations allow visual fallback. `collision_report.json`
records all fallback sources and affected object/mesh IDs.

Every POB cell, including exterior r0, retains `floor_vertices` (flat stage-world
Godot coordinates), solid `floor_indices`, and all original `floor_triangles`.
Each triangle preserves `id`, vertex `indices`, signed `neighbors`, transformed
`normal`, exact stored SWG `source_normal_raw`, three `edge_flags`, `fallthrough`, signed `tag`, and signed `portal_ids`.
Flags are 0 uncrossable, 1 crossable, 2 wall base, 3 wall top. Older FLR versions
0003–0005 store crossable booleans; 0006 stores edge enum values. `-1` is the absent
neighbor/portal sentinel. FLR versions through 0006 store inverted normals: the
original reader negates them after load. Exported `normal` applies this correction
and cells declare `floor_normals_corrected: true`; `source_normal_raw` remains
unmodified in original SWG axes. Consumers must not flip the corrected normal a
second time or force genuinely inverted/nonwalkable art triangles upward. Critically, a floor portal ID is the **cell-local index**
into `cell.portals`, not the POB polygon's global `id`; each portal also exports
`floor_portal_index`, reciprocal `leads_to`, passability and world-space polygon.

Standalone APPR floors on rock arches, bridges, sandcrawler and nonportal
buildings are retained too. Their placed regions use `object_id:floor:hash` keys,
`is_exterior: true` and `building_object_id: 0`; they supply ground support without
claiming an interior or punching a terrain cutout. Current supplied media yields
1,959 POB cells plus 511 standalone floor placements. The world contains 531
authored extent definitions (including 277 POB cell extents and transformed
component variants), used by 7,946 mesh instances. Another 8,348 instances
explicitly declare NULL collision; none is silently converted to a visual collider.
There are no collision/floor conversion errors in this supplied archive set.

Validate with `python3 tools/assets/validate_collision.py`. Pass `--stage`,
`--world` and `--baseline runtime/assets/tatooine_world` to compare a separately
prepared review export before activation. It validates full floor connectivity,
portal index bounds, extent trees, retained/world ownership and unchanged visual
geometry/transforms. `validate_world.py` additionally verifies all 6,171 source
hashes. The collision change preserves all 1,036 static meshes and 16,294 placed
mesh transforms exactly; the source `phong1.sht` alias limitation above remains.

### Datapad reference assets

`python tools/assets/prepare_datapad.py` exports the supplied original Tatooine
1024×1024 planet map, original map markers, datapad tabs/help, waypoint colors,
client POIs, and three original Verdana bitmap-font atlases to ignored
`runtime/assets/datapad/catalog.json`. Use `--tre-dir`, `--out`, and
`--core3-root` to select sources/output. `python tools/assets/validate_datapad.py`
checks source hashes, map bounds/projection, glyph atlas bounds and icons.

The map uses SWG coordinates: image right is +X, top is +Z, and its full bounds
are [-8192,-8192,8192,8192]. The catalog adds seven city centers from checked-out
Core3 regions and 32 exact original world-snapshot building positions, preserving
source object IDs/templates. Marker family assignment is explicit derived UI
metadata. The original planet image is not a high-resolution city map.

`ui.fonts[].path` is an AngelCode BMFont text file, loadable with Godot
`FontFile.load_bitmap_font(absolute_path)`. FontCharacter atlas rectangles,
advances and leading are retained; baseline defaults to source leading. These
are proprietary original game atlases supplied by the user, not a redistributed
open font. Generated fonts/images remain ignored with other user assets.

This is reference information, not a character inventory. Original tabs are
Waypoints, Group Waypoints, Data, POI and Draft Schematics. Original help states
that POIs and learned draft schematics consume no datapad space. No pets,
vehicles, waypoints or schematics are granted by the importer. Core3's common
starting items include an X31 landspeeder **deed in inventory**, which must not
be presented as an already-created datapad vehicle. Existing-character entries
must come from the authoritative backend. Preview appearance paths are source
references only; this importer does not convert their 3D models.

After the original NPC catalog exists, optional reference object thumbnails can
be rendered with:

```
godot --xr-mode off --path client --script ../tools/assets/render_datapad_previews.gd
```

This currently renders the exact original helper R2 mobile appearance/CDF to a
transparent PNG and records model/catalog hashes in `template_previews` and
`previews/manifest.json`. The datapad exporter retains this manifest on subsequent
runs. The UI uses the thumbnail only for an authoritative matching item entry.
Core3's `SpawnHelperDroidTask` can grant that genuine pet control device after
eligible starting skills outside the tutorial; an initially empty datapad is
therefore not evidence that it stays empty. Actual server readback remains the
source of ownership. The preview records authored default customization, not an
assertion that every player's droid has identical customization.

## Original interior layouts and soundscapes

Building templates also reference `interiorLayoutFileName`. These `INLY/0000`
files contain decorations and sound objects by **named POB cell**, with a rigid
3×4 transform local to the building. `interior_layout.py` resolves inherited
properties, verifies rigid transforms and cell names, and composes the original
building transform before mirroring SWG Z. Both stage and world conversion now
include these placements. The world keeps them in the owning building's chunk.

Generated instances retain `source_layout`, `source_layout_index`, and the raw
`source_layout_transform`, alongside ordinary `cell_id`, `building_object_id`,
mesh and authored collision fields. Their stable negative IDs are local render
identifiers, not Core3 object IDs. Decorations use the same source collision
rules as other objects, including explicitly nonblocking NULL extents. An
unsupported component particle does not discard the component's static mesh;
each omitted child remains in the conversion report.

Refresh an existing world without rebuilding terrain or the planet's snapshot
geometry:

```sh
python3 tools/assets/prepare_world.py --refresh-interiors
python3 tools/assets/prepare_environment.py
python3 tools/assets/validate_interiors.py
python3 tools/assets/validate_world.py
python3 tools/assets/validate_environment.py
```

The local fixture restores 7,114 static placements from 25 layouts across 48
buildings. Mos Eisley cantina, object 1082874, has all 258 original static layout
entries plus the two original sound objects. `interior_layout_report.json`
records 276 wholly unsupported placements elsewhere (particle appearances,
skinned props, empty source entries or no static appearance) and nine omitted
component children. These are converter/source limitations, not replacement
assets. The converter records hashes for every layout and dependency.

Environment conversion exports `interior_soundscapes` from the original
`datatables/interior/interior.iff`, keyed by `<POB stem>:<cell name>`. Lookup uses
the exact cell, `<POB stem>:default`, then `default:default`; an explicitly empty
cue remains empty. Entries contain original `day_ambient`, `night_ambient`,
`first_music`, `room_type`, source row and unmodified source fields. Layout ASND
sound objects use the normal `emitters` schema with cell ownership and layout
provenance. The Figrin D'an recording and cantina ambience are original supplied
samples. One unrelated interior-table cue, `sound/music_event_explore.snd`, is
absent from the active archive set and reported without a substitute.

`validate_interiors.py` compares the exported basis and translations against
independent original matrix application, verifies POB ownership and collision
references, and checks sound provenance. It does not validate headset rendering
or audibility.

## Original inventory item appearances

`prepare_inventory.py` incrementally prepares original item models selected by
an authoritative inventory snapshot. It grants no possessions and never writes
the snapshot back to Core3. Initial source creation-manager candidates can be
prepared before the first login:

```sh
python3 tools/assets/prepare_inventory.py --starter-items
python3 tools/assets/prepare_inventory.py --snapshot runtime/evidence/inventory-live-snapshot.json
python3 tools/assets/validate_inventory.py --snapshot runtime/evidence/inventory-live-snapshot.json
```

Repeat `--snapshot` or `--template object/.../item.iff` for additional selections.
Server and shared-template paths both resolve to the same item entry. `--refresh`
reconverts existing entries, for example after changing the active archive set.
The importer writes `runtime/assets/inventory/catalog.json` atomically, retaining
previous entries. Models/textures are local ignored assets; caller ownership,
quantity, equipment and object IDs remain in the backend snapshot.

The version-1 catalog provides `items[server_template]`, shared-template
`aliases`, and `generic_backpack.template`. Ready descriptors contain `model`,
`model_sha256`, `appearance`, `source_meshes`, `material_pipeline`, actual
`bounds_min`/`bounds_max`, `source_arrangements`, and conversion statistics.
Model JSON uses the existing static `surfaces` arrays and catalog-relative
texture paths. Original SAT/MGN wearables are frozen at their bind-space
vertices for item presentation; this does not implement equipping or animated
clothing. These surfaces retain original palette/texture-selector data and use
`AvatarMaterials` (`original_character`); ordinary static surfaces use
`StageLoader` materials (`original_static`). Each model keeps its original
origin. Preview fit/rotation belongs to the UI, not source conversion.

The fallback presentation bag is original `backpack_s01`, proven to share its
mesh with the original `dressed_ranger_trainer_01` CDF wearable. It is not a
granted inventory object. There is no authored hand-grip transform for this
backpack; `held_transform` is explicitly null and source `back` arrangements
remain metadata. An equipped backpack from the snapshot takes precedence.

Unsupported previews have `status: unsupported`, an explanation and no model;
no placeholder mesh is labeled original. Provenance records every consumed TRE
dependency, snapshot-selection hash, and Core3 creation-definition hash.
`validate_inventory.py` checks those hashes, model integrity, exact bounds,
triangle indices, material files, source NPC backpack evidence, and optional
complete snapshot-template coverage. It does not claim GPU or headset validation.

Authoritative snapshots containing `race` also prepare
`equipment[race][server_template]`. Pass `--equipment-race human_male` explicitly
when preparing a standalone template without a snapshot. These descriptors retain
original skinned geometry, bones, skin weights, occlusion layers and source slot
arrangements. Original owner-bound OPST material aliases resolve against that
race's original body shader; palette/customization controls remain live. The
previous unsupported shirt preview can therefore render once its actual owner
race is known, without an arbitrary skin texture. Rigid equipment retains its
original origin and source arrangements. Body-model and original shader hashes
link every wearable to the rig/material used for conversion. A wearable requiring
new virtual bones is reported unsupported rather than altering a tracked rig.

`Avatar.refresh_equipment(equipment)` replaces render meshes and recalculates
original clothing occlusion while retaining the existing skeleton, animation
players, tracked pose, calibrated transform and physical height. An explicit empty
equipment array removes gear without restoring starter clothes or removing body
and hair. `set_equipment_visual_hidden(ids, templates)` suppresses only equipment
whose presentation is owned by another system, such as the local combat rig.
Unknown source models remain explicit failures. The native mesh and original
material paths are shared with normal avatar rendering.

Gathering assets are prepared with `prepare_inventory.py --gathering-assets`.
The list comes from concrete Core3 survey-tool and resource-container definitions,
including their exact registered client template mappings. Resource containers
frequently use `shared_resource_container_...` names, so deriving a shared name
from the server filename is incorrect. All ten survey tools and 39 concrete
resource-container definitions in this checkout convert from the supplied TREs.
These reference models grant no items or resources. Mutable backend selections
are copied to ignored content-addressed `selections/<sha256>.json` evidence before
being added to the provenance ledger; original TRE/model hashes stay strict.

`prepare_corpses.py --planet tatooine` derives corpse references from concrete
Core3 Tatooine `Creature:new` definitions with positive meat/hide/bone amounts
and nonempty source resource types. In this checkout 95 source definitions map
to 42 original templates and 22 unique frozen models; all convert successfully.
Humanoid NPCs and animals from other planet folders are not selected by guessed
names. Exact source definition paths/hashes remain in the catalog.
`--template object/mobile/worrt_hue.iff` prepares one original animal, while
`--snapshot FILE` selects actual templates from its `corpses` array. The source SAT, skeleton, weighted MGN geometry and
ASH/LAT-selected incapacitated ANS frame are converted to a frozen mesh once;
there is no per-corpse skeletal animation evaluation. Dense skin influences
(such as bocatt) use the exact affine average of source skin matrices, preserving
all original influence weights rather than dropping small contributions. Worrt uses the original
30-bone frog skeleton and `frog_std_incapacitated.ans`. This is explicitly an
original incapacitated pose used to present an authoritative dead creature, not
a separately authored death clip. Source palettes remain configurable and actual
meter dimensions are retained. Unsupported species/poses remain explicit errors.
`validate_corpses.py` verifies source/model hashes, source pose lineage, geometry,
textures, exact posed bounds and inverse-bind/quaternion conversion numerically.

`deployed_resource_tools.gd` presents server-confirmed tool states, reserving real
tool IDs while retaining generation-qualified deployment IDs for pickup. It
checks loaded authored FLR/terrain collision, outdoors, slope and a full small
footprint before placement. A tool floats 1.2m above its unchanged source sampling
point, with one six-sided unshaded beam to that point. Counts come from confirmed
buffers. Up to 32 nearest tools within 64m render; hidden tools keep authoritative
state and reservations. `corpse_visuals.gd` applies the same visibility budget
with no local yield/loot authority. Its hover query returns a copied source record
and exact world bounds of the frozen original animal for the harvest UI.

Headless `deployed_resource_tools_smoke.gd` and `corpse_visuals_smoke.gd` test actual
original models, starport FLR support, hover endpoints, unchanged backend records,
render limits and unsupported-asset handling. `gathering_world_capture.gd` requires
Forward+ Vulkan with `--xr-mode off`; its synthetic preview IDs/counts and desktop
image are asset/presentation evidence, not native loot or live headset validation.

Native live population preparation follows source spawn dependencies rather than
the handful of creatures present during one launch:

```sh
python3 tools/server/export_combat_population.py --out runtime/assets/combat_population/tatooine
python3 tools/assets/prepare_npcs.py --out runtime/assets/combat_population/tatooine --placements runtime/assets/combat_population/tatooine/appearance_requests.json
python3 tools/assets/prepare_inventory.py --population-lairs runtime/assets/combat_population/tatooine/sources.json
```

The source index selects all 61 Tatooine groups, 206 lair definitions and 264
appearance templates in this checkout. `--population-lairs` validates its source
file hashes and records an immutable selection before preparing original models;
it creates no game entities. Model origins remain in source meters, including
below-ground lair roots. Existing exact ambient/beginner catalog entries can be
excluded from the appearance request list to avoid duplicate conversion.

Supplied-media gaps remain explicit: the dressed rebel 21B medic references
missing `clientdata/npc/client_shared_dro_dressed_rebel_medic2_21b_01.cdf`.
Missing CDF data does not discard an available body: the exact shared template's
own SAT remains visible, with unavailable CDF clothing/customization reported.
Two authored filename defects now have explicit, bounded source-metadata repairs:
the desert demon/leader's unsuffixed chitin gloves and the Valarian swooper
leader's `hat_s04_hum_f.lmg`. Their original appearance-table entries, SAT mesh
references, owner skeleton bindings and matching male chitin CDF pieces establish
the replacement paths. Each repaired wearable retains the original broken
reference and its complete repair evidence. No generic similarly named or
opposite-gender mesh fallback is used.
The original group-only index missed named/static city NPCs; use the broader
preparation below for live world sessions.

`refresh_npc_death_poses.py CATALOG_DIRECTORY ...` incrementally adds each body's
ASH/LAT-selected `incapacitated_face_up` clip to existing catalogs without
rebuilding clothing. Standard NPC conversion also exports this lazy
`incapacitated` clip. A frozen skeletal actor can therefore retain its exact CDF
outfit when the backend reports DEAD. This remains an original incapacitation
pose, not a claim to reproduce the original death transition or gameplay logic.

Full source-defined Tatooine entity coverage is reproducible with:

```sh
python3 tools/assets/prepare_planet_entities.py --planet tatooine
python3 tools/assets/test_planet_entities.py
python3 tools/assets/test_entity_parser_regressions.py
```

This unions all planet mobile definitions, region lairs, and registered mobile
names in Tatooine-named/referencing screenplays, including static/named city NPCs,
random commoner alternatives, quests and literal informant registration factories.
It deliberately includes a conservative superset from mixed-planet screenplays;
it does not execute Lua or assert which actors are currently spawned. Dynamic
spawn expressions remain listed in `sources.json`, not silently evaluated.
Existing exact catalogs and CDF equipment remain intact. Only new missing
templates convert into `combat_population/tatooine_entities/catalog.json`, with
immutable request batches and accumulated source provenance. Repeated runs skip
previously attempted unavailable templates; `--retry-missing` retries after new
media is supplied. `--index-only` regenerates source/coverage reports without
converting assets. `coverage.json` records the supplying catalog and component
failures per exact template.

The current source union has 978 appearances from 931 mobile definitions and
104 screenplay files: 963 complete appearances and 15 partial appearances, with
all 978 original bodies available. Thirteen exact CDF/wearable filenames remain
absent after searching all 96 physically distinct locally extracted TRE archives;
`runtime/evidence/entity-media-gap-search.json` records each result. Binary load
lifter and Sy Snootles have no source ground incapacitation loop in their own LAT,
so their missing dead pose remains explicit rather than borrowed from another rig.

The broader audit also corrected KFAT0003 locomotion metadata to use the original
16-bit key count/frame format, restoring original blastromech/treadwell gait
clips. Acklay's dense influences now combine equal-weight source joints into an
exact affine mean while retaining all other influences; none are pruned. The
parser regression test independently expands all 15 affected vertices back to
their original joint weights. Headless client catalog tests separately instantiate
the complete exact-template union; neither test claims live headset validation.

Service terminals, wallet and shuttles
------------------------------------

`python tools/assets/prepare_services.py` adds a compact local source catalog at
`runtime/assets/services/catalog.json` and prepares the original credit-chip,
travel-terminal and ticket-collector appearances in the inventory model catalog.
The source catalog includes all original Tatooine bazaar/bank/mission/crafting
placements and the native travel-point names. Negative ILF placement IDs are
explicitly marked `client_layout_placement`; they are not Core3 object IDs.
Even positive snapshot IDs require live discovery before any transaction.

Both original shuttle variants retain their SAT skeleton and ANS landing,
takeoff, ground and sky clips. The transport hull, three struts and door come
from five original CDF HOBJ hardpoint attachments. Source transforms and root
travel remain intact; humanoid grounding/root-motion removal is inappropriate
for this vehicle. `service_world.gd` renders native shuttle state, derives the
transport's walk-up threshold from the actual animated ramp's lowest vertices,
and uses the native collector anchor for the shuttleport model, which has no
separate source door bone. Neither assets nor the renderer manufacture boarding
authority, schedule, prices, tickets or credits.

`python tools/assets/test_services.py` verifies reference classification, unique
source placements, original attachment bones/geometry/textures, clip provenance,
and input hashes. `service_world_smoke.gd` and `service_peer_smoke.gd` exercise
source-model rendering setup and native IK with headless mocked service data.
Always use `--headless --xr-mode off`; these tests do not validate live VR.

`prepare_bazaar_categories.py` reads a locally inspected original
`SharedObjectTemplate.h` reference plus the user's `string/en/got_n.stf` labels.
It exports numeric GOT categories/subtypes, original localized sorting, the
All root and parent/child IDs to `services/bazaar_categories.json`. Reference
URLs and hashes are recorded there. The later NGE commodity exclusion table is
absent from all supplied media sets; the export reports this and does not
invent exclusions. Per-template NGE market leaves and resource-class subtrees
need separate native filters, so they are not mislabeled as GOT subtypes.

`prepare_services.py` also runs `audit_trainers.py`, exporting
`services/trainers.json` from original Core3 trainer definitions, user-media
`skill_teacher`/`mob/creature_names` strings and prepared ambient placements.
It covers the six basic professions, their original 18-skill lists, three
appearance alternatives each, and 51 Tatooine trainer placements with source
world/cell coordinates and hashes. Run the audit alone to refresh this small
reference without reconverting shuttle models. All trainer appearances reuse
existing ambient or original Tatooine entity catalogs. Native trainer IDs,
eligibility and transactions remain authoritative. Source placement matching
allows only documented same-trainer variants within 25cm in the same native
building and cell; the service renderer never adds a second trainer actor.

## Original ground planets and travel destinations

`python3 tools/assets/prepare_planets.py` prepares the ten original ground worlds:
Corellia, Dantooine, Dathomir, Endor, Lok, Naboo, Rori, Talus, Tatooine and
Yavin IV. It runs converters serially to bound memory use. Resume with the same
command; `--planets naboo corellia` selects a subset. Existing Tatooine paths and
its verified Mos Eisley origin remain unchanged. New worlds use SWG origin zero
and stream their complete snapshots, including original POB interiors, portal
ownership, FLR floors, authored collision declarations and ILF decorations.

The local `runtime/assets/planets/catalog.json` contains a `planets` dictionary.
Each descriptor exposes `planet`, `origin`, `ready`, `failures`, absolute local
`terrain`, `terrain_context`, `world`, `environment`, `services`, `trainers`,
`ambient_npcs`, `ambient_placements`, `entities`, `entity_catalogs`, `inventory`,
`corpses`, `datapad` and `stage` paths. Empty `stage` means the world streamer
owns all geometry; it never means substitute terrain or a proxy building.
`travel_points` and `default_entry` come directly from Core3's planet manager.
They are reference positions, not authorization to board or travel.

Shared datapad export now includes all ten original map rasters, source POIs,
cities and service buildings. `complete_planet_features.py` prepares original
lair models in the shared inventory catalog, harvestable corpse poses, trainer
references and the explicit appearance-catalog union. Exact source models may
be reused across worlds; clients must consult `entity_catalogs` rather than
assuming every reused model is copied into the current planet's directory.
No local ambient placement, source travel point or model cache is live state.
Native Core3 still controls spawns, tickets, schedules, prices and transactions.

Cache state records converter hashes. Existing outputs are adopted only after
recorded source dependencies validate; later converter or source changes trigger
reconstruction. `--force` explicitly rebuilds selected components. A diagnostic
`--skip-entities` pass does not claim full supported-feature readiness.
Run `python3 tools/assets/validate_planets.py` to audit coordinate agreement,
original travel positions, map availability, every exported mesh/cell/portal and
source dependency hashes. Render/headset validation is separate.

Readiness means the supported component manifests exist, not that every original
renderer effect has been reproduced. `source_asset_limitations`,
`terrain_rule_limitations`, `architecture_omissions` and `collision_coverage`
retain exact missing/partial conversion counts and source records. Original
procedural detail flora/weather and multipass shaders retain the prototype's
existing limitations. NULL collision declarations deliberately produce no
blocking shape. Kashyyyk and Mustafar are outside the pinned pre-CU planet set
and lack terrain/snapshot records in active media; the catalog reports them as
unsupported, with no fabricated environments or travel destinations.

## Factory references

After `python3 tools/assets/prepare_housing.py`, run
`python3 tools/assets/prepare_factories.py` to prepare all four native factory
deed previews and nine output-crate appearances, and audit the matching clothing, food, structure and item factory
geometry. The ignored `runtime/assets/factories/catalog.json` records Core3 deed
definition hashes, preview descriptors, housing geometry hashes and exact
manufacturing-schematic source provenance. These references grant no objects.

The original `object/manufacture_schematic/shared_generic_schematic.iff` and its
inherited templates supply no world or inventory appearance. This is a source
limitation, not a missing conversion or permission to substitute an original item
mesh. The client uses a labeled holographic blueprint UI card for native datapad
manufacturing schematics. Factory deeds retain their original datapad mesh.

## Moving vehicle and droid audio

`python3 tools/assets/prepare_mobile_audio.py --ensure` exports the original
vehicle saddle CDF `VTHR`/`VSND` damage bands and droid inherited client-data
`ASND`/`CSND` bindings. The launcher prepares it after the vehicle catalog.
All converted recordings, source hashes and failures stay under ignored
`runtime/assets/mobile_audio/`. Current media yield 55 templates, 40 bindings
and 86 sound definitions. No replacement recordings are downloaded or synthesized.

Vehicles use original idle/run loops and start/stop effects. Live player droids
use original ambient variants/repeat delays, movement and observed damage sounds.
Motion transitions use prototype thresholds; this is not original animation-event
timing. Attack, vocalization and fall slots are exported but await authoritative
runtime event wiring. Sources follow entity poses, expire with stale native state,
and share the bounded HMD spatial mixer and asynchronous Ogg cache.

Three referenced source files are absent from the active TREs:
`sound/dro_remote_fire.snd`, `sound/dro_remote_get_hit.snd`, and
`voice/sound/dro_protocol_m_hello.snd`. The catalog records these as missing assets.

## PvE bounty dependencies

Run `python3 tools/assets/prepare_bounty_assets.py` after the original planet
catalogs are prepared. It reads the native mission manager's three bounty target
pools and their exact mobile/dressgroup definitions, then incrementally merges
missing original appearances into `runtime/assets/ambient_npcs/catalog.json`.
The existing inventory pipeline provides both bounty droid items. Original
incapacitation poses are retained for native dead targets; the tool never creates
world placements, missions, inventory grants or rewards.

`runtime/assets/bounty/coverage.json` records all 34 target mobile families,
75 unique target/informant/droid appearances, 34 original terminal placements
across the ten ground planets, and source hashes. `assets.json` uses the combat
effect schema (`effects`, `particles`, `sounds`, `provenance`), with
`bounty_effects.probot_delivery` naming the original
`clienteffect/probot_delivery.cef`. Its two particles and impact sound use the
shared bounded renderer; nested attachment motion is flattened and XR camera
shake is omitted. Deployed droids use native actors and their exact original
animated models, not locally invented spawn effects or tracking authority.

The current supplied media lack `appearance/mesh/gloves_tusken_raider_f.lmg`,
referenced by `object/mobile/dressed_corsair_cutthroat_hum_f.iff`. Its original
body and remaining outfit are usable, with the missing gloves explicitly marked
as a partial appearance. Coverage therefore reports `passed: false` for full
fidelity and `functional_ready: true`. Exit status is zero only when all required
bodies, movement/death poses, droid items, effects and terminal catalogs are ready;
only recorded wardrobe references proven absent from the supplied archives may
remain partial. Missing bodies or unsupported conversions fail setup. No
replacement proprietary art is downloaded or substituted.

`python3 -m unittest discover -s tests -p test_bounty_assets.py` verifies the
complete original target union, droids, death poses, source placement equality,
source hashes, exact effect texture pixels, audio files and explicit media gaps.

`python3 tools/assets/audit_bounty_appearance.py --repair` rechecks all bounty
CDF wearable and rigid-child records against converted models and textures. It
also repairs the three known ambient/population CDF path defects above, including
cached equipment variants, using `npc_reference_repairs.py`. The audit records
354 distinct bounty model files, all 75 descriptors, source hashes and remaining
media gaps in `runtime/evidence/bounty-appearance-audit.json`. Repeated records in
the original CDFs are counted with their original multiplicity. Current remaining
gaps in the two audited NPC catalogs are the unsupported female Tusken glove,
the absent Twi'lek female hairstyle 10, and the rebel 21B medic CDF; no substitute
geometry is invented. This is a source/model audit, not GPU or headset evidence.

`python3 tools/assets/trace_bounty_sources.py` audits each archive from every
supplied extraction inventory independently, retaining superseded versions and
including inactive archives. It verifies archive hashes and writes
`runtime/evidence/bounty-source-history.json`; it does not activate later assets.
The current 96 archive instances (58 unique archive hashes) contain none of the
three exact missing paths. The broken references already exist in base-game
archives, and all 17 supplied appearance-table versions mark the female Tusken
glove unsupported. An optional `--web-evidence path.json` attaches reviewed public
release metadata without network access. A later retail edition is only a
candidate for inspection until its exact resource index proves otherwise.

The existing combat pipeline also prepares the two exact BH weapons:

```sh
python3 tools/combat/export_catalog.py
python3 tools/combat/prepare_assets.py
python3 -m unittest discover -s tests -p 'test_bounty_weapon_assets.py'
python3 -m unittest discover -s tests -p 'test_bounty_source_history.py'
```

`pistol_scatter` and `rifle_lightning` retain their original models, textures,
`muzzle` transforms, weapon-datatable effect mappings, sounds and projectile
descriptors. The lightning rifle is distinct from `heavy_lightning_beam`.
`catalog.json` separates hashed Core3 template defaults and certifications from
the prototype's normalized delivery settings in `client/combat/balance.json`.
The original projectile datatable does not supply the prototype projectile speed,
scatter cone or guidance limits. Those settings remain explicit balance policy.
