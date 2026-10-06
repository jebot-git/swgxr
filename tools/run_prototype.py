#!/usr/bin/env python3
"""Start local prototype services and launch the Godot client."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from client.launch_environment import client_environment
from client.remote_connection import connection_arguments
from client.start_voice_relay import ensure_local_voice

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime/server'


def option(args, name, default=''):
    """Match Godot's --name=value user-option convention."""
    key = '--' + name
    result = default
    for argument in args:
        if argument == key:
            raise ValueError(f'{key} requires a value: {key}=VALUE')
        if argument.startswith(key + '='):
            result = argument[len(key) + 1:]
    return result


def load_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def inventory_assets(snapshot=None, snapshot_path=None):
    """Prepare missing item appearances; never infer or grant possessions."""
    if load_json(ROOT / 'runtime/assets/chatter/catalog.json').get('schema') != 1:
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_chatter.py')], check=True, cwd=ROOT)
    gcw_catalog = load_json(ROOT / 'runtime/assets/gcw/catalog.json')
    if (gcw_catalog.get('schema') != 1
            or any(row.get('preview_status') == 'unprepared' for row in gcw_catalog.get('rewards', []))
            or any(not row.get('ready') for row in gcw_catalog.get('npc_appearances', {}).values())):
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_gcw.py'),
                        '--prepare-previews', '--prepare-npcs'], check=True, cwd=ROOT)
    if any(not (ROOT / 'runtime/assets/services' / name).exists() for name in ('catalog.json', 'trainers.json')):
        subprocess.run([sys.executable,str(ROOT / 'tools/assets/prepare_services.py')],check=True,cwd=ROOT)
    trainer_scope = ROOT / 'server/profession_scope.py'
    trainer_sources = load_json(ROOT / 'runtime/assets/services/trainers.json').get('provenance', {}).get('files_sha256', {})
    if trainer_sources.get(str(trainer_scope.resolve())) != hashlib.sha256(trainer_scope.read_bytes()).hexdigest():
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/audit_trainers.py')], check=True, cwd=ROOT)
    if not (ROOT / 'runtime/assets/services/bazaar_categories.json').exists():
        subprocess.run([sys.executable,str(ROOT / 'tools/assets/prepare_bazaar_categories.py')],check=True,cwd=ROOT)
    scout_catalog = load_json(ROOT / 'runtime/assets/scout/catalog.json')
    if scout_catalog.get('schema') != 2 or not scout_catalog.get('camouflage_kits') or not scout_catalog.get('ranger_skills'):
        subprocess.run([sys.executable,str(ROOT / 'tools/scout/prepare_assets.py')],check=True,cwd=ROOT)
    if not (ROOT / 'runtime/assets/crafting/catalog.json').exists():
        subprocess.run([sys.executable,str(ROOT/'tools/crafting/prepare_assets.py')],check=True,cwd=ROOT)
    if not (ROOT/'runtime/assets/housing/catalog.json').exists():
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_housing.py')],check=True,cwd=ROOT)
    if not (ROOT/'runtime/assets/factories/catalog.json').exists():
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_factories.py')],check=True,cwd=ROOT)
    directory = ROOT / 'runtime/assets/inventory'
    catalog = load_json(directory / 'catalog.json')
    command = [sys.executable, str(ROOT / 'tools/assets/prepare_inventory.py')]
    source = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/managers/player_creation_manager.lua'
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest() if source.exists() else ''
    previous_hash = catalog.get('provenance', {}).get('inputs', {}).get(str(source.resolve()), {}).get('sha256')
    generic = catalog.get('items', {}).get(catalog.get('generic_backpack', {}).get('template'), {})
    prepare_starters = not catalog or not generic or (source_hash and previous_hash != source_hash)
    if generic.get('status') == 'ready' and not (directory / generic.get('model', '')).is_file():
        prepare_starters = True
    if prepare_starters:
        command.append('--starter-items')
    gathering = catalog.get('gathering_assets', {}).get('templates', [])
    prepare_gathering = not gathering or any(
        catalog.get('items', {}).get(template, {}).get('status') != 'ready'
        or not (directory / catalog.get('items', {}).get(template, {}).get('model', '')).is_file()
        for template in gathering)
    if prepare_gathering:
        command.append('--gathering-assets')
    fishing_templates = ['object/tangible/terminal/terminal_player_structure.iff', 'object/tangible/fishing/fishing_pole.iff', 'object/tangible/fishing/marker.iff'] + [
        'object/tangible/fishing/bait/bait_'+name+'.iff' for name in ('worm','grub','insect','chum')]
    prepare_fishing = False
    for template in fishing_templates:
        item = catalog.get('items', {}).get(template, {})
        if item.get('status') != 'ready' or not (directory / item.get('model', '')).is_file():
            command.extend(['--template', template]); prepare_fishing = True
    missing = []
    requested = {}
    if snapshot is not None:
        # The asset tool preserves explicit Core3 shared-template aliases.
        sys.path.insert(0, str(ROOT / 'tools/assets'))
        from prepare_inventory import snapshot_template_pairs
        requested = snapshot_template_pairs(snapshot)
        race = str(snapshot.get('race', ''))
        for template, shared in requested.items():
            item = catalog.get('items', {}).get(template, {})
            if (item.get('shared_template') != shared or item.get('status') != 'ready'
                    or not (directory / item.get('model', '')).is_file()
                    or (race and item.get('owner_race') and item['owner_race'] != race)):
                missing.append(template)
            if race and template.startswith(('object/tangible/wearables/', 'object/weapon/')):
                equipped = catalog.get('equipment', {}).get(race, {}).get(template, {})
                if (equipped.get('shared_template') != shared or equipped.get('status') != 'ready'
                        or not (directory / equipped.get('model', '')).is_file()):
                    if template not in missing: missing.append(template)
    if missing:
        command.extend(['--snapshot', str(snapshot_path)])
    if prepare_starters or prepare_gathering or prepare_fishing or missing:
        print('Preparing original inventory appearances for this launch…', flush=True)
        subprocess.run(command, check=True, cwd=ROOT)
        catalog = load_json(directory / 'catalog.json')
    generic = catalog.get('items', {}).get(catalog.get('generic_backpack', {}).get('template'), {})
    if generic.get('status') != 'ready' or not (directory / generic.get('model', '')).is_file():
        raise ValueError('Original inventory backpack is unavailable. Inspect runtime/assets/inventory/catalog.json and run tools/assets/prepare_inventory.py --starter-items.')
    unsupported = [template for template in requested if catalog.get('items', {}).get(template, {}).get('status') != 'ready']
    if unsupported:
        print('Original item previews unavailable (explicit UI entries, no replacement models): ' + ', '.join(unsupported), flush=True)
    if (prepare_fishing or not (ROOT/'runtime/assets/services/screens.json').exists()) and (ROOT/'runtime/assets/tatooine_world/world.json').exists():
        subprocess.run([sys.executable,str(ROOT/'tools/client/build_terminal_screens.py')],check=True,cwd=ROOT)
    return {'requested': len(requested), 'prepared': bool(prepare_starters or prepare_gathering or missing), 'unsupported': unsupported}


