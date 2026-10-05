#!/usr/bin/env python3
"""Real disposable Core3 equipment, consumption and self-treatment regression."""
import argparse,json,subprocess,sys,urllib.error
from pathlib import Path
from inventory_smoke import request
ROOT=Path(__file__).resolve().parents[2]

def console(command):
    subprocess.run(['podman','exec','swgxr-core3-build','bash','-lc','printf "%s\\n" "$1" >/workspace/runtime/server/core3-console','fixture',command],check=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--fixture',type=Path,required=True);a=parser.parse_args();f=json.loads(a.fixture.read_text())
    assert f['account'].startswith('invtest') and f['name'].startswith('Ivtest')
    base={'account':f['account'],'character_id':f['id']};query='/inventory?account='+f['account']+'&character_id='+f['id']
    before=request(query);report={'fixture':f,'operations':[]}
    def item(suffix,snapshot=before):return next(i for i in snapshot['items'] if i['template'].endswith(suffix))
    def mutate(verb,entry,**kwargs):
        r=request('/inventory/'+verb,dict(base,item_id=entry['id'],**kwargs));assert r['source_kind']=='core3_inventory_'+verb and r['mutation']['success'];report['operations'].append(r['mutation']);return r['inventory']
    def reject(verb,entry,**kwargs):
        try:request('/inventory/'+verb,dict(base,item_id=entry['id'],**kwargs))
        except urllib.error.HTTPError as e:
            assert e.code==400;return json.load(e)['error']
        raise AssertionError('Invalid operation accepted')
    shirt=item('shirt_s03.iff');s=mutate('equip',shirt,arrangement=0)
    assert next(i for i in s['equipment'] if i['id']==shirt['id'])['customization']=={'/private/index_color_1':12}
    body=item('bodysuit_s01.iff');s=mutate('equip',body,arrangement=0)
    assert len(report['operations'][-1]['displaced_item_ids'])>=2
    for identifier in report['operations'][-1]['displaced_item_ids']:assert next(i for i in s['items'] if i['id']==identifier)['container_id']==s['inventory']['id']
    s=mutate('equip',item('shirt_s04.iff'),arrangement=0)
    for worn in before['equipment']:
        if any(slot.startswith(('pants','chest2')) for slot in worn['equipped_slots']):s=mutate('equip',worn,arrangement=worn['arrangement'])
    s=mutate('equip',item('knife_survival.iff'),arrangement=0)
    report['wrong_arrangement_rejected']=reject('equip',shirt,arrangement=31)
    food=item('foraged_fruit_s1.iff');s=mutate('consume',food);assert food['id'] not in {i['id'] for i in s['items']}
    another=next(i for i in s['items'] if i['template'].endswith('foraged_fruit_s1.iff'))
    report['duplicate_food_effect_rejected']=reject('consume',another)
    medicine=item('stimpack_sm_s1.iff')
    console('runLuaFunction Tests:swgxrEquipmentFixture:'+f['id']+':damage')
    s=mutate('consume',medicine);m=report['operations'][-1]
    assert m['remaining_use_count']==m['previous_use_count']-1
    assert m['after_stats']['ham'][0]>m['before_stats']['ham'][0]
    report['medicine_cooldown_rejected']=reject('consume',medicine)
    report.update(passed=True,multi_slot_displacement=True,customization_preserved=True,source_food_effect=True,source_medicine_healing=True)
    (ROOT/'runtime/evidence/equipment-core3-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
    (ROOT/'runtime/evidence/equipment-fixture-snapshot.json').write_text(json.dumps(s,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
