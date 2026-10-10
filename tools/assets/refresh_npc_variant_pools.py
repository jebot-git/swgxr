#!/usr/bin/env python3
"""Retain original NPC appearance pools for exact live/ambient ownership.

Updates ignored placement manifests only; never merges nearby NPC identities.
Stationary city slots include both original commoner and citizen pools. Source
hashes and unresolved definitions are retained alongside the placement audit.
"""
import hashlib
import json
from pathlib import Path
from prepare_planet_entities import source_union, clean, strings
from export_ambient_npcs import table, rows
ROOT = Path(__file__).resolve().parents[2]


def refresh(path):
    data = json.loads(path.read_text())
    sources = source_union(data['planet'])
    definitions = sources['mobiles']
    failures = []
    counts = 0
    for entry in data['instances']:
        names = [entry['mobile']]
        source = ROOT / entry['source_file']
        text = clean(source.read_text())
        kind = entry.get('selection', {}).get('kind')
        if kind == 'stationaryMobiles':
            names += strings(table(text, 'stationaryCommoners')[0]) + strings(table(text, 'stationaryNpcs')[0])
        elif kind == 'gcwMobs':
            for row, line in rows(text, kind):
                if line == entry['source_line'] and len(row)>1 and isinstance(row[1],str):names.append(row[1])
        templates = {entry['template']}
        for name in names:
            definition = definitions.get(name)
            if definition is None:
                failures.append(dict(placement=entry['id'],mobile=name,error='Original mobile definition unresolved'))
                continue
            templates.update(definition.get('appearance_templates', []))
        entry['source_templates'] = sorted(templates)
        counts += len(templates)>1
    data['variant_pool_audit'] = dict(randomized_placements=counts,failures=failures,
        source_files_sha256=sources['provenance']['files_sha256'])
    path.write_text(json.dumps(data,indent=2)+'\n')
    return dict(path=str(path.relative_to(ROOT)),placements=len(data['instances']),randomized=counts,failures=len(failures),sha256=hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    paths=[ROOT/'runtime/assets/ambient_npcs/placements.json']+sorted((ROOT/'runtime/assets/planets').glob('*/ambient/placements.json'))
    print(json.dumps([refresh(path) for path in paths],indent=2))
