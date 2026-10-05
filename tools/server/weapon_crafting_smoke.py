#!/usr/bin/env python3
"""Read actual owned Core3 weapons across logins; no fabricated crafted items."""
import json
import secrets
from pathlib import Path
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[2]

def request(path, data=None):
    req=urllib.request.Request('http://127.0.0.1:18080'+path, data=json.dumps(data).encode() if data else None,
                              headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=75) as stream: return json.load(stream)

def main():
    fixture_path=ROOT/'runtime/server/crafting-fixture.json'
    if not fixture_path.exists():
        account='craft'+secrets.token_hex(3)
        name='Craft'+''.join(secrets.choice('aeilnorstu') for _ in range(6))
        created=request('/characters',{'account':account,'name':name,'species':'human','profession':'combat_marksman'})
        fixture_path.write_text(json.dumps({'account':account,'id':created['character']['id'],'name':name})+'\n')
    fixture=json.loads(fixture_path.read_text())
    query='?account='+fixture['account']+'&character_id='+fixture['id']
    first=request('/weapons'+query)
    second=request('/weapons'+query)
    assert first==second and first['backend']=='core3' and first['weapons']
    entry=request('/enter',{'account':fixture['account'],'character_id':fixture['id']})
    assert entry['weapon_snapshot']==first
    for weapon in first['weapons']:
        assert weapon['source_kind']=='core3_weapon_instance' and weapon['item_id'].isdigit()
        if weapon.get('kind') == 'melee':
            assert weapon['power']>0 and weapon['stance_recovery']>0
            assert 'rpm' not in weapon and 'capacity' not in weapon
        else:
            assert weapon['rpm']>0 and weapon['capacity']>0
    try: request('/weapons?account=unownedfixture&character_id='+fixture['id'])
    except urllib.error.HTTPError as error: assert error.code==400
    else: raise AssertionError('Cross-account weapon access accepted')
    # Learned recipes and original POIs are never destructive targets.
    for entry_id in ['schematic:123','reference:mos_eisley']:
        try: request('/datapad/delete',{'account':fixture['account'],'character_id':fixture['id'],'entry_id':entry_id})
        except urllib.error.HTTPError as error: assert error.code==400
        else: raise AssertionError('Static/server-driven entry deletion accepted')
    (ROOT/'runtime/evidence/crafting-live-snapshot.json').write_text(json.dumps(first,indent=2)+'\n')
    report={'passed':True,'character_id':fixture['id'],'weapon_count':len(first['weapons']),
            'fresh_login_and_entry':True,'ownership_rejection':True,'protected_entry_rejection':True,
            'live_crafting_performed':False,'factory_and_trade_tested':False}
    (ROOT/'runtime/evidence/weapon-crafting-core3.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()
