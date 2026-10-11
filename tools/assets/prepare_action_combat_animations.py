#!/usr/bin/env python3
"""Refresh bounded original attack clips in existing local NPC catalogs."""
import argparse
import hashlib
import json
from pathlib import Path
from swg_formats import TreSet
from character_animations import load_lat, action_animation_bindings, decode_clip

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', action='append', type=Path)
    args = parser.parse_args()
    catalogs = args.catalog or [ROOT / 'runtime/assets' / p / 'catalog.json' for p in
        ('combat_population/native_current', 'combat_population/mos_eisley_easy', 'combat_population/tatooine',
         'combat_population/tatooine_entities', 'ambient_npcs')]
    tree = TreSet(ROOT / 'runtime/asset_sources/active_tre')
    seen = set(); rows = []; failures = []; tables = {}
    for catalog in catalogs:
        if not catalog.exists():
            continue
        for descriptor in json.loads(catalog.read_text())['races'].values():
            path = catalog.parent / descriptor['body']
            if path in seen:
                continue
            seen.add(path)
            model = json.loads(path.read_text())
            graph = model.get('animation_graph', {})
            for binding in graph.get('lat_bindings', [])[:1]:
                try:
                    if binding['lat'] not in tables:
                        tables[binding['lat']] = load_lat(tree, binding['lat'])[1]
                    for key, logical, leaf in action_animation_bindings(tables[binding['lat']], graph.get('selectors', {})):
                        clip = decode_clip(tree, leaf['source'], model['bones'], {b['name']: i for i, b in enumerate(model['bones'])})
                        assert clip['tracks'], 'No tracks bind to source skeleton'
                        clip.update(loop=False, logical=logical, source_speed_scale=leaf['speed_scale'])
                        encoded = json.dumps(clip, separators=(',', ':'))
                        relative = 'animations/' + hashlib.sha256(encoded.encode()).hexdigest()[:24] + '.json'
                        target = catalog.parent / relative; target.parent.mkdir(exist_ok=True)
                        target.write_text(encoded)
                        model.setdefault('animation_library', {})[key] = dict(path=relative, source=leaf['source'], logical=logical, loop=False)
                        rows.append(dict(model=str(path), key=key, source=leaf['source'], sha256=clip['source_sha256'], seconds=clip['length']/leaf['speed_scale']))
                    path.write_text(json.dumps(model, separators=(',', ':')))
                except Exception as error:
                    failures.append(dict(model=str(path), error=str(error)))
    report = dict(clips=rows, failures=failures)
    output = ROOT / 'runtime/action-prototype/animation-preparation.json'; output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(dict(clips=len(rows), failures=failures, output=str(output))))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
