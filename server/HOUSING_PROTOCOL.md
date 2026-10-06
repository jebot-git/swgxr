# Native architect housing

The client presents original player structures; Core3 owns placement, construction,
permissions, maintenance and all furnished items. `0049-native-housing.patch`
replays after fishing and the existing native profession patches.

## Controls

Grip and pull a structure deed from inventory. The original structure appears as a
full-size hologram at the hand's ground aim point, up to 60 metres away. Turning
that hand snaps the house to Core3's four supported orientations. Red means
unapproved, blocked, or stale; cyan means the current Core3 preview passed. Pull
the trigger to revalidate and start construction. Release the deed or return it to
the bag to cancel the preview without consuming it. Missing original geometry
prevents placement instead of displaying a substitute.

The original house terminal opens the standard holographic terminal panel. It
shows native upkeep, maintenance rate and item counts. Deposit uses the existing
credit slider and original cash-only `payMaintenance` transaction. Owners can
select Add/Remove Entry, Admin, Ban or Vendor permissions, then grip the target
player's hand for 0.25 seconds within 60 seconds. Both players must be tracked and
nearby in the same native cell. Selecting another option replaces the previous
one. Changing cells invalidates the contact proof; the owner can leave a private
house and make a fresh handshake outside during the same minute. Expiry or lost
tracking invalidates the gesture. Core3 repeats
owner and target checks and uses its original permission command, including list
limits, owner protection, bans and cell-permission updates.

Inside a house where the player has administrator permission, release an item
pulled from inventory to furnish it. Normal release settles at the original cell
floor; holding the right controller's A button (`ax_button`) during release keeps
its released position. Full local orientation is saved for both modes. Original
item dimensions are retained. The ordinary fall is a local animation toward the
server-confirmed floor pose, not a client physics simulation that writes items to
the server. Furnished models have collision. Grip a placed item with both hands to
return it to inventory; each hand must touch its model and be within one metre of
its native origin. Original transfer permissions and inventory capacity apply.

## Native authority and protocol

All requests use the existing authenticated `/services/house_*` bridge. IDs are
native unsigned decimal strings, position arrays use source X/Y-up/Z coordinates,
and mutations need a stable `request_id`.

- `status`: bounded nearby structures and current building contents.
- `preview`, `place`: `deed_id`, `placement_position`, `rotation` (0–3).
- `deposit`: `terminal_id`, positive `amount`, capped by native cash/reserve limits.
- `permission_arm`: `terminal_id`, `permission_list`, `permission_action`.
- `permission`: `target_id`, `arm_id`; adapter requires an authenticated handshake.
- `drop`: `item_id`, `placement_position`, source `local_quaternion` (x,y,z,w),
  boolean `suspended`.
- `recover`: `item_id`, tracked `left_hand` and `right_hand` positions.

Preview and placement share the original `PlaceStructureCommand` gates and
`StructureManager::placeStructureFromDeed` rules: state, mount, interior, native
cities, planet, water/no-build areas, footprint, zoning, city rank, faction,
required ability, deed ownership and available lots. Preview returns before
session creation or deed removal. Final placement still calls the deed's original
placement component and `PlaceStructureSession`; barricades, construction times,
lot accounting, deed-derived upkeep and completion are unchanged. Native movement
also checks `BuildingObject::isAllowedEntry` for house cells.

Furniture always goes through `transferitemmisc`. Its `CellObject::canAddObject`
checks the original house item limit, counting container contents. The bridge
checks same-cell floor support, line of sight and hand reach before transfer, then
saves the item's native pose. No local inventory store or substitute house-item
limit is used. Successful mutations have bounded native idempotency receipts.

## Original assets and verification

`tools/assets/prepare_housing.py` converts source POB meshes, portals, floors and
collision through the existing asset pipeline. Output and source SHA-256 hashes
stay under ignored `runtime/assets/housing`. The current media produces 143
structure templates. Missing references are recorded for
`player_house_naboo_medium_style_02` and faction `covert_detector/detector_32m`.
These do not prevent supported Tatooine houses. Terminal screen planes come from
the original terminal mesh. Dynamic houses register with the same native geometry,
ground support and cell classification used by the retained/streamed world.
No additional planet was enabled or deployed.

