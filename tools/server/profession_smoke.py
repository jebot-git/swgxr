#!/usr/bin/env python3
"""Original-source profession translation checks and explicit synthetic lab fixture."""
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'tools/assets'))
from server.profession_protocol import translate, weapon_class, class_progress, player_context, ADVANCED
from server.unarmed_protocol import resolve, player_stats
from tools.server.combat_protocol_smoke import fixture as wire_fixture, pack, numbers, ascii_string
from tools.combat.export_catalog import export
from character_formats import datatable
from swg_formats import TreSet


def main():
    catalog = export(ROOT/'vendor/Core3', json.loads((ROOT/'client/combat/balance.json').read_text()))
    assert not catalog['failures']
    rows = datatable(TreSet(ROOT/'runtime/assets/active_tre').read('datatables/skill/skills.iff'))
    trees = ['combat_marksman_', 'combat_brawler_'] + ['combat_' + value + '_' for value in ADVANCED.values()]
    learned = [row['NAME'] for row in rows if any(row['NAME'].startswith(prefix) for prefix in trees)]
    mods = {}
    for row in rows:
        if row['NAME'] not in learned: continue
        for mod in filter(None, row['SKILL_MODS'].split(',')):
            name, value = mod.split('=')
            mods[name] = mods.get(name, 0) + int(value)
    checks = 0
    for profile in catalog['weapons'].values():
        original = copy.deepcopy(profile)
        translate(profile, mods, learned)
        kind = weapon_class(profile)
        assert kind, profile['id']
        assert profile['core3'] == original['core3']
        assert len(profile['abilities']) == 1
        assert profile['abilities'][0]['cooldown_seconds'] == 15
        assert translate(copy.deepcopy(original), {}, [])['abilities'] == []
        again = copy.deepcopy(profile)
        translate(again, mods, learned)
        assert again == profile, 'Bonuses stacked on refresh'
        checks += 6
    assert class_progress('rifle', ['combat_pistol_master']) == 0
    assert class_progress('pistol', ['combat_pistol_master']) == 1
    assert class_progress('rifle', ['combat_marksman_rifle_01']) == 1/22
    checks += 3
    # Basic mastery grants an ability, but does not invent rifle branch levels.
    rifle = copy.deepcopy(catalog['weapons']['rifle_e11'])
    translate(rifle, {'pistol_accuracy':100, 'pistol_speed':100}, ['combat_marksman_master','combat_pistol_master'])
    assert rifle['profession']['rpm_scale'] == 1 and rifle['profession']['range_modifier_bonus'] == 0
    assert rifle['abilities'][0]['cooldown_seconds'] == 30
    checks += 2
    unarmed = resolve({'strength':300, 'quickness':300, 'unarmed_damage':mods['unarmed_damage'], 'unarmed_speed':mods['unarmed_speed']}, learned=learned, source='synthetic_profession_lab')
    previous = unarmed['stance_recovery']
    translate(unarmed, mods, learned)
    assert unarmed['stance_recovery'] * unarmed['profession']['stance_recovery_scale'] == previous
    checks += 1
    for key, multiplier in {'pistol_cdef':3.75, 'knife_survival':3.0, '2h_sword_maul':1.0, 'lance_staff_wood_s1':2.0}.items():
        assert catalog['weapons'][key]['abilities'][0]['damage_multiplier'] == multiplier
        checks += 1
    assert catalog['weapons']['pistol_cdef']['abilities'][0]['base_sac'] == {'health':10, 'action':15, 'mind':10}
    checks += 1
    record = wire_fixture()[0]
    record['baseline1'] = (bytes(8) + numbers([1000,300,300,1000,300,300,1000,300,300])).hex()
    record['baseline4'] = (bytes(8) + numbers([]) + pack('II',2,1)
                           + pack('B',0) + ascii_string('pistol_accuracy') + pack('ii',40,5)
                           + pack('B',0) + ascii_string('rifle_speed') + pack('ii',10,0)).hex()
    decoded = player_stats(record)
    assert decoded['skill_mods'] == {'pistol_accuracy':45, 'rifle_speed':10}
    context = player_context({'variables':{'replication':{'objects':{'o123':record}}}}, '123')
    assert context['complete'] and context['ham'][0] == 800 and context['ham'][1] == 100
    record.pop('baseline6')
    assert not player_context({'variables':{'replication':{'objects':{'o123':record}}}}, '123')['complete']
    checks += 3
    fixture = {'source':'synthetic_profession_lab', 'weapons':catalog['weapons'], 'unarmed':unarmed,
               'player_combat':{'character_id':'synthetic-profession-lab', 'complete':True,
                                'ham':[1000,300,300,1000,300,300,1000,300,300],
                                'max_ham':[1000,300,300,1000,300,300,1000,300,300],
                                'wounds':[0]*9, 'posture':0}}
    output = ROOT/'runtime/evidence/professions'
    output.mkdir(parents=True, exist_ok=True)
    (output/'fixture.json').write_text(json.dumps(fixture, indent=2)+'\n')
    report = {'passed':True, 'checks':checks, 'profiles':len(catalog['weapons']), 'source_skill_rows':len(learned), 'live_core3':False}
    (output/'translation.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__': main()
