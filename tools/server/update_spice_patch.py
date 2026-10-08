#!/usr/bin/env python3
"""Regenerate native smuggler changes against all pinned predecessors."""
import difflib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'vendor/Core3'
TARGET = ROOT / 'server/patches/0065-spice-lifecycle-combat.patch'
OWNED = ['MMOCoreORB/src/server/zone/'+name for name in (
 'objects/creature/commands/SwgxrSpice.h','objects/creature/commands/SwgxrLiveCombat.h',
 'objects/creature/commands/SwgxrSmuggler.h','objects/creature/commands/SwgxrScout.h',
 'objects/creature/commands/SquadLeaderCommand.h','objects/creature/commands/TumbleToStandingCommand.h',
 'objects/creature/commands/TumbleToProneCommand.h','objects/creature/commands/TumbleToKneelingCommand.h',
 'objects/creature/commands/MaskscentCommand.h','objects/creature/CreatureObjectImplementation.cpp',
 'objects/creature/buffs/BuffImplementation.cpp','objects/creature/buffs/SpiceBuffImplementation.cpp','objects/creature/buffs/SpiceDownerBuff.idl',
 'managers/player/PlayerManagerImplementation.cpp','managers/combat/CombatManager.cpp')]
BASELINES = {}


def function_text(text, name):
    start = text.index('int CreatureObjectImplementation::' + name + '(')
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        if text[end] == '{': depth += 1
        elif text[end] == '}': depth -= 1
        end += 1
    return text[start:end]


def filter_integrations(path, text):
    if path.endswith('/CreatureObjectImplementation.cpp') and path in BASELINES:
        text = text.replace('#include "server/zone/objects/creature/commands/SwgxrSpiceMedicine.h"\n', '')
        for name in ('healDamage', 'healWound'):
            text = text.replace(function_text(text, name), function_text(BASELINES[path], name), 1)
    return text





def desired_text(path):
    later = [patch for patch in sorted((ROOT / 'server/patches').glob('*.patch'), reverse=True)
             if patch.name > TARGET.name and ('+++ b/' + path + '\n') in patch.read_text()]
    if not later:
        return filter_integrations(path, (CORE / path).read_text())
    with tempfile.TemporaryDirectory(prefix='swgxr-ch-owned-') as temporary:
        tree = Path(temporary)
        subprocess.run(['git','init','-q',str(tree)],check=True)
        target = tree / path
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes((CORE / path).read_bytes())
        for patch in later:
            subprocess.run(['git','-C',str(tree),'apply','--reverse','--include='+path,str(patch)],check=True)
        return filter_integrations(path, target.read_text())


def main():
    all_patches = sorted((ROOT / 'server/patches').glob('*.patch'))
    patches = [p for p in all_patches if p.name < TARGET.name]
    paths = set(OWNED) | {line[6:] for patch in all_patches for line in patch.read_text().splitlines() if line.startswith('+++ b/')}
    with tempfile.TemporaryDirectory(prefix='swgxr-smuggler-patch-') as temporary:
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
            BASELINES[path] = baseline
            desired = desired_text(path)
            for line in difflib.unified_diff(baseline.splitlines(True), desired.splitlines(True), fromfile='a/' + path if baseline else '/dev/null', tofile='b/' + path, n=3):
                lines.append(line if line.endswith('\n') else line+'\n\\ No newline at end of file\n')
        TARGET.write_text(''.join(lines))
        subprocess.run(['git', '-C', str(tree), 'apply', str(TARGET)], check=True)
        for path in OWNED:
            assert (tree / path).read_text() == desired_text(path), path
        for patch in all_patches:
            if patch.name > TARGET.name:
                subprocess.run(['git', '-C', str(tree), 'apply', str(patch)], check=True)
        print('Spice lifecycle/combat patch verified:', len(lines), 'lines;', len(OWNED), 'owned paths; full patch stack applies')


if __name__ == '__main__':
    main()
