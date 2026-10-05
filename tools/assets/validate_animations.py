#!/usr/bin/env python3
"""Validate selected original animation graphs, all lazy clips and rig bindings."""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {'idle', 'walk', 'run', 'strafe_left', 'strafe_right', 'backpedal',
            'crouch', 'crouch_walk', 'prone', 'crawl', 'sit', 'jump',
            'stand_to_crouch', 'crouch_to_stand', 'stand_to_prone',
            'prone_to_stand', 'stand_to_sit', 'sit_to_stand'}


def validate(directory):
    catalog = json.loads((directory / 'catalog.json').read_text())
    counts = {'races': 0, 'bound_clips': 0, 'tracks': 0, 'keys': 0}
    unavailable = []
    cache = {}
    for race, descriptor in catalog['races'].items():
        model = json.loads((directory / descriptor['body']).read_text())
        assert REQUIRED <= model['animations'].keys(), (race, 'Missing required source animation')
        assert model['animation_graph']['selectors']['gender'] == ('f' if race.endswith('_female') else 'm')
        clips = dict(model['animations'])
        for key, entry in model['animation_library'].items():
            path = directory / entry['path']
            if path not in cache:
                cache[path] = json.loads(path.read_text())
            clips[key] = cache[path]
            assert clips[key]['source'] == entry['source'], (race, key)
        for state, clip in clips.items():
            assert clip['source'].startswith('appearance/animation/') and clip['source'].endswith('.ans')
            assert clip['length'] > 0 and clip['fps'] > 0 and clip['tracks']
            counts['bound_clips'] += 1
            for track in clip['tracks']:
                assert model['bones'][track['bone']]['name'] == track['name'], (race, state, track['name'])
                counts['tracks'] += 1
                for channel, width in [('rotations', 5), ('positions', 4)]:
                    previous = -1
                    for key in track[channel]:
                        assert len(key) == width and all(math.isfinite(v) for v in key)
                        assert previous <= key[0] <= clip['length'] + .001, (race, state, key[0])
                        previous = key[0]
                        if channel == 'rotations':
                            assert abs(sum(v*v for v in key[1:]) - 1) < .002, (race, state, 'Quaternion')
                        counts['keys'] += 1
        unavailable.extend({'race': race, **entry} for entry in model['animation_graph']['unavailable'] if 'error' in entry)
        counts['races'] += 1
    # This catches accidental traversal into a nested selector's VAL instead of
    # the current SSAT's table: female sitting uses the authored female branch.
    if 'human_female' in catalog['races']:
        model = json.loads((directory / catalog['races']['human_female']['body']).read_text())
        assert 'all_f_' in model['animations']['sit']['source']
    return {'passed': True, **counts, 'unique_lazy_clips': len(cache), 'unavailable_source_references': unavailable,
            'explicit_approximations': ['jump-phase fall/land', 'idle pose while turning', 'gameplay root motion']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'runtime/assets/characters')
    args = parser.parse_args()
    print(json.dumps(validate(args.directory), indent=2))