def backend_json(base, path, timeout=55, connection=None):
    if connection is not None:
        if base.rstrip('/') != connection.base_url:
            raise ValueError('Remote inventory endpoint differs from the authenticated profile.')
        value = connection.request_json(path, timeout=timeout)
    else:
        with urllib.request.urlopen(base.rstrip('/') + path, timeout=timeout) as response:
            value = json.load(response)
    if not isinstance(value, dict) or value.get('backend') != 'core3':
        raise ValueError('Inventory preparation requires an actual Core3 adapter response.')
    return value


def corpse_assets():
    """Prepare source-defined Tatooine animal corpse visuals, never spawn them."""
    directory = ROOT / 'runtime/assets/corpses'
    catalog = load_json(directory / 'catalog.json')
    templates = catalog.get('planets', {}).get('tatooine', {}).get('templates', [])
    if not templates or any(catalog.get('items', {}).get(template, {}).get('status') != 'ready'
            or not (directory / catalog['items'][template].get('model', '')).is_file() for template in templates):
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_corpses.py'),
                        '--planet', 'tatooine'], check=True, cwd=ROOT)


def selected_inventory_assets(args, connection=None):
    name = option(args, 'enter-character').strip()
    if not name:
        return None
    account = option(args, 'account', 'prototype').strip()
    base = option(args, 'backend', 'http://127.0.0.1:18080')
    # Startup readiness also prevents the client's one-shot automatic character
    # selection from racing Core3 startup. No retry of a mutation is involved.
    deadline = time.monotonic() + 120
    while True:
        health = backend_json(base, '/health', timeout=25, connection=connection)
        if health.get('core3', {}).get('ready'):
            break
        if time.monotonic() >= deadline:
            raise ValueError('Core3 did not become ready for the requested character inventory. Inspect runtime/server/adapter.log and retry.')
        print('Waiting for Core3 before reading the selected inventory…', flush=True)
        time.sleep(2)
    query = urllib.parse.urlencode({'account': account})
    characters = backend_json(base, '/characters?' + query, connection=connection).get('characters', [])
    character = next((entry for entry in characters if str(entry.get('name', '')).casefold() == name.casefold()), None)
    if character is None:
        raise ValueError(f'Character {name!r} does not belong to the selected account; inventory was not prepared.')
    oid = str(character.get('id', ''))
    if not oid.isdigit():
        raise ValueError('Core3 returned an invalid character identifier.')
    print(f'Reading original item appearances for {character["name"]}…', flush=True)
    query = urllib.parse.urlencode({'account': account, 'character_id': oid})
    snapshot = backend_json(base, '/inventory?' + query, connection=connection)
    if snapshot.get('source_kind') != 'core3_inventory' or str(snapshot.get('character_id')) != oid:
        raise ValueError('Inventory response did not identify the selected Core3 character.')
    # Hip/deployed tools live in native escrow, outside inventory.items. Include
    # their authoritative appearance records so a restart cannot lose their art.
    gathering = backend_json(base, '/gathering?' + query, connection=connection)
    if gathering.get('source_kind') != 'core3_gathering' or str(gathering.get('character_id')) != oid:
        raise ValueError('Gathering response did not identify the selected Core3 character.')
    snapshot['gathering_appearances'] = gathering
    raw = (json.dumps(snapshot, sort_keys=True, indent=2) + '\n').encode()
    folder = RUNTIME / 'inventory-snapshots'
    folder.mkdir(parents=True, exist_ok=True)
    # Immutable snapshot filenames preserve the importer's source-hash ledger.
    path = folder / f'{oid}-{hashlib.sha256(raw).hexdigest()[:16]}.json'
    if not path.exists():
        path.write_bytes(raw)
    return inventory_assets(snapshot, path)


