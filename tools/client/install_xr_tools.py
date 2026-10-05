#!/usr/bin/env python3
"""Install the pinned, unmodified MIT Godot XR Tools addon for Godot 4.7."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'https://github.com/GodotVR/godot-xr-tools.git'
TAG = '4.6.0-dev1'
COMMIT = 'ccd795c0d57944f15f4c39d44d284347c74b11fc'

def install():
    checkout = ROOT / 'vendor/godot-xr-tools'
    if not checkout.exists():
        subprocess.run(['git', 'clone', '--depth', '1', '--branch', TAG, REPOSITORY, str(checkout)], check=True)
    actual = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != COMMIT:
        raise SystemExit(f'XR Tools checkout mismatch: expected {COMMIT}, found {actual}. Existing checkout left untouched.')
    if subprocess.check_output(['git', '-C', str(checkout), 'status', '--porcelain'], text=True).strip():
        raise SystemExit('XR Tools checkout has local changes; refusing to copy a modified dependency.')
    source = checkout / 'addons/godot-xr-tools'
    target = ROOT / 'client/addons/godot-xr-tools'
    # Refuse to overwrite modified upstream source in the installed addon.
    if target.exists():
        for path in source.rglob('*'):
            relative = path.relative_to(source)
            existing = target / relative
            if path.is_file() and existing.exists() and not path.name.endswith('.import') and existing.read_bytes() != path.read_bytes():
                raise SystemExit(f'Installed XR Tools file was modified: {existing}')
    shutil.copytree(source, target, dirs_exist_ok=True)
    shutil.copy2(checkout / 'LICENSE', target / 'LICENSE')
    action_map = ROOT / 'client/openxr_action_map.tres'
    original_map = checkout / 'openxr_action_map.tres'
    # Seed only a missing map. Bindings belong to the application and may add
    # touch inputs or gameplay actions without modifying the pinned addon.
    if not action_map.exists():
        shutil.copy2(original_map, action_map)
    lock = {'repository': REPOSITORY, 'tag': TAG, 'commit': COMMIT, 'license': 'MIT',
            'action_map_owner': 'project',
            'upstream_action_map_sha256': hashlib.sha256(original_map.read_bytes()).hexdigest(),
            'action_map_sha256': hashlib.sha256(action_map.read_bytes()).hexdigest(),
            'reason': 'Godot 4.7 compatibility fixes; upstream development release, plugin.cfg still reports 4.5.1.'}
    (ROOT / 'client/xr-tools.lock.json').write_text(json.dumps(lock, indent=2)+'\n')
    print(f'Installed Godot XR Tools {TAG} at {COMMIT}')

if __name__ == '__main__':
    install()
