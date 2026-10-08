#!/usr/bin/env python3
"""Validate authored INLY transforms/cell ownership and exported interior sounds."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
from interior_layout import layout_records
from prepare_environment import snapshot
from prepare_stage import mirror, qrot
from static_assets import StaticAssets

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world', type=Path, default=ROOT / 'runtime/assets/tatooine_world/world.json')
    parser.add_argument('--environment', type=Path, default=ROOT / 'runtime/assets/tatooine_environment/environment.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'runtime/evidence/interior-assets-validation.json')
    args = parser.parse_args()
    world = json.loads(args.world.read_text()); environment = json.loads(args.environment.read_text())
    source = StaticAssets(Path(world['provenance']['tre_directory']), ROOT / 'runtime/assets/interior_audit')
    planet = world['planet']
    assert environment['planet'] == planet, 'Interior environment belongs to another planet'
    nodes = {node['id']: node for node in snapshot(source, planet)}
    origin = world['origin']; layouts = {}; ownership = {}; instances = []; cells = {}
    for descriptor in world['chunks'].values():
        chunk = json.loads((args.world.parent / descriptor['path']).read_text())
        assert len(chunk['instances']) == descriptor['instance_count']
        instances.extend(item for item in chunk['instances'] if item.get('source_layout'))
        cells.update(chunk['cells'])
    counts = collections.Counter(); ids = set(); max_transform_error = 0.0
    for instance in instances:
        layout = instance['source_layout']
        if layout not in layouts:
            layouts[layout] = layout_records(source.read, layout)
        original = layouts[layout][instance['source_layout_index']]
        building = nodes[instance['building_object_id']]
        assert original['template'] == instance['source_template']
        assert instance['object_id'] < 0 and abs(instance['object_id']) < 2**53
        # An object can contain multiple mesh components; IDs must still map to
        # one source layout record across the entire planet.
        identity = (instance['building_object_id'], layout, instance['source_layout_index'])
        assert ownership.setdefault(instance['object_id'], identity) == identity
        ids.add(instance['object_id'])
        cell = cells[instance['cell_id']]
        assert cell['name'] == original['cell_name']
        assert cell['building_object_id'] == instance['building_object_id']
        assert not instance['is_exterior']
        assert instance['collision_id'] in world['collisions']
        assert instance['mesh'] in world['meshes']
        # Independent matrix application verifies all basis axes and translation,
        # including rotation about arbitrary axes and the SWG/Godot Z reflection.
        matrix = original['source_layout_transform']
        x, y, z, w = instance['quaternion']
        swg_quaternion = (w, -x, -y, z)
        for probe in ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)):
            local = [sum(matrix[row * 4 + col] * probe[col] for col in range(3)) + matrix[row * 4 + 3] for row in range(3)]
            expected = mirror([a + b - origin[index] for index, (a, b) in enumerate(zip(qrot(building['q'], local), building['p']))])
            actual = [a + b for a, b in zip(mirror(qrot(swg_quaternion, probe)), instance['position'])]
            error = max(abs(a - b) for a, b in zip(expected, actual))
            assert error < 0.005, (identity, error)
            max_transform_error = max(max_transform_error, error)
        counts[instance['building_object_id']] += 1
    if planet == 'tatooine':
        assert counts[1082874] == 258, counts[1082874]
    sounds = [item for item in environment['emitters'] if item.get('source_layout')]
    cantina_sounds = [item for item in sounds if item['building_object_id'] == 1082874]
    if planet == 'tatooine':
        assert {item['sound'] for item in cantina_sounds} == {'sound/amb_cantina_large_lp.snd', 'sound/music_figrin_dan_song_1.snd'}
    for emitter in sounds:
        assert emitter['cell_id'] in cells
        assert emitter['sound'] in environment['sounds']
        assert emitter['source_layout'] in environment['provenance']['dependencies']
        assert all(math.isfinite(value) for value in emitter['position'])
    assert 'default:default' in environment['interior_soundscapes']
    if planet == 'tatooine':
        assert environment['interior_soundscapes']['thm_tato_cantina:default']['day_ambient'] == 'sound/amb_cantina_medium_lp.snd'
    for definition in environment['interior_soundscapes'].values():
        for role in ('day_ambient', 'night_ambient', 'first_music'):
            assert not definition[role] or definition[role] in environment['sounds']
    for layout in layouts:
        expected = world['provenance']['dependencies'][layout]
        assert hashlib.sha256(source.read(layout)).hexdigest() == expected['sha256']
    report = {'passed': True, 'layout_files': len(layouts), 'render_instances': len(instances), 'render_objects': len(ids), 'buildings': len(counts), 'maximum_transform_error_m': max_transform_error, 'cantina_instances': counts[1082874], 'layout_sound_emitters': len(sounds), 'cantina_sound_emitters': cantina_sounds, 'interior_soundscapes': len(environment['interior_soundscapes']), 'scope': 'Source transforms, cell ownership, collision references and sound provenance; no GPU or live headset validation.'}
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
