#!/usr/bin/env python3
"""Measure original clips relevant to the isolated worrt/thug encounter.

Reads user-supplied TREs only. The output is metadata, not converted animation
assets. Durations include LAT time scales; message names are preserved without
assuming a sound cue marks physical contact. This does not select runtime clips.
"""
import argparse
import hashlib
import json
import math
import re
import struct
from pathlib import Path

from character_animations import animation_messages, load_lat, resolve
from swg_formats import TreSet, parse_iff, cstring

ROOT = Path(__file__).resolve().parents[2]


def audit(tree):
    groups = {}
    failures = []
    # Restrict melee estimates to ordinary authored attack aliases. Prefix-only
    # matching also includes long combos, taunts and other special actions.
    basic_melee = set()
    for action in parse_iff(tree.read('appearance/ash/all_b.ash')).walk('ACTN'):
        name, offset = cstring(action.data)
        logical, _ = cstring(action.data, offset)
        if re.fullmatch(r'attack_(high|mid|low)_(left|center|right)_[012]', name):
            basic_melee.add(logical)
    for lat in ('appearance/lat/frog.lat', 'appearance/lat/all_m.lat'):
        ash, entries = load_lat(tree, lat)
        for logical, node in sorted(entries.items()):
            if lat.endswith('/frog.lat'):
                if not logical.startswith('cbt_stand_combat_attack_'):
                    continue
                group = 'worrt_special' if 'special' in logical else 'worrt_basic'
            elif logical in ('pistol_combat_standing_fire_1', 'pistol_combat_standing_fire_3', 'pistol_combat_standing_fire_5'):
                group = logical
            elif logical in basic_melee and logical.startswith('sword_1h_standing_ready_'):
                group = 'thug_one_handed_melee_candidates'
            elif logical in basic_melee and logical.startswith('pole_standing_ready_'):
                group = 'thug_polearm_candidates'
            elif logical == 'heal_other':
                group = 'support_standing_heal_candidate'
            else:
                continue
            try:
                for leaf in resolve(node, {'gender': 'm', 'mood': 'neutral'}):
                    source = leaf['source']
                    raw = tree.read(source)
                    iff = parse_iff(raw)
                    assert iff.tag in ('CKAT', 'KFAT'), iff.tag
                    fps, last_frame, *_ = struct.unpack('<f6h' if iff.tag == 'CKAT' else '<f6i', iff.first('INFO').data)
                    scale = leaf['speed_scale']
                    assert math.isfinite(fps) and fps > 0 and last_frame > 0
                    assert math.isfinite(scale) and scale > 0
                    groups.setdefault(group, []).append(dict(
                        logical=logical, lat=lat, ash=ash, source=source,
                        archive=str(tree.entries[source][0]),
                        sha256=hashlib.sha256(raw).hexdigest(), fps=fps,
                        last_frame=last_frame, raw_seconds=last_frame / fps,
                        speed_scale=scale, seconds=last_frame / fps / scale,
                        messages=[dict(message=m['message'], seconds=m['seconds'] / scale)
                                  for m in animation_messages(raw)]))
            except Exception as error:
                failures.append(dict(lat=lat, logical=logical, error=str(error)))
    summary = {name: dict(clips=len({r['source'] for r in rows}),
                         min_seconds=min(r['seconds'] for r in rows),
                         max_seconds=max(r['seconds'] for r in rows))
               for name, rows in groups.items()}
    assert len(groups) == 8, list(groups)
    return dict(method='ANS last_frame / fps / LAT speed_scale',
                scope='Standing original clips for worrt, weapon-dependent thug candidates and the support heal.',
                summary=summary, groups=groups, failures=failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre', type=Path, default=ROOT / 'runtime/asset_sources/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/action-prototype/animation-timing.json')
    args = parser.parse_args()
    report = audit(TreSet(args.tre))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(summary=report['summary'], failures=report['failures'], output=str(args.out)), indent=2))
    if report['failures']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
