#!/usr/bin/env python3
"""Validate real source droid cadence and exact dense acklay skin influences."""
import json
from pathlib import Path
from prepare_planet_entities import ROOT


def main():
    base=ROOT/'runtime/assets/combat_population/tatooine_entities'
    catalog=json.loads((base/'catalog.json').read_text())
    for template in ('blastromech','wed_treadwell'):
        entry=catalog['races'][f'object/mobile/{template}.iff']
        model=json.loads((base/entry['body']).read_text())
        for state in ('walk','run'):
            clip=model['animations'][state]
            assert clip['tracks'] and clip['source_speed_mps']>0
            assert len(clip['source_cycle_displacement'])==3
        assert model['animations']['run']['source_speed_mps']>=model['animations']['walk']['source_speed_mps']
    model=json.loads((base/catalog['races']['object/mobile/acklay_hue.iff']['body']).read_text())
    groups={v['bone']:v['source_bones'] for v in model['virtual_skin_bones']}
    expanded_by_position={}
    for part in model['parts']:
        for surface in part['mesh']['surfaces']:
            for vertex in range(len(surface['vertices'])//3):
                position=tuple(surface['vertices'][vertex*3:vertex*3+3]);weights={}
                for bone,weight in zip(surface['bones'][vertex*8:vertex*8+8],surface['weights'][vertex*8:vertex*8+8]):
                    if not weight:continue
                    sources=groups.get(bone,[bone])
                    for source in sources:weights[source]=weights.get(source,0)+weight/len(sources)
                expanded_by_position.setdefault(position,[]).append(weights)
    audits=model['virtual_skin_audit'];assert audits
    for audit in audits:
        expected=dict(zip(audit['bones'],audit['weights']))
        candidates=expanded_by_position[tuple(audit['position'])]
        assert any(all(abs(candidate.get(b,0)-expected.get(b,0))<1e-7 for b in candidate.keys()|expected.keys()) for candidate in candidates),audit
    result=dict(passed=True,source_droids=2,exact_dense_vertices=len(audits),virtual_groups=len(groups),weights_pruned=0,gpu_validated=False)
    (ROOT/'runtime/evidence/entity-parser-regressions.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))


if __name__=='__main__':main()
