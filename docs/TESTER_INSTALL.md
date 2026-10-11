# Install the SWGXR test client — 2026.10.11

Download the Linux or Windows client from the [test release](https://github.com/jebot-git/swgxr/releases/tag/v2026.10.11-test.12). Original game data is prepared locally from your SWG The Total Experience installation or all five installation ISO images. No private asset ZIP is required.

## Requirements

| Platform | Requirements |
| --- | --- |
| Linux | x86_64, glibc 2.43+, libstdc++ with GLIBCXX_3.4.30, Python 3.10+ with Tk, Vulkan drivers |
| Windows | x86_64 and Vulkan drivers; Python and Tcl/Tk are included |
| VR | Configured OpenXR runtime and connected headset |
| Storage | At least 40 GB free for original archives, preparation and rollback data |

Forward+ on Vulkan is the supported renderer. Standalone Quest, Mobile, Compatibility/OpenGL, Direct3D and ARM are unsupported. Linux requires Tk (`python3-tkinter` on Fedora, `python3-tk` on Debian/Ubuntu). Do not replace a distribution's system C library to run this build.

## Prepare your original game data

1. Extract the complete client into a short, writable path, such as `C:\SWGXR` on Windows.
2. Open `launcher.cmd` or `./launcher.sh` and choose **Prepare game data…**. Select your installed **SWG The Total Experience** folder. Alternatively put all **five** Total Experience `.iso` files into the client's `data/` folder; the launcher detects the complete set automatically.
3. Let extraction and conversion finish. Progress and errors appear in the launcher. Completed steps resume after an interruption. Preparation runs no original installer and needs no administrator privileges, compiler, pip or extra conversion tools.
4. Configure your OpenXR runtime and choose **Play in VR**, or use **Desktop mode** for regression and asset inspection.

`import-data.cmd` / `./import-data.sh` prepares data without starting the game. For a local installation from the command line, append `--game-installation "path to SWG"`. The GUI prompts for that folder when no five-disc set is present.

The supplied Total Experience discs contain all 51 archives used by the current pre-CU client, byte-for-byte identical to the active development source set. All 58 original archives are retained under `runtime/original-game/tre` for future recipes. The pinned 51 retain precedence; the other seven supply only otherwise absent client assets. This does not promise that future expansion assets, or every dangling reference inside an original file, exist on these discs. Missing source references and conversion failures remain in the catalogs and logs. The launcher never downloads original SWG media.

The package includes open-source converters, Python, Pillow, NumPy, FFmpeg and Unshield. Licenses and dependency hashes are under `engine/data-preparation/licenses` and `dependencies.json`. Source archive hashes are in `runtime/original-game/sources.json`; successful preparation creates `GAME_DATA_RECEIPT.json`. Logs are under `runtime/preparation/logs`. Existing prepared data is replaced only after conversion succeeds, with the prior set kept for rollback.

Do not move an installation after preparation: some converted catalogs contain absolute paths. To relocate, extract a fresh client and prepare again from your retained original files.

## Character to VRM

Choose **Export character to VRM…** in the launcher after preparing game data. Close the game, enter your account and password, and choose **Load characters**. Select your character, re-enter the password, and choose an output `.vrm` filename. The exporter uses the bundled engine with XR disabled; it does not launch the game world. Sign-in credentials are not saved, and its temporary login session is revoked after each server read.

**Export saved snapshot…** also accepts an offline full character response. The avatar includes current customization, hair and worn/held equipment, with a conversion report beside it. Existing files are preserved: choose a new filename. Exports inside the client folder belong under `runtime/character_exports`. Missing visible equipment fails explicitly. The output is VRM 1.0 without facial-expression presets or spring-bone simulation; verify it in your target avatar application. See `engine/character_export/README.md` for format details.

The bundled `engine/docs/MEDIA_SCOPE.md` documents missing original references that affect content through Rage of the Wookiees and distinguishes absent files from converter limitations. The [same audit is available online](https://github.com/jebot-git/swgxr/blob/main/docs/MEDIA_SCOPE.md).

## Updates and shortcuts

Use **Check & install updates** or `updates.cmd` / `./updates.sh`. Close the game first. Updates preserve accounts, connection settings and original source archives. When the conversion recipe changes, the next preparation updates local data from those retained sources. The updater itself does not launch the game. From test.15 onward, matching installations use verified incremental bundles from the corresponding `-patches` release tag. A changed or unsupported baseline falls back to the complete client archive. To bootstrap an older launcher without a full download, replace only `update_test_client.py` in the closed client folder with the standalone file from the test.15 patches release, then use the normal Updates shortcut.

Existing test.11 installations can update in place, then choose **Prepare game data…** and supply their original installation or five ISOs once. The old private asset archive alone does not include the new audio banks. The legacy `--asset-archive` import remains available for older distributions.

Run `install-shortcuts.cmd` / `./install-shortcuts.sh` to create SWGXR, VR, Desktop and Updates shortcuts. No administrator privileges are needed. For clients older than test.11, extract this complete release into a new folder, or use the standalone updater published with the release.

## Verify downloads

Compare the client archive against `CHECKSUMS.sha256` attached to the release. Original media is never included in those public archives.

## Connect and create a character

The package includes the server address **`https://87.106.27.237:18443`** and its public CA certificate. Keep `server.json` and `server-ca.pem` with the client. No account credentials or private keys are included.

Create a new account in the sign-in panel, then create/select a character. Invitations are not required on this test realm. Accounts created after the initial test-realm reset are preserved by this update. Your account's first character receives an original Luxury Yacht when entering its gameplay session; use an original starship terminal for crew preparation and launch. Ground scope is the ten original planets. Space includes the ten original JtL sectors and original hostile encounters; the Luxury Yacht remains excluded from combat. See [JtL test scope and limitations](JTL_TEST_STATUS.md). The realm restarts daily at **05:00 UTC**.

## Troubleshooting and test status

Client test.18 and later keep the latest eight play sessions under `runtime/client/logs`: engine output, launcher exit status, and the last 256 request timings/errors. Request diagnostics omit request bodies, account credentials and query strings. Include these files when reporting a disconnect.

Test.5 fixes microphone activation being disabled in the client project. Voice still starts muted; select your microphone in Settings, join an available voice channel, and select push-to-talk or voice activation. Failed activation can retry, and its message clears after capture succeeds. If opening still fails, check the selected device and operating-system microphone permissions.

Synthetic speech captured through a virtual Linux input passed the production RNNoise/Opus path, startup mute, push-to-talk and shutdown checks. Voice controller, codec, context, channel routing and microphone preference regressions passed. Physical headset microphones and native Windows microphone capture have not been tested in this update; headset tests remain suspended.

- **Missing archives:** select a complete Total Experience installation or all five matching ISO images. Base-game CDs alone are insufficient.
- **Preparation failure:** inspect the named log under `runtime/preparation/logs`, correct the source problem and retry. Existing installed assets are preserved.
- **Insufficient space:** allow at least 40 GB free, including conversion and rollback data.
- **Relocated data:** prepare again in a fresh client folder at the desired path.
- **GLIBC/GLIBCXX errors:** the Linux build requires the library versions listed above. This release does not provide an older-distribution build.
- **OpenXR initialization failure:** confirm that your headset is connected and the intended OpenXR runtime is active. Desktop mode is only a separate inspection/regression option.

Audio checks use original recordings through the production playback paths, including Linux PulseAudio mixing with muted physical output. Headless regression tests use the dummy renderer. Native Windows Vulkan/OpenXR and live headset validation remain separate; Wine does not establish hardware support.

All ten sectors were captured with desktop Forward+ Vulkan. Native Shipwright crafting/experimentation, pilot enlistment/first patrol, chassis redemption and component swapping passed live Core3 tests. See [JtL test status](JTL_TEST_STATUS.md) for combat-fixture boundaries and remaining source/presentation limitations. Windows uses standard spatial audio fallback and includes TwoVoIP.

UI pointing uses the controller aim throughout the client. Finger bending does not
move the cursor, and only a targeting dot is shown. Dropdowns open within the VR
panel: trigger to select, hold trigger and drag to scroll, or use the pointing
hand’s stick. Character-creation slider handles stay inside their scroll area.

Open the equipment hologram and select **Combat abilities** directly below the
character to equip skills. The same button returns to **Equipment**; right-stick
click remains a shortcut. Point with controller aim and release then press the
trigger to select the button. Walking 1.5 metres from where you opened the
hologram closes it and cancels unfinished drags; crouching keeps it open.

The client keeps its native gameplay session alive while idle or in the menu.
If the connection is lost, movement pauses and the menu offers **Reconnect**.
Reconnection restores the location confirmed by Core3. A timed-out deed, purchase,
or other action is not automatically repeated: refresh inventory or service state
before deciding whether to retry. Voice availability follows the native session;
group and faction channels also require the corresponding membership.

To return to the pilot seat after walking around the yacht, approach the seat on
the bridge, aim at **Take pilot seat** above the chair, and press the trigger.
Only controller aim moves this pointer. The ship commands wheel opens with the
dominant-hand stick click while seated as pilot or copilot. The offhand stick click leaves
the current station. The ship owner can pilot; occupied seats and seats in
another room remain unavailable.

Ship item placement waits for an in-flight walking update to finish. A rejected
or unconfirmed placement keeps the item in hand and replaces the pending message
with its outcome. Check inventory before retrying an unconfirmed action.

Entering a ship seat turns your view toward the controls. In **Virtual HOTAS**
mode, hold your main-hand controller upright briefly, then tilt for pitch and
roll or twist for yaw. Hold your off-hand controller sideways briefly, then
push forward to accelerate and pull back to slow down (28 cm for full travel).
Turn a hand out of its control pose to release and reposition it; the throttle
holds its setting. Returning to the pose captures your new comfortable position
without a throttle jump. The selected dominant hand determines steering.
Thumbsticks and grip buttons are free for other controls. Opening a panel,
losing tracking/focus, or stale server state cuts thrust; hold the poses again
to resume. These controls have automated mocked-tracking validation; live
headset comfort and controller-specific grip orientation still need testing.

Walking through a yacht doorway now updates the native room before item placement.
If that update is rejected, the client returns to the confirmed position and
keeps the item in hand. Ship-terminal holograms open above the keyboard.

At a starport travel terminal, select a destination to see its original planet
map, marked arrival point and fare. You can also select a destination by its map
marker. Press **Buy ticket** to purchase. Maps use the existing runtime assets;
the JtL update requires the matching new assets archive.

Physical crouching and prone movement resize the tracked collision capsule
without shifting its foot position or accumulating a vertical world offset.
Login also repairs a saved position up to two metres below an original floor,
within the saved horizontal footprint, when the full capsule fits. If falling
below a doorway left stale room membership, recovery may use its directly
connected original room. Missing floors, unconnected rooms and obstructed
destinations remain loading errors.

To recover a placed item in a house or ship, leave your seat, put away held items, close inventory, touch the item with both hands and squeeze both grips. Stay in the same room while the request completes. A confirmed recovery returns the item to inventory; it does not put it directly in your hand. If confirmation is lost, check inventory before trying again. Fixed house and ship fixtures cannot be recovered.


In a POB, the original ship housing terminal also lists recoverable placed items.
Select an item and confirm recovery while near the terminal. Original ownership,
room and inventory-capacity checks apply; fixed fixtures cannot be recovered.

Choose **Microphone** in Settings to save a capture device. A disconnected device
falls back to the system default and retains your preferred choice for its return.
Changing the device does not unmute or start transmission.

Pilot trainers, crafting, components, sector navigation, combat limits and known
missing source assets are documented in [JtL test status](JTL_TEST_STATUS.md).
Space mining is deferred to a later stage.

Creature mounts use the original saddle seat: touch the saddle and press trigger to board an owned, trained mount. Squeeze either grip or both to hold the reins, then use the left locomotion stick to move forward/backward and steer. Sideways stick input turns the creature; it cannot sidestep. Release both grips to stop driving. The existing jump button dismounts. Lost tracking, UI input capture, and a stale server connection suppress mount control.

The mount update passed 82 mocked-tracking checks, eight live Core3 mount checks, and the chassis-dealer appearance matching regression. Headset tests are suspended until the organizer requests them; this update has no new headset validation.


Flight readouts show throttle percentage and the native engine speed limit. In motion-stick mode, push the left stick forward to increase throttle and pull back to reduce it.

While piloting, open **Communications · request landing**, approach the desired station within its original 1,000-metre conversation range and choose a spaceport. Core3 lands you on the selected planet at that spaceport’s original coordinates. The command wheel and datapad no longer offer a return-to-launch-port shortcut. Hyperspace uses native countdown/entry/arrival phases with original cockpit particles and sounds; install the matching presentation data archive for these effects.

## Presentation update (test.6)

Bazaar browsing offers Local (this terminal), Planet, Galaxy and Vendor scopes. Galaxy is the default; Vendor searches visible player-vendor listings. Stock is a bounded initial batch on each ground planet, not an unlimited replenishing shop. Banking and selling panels sit beyond the terminal casing.

The hyperspace planner displays the original jump-point name and station distances. Corellia and Talus share the original `space_corellia` sector: choose a Corellia station and then the intended Corellia spaceport to land there. “Talus Secta” is a Talus-side jump point. Station dialogue appears in the centre of the communications wheel.

Pilot seats apply the original chair pose and a seated play-space height; head and controller tracking remain live. Hyperspace follows the tracked centre-eye frame. Original ship cabin/engine sounds and source-defined sector/combat music use the existing Ambience and Music volume controls. Empty original music bindings remain silent. Desktop Vulkan and synthetic checks cover these changes; live headset validation is suspended.


## Sector and companion menu update (test.7)

Point your empty offhand at a called, owned droid or creature pet and click that
hand's joystick to open its command wheel. Select **Invite / remove from party**,
then release and click the trigger to issue the command. Core3's trained Group
command joins an ungrouped companion or removes an already grouped companion.
The command appears only when the pet has learned it; droids still need power.
Walls, occupied hands and stale connections block the interaction.

The sector update fixes skybox seams and improves original stars, nebulae,
lighting and asteroid visibility. Test.7 used the test.6 private runtime data archive. Test.8 repackages the current
runtime dependency closure under the new asset filename above. Linux and Windows changes have
synthetic/desktop validation only. Keep VR testing suspended until requested.

The main menu now has **Settings → Audio**, **Controls** and **Graphics** pages.
Audio contains volume and microphone selection; Controls contains turning,
standing-height calibration and flight controls. Graphics offers **MSAA: Off,
2×, 4× or 8×**. Changes apply immediately to the headset, desktop and spectator
world views and are saved for the next launch. Higher MSAA levels use more GPU
power; the initial default remains Off. Use **‹ Settings** to return to the categories.

Runtime mipmap generation now also covers original weapon/effect artwork,
sun/moon textures and crafting previews. Ordinary RGB normal-map mipmaps are
renormalized; packed normal-map channels retain their encoding. Curve lookup
textures and nearest-sampled collision/portal masks deliberately remain unmipped.

The wrist minimap now has a larger invisible touch area for opening the datapad:
5 cm beyond each edge and 6 cm in front of or behind the display. Reveal the
minimap with the existing offhand fist gesture, then bring the other fingertip
near it. The visible minimap size and distant-ray behavior are unchanged.

## Terminal and shuttle fixes (test.9)

Banking, bazaar browsing and sale panels now fit inside the original terminal's
visible glass, with its authored orientation. Shuttle landing, takeoff, idle and
power-down sounds use the original client data and animation events; install the
matching test.9 data ZIP to obtain the new samples.

Buy a ticket at a travel terminal. Click the boarding terminal beside the pad,
or choose **Use ticket / board shuttle** at a purchase terminal within boarding range.
Select the owned ticket and confirm **Board shuttle** while the shuttle's doors
are open. This supports elevated pads from the terminal within Core3's boarding
range, without climbing onto the shuttle. Native ticket and schedule checks
still apply. Walking through a shuttle's boarding doorway remains supported.

Movement rejection recovery no longer selects a landing-pad roof several metres
above the player's feet. Original geometry checks covered 28 starport/pad exterior
placements across all ten ground planets, including Talus Imperial Outpost.
Validation used synthetic movement, dummy-renderer smoke tests and desktop Vulkan
terminal captures. Live headset testing remains suspended.

## Missions and combat presentation (test.10)

Test.10 uses the same private **test.9 data ZIP**; no new asset download is needed.
The datapad's **Missions** tab shows owned objectives, descriptions, rewards,
delivery phases and hunting kill counts. Native mission destinations appear on
the planet map. Active waypoints appear on wrist radar, with distant destinations
shown at its edge. Pickup changes a delivery waypoint to its recipient; cancelling
or completing the mission removes its derived marker.

A rejected CDEF or other ordinary ranged discharge restores its reserved shot
capacity, including the last round's automatic recovery. Confirmed discharges
remain spent even if the projectile misses. Nearby space ships use sector lighting;
stations already represented by original sector geometry no longer draw a second
overlapping hull. Desktop Vulkan validation confirmed mipmaps on all 78 textures
loaded for the Tatooine sector. Headset validation remains suspended.

The native damage audit found the existing CoreCU conversion on both minor and
ordinary worrts. Minor worrts are level 5 with a converted weapon range of 16–26;
ordinary worrts are level 6 with 17–29. An unarmoured 3,000-health test character
took 21–32 health per landed minor-worrt hit. Net health loss after combat also
reflects regeneration. This release does not change creature balance.


## Aim assist, combat timing and NPC waving (test.11)

Controls now offers **Ground weapon aim assist: Off / Subtle**. Subtle applies
at most a 0.5-degree correction to ordinary ground shots near a visible hostile
body. It fades out on stale target information and respects cover. Hands, weapon
and viewpoint stay under your control; special and guided attacks retain their
existing targeting.

Ordinary firing now accounts for delayed replies and bounded network jitter,
with server-enforced firing rate and shot costs. A shot that could not be sent in
time restores its reserved capacity. Damage remains server-confirmed.

To greet an interactable NPC, look toward them within 3 metres, raise either
empty hand, release grip and trigger, and wave side to side. Waving opens the
same panel as selecting them; choices and purchases still need confirmation.
Lower your hand before greeting again. Blocked sight lines, other interfaces,
occupied hands and ambiguous targets prevent activation.

Linux and Windows package preflights and synthetic interaction tests are used;
Windows execution is checked through Wine. Live headset testing remains suspended.

Junk dealers can be opened with a wave or a trigger from any facing direction.
Their panel lists eligible items and credit values, with a **Sell selection**
button and an explicit **Sell all eligible items** row. Different dealers buy
different categories; Jawa traders retain their original underworld language
requirement. Put loot in the main inventory to offer it. Items inside backpacks,
equipped items, crafted/sliced/broken/no-trade items and filled containers are
excluded. Sales credit cash and refresh inventory; repeated network requests do
not sell or pay twice.
