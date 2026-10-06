# Core3 terminal and wallet interactions

Approach a bazaar, mission terminal, bank, crafting station, or travel terminal
and point with the main hand, then press trigger. Its holographic interface is
visible only to the local player and stays in front of that terminal. Finger
clicks select controls; holding trigger or grip while moving the finger drags
lists and amount handles. Moving more than three metres away closes the screen.
Losing tracking, opening the system menu, changing character, or entering a
loading transition also releases the interface.

Terminal interaction draws no projected finger beam, including while the
hologram is open. A contact dot marks the selected control. Move the free-hand
stick to highlight a menu row and click that stick to select it. Crafting uses
the same confirmation on its schematic and resource panels.

The backpack remains accessible while browsing a bazaar or vendor. Its controls
temporarily take focus while the terminal stays open; closing the backpack
returns focus to the terminal. Draw an owned item and release it onto the market
to open its sale proposal, then set the price and confirm. Listing still requires
the native Core3 receipt. Wallet and bank interactions retain exclusive hand use.

The bazaar uses the original Game Object Type category hierarchy and source
string labels. Select a category to descend into its subcategories. **Back**
returns to the parent and restores its selection and scrolling position. Server
pages are filtered before the listing limit is applied. Purchases, bids and
retrieval invoke Core3's auction manager; the UI never creates an item or charges
a locally estimated price. The supplied media do not contain the later NGE
commodity exclusion table, so the exported hierarchy explicitly records that
patch-level limitation.

Mission terminals expose native offers and active missions. Refresh, accept and
abandon act on the original mission objects and persistent datapad. Rewards and
objective eligibility belong to Core3. Crafting stations list compatible owned
tools; selecting a tool draws its original model and enters the existing native
crafting interface. Source station type, range, skill, ingredients and original
crafting rolls still apply.

