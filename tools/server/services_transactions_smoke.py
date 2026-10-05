#!/usr/bin/env python3
"""Native bazaar/travel/payment fixtures. Hand tracking is synthetic; money is not."""
import json,sys,secrets,time,threading,math
from pathlib import Path
from services_smoke import ROOT,req,redact

def main():
 f=json.loads((ROOT/'runtime/server/services-fixture.json').read_text());path=ROOT/'runtime/server/services-recipient-fixture.json'
 if path.exists():g=json.loads(path.read_text())
 else:
  g={'account':'invtestservices'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))};r=req('/characters',dict(g,species='human',profession='crafting_artisan'));assert 'character'in r,r;g['id']=r['character']['id'];path.write_text(json.dumps(g))
 checks=[];responses=[];running=True
 def check(ok,name):
  checks.append({'passed':bool(ok),'label':name});print(name,bool(ok),flush=True)
  if not ok:raise AssertionError(name)
 def service(owner,action,**kw):
  data=dict(account=owner['account'],character_id=owner['id'],**kw)
  if action not in ('status','open'):data.setdefault('request_id','services_'+secrets.token_hex(10))
  r=req('/services/'+action,data);responses.append({'account':owner['account'],'action':action,'request':data,'response':r});return r
 report={'native_execution':True,'headset_tracking':'synthetic hand inputs only; no live VR test','fixtures':[f,g],'checks':checks,'responses':responses,'passed':False}
 try:
  catalog=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text());bazaar=min([t for t in catalog['static_terminals'] if t['kind']=='bazaar' and int(t['id'])>0],key=lambda t:math.dist(t['position'],[3527,5,-4810]))
  at=dict(terminal_id=bazaar['id'],position=bazaar['position'],building_id=bazaar['building_id'],cell_index=bazaar['cell_index'])
  inventory=req('/inventory?account='+g['account']+'&character_id='+g['id']);food=next(i for i in inventory['items'] if '/food/'in i['template'])
  sell=service(g,'bazaar_sell',**at,item_id=food['id'],price=35,description='Isolated services fixture sale',auction=False)
  check(sell.get('ok') and sell['mutation'].get('listing_id')==food['id'],'Original auction manager creates sale and charges source listing fee')
  browse=service(f,'open',**at,category_id=0,page=0)
  check(any(i['id']==food['id']for i in browse['state']['terminal']['listings']),'Galactic native listing visible to another owned character')
  before=browse['state']['wallet'];key='services_buy_'+secrets.token_hex(8)
  buy=service(f,'bazaar_buy',**at,listing_id=food['id'],price=35,request_id=key)
  check(buy.get('ok') and buy['state']['wallet']['bank']==before['bank']-35,'Native instant purchase debits original bank price')
  replay=service(f,'bazaar_buy',**at,listing_id=food['id'],price=35,request_id=key)
  check(replay.get('ok') and replay['state']['wallet']==buy['state']['wallet'] and replay['mutation'].get('replayed'),'Duplicate native purchase receipt does not charge again')
  retrieve=service(f,'bazaar_retrieve',**at,listing_id=food['id'])
  check(retrieve.get('ok'),'Original auction retrieval transfers item at the source bazaar')
  inventory=req('/inventory?account='+f['account']+'&character_id='+f['id']);check(any(i['id']==food['id']for i in inventory['items']),'Purchased original object survives separate authenticated inventory read')
  # Both authenticated actors' original world positions anchor synthetic fresh hand poses.
  point=[3511,5,-4927];s1=service(f,'status',position=point,building_id='0',cell_index=0);s2=service(g,'status',position=[3511.5,5,-4927],building_id='0',cell_index=0)
  tokens={f['id']:s1['presence']['token'],g['id']:s2['presence']['token']};states={f['id']:s1,g['id']:s2};hand=[3511.3,6,-4927];seen=[]
  def poses():
   seq=0
   while running:
    for owner in [f,g]:
     payload={'account':owner['account'],'character_id':owner['id'],'token':tokens[owner['id']],'sequence':seq,'position':states[owner['id']]['state']['player']['position'],'hand':{'position':hand,'grip':True,'tracked':True},'wallet_held':owner is f}
     seen.append(req('/services/presence',payload))
    seq+=1;time.sleep(.08)
  worker=threading.Thread(target=poses,daemon=True);worker.start();time.sleep(.65)
  started=time.monotonic();payment=service(f,'pay',target_id=g['id'],amount=7,position=point,building_id='0',cell_index=0);report['payment_seconds']=time.monotonic()-started;running=False;worker.join(2)
  check(payment.get('ok'), 'Authenticated mutual hand contact invokes original native player tip')
  recipient=service(g,'status');check(payment['state']['wallet']['cash']==s1['state']['wallet']['cash']-7 and recipient['state']['wallet']['cash']==s2['state']['wallet']['cash']+7,'Native cash payment conserved and persisted across recipient temporary-session logout')
  # Native source ticket terminal; source purchase selects allowed route/fare.
  status=service(f,'status',position=[3599,5,-4780],building_id='0',cell_index=0);travel=next(t for t in status['state']['terminals'] if t['kind']=='travel');at=dict(terminal_id=travel['id'],position=travel['position'],building_id=travel['building_id'],cell_index=travel['cell_index'])
  opened=service(f,'open',**at);check(any(d['available']for d in opened['state']['terminal']['destinations']),'Original scheduled shuttles become available after Core3 boot delay')
  before=opened['state']['wallet'];key='services_ticket_'+secrets.token_hex(8);purchase=service(f,'travel_purchase',**at,destination_id='Bestine Starport',request_id=key)
  check(purchase.get('ok') and len(purchase['state']['tickets'])>len(opened['state']['tickets']),'Original ticket purchase creates owned ticket')
  ticket=next(t for t in purchase['state']['tickets']if t['arrival']=='Bestine Starport');check(purchase['state']['wallet']['bank']==before['bank']-100,'Original travel fare charged')
  replay=service(f,'travel_purchase',**at,destination_id='Bestine Starport',request_id=key);check(replay.get('ok') and replay['state']['wallet']==purchase['state']['wallet'],'Ticket purchase idempotency preserved')
  shuttle=purchase['state']['shuttles'][0];position=shuttle['position']
  far=service(f,'travel_board',ticket_id=ticket['id'],position=[position[0]+40,position[1],position[2]],building_id='0',cell_index=0);check(far.get('http_error')==400,'Original shuttle boarding rejects outside25m')
  deadline=time.monotonic()+230
  while time.monotonic()<deadline:
   s=service(f,'status',position=position,building_id='0',cell_index=0);shuttle=s['state']['shuttles'][0]
   if shuttle['doors_open']:break
   time.sleep(2)
  check(shuttle['doors_open'],'Native schedule opens boarding doors')
  boarded=service(f,'travel_board',ticket_id=ticket['id'],position=position,building_id='0',cell_index=0)
  check(boarded.get('ok') and boarded.get('transport',{}).get('destination',{}).get('zone')=='tatooine','Native boarding supplies actual source destination')
  check(not any(t['id']==ticket['id']for t in boarded['state']['tickets']),'Native successful boarding consumes exactly owned ticket')
  check(math.dist(boarded['transport']['destination']['position'],[-1361.1917,12,-3600.0254])<12,'Native arrival is original Bestine Starport landing region')
  report['passed']=True
 finally:
  running=False;(ROOT/'runtime/evidence/services-transactions-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
