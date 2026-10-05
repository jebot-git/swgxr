#!/usr/bin/env python3
"""Original jump root curve and original knockdown clips, without physics motion."""
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/assets'))
from prepare_characters import CharacterImporter
from character_animations import load_lat, resolve, decode_clip


def main():
    source = ROOT/'runtime/assets/characters'
    output = ROOT/'runtime/combat/player_postures'
    imp = CharacterImporter(ROOT/'runtime/assets/active_tre', output)
    catalog = json.loads((source/'catalog.json').read_text())
    reference = json.loads((source/catalog['races']['human_male']['body']).read_text())['animations']['jump']
    raw = imp.read(reference['source'])
    assert hashlib.sha256(raw).hexdigest() == reference['source_sha256']
    root = next(track for track in reference['tracks'] if track['name'] == 'root')
    initial = root['positions'][0][2]
    curve = [[key[0],key[2]-initial] for key in root['positions']]
    curve[-1][1] = 0.0
    report = {'jump':{'source':reference['source'], 'source_sha256':reference['source_sha256'],
                      'duration':reference['length'], 'height_curve':curve,
                      'motion':'Original root Y displacement; cosmetic only, no body impulse.'}, 'knockdown':{}}
    for race, descriptor in catalog['races'].items():
        model = json.loads((source/descriptor['body']).read_text())
        graph = model['animation_graph']
        _, table = load_lat(imp, graph['lat_bindings'][0]['lat'])
        leaves = resolve(table['loop_incapacitated_face_up'], graph['selectors'])
        clip = decode_clip(imp, leaves[0]['source'], model['bones'], {b['name']:i for i,b in enumerate(model['bones'])})
        clip.update(loop=True, logical='loop_incapacitated_face_up')
        imp.write(race+'.json', clip)
        report['knockdown'][race] = {'path':race+'.json', 'source':clip['source'], 'source_sha256':clip['source_sha256']}
    report['provenance'] = imp.dependencies
    imp.write('catalog.json', report)
    print(json.dumps({'jump_duration':reference['length'], 'jump_peak_m':max(p[1] for p in curve), 'knockdown_rigs':len(report['knockdown'])}))


if __name__ == '__main__': main()