def combat_assets():
    """Inventory-held weapons use this dependency even without --combat-items."""
    addon = ROOT / 'client/addons/godot-steam-audio'
    lock = load_json(ROOT / 'client/steam-audio.lock.json')
    if any(not (addon / path).is_file() for path in lock.get('files', {})) or not (addon / 'bin/libgodot-steam-audio.gdextension').exists():
        subprocess.run([sys.executable, str(ROOT / 'tools/client/install_steam_audio.py')], check=True, cwd=ROOT)
    extensions = ROOT / 'client/.godot/extension_list.cfg'
    if not extensions.exists() or 'godot-steam-audio' not in extensions.read_text():
        subprocess.run(['godot', '--headless', '--xr-mode', 'off', '--audio-driver', 'Dummy',
                        '--path', str(ROOT / 'client'), '--editor', '--import', '--quit'], check=True, env=client_environment())
    if not (ROOT / 'runtime/combat/catalog.json').is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/combat/export_catalog.py')], check=True, cwd=ROOT)
    if not (ROOT / 'runtime/assets/combat/assets.json').is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/combat/prepare_assets.py')], check=True, cwd=ROOT)
    if not (ROOT / 'runtime/combat/abilities/catalog.json').is_file() or any(not (ROOT / 'runtime/combat/abilities' / (name + '.png')).is_file() for name in ('sampledna','animalattack','tame','emboldenpets','enragepets','mount','dismount','pethigh','petlow','trainmount','conceal','rescue','areatrack')):
        subprocess.run([sys.executable, str(ROOT / 'tools/combat/prepare_abilities.py')], check=True, cwd=ROOT)
    if not (ROOT / 'runtime/assets/professions/catalog.json').is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_professions.py')], check=True, cwd=ROOT)
    if not (ROOT / 'runtime/combat/player_postures/catalog.json').is_file():
        subprocess.run([sys.executable, str(ROOT / 'tools/combat/prepare_player_feedback.py')], check=True, cwd=ROOT)
    if len(load_json(ROOT / 'runtime/entertainment/catalog.json').get('effects', [])) < 21:
        subprocess.run([sys.executable, str(ROOT / 'tools/entertainment/prepare_assets.py')], check=True, cwd=ROOT)
    subprocess.run([sys.executable, str(ROOT / 'tools/entertainment/prepare_image_design.py'), '--ensure'], check=True, cwd=ROOT)

