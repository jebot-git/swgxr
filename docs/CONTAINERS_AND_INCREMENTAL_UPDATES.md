# Native containers and incremental portable updates

Environmental objects expose storage only when they are real native storage containers. Both native tangible-only containers and generic droid inventories are supported. Crafted containers placed in houses use the same interface; house permissions, locked-container checks, capacity, nesting, distance and line of sight remain native. Decorative scenery without native contents is not made lootable.

The container panel reuses the held-backpack inventory grid and original item models. Grip an item to transfer it into the selected carried container or equipped backpack, then hold its confirmed owned representation. Release a held owned item over the container panel to store it. Nested containers open within the authorized storage root. Transfers have durable request receipts, preventing duplicate moves after a retry. Closing or switching character cannot reopen a stale panel.

Called owned droids with an item-storage module expose this same panel through their normal command wheel. Power droids expose Recharge droid as a chassis action, independent of training a spoken alias. Recharge from battery searches carried containers and equipped bags, consumes one native battery use and reports failure when unavailable. Original power costs and the crafted-droid limit remain in place. The automatic tutorial helper no longer occupies a crafted-droid slot; it has its own native helper pet type.

Portable updates select a patch using the exact installed PACKAGE.json hash. Each patch carries its target manifest and changed managed files; unchanged files are verified and copied into staging. The complete reconstructed package must validate before installation. Existing transaction backup/rollback preserves game assets, media and connection settings. Corrupt local baselines fall back to the full release. Patch archive checksum failures stop the update.

Each full release retains its normal tag and complete archives. Its incremental bundles and standalone updater live under `<release>-patches`. Older launchers require the standalone updater bootstrap once to discover these bundles; their existing full-update path still works. Original SWG assets are never included in public patches.

Validation uses native isolated fixtures with explicitly granted original objects and a house, plus dummy-renderer client interaction tests. Item grants do not validate the complete crafting process, and these checks do not validate physical headset rendering or gestures.

## Recorded validation

The final native build passed 14 environmental/house-container checks and 37 power-droid/storage checks, including native item persistence across recall and template-derived capacity overflow rejection. The client passed 5 storage interaction checks and 66 existing service-interface checks with mocked tracking and the dummy renderer. Python protocol/updater regressions passed 47 tests, including incremental reconstruction, corrupt-baseline fallback and transaction rollback.
