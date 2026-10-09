# Install the SWGXR test client — 2026.10.10

Download the Linux or Windows client from the [test release](https://github.com/jebot-git/swgxr/releases/tag/v2026.10.10-test.1), then install the matching private SWG data ZIP. The repository and release are private; testers need repository access to download the clients.

## Requirements

| Platform | Requirements |
| --- | --- |
| Linux | x86_64, **glibc 2.43 or newer**, libstdc++ providing **GLIBCXX_3.4.30**, Python 3.10+, Vulkan graphics drivers |
| Windows | x86_64, Python 3.10+ with the `py` launcher, Vulkan graphics drivers |
| VR | A configured OpenXR runtime and connected headset; initial hardware target is Quest through SteamVR or WiVRn on Linux |
| Storage | At least **25 GB free** for the client, compressed data and installed data |

Use a supported Python version from [python.org](https://www.python.org/downloads/). Windows setup is covered by the [official Python installation guide](https://docs.python.org/3/using/windows.html); verify that `py -3 --version` works before proceeding. On Linux, verify `python3 --version` and `ldd --version`.

Older Linux distributions with glibc below 2.43 cannot run this particular build. Do not replace your system C library to work around that requirement. The client uses **Forward+ on Vulkan only**. Standalone Quest, Mobile, Compatibility/OpenGL, Direct3D and ARM builds are unsupported. Godot and the native extensions are included; no separate Godot installation or compiler is needed.

## Get the matching SWG assets

The client downloads contain no original SWG game data. Obtain **`test-data-20261010.zip` separately from the test organizer through the private distribution channel**, using your own original SWG media as required for participation. It is deliberately not attached to the GitHub release. There is no public asset download or automatic game-data downloader.

The matching ZIP is **7,953,081,442 bytes** (about 7.4 GiB). Its SHA-256 is:

```text
3996adb3bbc7e1772dd5f834e28e991557d2ca58a36391257b065680f1850b2f
```

It contains 57,066 verified data files: the converted ground/space assets, the 51 required original TRE archives, provenance and conversion reports. **A retail installation, loose TRE files or an arbitrary ZIP of your game folder is not a drop-in substitute.** This client expects the matching `swgxr-assets-v2` manifest and converted catalogs.

If you only have your own installation media, use the repository's [local asset preparation guide](https://github.com/jebot-git/swgxr/blob/v2026.10.10-test.1/tools/assets/README.md) with the test organizer to prepare the matching data. The documented source set uses original base-game, Jump to Lightspeed and Total Experience media to complete the pinned 51-file pre-CU archive allowlist. Base CDs alone supply only 30 of those archives. Extraction, activation, conversion and validation are a separate developer workflow; the packaged launcher only verifies and imports the completed data ZIP. Do not fetch replacement proprietary assets or publish the resulting bundle.

## Verify downloads

Download `CHECKSUMS.sha256` from the same release. It lists both client archives and the private data ZIP.

On Linux, from the download directory:

```sh
sha256sum test-client-linux-20261010.tar.gz test-data-20261010.zip
```

Compare both values with `CHECKSUMS.sha256`. On Windows, use PowerShell:

```powershell
Get-FileHash .\test-client-windows-20261010.zip -Algorithm SHA256
Get-FileHash .\test-data-20261010.zip -Algorithm SHA256
```

Compare the values with the checksum file (letter case does not matter). If a hash differs, obtain a fresh copy before importing it. The launcher also checks every individual data file during installation.

## Linux installation

1. Extract `test-client-linux-20261010.tar.gz` into a writable folder:

   ```sh
   tar -xzf test-client-linux-20261010.tar.gz
   cd test-client-linux-20261010
   ```

2. Copy the **unextracted** `test-data-20261010.zip` into `data/`. Keep exactly one ZIP in that folder.
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
2. Copy the **unextracted** `test-data-20261010.zip` into its `data` folder. Keep exactly one ZIP there.
3. Run `import-data.cmd`. It verifies and installs the assets without starting the client. From PowerShell, use `.\import-data.cmd`.
4. Configure your OpenXR runtime and connect the headset, then run `play-vr.cmd`.

Use `play-desktop.cmd` only for desktop regression or asset inspection. If `py` is not recognized, finish the Python installation and reopen the terminal. An equivalent import command is `python start_client.py --import-only` if that command selects Python 3.10 or newer.

After installation, the folder has this shape:

```text
test-client-<platform>-20261010/
  data/
    test-data-20261010.zip
  runtime/
    assets/
    asset_sources/
    asset_reports/
  engine/
  client/
  server.json
  server-ca.pem
  ASSET_RESTORE_RECEIPT.json
  play-vr.sh or play-vr.cmd
```

The importer creates the runtime directories and receipt. Do not manually unpack the data ZIP, run its embedded helper script, or move the client folder after importing: absolute catalog paths are rebased to the chosen location. To relocate or upgrade, extract a fresh client folder, copy the matching data ZIP into `data/`, and import again. Keep the data ZIP in `data/` after installation; repeat starts use the verified install receipt.

## Connect and create a character

The package includes the server address **`https://87.106.27.237:18443`** and its public CA certificate. Keep `server.json` and `server-ca.pem` with the client. No account credentials or private keys are included.

Create a new account in the sign-in panel, then create/select a character. Invitations are not required on this test realm. Previous test accounts and characters were reset for this release. Your account's first character receives an original Luxury Yacht when entering its gameplay session; use an original starship terminal for crew preparation and launch. Ground scope is the ten original planets; space is the bounded noncombat Tatooine test. The realm restarts daily at **05:00 UTC**.

## Troubleshooting and test status

- **“Place exactly one supplied SWGXR data ZIP…”:** put the matching ZIP in the extracted client's `data/` folder and remove extra ZIPs from that folder.
- **SHA-256/manifest errors:** use a complete matching data ZIP; do not edit its files or manifest.
- **“Insufficient free disk space”:** free enough space for both the ZIP and approximately 12.4 GiB of installed data, plus the client.
- **“Existing data belongs to a different…location”:** extract a fresh client folder at the desired path and import again.
- **GLIBC/GLIBCXX errors:** the Linux build requires the library versions listed above. This release does not provide an older-distribution build.
- **OpenXR initialization failure:** confirm that your headset is connected and the intended OpenXR runtime is active. Desktop mode is only a separate inspection/regression option.

Both executable/PCK packages passed headless native-loading and catalog preflight checks. The full Linux asset-install path and original-starport movement tests passed. The Windows native DLL passed the same stair ascent/descent test in an exported harness under Wine. Native Windows Vulkan/OpenXR and live headset validation remain pending; dummy-renderer tests do not validate a GPU or headset. The Windows package uses standard spatial audio fallback and includes TwoVoIP.
