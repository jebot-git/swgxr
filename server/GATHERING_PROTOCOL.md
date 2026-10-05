# Native gathering and corpse protocol

The loopback adapter authenticates the account, verifies character ownership and sends an owned-player command over the persistent Core3 protocol. Native snapshots use actual inventory objects, resource spawns, resource statistics, skills and waypoints. There is no adapter-owned inventory or output ledger.

`GET /gathering?account=...&character_id=...&tool_id=...` returns `source_kind: core3_gathering`, `tool`, current `resources`, `range_m`, `max_range_m`, `points_per_axis`, `hip_tool` and `deployments`. Range is the **full survey grid width**, not radius. Source skill thresholds yield widths 64/128/192/256/320/384m and 3/4/5 grid points per axis.

All POST requests include `account`, string `character_id` and an 8–64 character `request_id` (letters, digits, underscore, hyphen). Preserve the same key for an ambiguous retry. The native player retains the latest32 request fingerprints and receipts, shared by gathering and corpse mutations. Reusing a retained key with different arguments is rejected.

- `/gathering/survey`: `tool_id`, `resource_id`, `position:[x,y,z]`, `planet:tatooine`. Returns source grid densities and a persistent highest-density waypoint when positive; the existing survey waypoint is reused.
- `/gathering/deploy`: same fields. Moves the real tool into owner-bound native escrow. Returns a unique `deployment_id` (`toolID:generation`).
- `/gathering/collect`: `deployment_id`, `position:[x,y,z]`. Requires the submitted player position within2.5m of the native deployment and capacity for the tool plus all resource output, accounting for source100000-unit stack merges. No partial collection on capacity failure.
- `/gathering/holster`, `/gathering/return_tool`: `tool_id`. One tool of any native tool type can occupy the hip escrow reservation. Drawing it visually does not move the native item; returning to the bag requires capacity. Swapping the hip reservation requires space for the displaced tool.

Mutations return `source_kind: core3_gathering_<action>`, `mutation.success`, `state` (complete gathering context), and a fresh actual `inventory` snapshot. Survey additionally returns `survey.spots`, `highest` and `waypoint`.

Positions are SWG world y-up arrays; x/z must lie within±8192 and y within±2048. The client validates actual stage ground. The server validates finite bounds, ownership and native interaction distance; this prototype does not claim authoritative server movement or server terrain collision.

## Persistent unattended sampling

Tool escrow, resource anchors and screenplay metadata are persisted inside Core3. A zero-unit original ResourceContainer anchors each selected ResourceSpawn; output retains the original identity/statistics after the spawn expires. Metadata stores source density, skill/rate/size checkpoint, first result after3s and subsequent25s cycles. Native sampling follows `ResourceSpawner::sendSampleResults` baseline success/yield/XP formulas and source samplingMultiplier1. Original skill-based survey range comes from `SurveyToolImplementation.cpp`.

This unattended-tool policy intentionally omits the original self-sampling posture, action/mind costs, rich-node/gambling interactions and radiation wounds. Elapsed cycles are settled lazily on requests, including time across restart. At most1024 cycles are processed per request across16 deployed tools; remaining backlog stays pending and collection is blocked until settled. Buffered output has no gameplay quantity cap (signed64-bit storage). Sampling stops at the original resource expiry time. Skill changes apply after the previous checkpoint backlog settles.

Capacity preflight and native object transfer rollback cover ordinary request failure, under native owner/object locks. Core3 periodic database saves are unchanged: this is not a crash-atomic transaction across screenplay metadata, inventory, resource depletion and XP. Abrupt termination between updates has not been fault-injection validated. Idempotency is bounded to the latest32 receipts, not an unlimited history.

## Native corpses

`GET /gathering/corpses?account=...&character_id=...&position=x,y,z` returns `source_kind: core3_corpses`, up to64 actual dead Core3 agents within64m, and `truncated`. Records contain original template/shared template, customization, source position, heading, `height` and `scale`, native rights/availability, `resources` (meat/hide/bone source spawn and predicted native yield), and `loot` (credits/items).

