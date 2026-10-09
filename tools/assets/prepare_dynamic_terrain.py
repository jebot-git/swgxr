#!/usr/bin/env python3
"""Extract original camp/structure height layers for live terrain installation.

Original media and derived layers remain in ignored runtime directories. Flora
families are inventoried but are not translated into made-up height rules.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from static_assets import StaticAssets
from swg_formats import parse_iff
from terrain_formats import layer

ROOT = Path(__file__).resolve().parents[2]


def height_layer(value):
    out = dict(value)
    # Dynamic building layers use the authored boundary and height constants.
    # Independent shader/flora family IDs cannot be mixed into the planet table.
    unsupported = [r['type'] for r in value['affectors']
                   if r['type'].startswith('AH') and r['type'] != 'AHCN']
    if unsupported or value['filters'] or value['invert_boundaries']:
        raise ValueError('Unsupported dynamic height rule: ' + str(unsupported))
    out['affectors'] = [r for r in value['affectors'] if r['type'] == 'AHCN']
    out['children'] = [height_layer(c) for c in value['children']]
    return out


def bounds(layers):
    boxes = []
    for value in layers:
        for rule in value['boundaries']:
            if rule['type'] == 'BCIR':
                x, z = rule['center']; r = rule['radius']
                boxes.append([x-r, z-r, x+r, z+r])
            elif rule['type'] == 'BREC':
                x, z, xx, zz = rule['rect']
                boxes.append([min(x, xx), min(z, zz), max(x, xx), max(z, zz)])
            elif rule['type'] == 'BPOL':
                p = rule['points']
                boxes.append([min(v[0] for v in p), min(v[1] for v in p),
                              max(v[0] for v in p), max(v[1] for v in p)])
            else:
                raise ValueError('Unsupported dynamic boundary: ' + rule['type'])
        if value['children']:
            boxes.append(bounds(value['children']))
    if not boxes:
        raise ValueError('Unbounded terrain modification')
    return [min(v[0] for v in boxes), min(v[1] for v in boxes),
            max(v[2] for v in boxes), max(v[3] for v in boxes)]


def prepare(tre, output):
    output.mkdir(parents=True, exist_ok=True)
    assets = StaticAssets(tre, output)
    templates = set()
    inputs = {}
    for path, key in [('scout/catalog.json', 'camps'), ('housing/catalog.json', 'structures')]:
        catalog = ROOT/'runtime/assets'/path
        if catalog.exists():
            raw = catalog.read_bytes()
            templates.update(json.loads(raw).get(key, {}))
            inputs[path] = hashlib.sha256(raw).hexdigest()
    report = {'schema': 1, 'templates': {}, 'sources': {}, 'failures': [],
              'inputs_sha256': inputs,
              'scope': 'Original authored boundaries and height constants; no invented flatten radius'}
    for template in sorted(templates):
        try:
            p = Path(template)
            shared = str(p.parent/('shared_'+p.name.removeprefix('shared_')))
            name = assets.properties(shared).get('terrainModificationFileName', '')
            if not name:
                continue
            if name not in report['sources']:
                raw = assets.read(name); offset = 0; layers = []
                while offset < len(raw):
                    size = struct.unpack_from('>I', raw, offset+4)[0]+8
                    node = parse_iff(raw[offset:offset+size]); offset += size
                    if node.tag == 'LAYR':
                        layers.append(layer(node))
                authored = [height_layer(v) for v in layers]
                report['sources'][name] = {'layers': authored, 'bounds': bounds(authored),
                                          'sha256': hashlib.sha256(raw).hexdigest()}
            report['templates'][template] = {'source': name, 'shared_template': shared}
        except Exception as exc:
            report['failures'].append({'template': template, 'error': str(exc)})
    report['provenance'] = assets.dependencies
    (output/'catalog.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/asset_sources/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/terrain_modifications')
    args = parser.parse_args()
    report = prepare(args.tre_dir, args.out)
    print(json.dumps({'templates': len(report['templates']), 'sources': len(report['sources']),
                      'failures': report['failures']}))
