# Artisan crafting

`0024-artisan-crafting.patch` wraps the original Core3 `CraftingSession` and its
schematics, ingredient slots, assembly/experimentation rolls, customization,
prototype attributes, experience awards and complexity-based creation tasks.
The adapter grants no schematics, tools, resources or components. All possession
changes happen on the authenticated native creature. Original resource icons and
item models are exported from supplied media into ignored runtime directories.

## Controls

Draw an owned crafting tool from the bag or existing tool hip slot. A fresh
holding-hand trigger opens the usable schematic list. Select a schematic with the
other hand: ingredients appear in a filtered 4 × 3 inventory grid on the inner
side, using their original 3D models, names and quantities. The original item
preview appears on the outer side. Select an ingredient to inspect its quality
bars above the matching cubes. Grip its grid cell, move it to a matching cube,
and release. Point at a panel and move the offhand stick to scroll. Grip a
filled cube to clear its draft allocation. Optional slots may stay empty; a
partially allocated optional component slot must be completed or cleared.

Trigger advances assembly when required slots are filled. A compatible native
station within Core3's 7 m range enables experimentation. The native character's
learned experimentation skill controls points. Grip a knob and turn clockwise to
allocate; turn counterclockwise to release uncommitted points. Each step is 25°.
Knobs are spaced about 6.2 cm apart, with non-overlapping 2.4 cm grab radii.
Experimentation pages show four rows; scrolling exposes additional rows.
The source row limit and shared allowance clamp every change. Original palette
bars and draggable handles appear only for source customization options supported
by the item and learned customization skill. Trigger applies the allocation,
styles the item, and starts its original timer. Without experimentation the
assembly trigger starts crafting directly.

Stowing before creation starts cancels and refunds **all** inputs, including after
assembly and experimentation allocation. This deliberately changes SWG's original
assembly cancellation loss. Once the timer starts, stowing leaves the job running.
Held/hip tools and inventory tiles show countdowns; multiple tools can run at once.

## Transactions and reservations

Placement in cubes is a client draft. Assembly revalidates every original ID,
resource family, component type/condition/identity, quantity, and aggregate use
across slots. Original ingredient objects move to a private persistent native
escrow, reserving their original container slots. Native assembly uses isolated
copies with the same source properties; the copies cannot be selected from the
inventory. Cancelling destroys the unfinished prototype and staged copies and
returns the exact original objects, preserving quantities and customization.
Refund transfers retain the journal until successful and can restore reserved
slots even if an administrative grant bypassed ordinary capacity checks.

Creation checks root inventory space, applies native experimentation/customization,
persists the result, reserves one output slot, and commits the original ingredient
quantities once. The normal native task runs for `complexity * 2` seconds, including
complexity changes from experimentation. Native inventory counting includes escrow
and output reservations. Creation completion exchanges its reservation for the
actual prototype. Each mutation has a durable bounded receipt so replaying the
same request cannot consume ingredients or start a second timer.

The authenticated local transport disconnects after each request. Draft sessions
remain attached to their owned tools, not the disconnecting creature session.
A five-minute draft lease is refreshed by crafting status requests. On the next
crafting request, an expired draft or a draft whose native session was lost is
refunded from the persistent escrow journal. Running output prototypes and
completion deadlines persist; a crafting status request after restart resumes
settlement. No persistent JSON character or item store is used.

## API

GET `/crafting?account=...&character_id=...` reads state and settles jobs.
POST `/crafting/{open,select,assemble,finish,cancel}` includes `account`, owned
string `character_id`, and unique `request_id` (8–64 safe characters).

- Open: `tool_id`, source `position:[x,elevation,z]`, optional source `building_id`/`cell_index` for an interior station.
- Select: same fields, `session_id`, and eligible schematic `index`.
- Assemble: same fields and `allocations`, one list of original item IDs per slot.
- Finish: same identity/position, integer `points` per experimentation row and
  `colors` per exposed palette variable.
- Cancel: `session_id`; no tracked position or held tool is needed to refund.

Responses identify `source_kind:core3_crafting`, character identity, native stage,
eligible schematics, filtered ingredients and source quality weights, rows, points,
statistics, palette choices, server clock and running jobs. Mutating possession
responses also contain a fresh authenticated inventory snapshot. Incomplete or
mismatched identities are rejected. Lost mutation responses are not automatically
retried with a new key.

## Scope and verification

This is the bounded local Tatooine prototype. Station proximity uses the
source-world position and explicit original cell supplied by Godot, with native
station compatibility and the original 7 m range. Interior and exterior stations
are supported; this is not an MMO anticheat boundary. Factory manufacturing
schematic creation, practice mode, renaming, and alternate appearance templates
remain outside this first artisan interface. Crafting reuses an owned persistent
combat session when one exists. Send its token as `live_session_id`; `session_id`
continues to identify the crafting draft and must not be overwritten. Native item
attributes and inventory snapshots share the original live response fence.
Terminal station use exposes owned compatible tools; opening one still invokes
the original `CraftingSession` and learned schematic rules.

- `tools/crafting/prepare_assets.py`: original resource icons and artisan previews;
  unsupported source appearances remain explicitly recorded in the inventory asset
  catalog, with no replacement models or grants.
- `tests/test_crafting_protocol.py`: malformed ownership, positions and allocations.
- `client/tests/crafting_smoke.gd`: original-model grid, scrolling, knob spacing,
  physical twist, holographic drag/slot, quality, allowance and
  cancellation orchestration using captured native recipe data; mocked tracking.
- `tools/crafting/fixture.py` and `tools/crafting/smoke.py`: isolated native fixture,
  cancellation identity/quantity conservation, full bag rejection/refund, point
  limits, idempotency, concurrent timers, native output delivery and station range.
- `tools/crafting/component_smoke.py`: exact component identity refunds.
- `tools/crafting/restart_smoke.py`: graceful restart draft refunds and persisted
  crafted output retention.
- `client/tests/crafting_capture.gd`: explicit desktop Forward+ Vulkan evidence.
  It does not validate live headset rendering or ergonomics.

Restore the temporary fixture screenplay with `tools/crafting/fixture.py --restore`
after testing; the isolated fixture's persistent inventory remains in Core3.
