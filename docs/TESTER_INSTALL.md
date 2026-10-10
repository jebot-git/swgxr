# Install the SWGXR test client — 2026.10.10

Download the Linux or Windows client from the [test release](https://github.com/jebot-git/swgxr/releases/tag/v2026.10.10-test.2), then install the matching private SWG data ZIP. The repository and release are private; testers need repository access to download the clients.

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

The client downloads contain no original SWG game data. Obtain **`test-runtime-data-jtl-20261010.zip` separately from the test organizer through the private distribution channel**, using your own original SWG media as required for participation. It is deliberately not attached to the GitHub release. There is no public asset download or automatic game-data downloader.

The matching ZIP is **5,173,635,069 bytes** (about 4.82 GiB). Its SHA-256 is:

```text
3f9974e73037a6222ea80ffc1cb712c48bea7373b8fbd83f9447421bfa4210eb
```

It contains **55,240 verified runtime files**, occupying about **9.87 GiB** after extraction. These are the converted data referenced by the client for all ten ground planets and the ten original JtL sectors. Raw TRE archives, server-only catalogs, standalone developer reports and unreferenced conversion outputs are excluded. Source hashes and conversion limitations remain in the retained catalogs. Testers do not install TRE files separately. **A retail installation, loose TRE files or an arbitrary ZIP of your game folder is not a drop-in substitute.** This client expects the matching `swgxr-assets-v2` manifest and converted catalogs.

If you only have your own installation media, use the repository's [local asset preparation guide](https://github.com/jebot-git/swgxr/blob/main/tools/assets/README.md) with the test organizer to prepare the matching data. The documented source set uses original base-game, Jump to Lightspeed and Total Experience media to complete the pinned 51-file pre-CU archive allowlist. Base CDs alone supply only 30 of those archives. Extraction, activation, conversion and validation are a separate developer workflow; the packaged launcher only verifies and imports the completed data ZIP. Do not fetch replacement proprietary assets or publish the resulting bundle.

## Verify downloads

Download `CHECKSUMS.sha256` from the same release. It lists both client archives and the private data ZIP.

On Linux, from the download directory:

```sh
sha256sum test-client-linux-20261010.tar.gz test-runtime-data-jtl-20261010.zip
```

Compare both values with `CHECKSUMS.sha256`. On Windows, use PowerShell:

```powershell
Get-FileHash .\test-client-windows-20261010.zip -Algorithm SHA256
Get-FileHash .\test-runtime-data-jtl-20261010.zip -Algorithm SHA256
```

Compare the values with the checksum file (letter case does not matter). If a hash differs, obtain a fresh copy before importing it. The launcher also checks every individual data file during installation.

## Linux installation

1. Extract `test-client-linux-20261010.tar.gz` into a writable folder:

   ```sh
   tar -xzf test-client-linux-20261010.tar.gz
   cd test-client-linux-20261010
   ```

2. Copy the **unextracted** `test-runtime-data-jtl-20261010.zip` into `data/`. Keep exactly one ZIP in that folder.
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
2. Copy the **unextracted** `test-runtime-data-jtl-20261010.zip` into its `data` folder. Keep exactly one ZIP there.
3. Run `import-data.cmd`. It verifies and installs the assets without starting the client. From PowerShell, use `.\import-data.cmd`.
4. Configure your OpenXR runtime and connect the headset, then run `play-vr.cmd`.

Use `play-desktop.cmd` only for desktop regression or asset inspection. Keep the included `python/` folder with the client. If the launcher reports that bundled Python is missing, extract the complete client ZIP again.

The refreshed Windows download retains the filename `test-client-windows-20261010.zip`; verify it against the updated release checksum. Older copies that call `py -3` require a fresh download. Extract the updated package into a fresh folder and import the new matching JtL runtime data ZIP. This update requires both the new client and the new data.

After installation, the folder has this shape:

```text
test-client-<platform>-20261010/
  data/
    test-runtime-data-jtl-20261010.zip
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

## Upgrading an existing installation

Extract the new client into a fresh folder, put only `test-runtime-data-jtl-20261010.zip` in its `data/` folder, and run its import command. Older runtime ZIPs lack the new sectors and NPC hulls. Preserve the old installation until the new one works. Do not mix ZIPs or overwrite an imported installation: its receipt belongs to its original archive and location.

## Connect and create a character

The package includes the server address **`https://87.106.27.237:18443`** and its public CA certificate. Keep `server.json` and `server-ca.pem` with the client. No account credentials or private keys are included.

Create a new account in the sign-in panel, then create/select a character. Invitations are not required on this test realm. Accounts created after the initial test-realm reset are preserved by this update. Your account's first character receives an original Luxury Yacht when entering its gameplay session; use an original starship terminal for crew preparation and launch. Ground scope is the ten original planets. Space includes the ten original JtL sectors and original hostile encounters; the Luxury Yacht remains excluded from combat. See [JtL test scope and limitations](JTL_TEST_STATUS.md). The realm restarts daily at **05:00 UTC**.

## Troubleshooting and test status

- **“Place exactly one supplied SWGXR data ZIP…”:** put the matching ZIP in the extracted client's `data/` folder and remove extra ZIPs from that folder.
- **SHA-256/manifest errors:** use a complete matching data ZIP; do not edit its files or manifest.
- **“Insufficient free disk space”:** free enough space for both the ZIP and approximately 9.9 GiB of installed runtime data, plus the client.
- **“Existing data belongs to a different…location”:** extract a fresh client folder at the desired path and import again.
- **GLIBC/GLIBCXX errors:** the Linux build requires the library versions listed above. This release does not provide an older-distribution build.
- **OpenXR initialization failure:** confirm that your headset is connected and the intended OpenXR runtime is active. Desktop mode is only a separate inspection/regression option.

Both executable/PCK packages passed headless native-loading and catalog preflight checks. The new 55,240-file runtime ZIP passed every entry SHA-256 and ZIP CRC check. Full imports passed with the packaged Linux importer and the bundled Windows Python under Wine. Both executables then loaded the imported ground data, 277 ship descriptors and native clothing without errors. Original-starport stairs and yacht doorway movement passed using the native controller with XR disabled or mocked tracking.

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
