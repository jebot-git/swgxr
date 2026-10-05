# Original terminal services

The loopback adapter projects real Core3 terminals, auction listings, mission
objects, credits, compatible crafting tools, travel tickets and shuttle schedules.
There is no local market, wallet balance, mission reward or travel timer store.
Original user media provides models and the GOT/STF bazaar category tree.

POST `/services/{status,open,mission_refresh,mission_accept,mission_abort,
bazaar_buy,bazaar_retrieve,bazaar_sell,bazaar_cancel,bank_transfer,pay,
crafting_station,travel_purchase,travel_board,delivery_open,delivery_pickup,
delivery_complete}` uses `account`, owned string
`character_id`, optional persistent `session_id`, and source-world Y-up `position`.
Interior positions add `building_id` and `cell_index`. Omitted membership preserves
the original native cell; explicit `"0"`/`0` exits outdoors.

Mutations need an 8–64 character unique `request_id`. Core3 stores 64 durable
receipts per character. An exact replay returns the committed receipt; changing
its payload is rejected. Clients do not automatically retry ambiguous failures
with a new key. Independent native sessions default to ten and are per-account;
a service request reuses its existing session, including while combat is active.

Responses contain `backend:core3`, `source_kind:core3_services`, `character_id`,
`state`, `mutation`, and an ephemeral `presence` registration. State contains
`wallet:{cash,bank}`, native `player`, up to 128 nearby `terminals`, one selected
`terminal`, active `missions`, `tickets`, and nearby `shuttles`. Possession-changing
operations include a decoded original `inventory`, with item attribute replies
fenced before the snapshot. Live operations also carry `live_response`, whose
sequence and transport must be reconciled with other persistent session replies.

- `open`: `terminal_id`; `mission_refresh` uses that original terminal's manager.
  Mission operations use `mission_id`. Acceptance retains original limits,
  professions, objectives and persistence. Destroy, hunting, reconnaissance,
  delivery and crafting offers are supported. Other original offers remain
  visible with `supported:false` and a `blocked_reason`.
- Bazaar browsing uses numeric source `category_id` and zero-based `page`.
  Original `AuctionManager::checkItemCategory` filters before 100-row pagination;
  `has_more` signals another page. `categories` is the original localized GOT
  hierarchy, not a list invented from currently populated items. NGE's optional
  exclusion table is absent from the supplied media, and its resource-class
  nested special menu is recorded as a dataset limitation.
- `bazaar_buy`: `listing_id`, quoted `price`, optional auction `max_price`.
  Original instant purchase and proxy bidding apply. `bazaar_retrieve` uses the
  original retrieval location, ownership and inventory capacity checks. Buying
  does not remotely materialize an item: retrieval remains a separate action.
  Listing rows include source status/type, `buy_eligible`, `retrieve_eligible`
  and `min_bid`. `bazaar_sell` accepts owned `item_id`, `price`, bounded
  `description`, optional `auction`; original listing fees/limits apply.
  `bazaar_cancel` requires the owned `listing_id`.
- `bank_transfer`: bank `terminal_id`, `direction:deposit|withdraw`, positive
  integer `amount`; source transfer preserves total cash plus bank. `pay` takes
  `target_id` and `amount` after a fresh authenticated mutual grip handshake;
  native `TipCommand` validates the actual online recipient and cash transfer.
- `crafting_station`: `terminal_id`, owned compatible `tool_id`. The UI then
  opens the original crafting flow with that tool. See CRAFTING_PROTOCOL.md for
  the separate crafting `session_id` and persistent `live_session_id` fields.
- `travel_purchase`: native `terminal_id`, `destination_id` (original travel
  point name), optional `round_trip`. Original route, city ban/tax, fare and bag
  checks apply. If Core3 offers a new-player coupon dialog, this credit-purchase
  action selects the original pay-credits callback; it does not consume a coupon.
- `travel_board`: exact owned top-level `ticket_id`. Its departure must match
  the current source travel point before the original boarding command runs.
  Boarding requires the source shuttle state and 25 m range. Only rendered
  Tatooine destinations are exposed and accepted; other planets are rejected
  before consuming a ticket. Successful travel returns the original randomized
  destination and consumes the selected ticket. Live travel creates a pending
  `{id,kind:shuttle,destination}` transport using the existing validated position
  acknowledgment; stale pre-travel movement cannot undo it.

Terminal use checks native type, same cell and source range: missions 6 m,
crafting 7 m, bank/bazaar/travel 8 m. UI distance closure is additional presentation
behavior. Submitted movement is a local prototype trust boundary, not MMO
anticheat. Direct payments are capped and reject stale/remote/unowned actors.

