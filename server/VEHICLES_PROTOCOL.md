# Vehicle deed activation

`POST /vehicles/activate` accepts authenticated `account`, `character_id`, `item_id`, a stable `request_id` (8–64 ASCII letters, digits, `_` or `-`), source world `position`, `building_id`, `cell_index`, and optional `live_session_id`. It works with normal native login and an existing persistent session. Ownership, outdoors/peace/alive state, vehicle capacity and original deed behavior remain Core3 authority. This activates vehicle deeds, not unrelated loot schematics.

The `core3_vehicles` response includes `mutation.success`, consumed `item_id`, new native `device_id` and `vehicle_id`, authoritative `state.datapad`, and the committed decoded `inventory` snapshot. Persistent receipt replay returns the same IDs. Keep the original full payload on uncertain retry; do not silently retry with a new ID. `confirmed_rejection:true, mutation_started:false` is emitted only after durable receipt lookup and before original activation for proven preflight rejection. Unexpected errors after the native handler are not declared safe to repeat.

`runtime/evidence/gameplay-20261005/native-gameplay.json` and `native-final.json` exercise original normal/live deed activation, inventory removal, datapad creation, independent-login persistence, foreign ownership rejection, and exact receipt replay. Fixture starter deeds are consumed deliberately; these are isolated `invtest*` accounts. No live headset validation is asserted.

### Native descriptor deployment (0039)

Core3 reads `SWGXR_VEHICLE_CATALOG` when configured. Otherwise it tries the normal
repository path relative to `MMOCoreORB/bin`, a repository-root relative path,
and the local container `/workspace` path. Deploy `runtime/assets/vehicles/catalog.json`
alongside the server; this bounded original-derived metadata is required for
native seats/hull validation and does not require client geometry or textures.

The native cache checks for catalog replacement every2seconds and reloads changed
path/mtime/size. An initially missing file can become available without a Core3
restart. Missing, invalid, and absent-template catalogs have separate errors;
unknown descriptors never produce placeholder geometry or bypass native ownership.

### Datapad recall and follower droids (0040)

`POST /vehicles/recall` takes `device_id` and the usual authenticated character
and source location fields. It recalls an owned, stationary, unoccupied vehicle
within 7m and line of sight while at peace. It uses original control-device
storage; it does not fabricate hand coordinates. `/vehicles/store` retains the
existing two-hand hull-contact requirement.

`/vehicles/pet_call`, `/vehicles/pet_recall` and `/vehicles/pet_store` take the
same owned `device_id`. Only a native PetControlDevice in that character's
actual datapad controlling a droid is accepted, including the original helper
R2. They invoke original Core3 call/store behavior, preserving pet limits,
location rules, cooldowns and following AI. Recall requires both player and
droid at peace, within 7m and line of sight. `pet_store` additionally requires
finite source-world `left` and `right` positions within player reach and the
native droid height/radius contact volume. Another player's device cannot be used.

The existing `core3_vehicles` state adds owner-only `pet_datapad` entries and
nearby owned `pets`, each bounded to32 rows. Device entries identify `id` as the
control device and `pet_id` as the original creature; world rows identify `id`
as the creature and `device_id` as its control. Rows carry native template,
position, heading, height/radius, combat state and `spawned`. These controls do
not create another client world actor: the shared native world renders droids.

Original calls may be delayed; original StorePetTask executes asynchronously.
`mutation.pending=true` means accepted, not yet confirmed spawned/stored. Clients
poll native state and leave the visual entity until authority confirms removal.
The helper's original scene-ready auto-call lifecycle remains unchanged. There
is no local substitute inventory, follower AI, or persistent pet state.
