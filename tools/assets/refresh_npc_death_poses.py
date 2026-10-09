#!/usr/bin/env python3
"""Add exact authored incapacitation clips to existing original NPC catalogs.

Only animation metadata/models are refreshed; CDF equipment and source failures
remain intact. Native DEAD is the authority. This is not a dedicated death clip.
"""
import argparse
import hashlib
import json
from pathlib import Path

from prepare_characters import CharacterImporter
from character_animations import ash_summary, decode_clip, load_lat, resolve
from swg_formats import cstring, parse_iff


def refresh(directory):
    catalog = json.loads((directory / 'catalog.json').read_text())
    imp = CharacterImporter(Path(catalog['provenance']['tre_directory']), directory)
    results = {}
    for descriptor in catalog['races'].values():
        path = descriptor['body']
        if path not in results:
            try:
                model = json.loads((directory / path).read_text())
                raw = parse_iff(imp.read(descriptor['appearance'])).first('LATX').data
                _, offset = cstring(raw, 2)
                lat, _ = cstring(raw, offset)
                ash, table = load_lat(imp, lat)
                graph = ash_summary(imp, ash)
                state = next(s for s in graph['states'] if s['name'] == 'incapacitated_face_up')
                selectors = model.get('animation_graph', {}).get('selectors', {})
                leaves = resolve(table[state['loop']], selectors)
                if len(leaves) != 1:
                    raise ValueError('Ambiguous source incapacitation selector')
                leaf = leaves[0]
                clip = decode_clip(imp, leaf['source'], model['bones'], {b['name']: i for i, b in enumerate(model['bones'])})
                if not clip['tracks']:
                    raise ValueError('No original tracks match skeleton')
                clip.update(loop=False, logical=state['loop'], source_speed_scale=leaf.get('speed_scale', 1))
                encoded = json.dumps(clip, separators=(',', ':')).encode()
                relative = 'animations/' + hashlib.sha256(encoded).hexdigest()[:24] + '.json'
                imp.write(relative, clip)
                model.setdefault('animation_library', {})['incapacitated'] = dict(path=relative, source=leaf['source'], logical=state['loop'], loop=False)
                imp.write(path, model)
                results[path] = dict(ready=True, source=leaf['source'], tracks=len(clip['tracks']))
            except Exception as exc:
                results[path] = dict(ready=False, error=repr(exc))
        descriptor['incapacitated_pose'] = results[path]
        failures = [f for f in catalog['failures'] if f.get('template') == descriptor['template'] and f.get('phase') in ('wearable', 'client_data', 'cdf_attachment')]
        descriptor['appearance_complete'] = not failures
        if failures:
            descriptor['appearance_failures'] = failures
    catalog['provenance']['dependencies'].update(imp.dependencies)
    catalog['incapacitated_pose_report'] = dict(policy='Original authored incapacitated pose frozen for native DEAD; outfit retained; not a dedicated death animation', bodies=results)
    imp.write('catalog.json', catalog)
    return dict(directory=str(directory), bodies=len(results), ready=sum(v['ready'] for v in results.values()), failures={k:v for k,v in results.items() if not v['ready']})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='+')
    args = parser.parse_args()
    for directory in args.directory:
        print(json.dumps(refresh(directory)), flush=True)