`POST /services/presence` uses the token returned only after an owned native
observation. This endpoint runs outside the serialized native command lock; its
bounded transient hand poses allow smooth local peer interaction without spending
Core3's command budget. Tokens never authorize money directly. Fresh mutual
tracked grip contact creates one request-bound proof, then original native money
transfer remains authoritative. A legacy recipient gets a temporary native login
for the original online transfer and is closed afterward; existing sessions stay
alive. Presence expires and new source cells invalidate old contact proofs.

`0028-terminal-services.patch` exposes original shuttle task state, collector
positions and world terminal heading. Landing pose sampling follows the actual
native task phase, including its original timing arithmetic. The local server
profile changes only startup association delay to 5 seconds using Core3's
existing `ShuttleZoneComponent.BootDelay` setting; landing and departure periods
are unchanged. The native schedule task keeps waiting until Core3 finishes boot.

Validation artifacts in ignored runtime/evidence distinguish original native
transactions from synthetic hand inputs and headless geometry tests. They are
not evidence of live headset ergonomics. Live VR tests remain suspended.

Basic profession trainers use the same original NPC-mounted interaction and service receipts; see [TRAINERS_PROTOCOL.md](TRAINERS_PROTOCOL.md) for native eligibility, training, complete skills and XP snapshots.

## Native RPC admission (0033)

Native operations remain serialized, with at most four waiting requests and a three-second admission deadline. Rejection is HTTP503 `{error_code: "backend_busy", retry_after: 1, mutation_started: false}` plus Retry-After. Clients back off reads and never automatically resend mutations. Health observations cache for eight seconds. Normal service, gathering, inventory, crafting and vehicle RPCs use the native owned-character selection check once, omit unrelated biography/weapon/world replication, and retain original native state/permission checks. Full `/enter` scene replication remains intact.

Mission refresh now reports native cooldown, missing profession or unavailable terminal failures explicitly and only remembers a terminal after original MissionManager populated matching refresh-counter offers. No mission rewards or objectives are fabricated.

## Delivery and crafting parcels (0037)

`delivery_open` is read-only; `delivery_pickup` and `delivery_complete` require
a stable mutation receipt, owned `mission_id` and exact original `npc_id`.
Completion additionally requires the exact `parcel_id`. Core3 validates the active
objective, native giver/receiver, living actors, same zone/cell, range and line of
sight. Pose changes alone do not invalidate an otherwise identical receipt retry.

State projects bounded `delivery_contacts` (32) and `parcels` (16), original
localized dialogue, and original item appearance. A datapad parcel is a view of
the native inventory object, not a second item. Crafting pickup invokes the
original schematic/component reward; its original tool and timed crafting job
produce the tagged output accepted by the receiver. Completion and rewards use
the original asynchronous objective task; clients reconcile subsequent snapshots.

`mission_abort` returns fresh inventory even on receipt replay. Original abort
and timeout cleanup remove only IDs recorded for that objective, including craft
escrow and pending output. Stale crafting jobs cannot recreate cancelled items;
other missions and unrelated ingredients are preserved. Client sequence checks
prevent delayed responses from restoring the datapad or held parcel. Generic
`/datapad/delete` remains disallowed for native mission objects; the explicit
Cancel mission action uses `/services/mission_abort`. Older untracked crafting
items cannot safely be inferred solely by template.

Validation: `delivery-mission-native.json` passed 114 actual Core3 checks;
`mission-parcels-validation.json` distinguishes mocked client checks and desktop
Vulkan evidence. Original assets cover all 24 source delivery NPC variants and
the delivery disk plus five crafting outputs. No live XR validation is claimed.

### Original profession terminal offers (0039)

Mission terminal records carry the native `terminal_type` (`scout` is the
original Explorer terminal). Presentation resolves `terminal_name` and mission
target string-table keys using the installed original datasets. Artisan offers
are original survey/crafting objectives; Explorer offers are recon/hunting.
Neither terminal invents a novice profession prerequisite. Original city access,
refresh cooldown and two-active-mission limits still apply.

Only nonzero native mission types with positive rewards are offered. Core3
clears unused mission slots' type but retains earlier titles/rewards; those slots
must never become selectable offers. Survey completion uses the original
`SurveyMissionObjective` observer, matching resource family, percentage density,
and distance over 1024m from the issuer. It uses current compatible native
resource spawns and rejects remote survey grids from triggering objective credit
(the survey request must be within6m of the actual native player position).
