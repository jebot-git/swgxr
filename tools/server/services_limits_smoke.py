#!/usr/bin/env python3
"""Native category/capacity/closed-shuttle safeguards on one strict disposable fixture."""
import json,secrets,time,math
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 f=json.loads((ROOT/'runtime/server/services-fixture.json').read_text());assert f['id']=='281474993795347' and f['account']=='invtestservices235692'
 checks=[];responses=[]
 def check(ok,name):
  checks.append({'passed':bool(ok),'label':name});print(name,bool(ok),flush=True)
  if not ok:raise AssertionError(name)
 def service(action,**kw):
  p=dict(account=f['account'],character_id=f['id'],**kw)
  if action not in('status','open'):p.setdefault('request_id','services_limit_'+secrets.token_hex(8))
  r=req('/services/'+action,p);responses.append({'action':action,'response':r});return r
 code='''\n-- BEGIN SWGXR SERVICES CAPACITY FIXTURE ONLY
function Tests:swgxrServicesCapacity(phase)
 local player=getSceneObject(281474993795347) if player==nil then return end
 local inv=SceneObject(player):getSlottedObject("inventory") if inv==nil then return end
 if phase=="fill" then
  for i=1,80 do if SceneObject(inv):getContainerObjectsSize()>=80 then break end; giveItem(inv,"object/tangible/food/foraged/foraged_fruit_s3.iff",-1) end
 elseif phase=="clear" then
  for i=SceneObject(inv):getContainerObjectsSize()-1,0,-1 do local o=SceneObject(inv):getContainerObject(i)
   if SceneObject(o):getTemplateObjectPath()=="object/tangible/food/foraged/foraged_fruit_s3.iff" then SceneObject(o):destroyObjectFromWorld();SceneObject(o):destroyObjectFromDatabase() end
  end
 end
end
-- END SWGXR SERVICES CAPACITY FIXTURE ONLY
'''
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';added=False
 report={'native_execution':True,'fixture_capacity_setup':'Strict isolated account fill then exact filler-template cleanup only; no normal player modifications','checks':checks,'responses':responses,'passed':False}
 try:
  catalog=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text());b=min([t for t in catalog['static_terminals'] if t['kind']=='bazaar' and int(t['id'])>0],key=lambda t:math.dist(t['position'],[3527,5,-4810]));at=dict(terminal_id=b['id'],position=b['position'],building_id=b['building_id'],cell_index=b['cell_index'])
  opened=service('open',**at,category_id=131072,page=0);term=opened['state']['terminal'];check(term.get('category_id')==131072 and term.get('page')==0 and len(term.get('categories',[]))>10,'Original GOT category tree and native category/page query exposed')
  check(all((i['category_id'] & 131072)!=0 for i in term['listings']),'Category-filtered native listings contain only matching object types')
  check(service('open',**at,category_id=True).get('http_error')==400,'Noninteger source category rejected')
  s=service('status',position=[3599,5,-4780],building_id='0',cell_index=0);check(len(s['state']['shuttles'])==1,'Configured5s startup association yields actual native shuttle')
  shuttle=s['state']['shuttles'][0];check(bool(shuttle.get('collector_position')) and shuttle['landing_duration_seconds']>0,'Original collector and authoritative animation phase timing present')
  t=next(t for t in s['state']['terminals']if t['kind']=='travel');travel=dict(terminal_id=t['id'],position=t['position'],building_id=t['building_id'],cell_index=t['cell_index'])
  purchase=service('travel_purchase',**travel,destination_id='Bestine Starport',round_trip=True);check(purchase.get('ok'),'Original round-trip creates outbound and return tickets')
  outbound=next(i for i in purchase['state']['tickets']if i['arrival']=='Bestine Starport');wrong=next(i for i in purchase['state']['tickets']if i['departure']=='Bestine Starport')
  p=shuttle['position'];bad=service('travel_board',ticket_id=wrong['id'],position=p,building_id='0',cell_index=0);check(bad.get('error')=='ticket_departure_mismatch','Stale selected ticket cannot silently consume different single eligible ticket')
  inv=req('/inventory?account='+f['account']+'&character_id='+f['id']);check(not any(i['template'].endswith('/foraged_fruit_s3.iff')for i in inv['items']),'Capacity fixture does not overlap existing items')
  script.write_text(script.read_text()+code);added=True;console('reloadscreenplays');console('runLuaFunction Tests:swgxrServicesCapacity:fill');time.sleep(.3)
  before=service('open',**travel);failed=service('travel_purchase',**travel,destination_id='Bestine Starport');check(failed.get('http_error')==400,'Original ticket purchase rejects full inventory before charging')
  after=service('status');check(after['state']['wallet']==before['state']['wallet'] and len(after['state']['tickets'])==len(before['state']['tickets']),'Rejected full-bag ticket purchase preserves money and ticket count')
  console('runLuaFunction Tests:swgxrServicesCapacity:clear');time.sleep(.3)
  deadline=time.monotonic()+210
  while time.monotonic()<deadline:
   s=service('status',position=p,building_id='0',cell_index=0);shuttle=s['state']['shuttles'][0]
   if not shuttle['doors_open']:break
   time.sleep(2)
  check(not shuttle['doors_open'],'Observed actual native shuttle closed/away phase')
  denied=service('travel_board',ticket_id=outbound['id'],position=p,building_id='0',cell_index=0);check(denied.get('http_error')==400,'Native schedule rejects boarding through closed doors')
  s=service('status');check(any(i['id']==outbound['id']for i in s['state']['tickets']),'Closed-door rejection preserves original ticket')
  report['passed']=True
 finally:
  if added:
   console('runLuaFunction Tests:swgxrServicesCapacity:clear');script.write_text(script.read_text().replace(code,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/services-limits-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}))
if __name__=='__main__':main()
