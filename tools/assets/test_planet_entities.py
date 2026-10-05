#!/usr/bin/env python3
"""Regression checks against the real local Core3 appearance dependency graph."""
import hashlib
from pathlib import Path
from prepare_planet_entities import ROOT, clean, source_union


def main():
    assert clean('name="two--words" -- ignored\nnext="yes"') == 'name="two--words"           \nnext="yes"'
    manifest=source_union()
    assert not manifest['failures'],manifest['failures']
    actual=set(manifest['appearance_templates'])
    # These exact native models were absent when selection only followed wild
    # lair groups or the deterministic ambient city's single random choice.
    expected={
        'object/mobile/junk_malik.iff',
        'object/mobile/dressed_commoner_old_twilek_female_02.iff',
        'object/mobile/dressed_commoner_tatooine_aqualish_male_07.iff',
        'object/mobile/dressed_commoner_old_zabrak_male_01.iff',
        'object/mobile/dressed_tatooine_valarian_henchman.iff',
        'object/mobile/worrt_hue.iff',
        'object/mobile/dressed_hutt_informant_quest.iff',
    }
    assert expected<=actual,expected-actual
    assert {'informant_npc_lvl_1','informant_npc_lvl_2','informant_npc_lvl_3'}<=manifest['mobiles'].keys()
    assert all(Path(v['source']).parts[-1].endswith('.lua') for v in manifest['mobiles'].values())
    for path,digest in manifest['provenance']['files_sha256'].items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
    assert all(t.startswith(('object/mobile/','object/creature/')) for t in actual)
    assert manifest['mode']=='source_dependency_index_not_live_population'
    print({'passed':True,'templates':len(actual),'source_mobile_definitions':len(manifest['mobiles']),'verified_sources':len(manifest['provenance']['files_sha256']),'live_spawned':False})


if __name__=='__main__':main()