POST `/gathering/corpse/inspect|harvest|loot` accepts `corpse_id`, source player `position`, `request_id`; harvest also accepts `kind: meat|hide|bone`. Source kinds are `core3_corpse_inspect`, `core3_corpse_harvest`, `core3_corpse_loot`. Mutations return `.corpse`, `.mutation.success`, and a fresh `.inventory`.

Only outdoor actual native dead agents qualify. During the locked request the player's coordinates are temporarily projected to the submitted local position, then restored without moving the zone tree or persisting a teleport. Original corpse location, dead state, harvest rights, skill, already-harvested state, source command restrictions and7m harvest/16m loot ranges remain checked. Corpse harvesting uses native `CreatureManager::harvest`, source density/group yield modifiers, scoutXP and observers, with exact capacity preflight to avoid the source helper's partial-stack failure case.

Loot currently supports **personal owner rights only**. Native group loot distribution is explicitly unavailable. All source items must fit before any transfer; failed item transfers roll back before credit commit. After successful item transfer, native `PlayerManager::lootAll` handles credits, source luck bonus, observers and corpse cleanup. Local training targets cannot create persistent corpse rewards.

## Verification fixtures

`tools/server/prepare_gathering_fixture.py --fixture <explicit invtest JSON>` temporarily installs a Lua helper bound to that single disposable character ID. `--phase` supplies source skills, original test items, or a real source worrt with controlled native DEAD posture and explicit fixture ownership/loot. This controlled corpse state tests interaction authority; it does **not** validate a native combat/death bridge. `--restore` removes the helper. Keep fixture IDs separate from user accounts.

Actual backend evidence: `runtime/evidence/gathering-native-initial.json`, `gathering-core3-smoke.json`, `corpse-core3-smoke.json`. Native gathering was retained across graceful Core3 restart; capacity/distance rejection, reservation, source sampling, pickup and receipt replay were exercised. Automatic rollback under injected transfer failure, abrupt-crash consistency, resource expiry rollover and group loot are not claimed as tested.

## RPC responsiveness and sampling outcomes (0033)

`POST /gathering/status` supports the same context as GET and accepts `live_session_id`. All tool mutations also accept this transport identity. Existing persistent sessions are reused; normal requests authenticate the character once through native `selectContext`. Mutation responses include the committed inventory in the same native transaction, avoiding an extra login after pickup.

Each deployment includes `sample_status`, localized `sample_message`, `last_sample_units`, `next_sample_at_unix`, and fractional `minimum_productive_density` / `recommended_density`; state includes `server_time`. Source novice surveying20 at29% density produces one unit, which original Core3 rejects as `trace_amount`; minimum productive density is roughly35.7%, reliable size threshold40%. Chance failures still follow native rules. These thresholds describe original yield behavior rather than increasing yields.

Recovery retries after an uncertain transport failure must preserve request ID and the exact original semantic payload, including pickup position. A changed payload with the same ID is rejected. A new `backend_busy` response states only that that attempt did not enter native mutation; it does not resolve an earlier uncertain attempt.

### Resource waypoints and original survey missions (0039)

Resource rows include `mission_family`, the original ResourceSpawn survey-family
value, distinct from the narrower inventory family. Successful survey grids
notify original survey objectives with the maximum density in percent, preserving
native family/density/distance checks and original reward handling. Native request
receipts prevent duplicate survey notifications when retrying an operation.

The original `SPECIALTYPE_RESOURCE` waypoint is removable through
`/datapad/delete`, as are ordinary owned waypoints. The command verifies its exact
ID in the authenticated player's waypoint list, calls original removal/database
destruction, and persists the player ghost. Mission/quest/static waypoints remain
protected. Removing a survey marker does not cancel a survey objective or delete a
deployed tool. A later survey creates a new original marker if needed; it does not
resurrect a client-hidden object.
