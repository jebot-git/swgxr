#!/usr/bin/env python3
"""Verify a real owned starter knife across Core3 logins; never fabricate item data."""
import json
from pathlib import Path
from weapon_crafting_smoke import request

ROOT = Path(__file__).resolve().parents[2]

def main():
    fixture = json.loads((ROOT/'runtime/server/datapad-fixture.json').read_text())
    query = '?account='+fixture['account']+'&character_id='+fixture['id']
    first = request('/weapons'+query)
    second = request('/weapons'+query)
    assert first == second and first['backend'] == 'core3'
    melee = [weapon for weapon in first['weapons'] if weapon.get('kind') == 'melee']
    assert melee, 'Fixture must own a supported melee weapon'
    for weapon in melee:
        assert weapon['source_kind'] == 'core3_weapon_instance'
        assert weapon['power'] > 0 and weapon['stance_recovery'] > 0
        assert 'rpm' not in weapon and 'capacity' not in weapon
        assert set(weapon['crafting_modifiers']) == {'power','stance_recovery'}
    entry = request('/enter', {'account':fixture['account'],'character_id':fixture['id']})
    assert entry['weapon_snapshot'] == first
    (ROOT/'runtime/evidence/melee-live-snapshot.json').write_text(json.dumps(first,indent=2)+'\n')
    report = {'passed':True,'character_id':fixture['id'],'melee_items':[w['item_id'] for w in melee],
              'fresh_login_and_entry':True,'live_crafting_performed':False,'persistent_combat_tested':False}
    (ROOT/'runtime/evidence/melee-core3-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))

if __name__ == '__main__': main()