`tests/test_housing_protocol.py` covers input validation, ownership-bound presence,
handshake expiry/replay, stale tracking and permission replacement.
`client/tests/housing_smoke.gd` exercises original house/furniture assets, native
floor queries, persistent cell IDs, collision, hologram cancellation and approval
invalidation, gravity/suspension presentation, response identity and terminal UI.
These are dummy-renderer and mocked-backend tests, not a live house placement or
headset acceptance test. That housing milestone lacked access to the Podman build environment and
X11/Wayland display. Later factory build and desktop evidence is recorded below. Live Core3 placement/restart, permission exchange,
maintenance debit and headset furnishing remain the integration acceptance pass.


## Harvesters and generators

`0052-harvesters.patch` reuses native structure placement for architect-crafted
harvesters and generators. Owned deeds also appear as draggable references in the
datapad's Data list. They remain native inventory objects, so no duplicate deed or
local persistence is created. Grip and pull a reference to draw the original
full-size placement hologram; red means blocked, unapproved or stale. Trigger
revalidates Core3 placement rules and starts normal construction. Releasing the
preview cancels without consuming the deed. Wall faces are not placement floors.

Point at a deployed harvesting structure and click trigger to open its holographic
interface. Native administrator access and the original 20-metre operating range
are enforced again on every server operation.

- Centre: resources supported by that installation on its current planet, with
  current density and extraction rate. Selecting a resource requests native
  selection and activation. Start/Stop controls remain available; Core3 can
  refuse operation for depleted resources, insufficient density, power,
  maintenance or a full hopper.
- Left: drop a held energy resource stack into the energy cube to deposit it.
  Only that stack is consumed, using Core3's potential-energy conversion
  `max(1, PE / 500)`. The maintenance slider is limited by carried credits;
  click Deposit to call the native maintenance payment. The slider supports
  pointer input and grabbing its holographic handle.
- Right: a paged output grid with original resource models and native quantities.
  Click a stack or grip and pull to withdraw up to the native stack maximum.
  The original resource spawner inventory transaction supplies the resources;
  hopper quantity decreases only after a successful transfer. Full inventory
  rejects withdrawal.

Grab the deployed structure with both hands to recover it. Client contact uses
its original model bounds; the server repeats hand reach, ownership and native
redeeding checks. The hopper must be empty and inventory must have room for the
original deed (and the self-powered kit when applicable). Recovery refuses any
path that would merely destroy the structure. Native redeeding pays its normal
maintenance cost and preserves remaining maintenance/power on the deed. The
returned deed appears in the datapad again after the authoritative refresh.

Authenticated service routes are `house_harvester_status`, `_select`, `_active`,
`_power`, `_deposit`, `_collect` and `_recover`. All use `structure_id`; selection
and collection use `resource_id`, power uses `item_id`, collection uses
`quantity`, maintenance uses `amount`, and recovery carries both hand positions.
Mutations use the existing persistent housing receipts. An uncertain client
response retains its request ID and original payload for retries. Character
reset clears the UI and pending local requests.

Validation: 36 Python protocol/asset/regression checks and headless client checks
covering harvesting (20), housing (25), normal service sessions (11), and vendor
placement (29). All 20 source-defined harvester/generator structures have original
geometry locally. The full patch stack applies through 0052. Godot checks use
`--headless --xr-mode off` with mocked tracking and backend responses; these do
not validate native extraction, GPU rendering or a headset. At that harvester milestone, native validation was blocked by Podman's
read-only `/run/user/1000/libpod`. Later factory verification is recorded below. No deployment or planet expansion is part of this change.

## Factories

Point at a deployed factory and press trigger to open its simplified crafting
interface. The source slot above the centre panel accepts only a manufacturing
blueprint dragged from the datapad. Grip and pull the installed blueprint to
return it to the datapad while stopped. Drop matching resources or components
from inventory onto the centre input panel; click or grip and pull an input row
to retrieve it. The right panel holds finished output separately. The left
panel uses the same energy drop cube, upkeep slider and Start/Stop controls as
harvesters. Blueprint references are labeled holographic records: the supplied
original manufacturing schematic template has no 3D appearance.