Deployed factories open by pointing and pressing trigger. Insert a source
manufacturing blueprint from the datapad into the slot above the centre panel.
Drag matching inventory resources into the centre input inventory, and grip/pull
them back out to retrieve them. Finished items appear in the separate right
output panel. Energy and upkeep controls sit on the left. Factories share
harvester placement and two-hand recovery; stop production and empty both
inventories and the blueprint slot before recovery. See
[factory controls and authority](../server/HOUSING_PROTOCOL.md#factories).

Mission types needing an interaction this prototype does not yet provide, such
as delivery-NPC conversations, remain visible with an explanation and a disabled
Accept control. Existing active missions can still be abandoned. Target
coordinates, difficulty and rewards come from the original mission record.

The six basic profession trainers—Artisan, Brawler, Entertainer, Marksman, Medic
and Scout—use the same local holographic interaction. Approach the existing
trainer NPC, point and press trigger. Select a skill to inspect its requirements
and training cost, then use the training control when eligible. Core3 checks the
actual trainer, range, prerequisites, XP, remaining skill points and credits again
before granting a skill. Training uses carried credits first and bank credits
for any remainder, following the original trainer rules. Original trainer text
and skill descriptions come from the supplied media. Moving away closes the UI.

In the datapad's skill trees, unlearned boxes show current XP against the source
skill requirement. Each bar uses the shared Core3 XP pool for that experience
type, including boxes whose prerequisites remain locked. Filling a bar does not
bypass prerequisites, credit costs or skill-point limits. Training spends XP and
updates all affected bars; learned boxes omit the bar. Missing character data is
shown as unavailable, and skills with zero XP cost say "No XP required". Live
updates retain the selected box and scroll position.

Reach behind the lower back with the offhand and squeeze grip to draw the
original credit-chip wallet. Keep grip held to hold it; release stows it. Carried
and bank balances appear above it. A bank terminal provides deposit/withdraw
controls and a grabbed amount slider. Adjusting a slider is a proposal only;
**Transfer** submits the amount to Core3.

For a direct payment, hold the wallet and grip/shake the other player's tracked
main hand with the free main hand. The local payment panel appears above the
wallet after fresh mutual contact is confirmed. Set the amount, check the named
recipient, then press **Send credits**. The hand-contact authorization expires,
is bound to one request, and becomes unusable if tracking or proximity is lost.
Original Core3 tip rules perform the cash transfer. Transient hand presence is
not a character or balance database. Remote participants use their source race
and native appearance; unavailable appearance data is explicitly labelled.

Buy an original ticket at a travel terminal. Core3 controls shuttle landing and
departure. Walk into the open-door boarding area while holding a valid ticket in
inventory. One eligible ticket boards directly; multiple eligible tickets open a
local chooser in place of the datapad. Native boarding checks the ticket and
schedule again. A loading cover stays up until the server-selected destination's
streamed terrain, original cells and collision floor are ready. This client
supports the ten original ground planets. Routes must be available in the running
Core3 realm and destination assets must be ready; unsupported or unprepared trips
are rejected before a ticket is consumed. The owned session remains connected
while old world geometry/entities are retired and the destination loads. Failed
loading stays covered with a retry option; acknowledgment follows valid original
floor placement.

## Validation and operation

`python tools/assets/prepare_services.py` exports source models, shuttle clips,
and terminal metadata to ignored `runtime/assets/services`. Its trainer audit
records all 51 basic-profession trainer placements on Tatooine and their original
appearance variants, so native trainers reuse the existing population.
`python tools/assets/prepare_bazaar_categories.py` exports the category hierarchy
using local STF labels and a pinned, hash-checked public source-code enum.
`setup.sh` and the launcher's inventory asset preflight prepare this catalog when
needed. Native discovery supplies the actual terminal object IDs; negative
client-layout placement IDs in the source catalog are never sent as native IDs.

Relevant checks:

```sh
python -m unittest tests.test_services_protocol tests.test_services_presence tests.test_live_service_sessions tests.test_trainers_protocol
python tools/assets/test_services.py
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/xr_services_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/services_controller_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/bazaar_tree_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/profession_xp_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/trainer_services_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/service_world_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/service_peer_smoke.gd
godot --headless --xr-mode off --audio-driver Dummy --path client --script res://tests/service_travel_floor_smoke.gd
```

The floor check covers all thirteen original Tatooine travel centers using
streamed source geometry and the actual collision capsule. UI captures use
desktop Forward+ Vulkan with mock transaction data. Neither headless tests nor
desktop captures establish live headset ergonomics. Live VR tests remain
suspended at the user's request.

Native validation reports are in ignored `runtime/evidence/services-*-native.json`
and `services-native-smoke.json`. They cover original bank balance conservation,
persistent mission acceptance/abandonment, bazaar purchase/retrieval, direct cash
payment between test characters, shared live sessions, compatible crafting
station/tool selection, ticket purchase and boarding. Capacity, wrong-departure
ticket and closed-shuttle checks verify rejection without losing credits or
tickets. These exercise local Core3; hand poses used for payment validation are
synthetic, so they do not establish physical handshake usability in a headset.

`services-mission-native.json` additionally records a complete original destroy
mission: native acceptance, mission-launched lair, a certified owned FWG5 shot,
MissionObserver completion, bank reward and combat/pistol XP, then independent
login verification. Its helper `tools/server/services_mission_smoke.py` requires
an explicit dedicated-fixture flag and weakens only the newly spawned fixture
lair to keep that integration check short. It does not call an objective-complete
shortcut. The helper restores the test character's position and removes its
temporary fixture script; Core3 remains running.

Trainer evidence is recorded in `runtime/evidence/trainers-validation.json`:
35 actual Core3 checks cover all six professions, exact XP/skill-point/credit
deductions, rejected training, durable replay, reconnect persistence, interior
trainers and live-session training. Complete XP maps agree across services,
legacy datapad and live snapshots. The client has 75 trainer checks and 17 XP-bar
checks; desktop Vulkan captures use synthetic eligibility/XP and original source
definitions. See `server/TRAINERS_PROTOCOL.md` for the backend contract.

## Gameplay recording follow-up — 2026-10-05

The supplied `core.mp4` shows populated survey results and a populated crafting
recipe list, but missing crafting previews, unreadable wrist panels and a long
inventory read while recovering a deployed sampler. At surveying skill20 and
29% density, the original sampling rule produces one unit and rejects it as a
trace amount; a zero display alone did not distinguish this from a stalled tool.
The sampler now exposes the native outcome, next cycle and productive-density
guidance. Its left pane shows the selected resource's original container and
source quality attributes. Recovery returns the committed inventory within the
same native transaction and retains a receipt for explicit uncertain retries.

Dedicated service RPCs skip unrelated biography, weapon and nearby-scene reads.
Native character ownership remains checked by `SelectContextAction`. Adapter
admission is bounded: a saturated queue returns `backend_busy` before mutation.
Client inventory/gathering/crafting/service/vehicle HTTP calls have a15-second
deadline; timeout is an unconfirmed outcome, never a success or automatic retry.
Idle terminal polling is5seconds; nearby shuttle boarding uses1second updates.

Terminal panels use original screen centroids and normals extracted by
`tools/client/build_terminal_screens.py`:14 templates have measured screen data;
three crafting templates without separate screen geometry use an object-relative
facade. All poses stay fixed to the terminal. Source and native terminal/trainer
POIs appear in map filters; source references do not authorize interactions.

Voice and HAM share a forearm-bone attachment, with their long axes along the
arm. Left/right bases preserve outward normals and readable text orientation.
The preview camera uses independent world-up so it cannot conceal inverted text.
The voice panel shows a depth-prioritized fingertip cursor. Crafting side panes
are spaced and tilted; main-hand joystick input scrolls its schematics directly.

Focused original-skeleton/UI regressions and desktop Forward+ Vulkan captures
are under `runtime/evidence/voice/`, `runtime/evidence/wrist-services/`, and
`runtime/evidence/survey-tool-preview.png`. Native mission offers, acceptance,
persistence and abandonment passed; the recording's absent mission interface
was not reproduced by native tests. Screen placement, polling and explicit
rejection reporting were corrected. No live headset test was launched.

## Second recording follow-up: core1.mp4

Mission controls use separate trigger-click and grip-drag edges. A pre-press hover
latch preserves the intended button while squeezing the trigger curls the rendered
index finger. Dragging captures hand translation until release. Only the pointing
hand's joystick is consumed by a terminal list; the other hand can move away.
Open static terminal UI survives delayed status refreshes, while original cell and
range checks still close it and Core3 validates every mutation. Shuttle freshness
requirements are unchanged.

Voice and HAM mounts use the source forearm center/long axis plus tracked wrist
axial twist. The original lower-arm IK basis alone stayed neutral during wrist
roll, which caused the recording's permanently hidden readouts. Fixed-eye desktop
Vulkan captures now show both arms' controls revealed by native tracked roll, with
no camera-following correction. Shared finger rays derive their source skin extent
once and transform it using the rendered skeleton each frame.

Client regression evidence is in `runtime/evidence/gameplay-core1/`,
`runtime/evidence/forearm-roll/`, and `runtime/evidence/datapad-vehicle-preview.png`.
Native session ownership, saved interior/world position and vehicle lifecycle
checks are in `runtime/evidence/session-20261005/`. All use dedicated fixtures or
mocked tracking; no live headset test was launched.

### Landspeeder yoke controls

While gripping a landspeeder yoke, the main-hand joystick controls forward
throttle and braking/reverse with a 12% deadzone. Moving the hands around the
wheel steers; pushing or pulling the hands does not change throttle. Rendered
avatar hands attach to the original riding grip sockets and use original rider
finger poses. Releasing, losing tracking or dismounting restores normal hand
tracking. Controller and HMD transforms are never modified by this attachment.

The original X31/X34 and AV21 steering components rotate locally. The exporter
separates complete disconnected source components, retaining every original
triangle and material. Flash's component joins the dashboard stem, so it remains
static with an explicit unsupported-split diagnostic. No substitute art is used.
Validation is recorded in `runtime/evidence/vehicle-yoke/validation.json`; the
Vulkan capture is desktop evidence, not live headset validation.


## Merchant vendor placement

The datapad **Vendors** tab references vendors already hired and owned in Core3.
Grip a row with the main hand and pull it away from the datapad. Keep gripping
while moving the original-model hologram across the floor and rotating it with
your hand. Cyan means the local preview passes the current permission, room,
floor, obstruction and four-metre reach checks; orange means it cannot be placed.
Release and press trigger while holding the hologram to place it. Releasing grip
before confirmation, losing tracking, opening the menu or changing session
cancels the preview without moving or consuming the native vendor.

Core3 rechecks ownership, uninitialized state, inventory possession, public
building/admin-or-vendor permission, same cell, native floor and line of sight.
The normal vendor initialization starts its original maintenance checks. A
successful receipt removes the inventory reference and presents the native
placed object to clients in that room. Releasing grip after the trigger request
has already been submitted hides the preview but cannot reverse that request.
Repeated trigger holds do not resubmit, and a busy service never queues a delayed
placement. An uncertain reply requires a fresh authoritative vendor snapshot.

Hiring remains outside this interface. NPC vendor previews use the original
bind-pose item mesh and customization, including body and face morphs, without
dynamic clothing or idle animation. Terminal and droid models retain their authored origin and scale.
`tools/assets/prepare_vendors.py` records original asset hashes in the inventory
catalogue and conversion coverage in `runtime/assets/vendors/coverage.json`.

Implementation: `0043-vendor-placement.patch`, `/services/vendor_place`, and
`client/scripts/vendor_placement.gd`. Headless protocol and mocked-controller
checks pass; these do not validate native deployment or live XR. The current
sandbox prevents Podman access (`/run/user/1000/libpod` is read-only), so native
compilation, persistent placement/restart checks, and live headset verification
remain outstanding.


## Vendor and bazaar selling, customization and recovery

Drag an owned inventory item onto a bazaar terminal or an owned vendor and
release it. This opens a holographic sale proposal with coarse/fine credit
sliders, a full-colour item preview and a grip-operated galactic-search knob.
Clockwise enables search; counterclockwise disables it. Touch **Confirm** and
press trigger to submit; **Cancel**, tracking loss or leaving the interface
returns to normal play without transferring the item. The item remains in its
native inventory until Core3 confirms the sale. The original limits apply:
20,000 credits for bazaars and 99,999,999 for vendors, together with native fees,
capacity, trade restrictions and ownership checks.

The search knob controls the individual listing. Off listings remain visible at
their own terminal and to their seller/buyer. Global bazaar browsing can discover
searchable vendor listings and their location; purchase and retrieval of vendor
stock require visiting that vendor. Existing listings default to searchable.
Core3 records visibility before publishing the listing, and both native search
and the VR services bridge honor it.

With both hands touching an owned placed vendor, release then press both
triggers to open customization. Grip the original colour and body/face sliders;
the full-colour preview updates locally. Pages expose the source template's
permitted values. Confirm commits the proposal; Cancel leaves the native vendor
unchanged. Models with no original editable controls show that limitation.
Changing outfits or hair objects is not part of this first vendor editor.

A fresh two-hand grip with both triggers released recovers the vendor into its
native inventory and datapad reference. Trigger customization takes precedence
if grips and triggers are pressed together. Inventory space is checked before
recovery. Stored vendors keep their identity and listings, become unavailable
to buyers/search, and stop their maintenance task, planetary marker and barks.
Normal listing expiry remains in effect. Replacing the vendor restores native
location/indexing and its previous search setting. Recovery is an explicit
extension to Core3's normal prohibition on moving initialized vendors.

`0044-vendor-commerce.patch` contains the authoritative changes. The client never
queues a deferred economic mutation behind a busy service. Ambiguous retries
retain the exact original proposal and request ID; changing character clears
local drafts and old input state.

Validation evidence: `runtime/evidence/vendor-commerce.json`. Protocol,
headless mocked-controller checks and Core3 IDL generation pass. Full C++ build,
native sale/recovery/restart testing and live headset verification remain
blocked by the current Podman access restriction; the host also lacks the native
Lua/Berkeley DB development headers. These changes have not been deployed.