def rendering_args(args):
    """Reject unsupported explicit overrides before starting any services."""
    accepted = {'--rendering-method': 'forward_plus', '--rendering-driver': 'vulkan'}
    result = []
    index = 0
    while index < len(args):
        argument = args[index]
        key, separator, value = argument.partition('=')
        if key in accepted:
            if not separator:
                index += 1
                value = args[index] if index < len(args) else ''
            if value != accepted[key]:
                raise ValueError(f'{key} must be {accepted[key]}; only Forward+ on Vulkan is supported.')
        else:
            result.append(argument)
        index += 1
    return result


def combat_args(args):
    """Live combat always uses owned Core3 items, never the offline training lab."""
    result = list(args)
    if '--live-combat' in result:
        if '--offline' in result or '--combat-lab' in result or '--combat-profession-lab' in result:
            raise ValueError('--live-combat requires real Core3 item combat; offline/training labs are incompatible.')
        if '--combat-items' not in result:
            result.append('--combat-items')
    return result


def mission_assets():
    subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_mission_assets.py')], check=True, cwd=ROOT)

def cached_world_assets():
    subprocess.run([sys.executable, str(ROOT / 'tools/vehicles/prepare_assets.py'), '--ensure'], check=True, cwd=ROOT)
    subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_mobile_audio.py'), '--ensure'], check=True, cwd=ROOT)
    subprocess.run([sys.executable, str(ROOT / 'tools/pets/prepare_bounds.py'), '--ensure'], check=True, cwd=ROOT)
    subprocess.run([sys.executable, str(ROOT / 'tools/assets/refresh_static_materials.py'), '--ensure'], check=True, cwd=ROOT)


def planet_assets(args):
    """Validate prepared descriptors without rebuilding worlds during login."""
    path = ROOT / 'runtime/assets/planets/catalog.json'
    requested = option(args, 'planet', 'tatooine')
    if not path.exists():
        if requested != 'tatooine':
            raise ValueError('Planet catalog unavailable. Run python3 tools/assets/prepare_planets.py first.')
        return ['tatooine']  # Existing single-planet workspaces remain inspectable.
    catalog = load_json(path)
    if catalog.get('schema_version') != 1 or not isinstance(catalog.get('planets'), dict):
        raise ValueError('Invalid prepared planet catalog: '+str(path))
    ready = []
    required = ('terrain', 'terrain_context', 'world', 'environment', 'services',
                'ambient_npcs', 'ambient_placements', 'entities')
    for name, row in catalog['planets'].items():
        if not isinstance(row, dict) or not row.get('ready'):
            continue
        if row.get('planet') != name or any(not isinstance(row.get(key), str) or not Path(row[key]).is_file() for key in required):
            raise ValueError('Prepared planet manifests are missing or inconsistent: '+name+'. Run tools/assets/prepare_planets.py.')
        ready.append(name)
    if requested not in ready:
        raise ValueError('Planet is not prepared: '+requested+'. Inspect '+str(path))
    print('Prepared ground planets: '+', '.join(sorted(ready))+'. Travel also requires an available Core3 route.', flush=True)
    return ready