Factories use the same native structure placement preview, four quarter turns,
construction, maintenance and original-deed recovery path as harvesters.
`housing.structures[].factory` identifies actual Core3 factory objects.
`housing.deeds` includes owned factory deeds, normalized to `type:factory_deed`.
`housing.blueprints` contains actual owned manufacturing schematics in the native
character datapad, with `type:manufacturing_blueprint`; these are source objects,
not draft schematic definitions or fabricated inventory items. The crafting
finish action can create these schematics at eligible crafting stations.

Authenticated service actions are `house_factory_status`, `_blueprint`,
`_remove_blueprint`, `_input`, `_withdraw`, `_collect`, `_active`, `_power`,
`_deposit`, and `_recover`. Every action requires `structure_id`; all mutations
also require the standard stable housing `request_id`. Status is read-only.
Blueprint installation, input deposit, input withdrawal, output collection and
energy fueling require `item_id` and transfer the entire actual object/stack.
Blueprint removal needs no item ID and returns the installed source schematic to
the native datapad. Active requires a boolean `active`; upkeep requires integer
`amount`; recovery requires both tracked `left_hand` and `right_hand` positions.

`mutation.factory` contains `id`, `active`, `blueprint` (or `{}`), available
`blueprints`, native `requirements`, `input`, `output`, hopper capacities,
`power`, `power_rate`, `maintenance`, `maintenance_rate`, `cash`, `owner`,
`redeed_cost`, and `redeedable`. Requirements name the exact resource spawn or
component identity and, when necessary, its manufacturing serial number.

Core3 verifies native administrator access, the selected zone, outdoor player
state and a 16-meter interaction range. Installing a blueprint requires a stopped
factory with an empty slot, an actual owned datapad schematic with remaining
runs, and a supported native crafting tab. Inputs must match the installed
blueprint's exact resource spawn or component CRC/serial. Native item transfer
validates hopper/player capacity, permissions and range; clients cannot submit
output contents or resource quantities. Input changes refresh native matching
entries under the factory lock, including while production is active.

Activation uses the native scheduled factory production task. The adapter does
not produce items or advance production clocks. Source blueprint run limits,
resource consumption, output crates, upkeep and power remain Core3 authority.
Fuel consumes only the dragged owned energy stack using native potential-energy
conversion. Recovery requires the owner, inactive factory, removed blueprint,
empty input/output hoppers, native redeed eligibility and space for the original
deed. Both hands must touch the factory within player reach. Mutations persist
native objects and use the existing bounded housing retry receipts.

Recovery acknowledges the original deed's synchronous transfer and cleared native
structure deed ID. Core3 queues world destruction on its slow task queue, so an
immediate non-null zone is not a recovery failure. Pending-recovery installations
are omitted from housing snapshots and reject further mutations. This also fixes
the shared harvester recovery path; successful recovery receives a durable retry
receipt before the queued world cleanup completes.

Native recovery transfers the original deed before queued world removal finishes.
Factory and harvester success therefore checks the returned deed and cleared
structure deed reference. Pending removals are hidden from housing snapshots and
reject further mutations; durable recovery receipts still replay after removal.

Factory verification on 2026-10-05: the complete native patch stack through 0054
applies, and Core3 compiles and links. Build evidence is
`runtime/evidence/factories-native-build.json`. Python protocol and launcher
regressions pass (56 checks); client headless factory, harvester, housing, datapad
and crafting checks pass (133 checks total). These use `--xr-mode off` and mocked
tracking. `runtime/evidence/factories-desktop-vulkan.png` is a reviewed desktop
Forward+ Vulkan UI capture with fixture state, not a live headset test.

`tools/factories/smoke.py` exercises an isolated `invtestfactory` character against
local Core3. It grants test-only tools, resources and a deed, crafts an actual
manufacturing schematic, validates placement/construction, hopper transfers,
resource rejection, upkeep receipts, fueling, native timed output, collection,
blueprint retrieval and original-deed recovery replay. Test characters are
protected from ambient combat. Temporary screenplay hooks are removed afterward;
the fixture's native items remain in its isolated account. The optional
`SWGXR_FACTORY_TEST_URL` selects another local adapter port. Original assets stay
ignored; no live VPS or planet-scope deployment is part of this work.

The live local factory lifecycle passed all 23 checks; results are saved in
`runtime/evidence/factories-native.json`. This proves native transactions and
production with synthetic hand positions, not headset rendering or ergonomics.
