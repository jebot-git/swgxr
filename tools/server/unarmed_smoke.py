#!/usr/bin/env python3
"""Read persistent Brawler stats from Core3; no skill grants or fabricated modifiers."""
import json
import secrets
from pathlib import Path
from weapon_crafting_smoke import request
ROOT=Path(__file__).resolve().parents[2]

def main():
    path=ROOT/'runtime/server/unarmed-fixture.json'
    if not path.exists():
        account='fist'+secrets.token_hex(4)
        name='Fist'+''.join(secrets.choice('aeilnorstu') for _ in range(6))
        created=request('/characters',{'account':account,'name':name,'species':'human','profession':'combat_brawler'})
        path.write_text(json.dumps({'account':account,'id':created['character']['id'],'name':name})+'\n')
    fixture=json.loads(path.read_text())
    query='?account='+fixture['account']+'&character_id='+fixture['id']
    first=request('/weapons'+query)
    second=request('/weapons'+query)
    assert first==second
    fist=first['unarmed']; stats=fist['player_stats']
    assert fist['source_kind']=='core3_player_stats' and fist['character_id']==fixture['id']
    assert 'combat_brawler_novice' in fist['skills']
    assert stats['unarmed_speed']>=5 and stats['unarmed_damage']>=15
    assert fist['power']==100+stats['strength']*.1+stats['unarmed_damage']*.25
    assert fist['stance_recovery']==100+stats['quickness']*.1+stats['unarmed_speed']
    assert 'item_id' not in fist and 'capacity' not in fist and 'rpm' not in fist
    entry=request('/enter',{'account':fixture['account'],'character_id':fixture['id']})
    assert entry['weapon_snapshot']==first
    (ROOT/'runtime/evidence/unarmed-live-snapshot.json').write_text(json.dumps(first,indent=2)+'\n')
    report={'passed':True,'character_id':fixture['id'],'power':fist['power'],'stance_recovery':fist['stance_recovery'],
            'player_stats':stats,'fresh_login_and_entry':True,'live_teras_kasi_training_tested':False,'persistent_combat_tested':False}
    (ROOT/'runtime/evidence/unarmed-core3-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
