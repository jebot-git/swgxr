#!/usr/bin/env python3
"""Regenerate the opt-in action prototype against its pinned predecessors."""
import difflib
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'vendor/Core3'
TARGET = ROOT / 'server/patches/0138-action-combat-prototype.patch'
OWNED = ['MMOCoreORB/src/server/zone/objects/creature/commands/'+name for name in
         ('ActionCombatPolicy.h', 'SwgxrActionCombat.h', 'SwgxrLiveCombat.h')]+[
    'MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp',
    'MMOCoreORB/src/client/zone/NativeMotionStream.h',
    'MMOCoreORB/src/client/zone/ZonePacketHandler.cpp']

def main():
    if (ROOT/'server/patches/0139-mos-eisley-ground-combat.patch').exists():
        raise SystemExit('0138 is frozen below the ground integration. Edit current native sources and use update_ground_combat_patch.py.')
    patches = [p for p in sorted((ROOT/'server/patches').glob('*.patch')) if p.name < TARGET.name]
    paths = set(OWNED) | {line[6:] for p in patches for line in p.read_text().splitlines() if line.startswith('+++ b/')}
    with tempfile.TemporaryDirectory(prefix='swgxr-action-patch-') as directory:
        tree = Path(directory)
        subprocess.run(['git', 'init', '-q', str(tree)], check=True)
        for path in paths:
            old = subprocess.run(['git', '-C', str(CORE), 'show', 'HEAD:'+path], capture_output=True)
            if old.returncode == 0:
                target = tree/path;target.parent.mkdir(parents=True, exist_ok=True);target.write_bytes(old.stdout)
        for patch in patches:
            subprocess.run(['git', '-C', str(tree), 'apply', str(patch)], check=True)
        lines = []
        for path in OWNED:
            baseline = (tree/path).read_text() if (tree/path).exists() else ''
            name = Path(path).name
            source = ROOT/'server/combat'/name if name in ('ActionCombatPolicy.h','SwgxrActionCombat.h') else CORE/path
            desired = source.read_text()
            (CORE/path).write_text(desired)
            lines.extend(difflib.unified_diff(baseline.splitlines(True), desired.splitlines(True), fromfile='a/'+path if baseline else '/dev/null', tofile='b/'+path))
        TARGET.write_text(''.join(lines))
        subprocess.run(['git', '-C', str(tree), 'apply', str(TARGET)], check=True)
        for path in OWNED:assert (tree/path).read_bytes() == (CORE/path).read_bytes(), path
    print('Full pinned patch stack and action prototype verified')
if __name__ == '__main__':main()
