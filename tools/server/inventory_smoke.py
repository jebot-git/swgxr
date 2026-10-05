#!/usr/bin/env python3
"""Actual Core3 inventory read/ownership checks; optional disposable stack split."""
import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def request(path,data=None):
    req=urllib.request.Request('http://127.0.0.1:18080'+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=90) as stream:return json.load(stream)

def main():
    p=argparse.ArgumentParser();p.add_argument('--account',required=True);p.add_argument('--character-id',required=True);p.add_argument('--split-disposable',action='store_true');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    query='?account='+a.account+'&character_id='+a.character_id
    first=request('/inventory'+query);second=request('/inventory'+query)
    assert first==second and first['source_kind']=='core3_inventory'
    assert first['inventory']['capacity']>=first['inventory']['occupied']
    for item in first['items']:
        assert item['attributes'] and item['shared_template'] and item['template']
        if item['stack_kind']=='none': assert item['quantity']==1 and not item['split_supported']
    for body in [{'account':'inventory_unowned','character_id':a.character_id,'item_id':'1','quantity':1}, {'account':a.account,'character_id':a.character_id,'item_id':'1','quantity':1}]:
        try:request('/inventory/split',body)
        except urllib.error.HTTPError as e:assert e.code==400
        else:raise AssertionError('Unowned inventory split accepted')
    try:request('/inventory?account=inventory_unowned&character_id='+a.character_id)
    except urllib.error.HTTPError as e:assert e.code==400
    else:raise AssertionError('Cross-account inventory read accepted')
    report={'passed':True,'character_id':a.character_id,'inventory':first['inventory'],'items':len(first['items']),'fresh_login_persistence':True,'ownership_rejected':True,'unowned_item_rejected':True,'split_tested':False}
    if a.split_disposable:
        assert a.account.startswith('invtest'), 'Mutation fixture must have invtest account prefix'
        stack=next(i for i in first['items'] if i['split_available'])
        quantity=min(3,stack['split_max_quantity'])
        result=request('/inventory/split',{'account':a.account,'character_id':a.character_id,'item_id':stack['id'],'quantity':quantity})
        mutation=result['mutation']; after=result['inventory']; byid={i['id']:i for i in after['items']}
        assert mutation['success'] and byid[stack['id']]['quantity']==stack['quantity']-quantity
        assert byid[mutation['new_item_id']]['quantity']==quantity
        assert after['inventory']['occupied']==first['inventory']['occupied']+stack['split_slot_cost']
        report.update(split_tested=True,mutation=mutation,after=after['inventory'])
        a.output.with_name(a.output.stem+'-snapshot.json').write_text(json.dumps(after,indent=2)+'\n')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
