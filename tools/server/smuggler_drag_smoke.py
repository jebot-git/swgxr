#!/usr/bin/env python3
"""Real two-account feigned-patient drag, using existing native medic poses/leases."""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console
from live_combat_smoke import Test

def tracking(p,crossed=False):
 return dict(tracked=True,crossed=crossed,grips=True,left=[p[0]-.12,p[1]+.3,p[2]],right=[p[0]+.12,p[1]+.3,p[2]])

def main():
 owners=[];sessions=[];checks=[];records=[];added=False
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';begin='\n-- BEGIN SWGXR SMUGGLER DRAG TEST\n';end='-- END SWGXR SMUGGLER DRAG TEST\n'
 report={'passed':False,'native_execution':True,'headset_tested':False,'checks':checks,'records':records,'fixtures':owners}
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def fixture(name):console('runLuaFunction Tests:'+name);time.sleep(.35)
 def medical(index,action,**kw):
  f=owners[index];q=dict(account=f['account'],character_id=f['id'],live_session_id=sessions[index].session,request_id='smuggler_drag_'+secrets.token_hex(8),**kw)
  out=req('/medic/'+action,q);records.append({'action':action,'index':index,'result':out});return out
 try:
  for i in range(2):
   f={'account':'invtestsmugdrag'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8))};created=req('/characters',dict(f,species='human',profession='science_medic' if i==0 else 'combat_marksman'));assert 'character'in created,created;f['id']=created['character']['id'];owners.append(f)
   for attempt in range(6):
    inv=req('/inventory?account='+f['account']+'&character_id='+f['id'])
    if 'items'in inv:break
    time.sleep(.5)
   assert 'items'in inv,inv
  doc,patient=owners;key='swgxrSmugglerDrag:'+patient['id']
  source=(ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/trainers/trainerData.lua').read_text();skills=re.findall(r'"([a-z0-9_]+)"',re.search(r'trainer_smuggler\s*=\s*\{([^}]+)',source).group(1));grants='\n'.join('awardSkill(p,"'+v+'")'for v in skills)
  code=f'''function Tests:swgxrSmugglerDragSetup()
 local d=getSceneObject({doc['id']}) local p=getSceneObject({patient['id']}) if d==nil or p==nil then return end
 awardSkill(d,"science_medic_novice") awardSkill(d,"science_medic_injury_speed_02") {grants}
 for i,o in ipairs({{d,p}}) do CreatureObject(o):clearCombatState(true);SceneObject(o):teleport(5000+(i-1),getTerrainHeight(o,5000+(i-1),-5400),-5400,0) end
end
function Tests:swgxrSmugglerDragHit()
 local p=getSceneObject({patient['id']}) if p==nil then return end
 local m=spawnMobile("tatooine","worrt",0,5004,getTerrainHeight(p,5004,-5400),-5400,0,0)
 if m~=nil then writeData("{key}",SceneObject(m):getObjectID());AiAgent(m):setDefender(p) end
end
function Tests:swgxrSmugglerDragCleanup()
 local m=getSceneObject(readData("{key}")) if m~=nil then SceneObject(m):destroyObjectFromWorld() end deleteData("{key}")
end
'''
  script.write_text(script.read_text()+begin+code+end);added=True;console('reloadscreenplays');time.sleep(.4);fixture('swgxrSmugglerDragSetup')
  for f in owners:
   state=req('/services/status',dict(account=f['account'],character_id=f['id']));f['position']=state['state']['player']['position'];t=Test(f,'http://127.0.0.1:18080');sessions.append(t);t.request('start',{'position':f['position']});t.request('update',{'position':f['position'],'ready':True})
  p=sessions[1].last['snapshot']['player']['position'];feign=sessions[1].request('update',{'position':p,'smuggler_pose':dict(tracked=True,feign=True,upright=False)})
  check(feign['snapshot']['player']['feigning_death'] and not feign['snapshot']['player']['incapacitated'],'Real Smuggler enters pending feign with healthy HAM')
  medical(1,'status',pose=tracking(p));start=medical(0,'drag',target_id=patient['id'],release=False,pose=tracking(p));check(start.get('mutation',{}).get('started'),'Medic can start original two-hand drag on pending feigned player')
  shifted=[p[0]+.15,p[1],p[2]];medical(1,'status',pose=tracking(p));moved=medical(0,'drag',target_id=patient['id'],release=False,pose=tracking(shifted));check(moved.get('mutation',{}).get('position',[0])[0]>p[0]+.1,'Feigned patient moves across native collision-checked ground')
  medical(0,'drag',target_id=patient['id'],release=True);fixture('swgxrSmugglerDragHit');deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   state=sessions[1].poll()['snapshot']['player']
   if state['posture']==13:break
   time.sleep(.4)
  check(state['posture']==13 and state['feigning_death'] and not state['incapacitated'],'Actual MOB extra blow completes native feigned posture')
  p=state['position'];medical(1,'status',pose=tracking(p));start=medical(0,'drag',target_id=patient['id'],release=False,pose=tracking(p));check(start.get('mutation',{}).get('started'),'Medic can drag active feigned-incap posture as well')
  visible=next(row for row in start['state']['players']if row['id']==patient['id']);check(visible.get('feigning_death'),'Medic native target list identifies feigned patient')
  medical(1,'status',pose=tracking(p,True));denied=medical(0,'drag',target_id=patient['id'],release=False,pose=tracking(p));check(denied.get('http_error')==400,'Existing crossed-arm consent cancels feigned-player drag')
  upright=sessions[1].request('update',{'position':p,'smuggler_pose':dict(tracked=True,feign=False,upright=True)});check(not upright['snapshot']['player']['feigning_death'],'Standing restores conscious patient state')
  medical(1,'status',pose=tracking(p));denied=medical(0,'drag',target_id=patient['id'],release=False,pose=tracking(p));check(denied.get('http_error')==400,'Medic cannot continue dragging player after upright release')
  report['passed']=True
 finally:
  for t in sessions:
   if t.session:
    try:t.request('update',{'position':t.last['snapshot']['player']['position'],'smuggler_pose':dict(tracked=True,feign=False,upright=True)});t.request('stop')
    except Exception:pass
  if added:
   fixture('swgxrSmugglerDragCleanup');s=script.read_text()
   if begin in s:script.write_text(s[:s.index(begin)]+s[s.index(end)+len(end):]);console('reloadscreenplays')
  (ROOT/'runtime/evidence/smuggler-native-drag.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}),flush=True)
if __name__=='__main__':main()
