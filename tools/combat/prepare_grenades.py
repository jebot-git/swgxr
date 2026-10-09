#!/usr/bin/env python3
"""Prepare supplied grenade detonation effects for the shared bounded renderer."""
import json
from pathlib import Path

from prepare_assets import Assets

ROOT = Path(__file__).resolve().parents[2]
STEMS = {'fragmentation_light': 'fragmentation', 'fragmentation': 'fragmentation',
         'cryoban': 'cryoban', 'glop': 'glop', 'imperial': 'imp_detonator',
         'thermal': 'thermal_detonator', 'proton': 'proton'}


def prepare(importer):
    mapping, failures = {}, []
    for family, stem in STEMS.items():
        source = 'clienteffect/combat_grenade_'+stem+'.cef'
        try:
            mapping[family] = importer.effect(source)
        except (ValueError, KeyError) as exc:
            failures.append({'family': family, 'source': source, 'error': str(exc)})
    return mapping, failures


def main():
    out = ROOT/'runtime/assets/grenades'
    out.mkdir(parents=True, exist_ok=True)
    importer = Assets(ROOT/'runtime/asset_sources/active_tre', out, bounded_particle_graphs=True)
    mapping, failures = prepare(importer)
    failures += importer.failures + importer.audio_importer.failures
    provenance = dict(importer.dependencies, **importer.audio_importer.dependencies)
    result = {'schema': 1, 'grenade_effects': mapping, 'effects': importer.effects,
              'particles': importer.particles, 'sounds': importer.audio_importer.sounds,
              'provenance': provenance, 'failures': failures,
              'limitations': ['Original quad textures and curves use bounded presentation.',
                             'Nested attachment motion is flattened; unsupported mesh emitters are recorded.',
                             'No source camera shake or dynamic CEF lights are applied.']}
    (out/'assets.json').write_text(json.dumps(result, separators=(',', ':')))
    print(json.dumps({'families': len(mapping), 'effects': len(importer.effects),
                      'particles': len(importer.particles), 'failures': failures}, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
