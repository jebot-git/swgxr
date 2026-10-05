#!/usr/bin/env python3
"""Check converted SWG avatars, skin bindings, morphs and local asset provenance."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from swg_formats import TreSet

ROOT = Path(__file__).resolve().parents[2]


def validate(directory):
    catalog = json.loads((directory / 'catalog.json').read_text())
    counts = dict(races=len(catalog['races']), models=0, surfaces=0, vertices=0,
                  triangles=0, morph_arrays=0, animation_clips=0,
                  animation_tracks=0, verified_dependencies=0)
    assert catalog['races'], 'No playable models'
    for path in sorted(directory.rglob('*.json')):
        model = json.loads(path.read_text())
        if not isinstance(model, dict) or 'parts' not in model:
            continue
        bones = model['bones']
        assert bones and len({b['name'] for b in bones}) == len(bones), path
        for index, bone in enumerate(bones):
            assert -1 <= bone['parent'] < index, (path, bone['name'], 'parent order')
            assert len(bone['rest_position']) == 3
            assert all(math.isfinite(v) for v in bone['rest_position'])
            rotation = bone['rest_rotation']
            assert len(rotation) == 4 and abs(sum(v*v for v in rotation)-1) < 0.002
        for animation in model.get('animations', {}).values():
            assert animation['length'] > 0 and animation['fps'] > 0
            for track in animation['tracks']:
                assert 0 <= track['bone'] < len(bones)
                assert bones[track['bone']]['name'] == track['name']
                for field, width in [('rotations', 5), ('positions', 4)]:
                    previous_time = -1.0
                    for key in track.get(field, []):
                        assert len(key) == width and all(math.isfinite(v) for v in key)
                        assert previous_time <= key[0] <= animation['length'] + 0.001
                        previous_time = key[0]
                        if field == 'rotations':
                            assert abs(sum(v*v for v in key[1:])-1) < 0.002
                counts['animation_tracks'] += 1
            counts['animation_clips'] += 1
        for part in model['parts']:
            mesh = part['mesh']
            assert mesh['bone_count'] == len(bones), (path, part['id'], 'bone count')
            assert len(set(mesh.get('blend_shapes', []))) == len(mesh.get('blend_shapes', []))
            for surface in mesh['surfaces']:
                vertices = surface['vertices']
                n = len(vertices) // 3
                assert n > 0 and len(vertices) == n * 3
                for field, width in [('vertices', 3), ('normals', 3), ('uv', 2)]:
                    values = surface.get(field, [])
                    assert len(values) in (0, n * width), (path, field)
                    assert all(math.isfinite(v) for v in values), (path, field)
                indices = surface['indices']
                assert len(indices) % 3 == 0
                assert all(isinstance(i, int) and 0 <= i < n for i in indices)
                zones = surface.get('triangle_zones', [])
                assert not zones or len(zones) == len(indices) // 3
                joints, weights = surface['bones'], surface['weights']
                width = len(joints) // n
                assert width in (4, 8) and len(joints) == len(weights) == width * n
                assert all(isinstance(i, int) and 0 <= i < len(bones) for i in joints)
                assert all(math.isfinite(w) and w >= 0 for w in weights)
                assert all(abs(sum(weights[i:i+width])-1) < 0.001 for i in range(0, len(weights), width))
                for name, morph in surface.get('blend_shapes', {}).items():
                    assert name in mesh['blend_shapes']
                    for field in ('vertices', 'normals'):
                        values = morph.get(field, [])
                        assert len(values) in (0, n * 3), (path, name, field)
                        assert all(math.isfinite(v) for v in values)
                    counts['morph_arrays'] += 1
                texture = surface.get('texture')
                if texture:
                    assert (directory / texture).read_bytes().startswith(b'\x89PNG'), texture
                counts['surfaces'] += 1
                counts['vertices'] += n
                counts['triangles'] += len(indices) // 3
        counts['models'] += 1
    for race in catalog['races'].values():
        assert (directory / race['body']).is_file()
        for hair in race.get('hair', []):
            assert (directory / hair['model']).is_file()
    provenance = catalog['provenance']
    tre = TreSet(provenance['tre_directory'])
    for name, dependency in provenance['dependencies'].items():
        data = tre.read(name)
        assert len(data) == dependency['bytes'], name
        assert hashlib.sha256(data).hexdigest() == dependency['sha256'], name
        counts['verified_dependencies'] += 1
    counts.update(status='passed', conversion_failures=catalog.get('failures', []),
                  scope='Asset structure and provenance; visual appearance and Core3 readback tested separately.')
    (directory / 'validation_report.json').write_text(json.dumps(counts, indent=2) + '\n')
    return counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'runtime/assets/characters')
    print(json.dumps(validate(parser.parse_args().directory), indent=2))
