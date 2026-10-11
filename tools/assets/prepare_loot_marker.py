#!/usr/bin/env python3
"""Prepare the original SWG glowing coin for the client-only Loot All marker."""
import argparse
import json
from pathlib import Path
from static_assets import StaticAssets
ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'appearance/pt_glowing_imperial_coin.apt'

def prepare(tre, out):
    assets = StaticAssets(tre, out)
    parts = assets.resolve(SOURCE)
    if len(parts) != 1 or assets.failures:
        raise ValueError('Original loot coin conversion failed: ' + repr(assets.failures))
    model = assets.meshes[parts[0]['mesh']]['path']
    catalog = {'schema_version': 1, 'items': {'loot_coin': {'status': 'ready', 'model': model}},
               'provenance': {'source_appearance': SOURCE, 'dependencies': assets.dependencies},
               'failures': assets.failures, 'policy': 'Original user-owned SWG coin; gold tint and spin are client UI presentation only.'}
    (out / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    return catalog

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/asset_sources/active_tre')
    p.add_argument('--out', type=Path, default=ROOT/'runtime/assets/loot_marker')
    a = p.parse_args(); a.out.mkdir(parents=True, exist_ok=True)
    prepare(a.tre_dir, a.out)
