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


### Droid and creature pet commands (0046)

`0046-pet-commands.patch` extends call/recall/storage to native creature pets,
including bio-engineered pets, while retaining original owner, pet-level,
Creature Handler, active-pet, location and cooldown rules. Owning a crafting
profession does not manufacture a pet, grant commands, or bypass those rules.
The original `PetControlDevice` call path installs the pet AI template. Commands
use original Core3 pet handlers and wake its AI behavior/recovery; movement and
combat stay on Core3, with shared-world actor replication on the client.

Hold the **empty offhand** over a visible owned pet/droid and click its trigger.
The standard holographic wheel follows that hand. Move its stick to select one
of that specific control device's trained commands. The prepared icon appears
over the offhand. For an untargeted command, the next fresh trigger click executes
it. For a targeted command, the first click enables an independent hand-bound
reticle; the second click requests the command against the first eligible visible
recipient. Obstructed or missing targets leave aiming active. Dispatch consumes
the selection, including a subsequently rejected/unconfirmed native request;
no automatic retries or deferred busy actions occur. Choose another command
from the pet to act again. Offhand stick click or trigger closes an open wheel.

The offhand slot is independent of weapon selection and the saved medical
selection. A medical tool, bag/tool interaction, vehicle control or two-hand
weapon support makes it unavailable. Becoming occupied hides the pet UI and
cancels aiming but preserves the prepared command. Tracking loss requires a
release and fresh trigger press. The command trigger is reserved until release,
so the same click cannot also punch or sample DNA. Menu stick capture uses its
own field and releases after selection/closure once the stick returns to neutral. Both dominant-hand preferences
are supported. **Both hands touching the pet and gripping recovers it**; original
call/store restrictions still apply. Contact uses the current rendered original
bounds on the client and the original appearance sphere on Core3, including
large creature pets. Unavailable original appearances cannot be touched.

`POST /vehicles/pet_command` carries `device_id`, an integer `command_id` from
Core3's 1–23 command table, and a stable `request_id`. Targeted commands also
require the actual native `target_id`; untargeted commands reject a supplied
target. The server validates ownership, trained command, called/living pet,
64 m command/target envelope, zone/cell, target category and line of sight before
invoking the native handler. Its power, modules, target legality, group and
transfer checks still apply. A bounded persistent receipt ledger makes an exact
retry idempotent, without binding the receipt to moving hand/body coordinates.
The client does not inject chat text or alter the main-hand weapon target.
Guard accepts the explicit offhand target while legacy chat retains its normal
selected-target behavior. Commands such as patrol, mark/clear patrol point,
formations, tricks, special attacks, ranged-mode toggle, repair, recharge,
trap, harvest, friend, group and transfer appear only when actually trained.
“Mark patrol point here” retains Core3's player-position mechanic.

Owner snapshots add `pet_kind`, death/incapacitation flags and `commands` to
`pets`/`pet_datapad`. Shared actor snapshots expose `attackable` and `droid` for
reticle filtering; Core3 rechecks the final target. Original generic SWG action
icons are reused for the labeled commands; their source hashes remain in
`runtime/combat/abilities/catalog.json`. No replacement pet art or local AI is
introduced.

Validation results: `runtime/evidence/pet-commands.json`. Protocol tests, mocked
controller/reticle tests, original weapon input, medical, DNA and datapad recall
regressions pass using `--headless --xr-mode off` and the dummy renderer. Patch
replay checks pass. Native compilation, running-server AI movement/attack/
patrol/power/receipt verification and live VR remain **unverified and undeployed**:
Podman cannot access read-only `/run/user/1000/libpod`, and the host lacks required
Lua and Berkeley DB development headers. Headless tests are not Vulkan evidence.

## Creature Handler gestures and native training

Creature Handler requests use an existing owned, retained Core3 gameplay session
(`live_session_id` or `session_id`). The adapter rejects an ephemeral login for
these actions: original taming schedules a native task that outlives its initial
acknowledgement. Source position, zone and building/cell context use the same
validation as other vehicle/pet requests.

