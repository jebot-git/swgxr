#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
if podman container exists "${SWGXR_CONTAINER:-swgxr-core3-build}" 2>/dev/null && podman exec "${SWGXR_CONTAINER:-swgxr-core3-build}" bash -lc 'test -f /workspace/runtime/server/core3.pid && p=$(cat /workspace/runtime/server/core3.pid) && test -r /proc/$p/status && ! grep -q "State:.*Z" /proc/$p/status && test "$(cat /proc/$p/comm)" = core3 && kill -0 "$p" 2>/dev/null' 2>/dev/null; then
  echo 'Stop Core3 with tools/server/stop-core3.sh before preparing archives again.' >&2
  exit 1
fi
python3 -c 'from PIL import Image' || { echo 'Python Pillow is required for local DDS texture conversion.' >&2; exit 1; }
python3 tools/assets/extract_media.py --bootstrap-unshield "$@"
JTL_CUE="$ROOT/Star Wars Galaxies - Jump to Lightspeed (USA).cue"
if [[ -f "$JTL_CUE" ]]; then
  python3 tools/assets/extract_media.py --output-root runtime/assets/jtl --bootstrap-unshield "$JTL_CUE"
fi
TTE_IMAGES=("$ROOT"/SWG_TTE_CD*.ISO)
if [[ -f "${TTE_IMAGES[0]}" ]]; then
  python3 tools/assets/extract_media.py --output-root runtime/assets/tte --bootstrap-unshield "${TTE_IMAGES[@]}"
fi
python3 tools/assets/activate_archives.py
python3 tools/assets/prepare_stage.py --tre-dir runtime/assets/active_tre
python3 tools/assets/validate_stage.py
python3 tools/assets/prepare_characters.py --tre-dir runtime/assets/active_tre
python3 tools/assets/validate_characters.py
python3 tools/assets/validate_animations.py
python3 tools/assets/prepare_terrain.py
python3 tools/assets/prepare_terrain_context.py
python3 tools/assets/prepare_world.py
# Provision pins Core3, replays prototype patches/config, then builds inside Podman.
tools/server/provision.sh
tools/server/init-db.sh
python3 tools/server/export_ambient_npcs.py --city all
python3 tools/assets/prepare_environment.py
python3 tools/assets/validate_environment.py
python3 tools/assets/prepare_npcs.py
python3 tools/assets/prepare_planet_entities.py --planet tatooine
python3 tools/assets/prepare_datapad.py
python3 tools/assets/validate_datapad.py
python3 tools/assets/prepare_inventory.py --starter-items --gathering-assets --population-lairs runtime/assets/combat_population/tatooine_entities/sources.json --refresh
python3 tools/assets/prepare_mission_assets.py
python3 tools/assets/validate_inventory.py
python3 tools/assets/prepare_services.py
python3 tools/assets/prepare_bazaar_categories.py
python3 tools/assets/prepare_professions.py
python3 tools/entertainment/prepare_assets.py
python3 tools/entertainment/prepare_image_design.py
python3 tools/crafting/prepare_assets.py
python3 tools/assets/prepare_vendors.py
python3 tools/assets/prepare_corpses.py --planet tatooine
python3 tools/vehicles/prepare_assets.py
python3 tools/assets/refresh_static_materials.py --ensure
python3 tools/assets/validate_corpses.py
# Reconstruct all original ground worlds, retaining per-source limitations.
python3 tools/assets/prepare_planets.py
python3 tools/combat/export_catalog.py
python3 tools/combat/prepare_assets.py
python3 tools/pets/prepare_bounds.py --ensure
tools/client/build_native.sh
python3 tools/client/install_xr_tools.py
python3 tools/client/install_steam_audio.py
python3 tools/client/install_twovoip.py
godot --headless --xr-mode off --audio-driver Dummy --path client --editor --import --quit
printf '%s\n' 'Prepared. Start the prototype with ./run.sh'