def live_entity_assets(args):
    """Index source coverage before live sessions; convert only new templates.

    This runs before service startup and performs no native spawn or RPC. Known
    absent components remain explicit partial visuals, not a launch retry loop.
    """
    if '--live-combat' not in args:
        return None
    directory = ROOT / 'runtime/assets/combat_population/tatooine_entities'
    subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_planet_entities.py'),
                    '--planet', 'tatooine'], check=True, cwd=ROOT)
    coverage = load_json(directory / 'coverage.json')
    sources = load_json(directory / 'sources.json')
    if not coverage.get('templates') or not sources.get('appearance_templates'):
        raise ValueError('Tatooine entity preparation did not publish source coverage.')
    if coverage.get('source_resolution_failures'):
        raise ValueError('Tatooine entity source references are unresolved; inspect runtime/assets/combat_population/tatooine_entities/coverage.json.')
    inventory_dir = ROOT / 'runtime/assets/inventory'
    inventory = load_json(inventory_dir / 'catalog.json')
    lairs = {template for lair in sources.get('lairs', {}).values()
             for template in lair.get('building_templates', [])}
    missing_lairs = [template for template in lairs
                     if inventory.get('items', {}).get(template, {}).get('status') != 'ready'
                     or not (inventory_dir / inventory['items'][template].get('model', '')).is_file()]
    if missing_lairs:
        subprocess.run([sys.executable, str(ROOT / 'tools/assets/prepare_inventory.py'),
                        '--population-lairs', str(directory / 'sources.json')], check=True, cwd=ROOT)
    counts = coverage.get('counts', {})
    print('Original Tatooine entity coverage: '
          f'{counts.get("ready", 0)} complete, {counts.get("partial", 0)} partial, '
          f'{counts.get("missing", 0)} unavailable. Component details: '
          'runtime/assets/combat_population/tatooine_entities/coverage.json', flush=True)
    return {'counts': counts, 'lairs_prepared': bool(missing_lairs)}