| Route suffix | Additional fields | Native behavior |
| --- | --- | --- |
| `ch_status` | none | Current skills, commands, XP, tame candidates/progress and owned-pet eligibility. |
| `ch_tame` | `target_id`, `request_id` | Original `tame` command; eligible wild baby within 8 m, same cell and unobstructed sight, original level/storage/control limits. |
| `ch_embolden`, `ch_enrage` | `request_id` | Learned original command affects eligible active creature pets within 50 m. Original mind cost, 60-second buffs and 300-second per-pet cooldown apply. |
| `ch_train_mount` | `device_id`, `hand`, `request_id` | Original support-IV, species and scale checks, reachable source-body touch, then original `PetControlDevice::trainAsMount`. |
| `ch_train_command` | `device_id`, `command_id`, `request_id` | Original profession/radial eligibility and probabilistic `PetManager` command training; original XP on actual new learning. |

The client recognizes gestures; gesture duration does not grant a skill, pet or
training result. HTTP fields such as `force`, `adult`, custom probabilities or
client-supplied skill levels are never forwarded. IDs are ASCII unsigned native
object IDs. Mutation receipts are bound to the semantic action/target/command,
excluding changing body and hand poses. Repeating a receipt returns its original
result without another training roll, buff cost or tame task.

The existing envelope remains `source_kind: core3_vehicles`, `state`, and
`mutation.success`; it does not require a new top-level `ok` flag.
`state.creature_handler` contains `skills`, `commands`, `experience`, at most
32 nearby `candidates`, and `taming`. Candidates include original template,
position, baby/level, `can_tame`/`eligible`, a rejection reason and source bounds.
Each `state.pets`/`pet_datapad` row has `creature_handler` eligibility for
`embolden`, `enrage`, `train_mount`, `trained_as_mount`, and `train_commands`.
Mount training is an original skill-gated radial; clients must use per-pet
`train_mount`, rather than assuming a `trainmount` ability string exists.

Taming acceptance returns `mutation.pending: true`. Original Core3 taming uses
three 10-second phases after acceptance, with its normal chance and interruption
checks. Poll `taming.state` (`pending`, `succeeded`, `failed`) and inspect the
actual resulting `device_id`. A successful command acknowledgement is not a
tamed pet. Similarly, `ch_train_command` can be accepted with `learned: false`;
that is an unsuccessful native roll, not an unlocked command. A terminal tame
result is persisted after native ownership is established; storing, calling,
relogging or later transferring the pet cannot change that historical result.
Native pet storage
and calling can also return `pending`; wait for authoritative `spawned` state.

### Source bounds for skeletal creatures

Core3's original appearance parser does not provide SAT skeletal bounds. Global
pet touch validation therefore uses the server-owned converted source catalogue
`runtime/assets/pets/body_bounds.json`, with the optional
`SWGXR_PET_BOUNDS_CATALOG_PATH` override. The catalogue is generated from original
user-owned meshes/skeletons, records source and model hashes, and includes the
same visual grounding used by the client. It contains no client-supplied bounds.
Native loading is bounded to 2 MiB/1,024 templates and cached with a two-second
reload check. Original creature collision-template dimensions remain a labelled
fallback if converted metadata is absent; they are not silently expanded.

Unscaled catalogue coordinates are original X/Y-up/Z. Apply the native pet scale
and world heading, including a containing building's rotation. The global touch
check retains its 3.5 m owner reach and 0.2 m surface margin. The client still
uses the actual animated head for a head-pat gesture. This distinction matters:
bantha's original generic collision height is 1.8 m, while its original head
extends above and beyond that cylinder. The source mesh bounds admit its real
head without introducing a fabricated body size.

`tools/server/creature_handler_smoke.py` exercises real native actions on fresh
`invtestch` accounts. Its trusted server screenplay explicitly provisions source
master prerequisites, an original wild baby, and later original pet maturation;
those diagnostic prerequisites are not claimed as earned progression. Taming,
training rolls/XP, buffs, costs, mount training, storage/calling and persistence
remain actual native operations. No HTTP administrator route is added.
