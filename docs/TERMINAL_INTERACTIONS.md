# Core3 terminal and wallet interactions

Approach a bazaar, mission terminal, bank, crafting station, or travel terminal
and point with the main hand, then press trigger. Its holographic interface is
visible only to the local player and stays in front of that terminal. Finger
clicks select controls; holding trigger or grip while moving the finger drags
lists and amount handles. Moving more than three metres away closes the screen.
Losing tracking, opening the system menu, changing character, or entering a
loading transition also releases the interface.

Pointing at a closed terminal does not draw a guiding line. The opened hologram
retains its fingertip pointer and click dot for selecting and dragging controls.

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
currently renders Tatooine, so unsupported interplanetary trips are rejected
before a ticket is consumed.

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
