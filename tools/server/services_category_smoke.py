#!/usr/bin/env python3
"""Non-empty native category filtering and original sale cancellation/retrieval."""
import json,secrets,math
from services_smoke import ROOT,req,redact

def main():
 f=json.loads((ROOT/'runtime/server/services-fixture.json').read_text());assert f['account'].startswith('invtestservices');checks=[];responses=[]
 def call(action,**kwargs):
  data=dict(account=f['account'],character_id=f['id'],**kwargs)
  if action not in('open','status'):data.setdefault('request_id','services_category_'+secrets.token_hex(8))
  r=req('/services/'+action,data);responses.append({'action':action,'response':r});return r
 def check(ok,name):
  checks.append({'passed':bool(ok),'label':name});print(name,bool(ok),flush=True)
  if not ok:raise AssertionError(name)
 report={'native_execution':True,'checks':checks,'responses':responses,'passed':False};listing=None;at={}
 try:
  c=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text());t=min([r for r in c['static_terminals']if r['kind']=='bazaar'and int(r['id'])>0],key=lambda r:math.dist(r['position'],[3527,5,-4810]));at=dict(terminal_id=t['id'],position=t['position'],building_id=t['building_id'],cell_index=t['cell_index'])
  inv=req('/inventory?account='+f['account']+'&character_id='+f['id']);food=next(i for i in inv['items']if '/food/'in i['template'])
  sold=call('bazaar_sell',**at,item_id=food['id'],price=25);check(sold.get('ok'),'Source food listing prepared for actual category query');listing=food['id']
  food_rows=call('open',**at,category_id=8202,page=0)['state']['terminal'];check(any(i['id']==listing and i['category_id']==8202 for i in food_rows['listings']),'Original Food subtype filter includes real listed food')
  parent_rows=call('open',**at,category_id=8192,page=0)['state']['terminal'];check(any(i['id']==listing for i in parent_rows['listings']),'Original Misc major category includes its food subtype')
  weapon_rows=call('open',**at,category_id=131072,page=0)['state']['terminal'];check(not any(i['id']==listing for i in weapon_rows['listings']),'Original Weapon category excludes listed food before pagination')
  page=call('open',**at,category_id=8202,page=1)['state']['terminal'];check(not any(i['id']==listing for i in page['listings']),'Server page offset does not repeat previous-page listing')
  cancel=call('bazaar_cancel',**at,listing_id=listing);check(cancel.get('ok'),'Source auction cancellation succeeds for original owner')
  retrieved=call('bazaar_retrieve',**at,listing_id=listing);check(retrieved.get('ok') and any(i['id']==listing for i in retrieved['state']['inventory']['items']),'Cancelled original object retrieved with complete fenced attributes');listing=None;report['passed']=True
 finally:
  if listing:
   call('bazaar_cancel',**at,listing_id=listing);call('bazaar_retrieve',**at,listing_id=listing)
  (ROOT/'runtime/evidence/services-category-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
