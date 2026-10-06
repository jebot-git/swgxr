# Artisan crafting

## Advanced artisan professions

`0042-artisan-professions.patch` extends the existing native trainer catalogue
to Armorsmith, Weaponsmith, Chef, Tailor, Architect, Droid Engineer, Merchant
and Shipwright. These are the eight original professions whose novice box
requires an Artisan branch. Bio-Engineer derives from Scout and Medic and is
covered separately below by `0051-bioengineer-profession.patch`. All 144 advanced skill boxes use the existing
trainer UI and original SkillManager prerequisite, XP, money and skill-point
checks; selecting a box never grants its prerequisites. The datapad already
loads the complete original skill graphs. Source schematic-group grants are now
retained in its exported definitions as well.

CraftingSession already selects learned recipes by the owned tool, nearby
compatible station and native skill modifiers. Specialist assembly,
experimentation, customization and XP therefore use the same holographic
crafting interface and refund/timer rules. Merchant retains its native passive
modifiers; no fictitious Merchant recipes are added. This change does not add
vendor creation/management, structure placement, factory management, ship flight
or reverse-engineering interfaces; it exposes these professions through the
existing training and crafting mechanics only.

Trainer audits and datapad map references now include all 14 supported trainer
types on the ten prepared planets (86 source placements on Tatooine). Recipe
preview selection is derived from original assembly skill modifiers and Core3
recipe definitions instead of being limited to `general_assembly`. Setup exports the profession definitions and specialist previews. The ignored
`runtime/assets/crafting/professions.json` records recipe coverage and source
hashes. Unconverted appearances remain explicit in the inventory catalogue;
they do not block native recipes or become replacement models.

Validation: 16 Python source/protocol/asset checks, a standalone C++14 catalogue
compile, 139 mocked trainer UI checks, 34 mocked crafting checks and 17 synthetic
XP checks pass. Headless checks use `--xr-mode off` and the dummy renderer.
This session could not rebuild/restart Core3: the filesystem sandbox blocks
Podman's access to `/run/user/1000/libpod`. The patch is verified against its
predecessors, but native training/crafting of the new branches has not been
live-tested or deployed. Rebuild with `tools/server/build.sh` when container
access is available. Source preview limitations are recorded separately in
`runtime/evidence/artisan-professions.json`.

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

At a compatible station, factory-eligible recipes also show **Create factory
blueprint · 1000 runs** after assembly. Select it before the finishing trigger to
create a native manufacturing schematic in the datapad. It records the finished
item, exact resource spawns, component serials and a bounded manufacturing limit.
Draw that blueprint from the datapad and insert it into a compatible factory.
Blueprint creation consumes the same committed ingredients and creates no timed
prototype job; factory production uses its own native timer and input hopper.

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
  `colors` per exposed palette variable; optional `output` is `prototype` (default)
  or `blueprint`. Blueprint `manufacture_limit` defaults to 1000, bounded 1–1000.
- Cancel: `session_id`; no tracked position or held tool is needed to refund.

Responses identify `source_kind:core3_crafting`, character identity, native stage,
eligible schematics, filtered ingredients and source quality weights, rows, points,
statistics, palette choices, `can_create_blueprint`, server clock and running jobs. Mutating possession
responses also contain a fresh authenticated inventory snapshot. Incomplete or
mismatched identities are rejected. Lost mutation responses are not automatically
retried with a new key.

## Scope and verification

This is the bounded local Tatooine prototype. Station proximity uses the
source-world position and explicit original cell supplied by Godot, with native
station compatibility and the original 7 m range. Interior and exterior stations
are supported; this is not an MMO anticheat boundary. Practice mode, renaming,
and alternate appearance templates remain outside this artisan interface. Crafting reuses an owned persistent
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


## Bio-Engineer

`0051-bioengineer-profession.patch` enables all 18 original Bio-Engineer boxes
through the existing trainer and datapad interfaces. Scout/Medic prerequisites,
XP, credits, skill points, schematic grants and sampling modifiers remain native.
The Tatooine audit includes its original Bio-Engineer trainer; no other planet is
enabled by this change.

The existing tool, station, inventory grid, resource cubes, experimentation knobs,
customization, timers and cancellation flow are reused. Preview coverage now
includes 105 original recipes: 28 tissue/component recipes, 69 creature deeds,
one generic DNA template and seven pet supplies. Preview inclusion does not
unlock a recipe. Core3 still selects learned schematics for the current tool.
Genetic assembly and experimentation continue through `GeneticLabratory`, with
five original DNA profile slots and their native formulas. DNA ingredient bars
show the two native attributes for each profile, labelled with their raw values
and displayed on the native 1–1000 scale. Resource quality bars remain unchanged.
A single one-use sample cannot fill several profiles. Existing ingredient escrow
returns the exact original samples on cancellation; only committing production
consumes them.

Hold a crafted creature deed and press trigger to register it. The existing
`/vehicles/activate` receipt path also accepts native `PetDeed` objects and calls
Core3's original menu action 20. Core3 checks ownership, state, location, datapad
space, stored/active pet limits and creature-control skills, then creates the
original genetic pet and control device. The bridge verifies the new device and
consumed inventory deed before acknowledging success. Confirmed native
rejections release the client receipt; uncertain responses retain the same
request ID and original request position. Called pets use the existing AI,
offhand commands, datapad recall and two-hand recovery.

`tools/pets/prepare_bioengineer.py`, also called by the full crafting asset
preparation, resolves every crafted pet from original deed/mobile definitions.
It reuses converted appearances and prepares missing original models. Its ignored
`runtime/assets/bioengineer/appearance_catalogs.json` records source hashes and
exact appearance catalogue paths. Actor loading can use these appearances on
Tatooine without loading their source planet. This run resolved all 69 appearances
and imported four previously absent bodies; all 105 recipe output models are ready.

Validation (2026-10-05): 31 Python profession/protocol checks plus four service
asset checks passed. New dummy-renderer client checks passed for DNA allocation
and profile bars (12), creature-deed trigger/retry handling (17), and original pet
models/animations (553). Existing crafting, pet-command, trainer and DNA-sampling
regressions also passed. All Godot runs used `--headless --xr-mode off`; HTTP and
tracking fixtures do not validate native server outcomes or headset rendering.
The complete patch stack through 0051 applies. Native rebuild/live validation is
blocked by Podman's read-only `/run/user/1000/libpod` in this sandbox. Nothing was
deployed and the live Tatooine-only restriction remains in effect.
