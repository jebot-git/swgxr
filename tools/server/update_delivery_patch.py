#!/usr/bin/env python3
"""Regenerate owned mission parcel changes against all pinned predecessors."""
import difflib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'vendor/Core3'
TARGET = ROOT / 'server/patches/0037-native-mission-parcels.patch'
OWNED = [
    'MMOCoreORB/src/server/zone/objects/creature/commands/' + name
    for name in ('SwgxrDelivery.h', 'SwgxrMissionItems.h', 'SwgxrServices.h')
] + [
    'MMOCoreORB/src/server/zone/objects/mission/DeliverMissionObjectiveImplementation.cpp',
    'MMOCoreORB/src/server/zone/objects/mission/CraftingMissionObjectiveImplementation.cpp',
    'MMOCoreORB/src/server/zone/objects/player/sessions/crafting/CraftingSessionImplementation.cpp',
    'MMOCoreORB/src/server/zone/objects/player/sessions/crafting/events/CreateObjectTask.h',
    'MMOCoreORB/src/server/zone/objects/player/sessions/crafting/events/UpdateToolCountdownTask.h',
]


def main():
    patches = [p for p in sorted((ROOT / 'server/patches').glob('*.patch')) if p.name < TARGET.name]
    paths = set(OWNED) | {line[6:] for patch in patches for line in patch.read_text().splitlines() if line.startswith('+++ b/')}
    with tempfile.TemporaryDirectory(prefix='swgxr-delivery-patch-') as temporary:
        tree = Path(temporary)
        subprocess.run(['git', 'init', '-q', str(tree)], check=True)
        for path in paths:
            old = subprocess.run(['git', '-C', str(CORE), 'show', 'HEAD:' + path], capture_output=True)
            if old.returncode == 0:
                (tree / path).parent.mkdir(parents=True, exist_ok=True)
                (tree / path).write_bytes(old.stdout)
        for patch in patches:
            subprocess.run(['git', '-C', str(tree), 'apply', str(patch)], check=True)
        lines = []
        for path in OWNED:
            baseline = (tree / path).read_text() if (tree / path).exists() else ''
            desired = (CORE / path).read_text()
            lines.extend(difflib.unified_diff(baseline.splitlines(True), desired.splitlines(True), fromfile='a/' + path if baseline else '/dev/null', tofile='b/' + path, n=3))
        TARGET.write_text(''.join(lines))
        subprocess.run(['git', '-C', str(tree), 'apply', str(TARGET)], check=True)
        for path in OWNED:
            assert (tree / path).read_bytes() == (CORE / path).read_bytes(), path
        print('Mission parcel patch verified:', len(lines), 'lines;', len(OWNED), 'owned paths')


if __name__ == '__main__':
    main()
