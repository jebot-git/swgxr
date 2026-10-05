# SWG client optimization comparison

The portal-culling and animation-resource milestone follows mechanisms visible
in the SWG client source. Fully suspending hidden ambient NPCs is an additional
SWGXR policy; the inspected client code does not establish that the original
client stopped all hidden animation processing.

## Source boundary

Inspected `SWG-Source/client-tools` at commit
[`949451032647e45e42c3aaef3f41b132c8af36e3`](https://github.com/SWG-Source/client-tools/commit/949451032647e45e42c3aaef3f41b132c8af36e3),
dated 2026-05-13, retrieved 2026-10-04. This is the requested NGE-era source
comparison, **not a verified pristine retail NGE revision**. The repository
maintainers describe substantial changes since 2013 and incomplete Git history;
individual engine mechanisms may predate NGE. The findings below describe this
pinned code. [Repository history statement, README lines 29–30](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/README.md#L29-L30).

Reference files and SHA-256 hashes are in ignored
`runtime/reference/nge-optimization/{revision,sources}.json`. No game assets or
DPVS implementation were downloaded, and no reference implementation was copied
into the client. The comparison establishes architectural parallels, not a
performance result or implementation-equivalence claim.

## Portal visibility

`RenderWorldNamespace::createDpvsPortal` builds a physical portal from authored
polygon geometry and the neighboring cell, enables portal backface culling,
and handles disabled portals. `RenderWorld::drawScene` supplies the camera's
cell, transform and frustum, enables view-frustum/occlusion culling, and invokes
DPVS visibility resolution with a portal-depth limit of eight in this revision.
[Portal creation, lines 683–737](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGraphics/src/shared/RenderWorld.cpp#L683-L737),
[camera setup, lines 860–921](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGraphics/src/shared/RenderWorld.cpp#L860-L921),
[visibility query, lines 1036–1047](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGraphics/src/shared/RenderWorld.cpp#L1036-L1047).

`RenderWorldCommander::command` records visible cells and submits visible,
active appearances for rendering; it also marks appearances rendered that
frame. [Cell reporting, lines 179–185](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGraphics/src/shared/RenderWorldCommander.cpp#L179-L185),
[instance reporting, lines 361–422](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientGraphics/src/shared/RenderWorldCommander.cpp#L361-L422).

**SWGXR mapping:** traverse the original POB cell/portal graph using clipped
camera frusta, then apply the resulting visibility to geometry, NPCs and their
attached equipment. Whole-building visibility is a coarser approximation.
Godot frustum rejection alone does not reproduce DPVS portal traversal or its
occlusion tests. Visual portal availability must remain distinct from movement
passability; a movement restriction alone is not evidence of an opaque wall.
For VR, conservatively union both eyes and any active third-person mirror view.
Do not copy the historical depth limit without testing deep portal chains and
providing a conservative traversal-budget fallback.

## Shared resources, independent playback

`SkeletalAnimationTemplateList::fetch(name)` looks up an existing named template
and increments its reference count; otherwise it loads and registers one.
`KeyframeSkeletalAnimationTemplate::fetchSkeletalAnimation` creates a playback
instance using that template, an animation environment and a transform-name
map. Shared source data therefore does not imply shared animation phase.
[Template cache, lines 127–180](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/animation/SkeletalAnimationTemplateList.cpp#L127-L180),
[playback instance, lines 800–809](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/animation/KeyframeSkeletalAnimationTemplate.cpp#L800-L809).

The appearance-template layer also preloads mesh-generator, skeleton and logical
animation-table resources once, with a separate garbage-collection path.
[SkeletalAppearanceTemplate resource lifetime, lines 455–525](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/appearance/SkeletalAppearanceTemplate.cpp#L455-L525).

**SWGXR mapping:** cache immutable Godot `Animation`/`AnimationLibrary` resources,
while keeping each actor's `AnimationPlayer`, skeleton, phase and customization
state independent. Include the converted clip and target skeleton/track mapping
in the cache identity; identical clip names are insufficient. A parsed JSON
cache alone does not prevent rebuilding animation tracks per actor. Bound cache
residency and test unload/reload so sharing does not become permanent retention.

## Hidden actors and character budgets

`SkeletalAppearance2::alter` still advances its animation resolver. Rendering
separately computes projected size, can reject very small characters, selects
LOD and chooses skinning/batching modes. This is evidence for reducing visible
character work, **not blanket offscreen actor suspension**.
[Alter, lines 1451–1486](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/appearance/SkeletalAppearance2.cpp#L1451-L1486),
[projected-size rejection, lines 1528–1551](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/appearance/SkeletalAppearance2.cpp#L1528-L1551),
[skinning/batching selection, lines 1691–1759](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/appearance/SkeletalAppearance2.cpp#L1691-L1759).

`TransformAnimationResolver` evaluates individual bone transforms on demand and
caches them until its next alter step. Its clock/controller advancement and
bone evaluation are distinct operations.
[Lazy evaluation, lines 668–704](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/controller/TransformAnimationResolver.cpp#L668-L704),
[controller advancement, lines 786–815](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/controller/TransformAnimationResolver.cpp#L786-L815).

`CharacterLodManager::planNextFrame` sorts previously submitted characters by
distance, assigns detail tiers, and applies configurable character-count
thresholds for alternate-frame and simplified skinning.
[Character-budget planning, lines 182–235](https://github.com/SWG-Source/client-tools/blob/949451032647e45e42c3aaef3f41b132c8af36e3/src/engine/client/library/clientSkeletalAnimation/src/shared/core/CharacterLodManager.cpp#L182-L235).

**SWGXR mapping:** hiding a mesh is insufficient if its animation, skeleton and
attachment updates continue. Hidden ambient presentation can suspend those
updates, retaining a logical clip time and restoring the current phase before
revealing the actor. That stronger policy needs explicit handling of animation
events; soundscapes, persistent RPG state, authoritative movement and combat must
not stop because an actor is invisible. Keep the tracked player and any actor
visible to either eye or the desktop mirror active. Visible crowds still need
separate distance/projected-size budgets; sharing resources does not eliminate
per-character pose evaluation or draw calls.

## Integration status and limits

Read-only review of the current milestone finds native portal-cone traversal
unioned across XR eyes and the spectator, conservative graph/budget fallbacks,
actual room-mesh visibility changes, and retained exterior-shell shader clipping.
Traversal starts without camera-frustum planes; NPC bounds have a separate
per-view frustum test. This is conservative portal reachability, not the full
DPVS visibility pipeline. See `client/native/src/portal_visibility.cpp` and
`client/scripts/portal_visibility.gd`.

`animation_clip_cache.gd` shares compiled clips with independent players and
limits cache-owned references to 256 clips/500,000 track keys. Players can retain
evicted resources, so these are not total animation-memory limits.
`ambient_npcs.gd` pauses body/face evaluation, accumulates elapsed time, then seeks
and refreshes skeleton/equipment/virtual skin before revealing actors. Its
existing 50 m animation-distance policy still applies to visible distant actors.
Current actor bounds include an attachment envelope and motion margin; extreme
gestures need validation because these are not measured full-clip bounds.

GPU-baked crowd poses, skeletal crowd instancing/MultiMesh, and a visible-character
pose-budget scheduler remain deferred. The inspected original batching and
skinning choices motivate profiling those options; they do not establish that
Godot offers equivalent behavior automatically. No live VR or GPU performance
result is asserted by this source review.

## Milestone acceptance evidence

- Traverse the starport and cantina doors, angled corridors and multiple portal
  chains in both directions; verify both eyes and mirror retain visible content.
- Instantiate repeated NPCs with different phases and outfits. Verify shared
  clip resources, independent playback, original equipment attachment, and
  bounded resource counts through unload/reload.
- Record visible, hidden and animation-active NPC counts alongside main-thread
  frame percentiles. Verify hidden work decreases and reappearance preserves
  pose/phase without a spike. Repeat the same populated scene and camera path.

These checks evaluate SWGXR's Forward+ Vulkan/OpenXR implementation. They cannot
establish NGE client throughput, equivalent DPVS occlusion, or an MMO population
limit without separate measurements.
