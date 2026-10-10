# Install the SWGXR test client — 2026.10.10

Download the Linux or Windows client from the [test release](https://github.com/jebot-git/swgxr/releases/tag/v2026.10.10-test.9), then install the matching private SWG data ZIP. The repository and client releases are public. Original SWG data remains separately distributed in private.

## Requirements

| Platform | Requirements |
| --- | --- |
| Linux | x86_64, **glibc 2.43 or newer**, libstdc++ providing **GLIBCXX_3.4.30**, Python 3.10+, Vulkan graphics drivers |
| Windows | x86_64, Vulkan graphics drivers; **Python is included** |
| VR | A configured OpenXR runtime and connected headset; initial hardware target is Quest through SteamVR or WiVRn on Linux |
| Storage | At least **25 GB free** for the client, compressed data and installed data |

Windows includes a private Python 3.13.16 runtime for data installation and startup. No Python installation, `py` launcher, pip, compiler, administrator setup, or developer tools are required. The launchers use the bundled runtime without changing system Python settings.

On Linux, Python 3.10+ is still required; use a supported version from [python.org](https://www.python.org/downloads/) or your distribution. Verify `python3 --version` and `ldd --version`.

Older Linux distributions with glibc below 2.43 cannot run this particular build. Do not replace your system C library to work around that requirement. The client uses **Forward+ on Vulkan only**. Standalone Quest, Mobile, Compatibility/OpenGL, Direct3D and ARM builds are unsupported. Godot and the native extensions are included; no separate Godot installation or compiler is needed.

## Get the matching SWG assets

The client downloads contain no original SWG game data. Obtain **`test-runtime-data-test9-20261010.zip` separately from the test organizer through the private distribution channel**, using your own original SWG media as required for participation. It is deliberately not attached to the GitHub release. There is no public asset download or automatic game-data downloader.

The matching ZIP is **5,187,073,127 bytes** (about 4.83 GiB). Its SHA-256 is:

```text
953b058b06dd3c57c73aa1e529e51853682c13fa7d89ca35d78b69097a49fc8b
```

It contains **55,288 verified runtime files**, occupying about **9.90 GiB** after extraction. These are the converted data referenced by the client for all ten ground planets and the ten original JtL sectors. Raw TRE archives, server-only catalogs, standalone developer reports and unreferenced conversion outputs are excluded. Source hashes and conversion limitations remain in the retained catalogs. Testers do not install TRE files separately. **A retail installation, loose TRE files or an arbitrary ZIP of your game folder is not a drop-in substitute.** This client expects the matching `swgxr-assets-v2` manifest and converted catalogs.

If you only have your own installation media, use the repository's [local asset preparation guide](https://github.com/jebot-git/swgxr/blob/main/tools/assets/README.md) with the test organizer to prepare the matching data. The documented source set uses original base-game, Jump to Lightspeed and Total Experience media to complete the pinned 51-file pre-CU archive allowlist. Base CDs alone supply only 30 of those archives. Extraction, activation, conversion and validation are a separate developer workflow; the packaged launcher only verifies and imports the completed data ZIP. Do not fetch replacement proprietary assets or publish the resulting bundle.

## Verify downloads

Download `CHECKSUMS.sha256` from the same release. It lists both client archives and the private data ZIP.

On Linux, from the download directory:

```sh
sha256sum test-client-linux-20261010.tar.gz test-runtime-data-test9-20261010.zip
```

Compare both values with `CHECKSUMS.sha256`. On Windows, use PowerShell:

```powershell
Get-FileHash .\test-client-windows-20261010.zip -Algorithm SHA256
Get-FileHash .\test-runtime-data-test9-20261010.zip -Algorithm SHA256
```

Compare the values with the checksum file (letter case does not matter). If a hash differs, obtain a fresh copy before importing it. The launcher also checks every individual data file during installation.

## Linux installation

1. Extract `test-client-linux-20261010.tar.gz` into a writable folder:

   ```sh
   tar -xzf test-client-linux-20261010.tar.gz
   cd test-client-linux-20261010
   ```

2. Copy the **unextracted** `test-runtime-data-test9-20261010.zip` into `data/`. Keep exactly one ZIP in that folder.
3. Install and verify the data without starting the client:

   ```sh
   ./import-data.sh
   ```

4. Configure your OpenXR runtime, connect the headset, then start:

   ```sh
   ./play-vr.sh
   ```

For desktop regression or asset inspection, use `./play-desktop.sh`, which explicitly disables XR. If an executable bit was lost during extraction, use `sh import-data.sh` or `sh play-vr.sh`.

## Windows installation

1. Extract **all** of `test-client-windows-20261010.zip` into a short writable path such as `C:\SWGXR`. Open the extracted `test-client-windows-20261010` folder; do not run files from inside the ZIP.
2. Copy the **unextracted** `test-runtime-data-test9-20261010.zip` into its `data` folder. Keep exactly one ZIP there.
3. Run `import-data.cmd`. It verifies and installs the assets without starting the client. From PowerShell, use `.\import-data.cmd`.
4. Configure your OpenXR runtime and connect the headset, then run `play-vr.cmd`.

Use `play-desktop.cmd` only for desktop regression or asset inspection. Keep the included `python/` folder with the client. If the launcher reports that bundled Python is missing, extract the complete client ZIP again.

The refreshed Windows download retains the filename `test-client-windows-20261010.zip`; verify it against the updated release checksum. Older copies that call `py -3` require a fresh download. Extract the updated package into a fresh folder and import the new matching JtL runtime data ZIP. Test.6 requires both the new client and presentation data, including when upgrading from test.5. The data adds original seated avatar poses, ship and sector audio, and source NPC variant pools.

After installation, the folder has this shape:

```text
test-client-<platform>-20261010/
  data/
    test-runtime-data-test9-20261010.zip
  runtime/
    assets/
  engine/
  python/       # Windows only; included in the client ZIP
  client/
  server.json
  server-ca.pem
  ASSET_RESTORE_RECEIPT.json
  play-vr.sh or play-vr.cmd
```

The importer creates the runtime directories and receipt. Do not manually unpack the data ZIP or move the client folder after importing: absolute catalog paths are rebased to the chosen location. To relocate or upgrade, extract a fresh client folder, copy the matching data ZIP into `data/`, and import again. Keep the data ZIP in `data/` after installation; repeat starts use the verified install receipt.

## Desktop launchers and updates (test.8)

Run `./install-shortcuts.sh` on Linux or `install-shortcuts.cmd` on Windows.
This creates **SWGXR**, **SWGXR VR**, **SWGXR Desktop**, and **SWGXR Updates**
shortcuts on your desktop. Linux also receives application-menu entries. If your
desktop asks, mark the shortcuts trusted / allow launching. Installation needs
no administrator privileges and does not start the game.

**SWGXR** opens a small terminal menu for VR, desktop mode, asset import, updates,
and refreshing shortcuts. `launcher.sh` / `launcher.cmd` opens the same menu.
**SWGXR Updates** opens the GitHub release downloads page in your browser; sign
in with your authorized GitHub account. It does not automatically download or
replace the client. Prereleases appear on this page too. The client does not
store GitHub credentials. Original assets are still supplied separately.

## Upgrading an existing installation

Extract the new client into a fresh folder, put only `test-runtime-data-test9-20261010.zip` in its `data/` folder, and run its import command. Runtime ZIPs from before test.6 lack seated avatar poses, ship and sector audio, and NPC variant pools. The test.9 bundle retains those assets and adds original shuttle landing, takeoff, power-down and idle audio. Pre-mount ZIPs also lack saddle and rein metadata; pre-JtL ZIPs lack sectors and NPC hulls. Run the new folder's `install-shortcuts` script to retarget all four shortcuts to the new version. Preserve the old installation until the new one works. Do not mix ZIPs or overwrite an imported installation: its receipt belongs to its original archive and location.

## Connect and create a character

The package includes the server address **`https://87.106.27.237:18443`** and its public CA certificate. Keep `server.json` and `server-ca.pem` with the client. No account credentials or private keys are included.

Create a new account in the sign-in panel, then create/select a character. Invitations are not required on this test realm. Accounts created after the initial test-realm reset are preserved by this update. Your account's first character receives an original Luxury Yacht when entering its gameplay session; use an original starship terminal for crew preparation and launch. Ground scope is the ten original planets. Space includes the ten original JtL sectors and original hostile encounters; the Luxury Yacht remains excluded from combat. See [JtL test scope and limitations](JTL_TEST_STATUS.md). The realm restarts daily at **05:00 UTC**.

## Troubleshooting and test status

Test.5 fixes microphone activation being disabled in the client project. Voice still starts muted; select your microphone in Settings, join an available voice channel, and select push-to-talk or voice activation. Failed activation can retry, and its message clears after capture succeeds. If opening still fails, check the selected device and operating-system microphone permissions.

Synthetic speech captured through a virtual Linux input passed the production RNNoise/Opus path, startup mute, push-to-talk and shutdown checks. Voice controller, codec, context, channel routing and microphone preference regressions passed. Physical headset microphones and native Windows microphone capture have not been tested in this update; headset tests remain suspended.

- **“Place exactly one supplied SWGXR data ZIP…”:** put the matching ZIP in the extracted client's `data/` folder and remove extra ZIPs from that folder.
- **SHA-256/manifest errors:** use a complete matching data ZIP; do not edit its files or manifest.
- **“Insufficient free disk space”:** free enough space for both the ZIP and approximately 9.9 GiB of installed runtime data, plus the client.
- **“Existing data belongs to a different…location”:** extract a fresh client folder at the desired path and import again.
- **GLIBC/GLIBCXX errors:** the Linux build requires the library versions listed above. This release does not provide an older-distribution build.
- **OpenXR initialization failure:** confirm that your headset is connected and the intended OpenXR runtime is active. Desktop mode is only a separate inspection/regression option.

Both executable/PCK packages passed headless native-loading and catalog preflight checks. The runtime ZIP is checked against every entry SHA-256 and ZIP CRC during packaging. Full imports passed with the packaged Linux importer and the bundled Windows Python under Wine. Both executables then loaded the imported ground data, 277 ship descriptors and native clothing without errors. Original-starport stairs and yacht doorway movement passed using the native controller with XR disabled or mocked tracking.

All ten sectors were captured with desktop Forward+ Vulkan. Native Shipwright crafting/experimentation, pilot enlistment/first patrol, chassis redemption and component swapping passed live Core3 tests. See [JtL test status](JTL_TEST_STATUS.md) for combat-fixture boundaries and remaining source/presentation limitations. Native Windows Vulkan/OpenXR and live headset validation are separate; dummy-renderer and Wine checks do not validate a GPU or headset. Windows uses standard spatial audio fallback and includes TwoVoIP.

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
mode, grip the right handle for the stick and the left handle for throttle;
release grip to let go. Handles are placed below eye level when you enter the
seat. Ship scenery moves smoothly between the positions confirmed by Core3.

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