def run():
    try:
        args, connection = connection_arguments(combat_args(rendering_args(sys.argv[1:])), ROOT)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    offline = '--offline' in args
    desktop = '--desktop' in args or any(a.startswith(('--smoke-test', '--integration-test', '--screenshot=', '--creation-preview=')) for a in args)
    if not (ROOT / 'client/addons/godot-xr-tools/plugin.cfg').exists():
        raise SystemExit('Godot XR Tools is not installed. Run python3 tools/client/install_xr_tools.py, then import the Godot project.')
    if not (ROOT / 'runtime/assets/mos_eisley/scene.json').exists():
        raise SystemExit('Mos Eisley assets are not prepared. Run ./setup.sh first.')
    if not (ROOT / 'runtime/assets/characters/catalog.json').exists():
        raise SystemExit('Player assets are not prepared. Run python3 tools/assets/prepare_characters.py, or run ./setup.sh.')
    if not (ROOT / 'client/native/bin/libswg_native.so').exists():
        raise SystemExit('Native client extension is not built. Run tools/client/build_native.sh, then import the Godot project, or run ./setup.sh.')
    for name in ('terrain/tatooine.json', 'terrain/context.json', 'tatooine_world/world.json', 'tatooine_environment/environment.json', 'ambient_npcs/placements.json', 'ambient_npcs/catalog.json'):
        if not (ROOT / 'runtime/assets' / name).exists():
            raise SystemExit(f'World data missing: {name}. Run the terrain/world/environment/NPC importers or ./setup.sh.')
    if '--combat-lab' in args and '--combat-items' in args:
        raise SystemExit('Choose either the synthetic combat lab or Core3 item combat.')
    if '--combat-items' in args and offline:
        raise SystemExit('--combat-items requires a Core3 character session.')
    if '--combat-profession-lab' in args:
        if '--combat-lab' not in args or '--combat-items' in args:
            raise SystemExit('--combat-profession-lab requires the explicit --combat-lab mode.')
        subprocess.run([sys.executable, str(ROOT / 'tools/server/profession_smoke.py')], check=True, cwd=ROOT)
    try:
        planet_assets(args)
        inventory_assets()
        corpse_assets()
        combat_assets()
        live_entity_assets(args)
        mission_assets()
        cached_world_assets()
    except (ValueError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f'Client asset preparation failed: {exc}') from exc
    if not offline:
        if connection is not None:
            # Interactive startup must reach sign-in even when an old token was
            # revoked. The client checks TLS and authentication before game RPCs.
            if option(args, 'enter-character').strip():
                if not connection.authenticated:
                    raise SystemExit('Automatic character entry requires an authenticated profile. Launch without --enter-character to sign in.')
                try:
                    backend_json(connection.base_url, '/health', timeout=25, connection=connection)
                except (ValueError, OSError) as exc:
                    raise SystemExit('Remote Core3 HTTPS health check failed. Verify the private profile, trusted CA, and gateway availability.') from exc
            print('Remote galaxy selected. Sign-in and server readiness are checked in the client; local server services are not started.', flush=True)
        else:
            if not (ROOT / 'vendor/Core3/MMOCoreORB/bin/core3').exists():
                raise SystemExit('Core3 has not been built. Run ./setup.sh first, or use ./run.sh --offline to inspect assets only.')
            container = os.environ.get('SWGXR_CONTAINER', 'swgxr-core3-build')
            subprocess.run(['podman', 'start', container], check=True, stdout=subprocess.DEVNULL)
            subprocess.run([str(ROOT/'tools/server/start-core3.sh')], check=True)
            try:
                with urllib.request.urlopen('http://127.0.0.1:18080/health', timeout=25) as response:
                    health = json.load(response)
                if health.get('backend') != 'core3':
                    raise SystemExit('Port 18080 is occupied by an unexpected service.')
            except urllib.error.URLError as exc:
                # Only start a server when the port refuses connections. A busy or
                # malformed existing service must not cause a second adapter.
                if not isinstance(exc.reason, ConnectionRefusedError):
                    raise SystemExit(f'Cannot verify existing adapter: {exc}') from exc
                RUNTIME.mkdir(parents=True, exist_ok=True)
                with (RUNTIME/'adapter.log').open('ab') as log:
                    process = subprocess.Popen([sys.executable,str(ROOT/'server/adapter.py')], cwd=ROOT,
                                               stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
                (RUNTIME/'adapter.pid').write_text(str(process.pid)+'\n')
                time.sleep(0.3)
                if process.poll() is not None:
                    raise SystemExit('Adapter failed to start; inspect runtime/server/adapter.log.')
            except (TimeoutError, ValueError) as exc:
                raise SystemExit(f'Existing adapter did not return a valid health response: {exc}') from exc
            print('Core3 is starting or running. The client enables character actions after the real login/zone readiness check.', flush=True)
            try:
                ensure_local_voice(ROOT)
            except (OSError,ValueError) as exc:
                print('Local voice unavailable: '+str(exc),flush=True)
        try:
            if connection is None or connection.authenticated:
                selected_inventory_assets(args, connection=connection)
        except (ValueError, OSError, subprocess.CalledProcessError) as exc:
            raise SystemExit(f'Selected inventory preparation failed: {exc}') from exc
    command = ['godot','--path',str(ROOT/'client')]
    if os.environ.get('WAYLAND_DISPLAY'):
        command += ['--display-driver','wayland']
    command += ['--xr-mode', 'off' if desktop else 'on', '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
    if desktop and '--desktop' not in args:
        args.append('--desktop')
    command += ['--'] + args
    return subprocess.call(command, cwd=ROOT, env=client_environment())

if __name__ == '__main__':
    sys.exit(run())
