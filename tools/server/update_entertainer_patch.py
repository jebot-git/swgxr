#!/usr/bin/env python3
"""Regenerate native entertainer changes against all pinned predecessors."""
import difflib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'vendor/Core3'
TARGET = ROOT / 'server/patches/0047-native-entertainer.patch'
OWNED = ['MMOCoreORB/src/server/zone/objects/creature/commands/'+name for name in ('SwgxrEntertainer.h','SwgxrImageDesign.h','SwgxrLiveCombat.h','SwgxrTrainerCatalog.h')] + ['MMOCoreORB/src/server/zone/objects/building/BuildingObject.idl','MMOCoreORB/src/server/zone/objects/player/sessions/ImageDesignSession.idl','MMOCoreORB/src/server/zone/managers/skill/PerformEffect.h']


def desired_text(path):
    text = (CORE / path).read_text()
    # The later housing milestone owns this independent entry-policy addition.
    if path.endswith("/SwgxrLiveCombat.h"):
        text = text.replace('if(building!=nullptr && building->isBuildingObject() && !static_cast<BuildingObject*>(building.get())->isAllowedEntry(c))throw std::runtime_error("house_entry_denied");', "")
    return text


def main():
    all_patches = sorted((ROOT / 'server/patches').glob('*.patch'))
    patches = [p for p in all_patches if p.name < TARGET.name]
    paths = set(OWNED) | {line[6:] for patch in all_patches for line in patch.read_text().splitlines() if line.startswith('+++ b/')}
    with tempfile.TemporaryDirectory(prefix='swgxr-entertainer-patch-') as temporary:
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
            desired = desired_text(path)
            lines.extend(difflib.unified_diff(baseline.splitlines(True), desired.splitlines(True), fromfile='a/' + path if baseline else '/dev/null', tofile='b/' + path, n=3))
        TARGET.write_text(''.join(lines))
        subprocess.run(['git', '-C', str(tree), 'apply', str(TARGET)], check=True)
        for path in OWNED:
            assert (tree / path).read_text() == desired_text(path), path
        for patch in all_patches:
            if patch.name > TARGET.name:
                subprocess.run(['git', '-C', str(tree), 'apply', str(patch)], check=True)
        print('Entertainer patch verified:', len(lines), 'lines;', len(OWNED), 'owned paths; full patch stack applies')


if __name__ == '__main__':
    main()
