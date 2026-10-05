#!/usr/bin/env python3
"""Mutating live Core3 fixture test. Never uses local target/HP/reward substitutes.

Only the explicitly provisioned ranged-test-fixture character is accepted. Run
with exclusive ownership of its live session after native build/readiness proof.
"""
from __future__ import annotations
import argparse,json,math,time,urllib.request,urllib.error,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class Test:
 def __init__(self,fixture,url):
  self.fixture=fixture;self.url=url;self.session='';self.seq=-1;self.last={};self.checks=[];self.responses=[];self.serial=0;self.next_fire=0
 def check(self,ok,description):
  self.checks.append({'passed':bool(ok),'description':description})
  if not ok:raise AssertionError(description)
 def request(self,action,fields=None):
  payload={'account':self.fixture['account'],'character_id':str(self.fixture['id'])}
  if self.session:payload['session_id']=self.session
  payload.update(fields or {})
  req=urllib.request.Request(self.url+'/combat/session/'+action,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'},method='POST')
  with urllib.request.urlopen(req,timeout=45) as response:data=json.load(response)
  if action=='start':self.session=data.get('session_id','')
  if action!='stop':
   self.check(data.get('source_kind')=='core3_live_combat' and data.get('session_live') and data.get('session_id')==self.session,'Native live session envelope: '+action)
   self.check(int(data['sequence'])>self.seq,'Monotonic server sequence: '+action);self.seq=int(data['sequence']);self.last=data
  self.responses.append({'action':action,'sequence':data.get('sequence'),'mutation':data.get('mutation'),'actors':len(data.get('snapshot',{}).get('actors',[])),'player':data.get('snapshot',{}).get('player',{})})
  return data
 def poll(self):
  payload={'account':self.fixture['account'],'character_id':str(self.fixture['id']),'session_id':self.session}
  req=urllib.request.Request(self.url+'/combat/session?'+urllib.parse.urlencode(payload))
  with urllib.request.urlopen(req,timeout=45) as response:data=json.load(response)
  self.check(data.get('session_live') and data.get('session_id')==self.session and int(data['sequence'])>self.seq,'Fresh native poll stays connected')
  self.seq=int(data['sequence']);self.last=data;return data
 def shot(self,target,*,hit=None,target_id=None,origin=None,direction=None):
  weapon=self.last['snapshot']['weapon'];player=self.last['snapshot']['player']
  delay=self.next_fire-time.monotonic()
  if delay>0:time.sleep(delay)
  self.serial+=1;shot_id='core3-smoke-'+str(self.serial)
  origin=origin or [player['position'][0],player['position'][1]+1.0,player['position'][2]]
  hit=hit or [target['position'][0],target['position'][1]+0.3,target['position'][2]]
  delta=[hit[i]-origin[i] for i in range(3)];distance=math.sqrt(sum(x*x for x in delta));direction=direction or [x/max(distance,.001) for x in delta]
  launched=time.monotonic();reply=self.request('fire',{'shot_id':shot_id,'item_id':weapon['item_id'],'origin':origin,'direction':direction})
  self.check(reply.get('mutation',{}).get('success'),'Native launch accepted')
  self.next_fire=launched+float(weapon['fire_interval_seconds'])+.08
  time.sleep(min(distance/float(weapon['projectile_speed'])+.04,1))
  impact=self.request('impact',{'shot_id':shot_id,'target_id':str(target_id or target['id']),'hit_position':hit,'projectile_age_seconds':time.monotonic()-launched})
  return reply,impact
 def actor(self,identity):return next((a for a in self.last['snapshot']['actors'] if a['id']==identity),None)
 def readiness(self):
  initial=self.request('start',{'position':self.fixture['position'],'heading_radians':0,'spawn_test_lair':True})['snapshot']
  player=initial['player'];weapon=initial['weapon']
  self.check(initial.get('ready') is False and player.get('on_load_screen') is True,'Native initial session uses original load-screen protection')
  self.check(player.get('invulnerable') is False,'Readiness does not grant native invulnerability')
  self.check(player['ham']==player['max_ham'] and player.get('posture')==0,'Controlled test character begins healthy and upright')
  lair_id=initial.get('test_lair_id','');deadline=time.monotonic()+20
  while not any(a.get('lair_id')==lair_id and a.get('kind')=='creature' and not a.get('dead') for a in self.last['snapshot']['actors']) and time.monotonic()<deadline:
   time.sleep(.5);self.poll()
  self.check(bool(lair_id) and any(a.get('lair_id')==lair_id and a.get('kind')=='creature' and not a.get('dead') for a in self.last['snapshot']['actors']),'Actual native passive lair children spawn at controlled site')
  before=player['ham'].copy();origin=player['position'].copy();origin[1]+=1
  denied=self.request('fire',{'shot_id':'readiness-denied-shot','item_id':weapon['item_id'],'origin':origin,'direction':[1,0,0]})
  self.check(denied.get('error_code')=='session_not_ready' and not denied.get('mutation',{}).get('success'),'Native rejects shot before client readiness')
  self.check(denied['snapshot']['player']['ham']==before,'Rejected loading-time shot charges no native HAM')
  position=denied['snapshot']['player']['position']
  ready=self.request('update',{'position':position,'heading_radians':0,'ready':True})['snapshot']
  self.check(ready.get('ready') is True and ready['player'].get('on_load_screen') is False,'Scene-ready transition removes original load-screen protection')
  again=self.request('update',{'position':position,'heading_radians':0,'ready':False})['snapshot']
  self.check(again.get('ready') is True and again['player'].get('on_load_screen') is False and again['player'].get('invulnerable') is False,'Focus loss cannot re-enable protection or invulnerability')
  return {'readiness_only':True,'player_final':again['player']}
 def run(self,max_shots):
  started=self.request('start',{'position':self.fixture['position'],'heading_radians':0,'spawn_test_lair':True})
  snap=started['snapshot'];lair_id=snap.get('test_lair_id','')
  self.check(lair_id and any(a['id']==lair_id and a['kind']=='lair' for a in snap['actors']),'Actual native lair object created')
  self.check(snap['weapon']['certified'] and snap['weapon']['item_id']==str(self.fixture['weapon_item_id']),'Equipped FWG5 is certified and exact owned instance')
  deadline=time.monotonic()+20;target=None
  while time.monotonic()<deadline:
   candidates=[a for a in self.last['snapshot']['actors'] if a['kind']=='creature' and a.get('lair_id')==lair_id and not a['dead']]
   if candidates:target=min(candidates,key=lambda a:math.dist(a['position'],self.last['snapshot']['player']['position']));break
   time.sleep(.5);self.poll()
  self.check(target is not None and target.get('passive',False),'Real passive lair child spawned through native AI')
  target_id=target['id'];initial_xp=self.last['snapshot']['player'].get('experience',{}).copy()
  # Actual mob ground height supplies a nearby supported outdoors start; no fake actor.
  p=target['position'];self.request('update',{'position':[p[0]-12,p[1],p[2]],'heading_radians':0,'ready':True})
  before=self.actor(target_id)['health'];time.sleep(1.1);self.poll()
  self.check(self.actor(target_id)['health']==before,'No damage occurs before any shot')
  target=self.actor(target_id);weapon=self.last['snapshot']['weapon'];origin=self.last['snapshot']['player']['position'].copy();origin[1]+=1
  self.serial+=1;sid='core3-smoke-'+str(self.serial);aim=[target['position'][i]-origin[i] for i in range(3)];length=math.sqrt(sum(x*x for x in aim));aim=[x/length for x in aim]
  launched=time.monotonic();first=self.request('fire',{'shot_id':sid,'item_id':weapon['item_id'],'origin':origin,'direction':aim});self.next_fire=launched+weapon['fire_interval_seconds']+.08
  self.check(first.get('mutation',{}).get('ham_cost_committed') is True,'Native launch commits source HAM cost')
  self.serial+=1;denied=self.request('fire',{'shot_id':'core3-smoke-'+str(self.serial),'item_id':weapon['item_id'],'origin':origin,'direction':aim})
  self.check(denied.get('error_code')=='cadence' and not denied['mutation']['success'],'Native cadence prevents a second launch')
  # Unknown target consumes the registered shot without fabricated damage.
  bad=self.request('impact',{'shot_id':sid,'target_id':'1','hit_position':target['position'],'projectile_age_seconds':max(.3,time.monotonic()-launched)})
  self.check(not bad['mutation']['success'],'Stale native entity ID cannot receive damage')
  replay=self.request('impact',{'shot_id':sid,'target_id':target_id,'hit_position':target['position'],'projectile_age_seconds':.5})
  self.check(replay.get('error_code')=='unknown_or_spent_shot','Consumed shot cannot be replayed at a different native target')
  target=self.actor(target_id);far=[target['position'][0]+200,target['position'][1],target['position'][2]]
  _,rejected=self.shot(target,hit=far)
  self.check(rejected.get('error_code')=='projectile_range_or_time','Server rejects fabricated over-range projectile contact')
  native_lair=self.actor(lair_id)
  _,lair_hit=self.shot(native_lair,hit=native_lair['position'])
  self.check(lair_hit.get('mutation',{}).get('native_result') is not None,'Native attack command also resolves the real lair object')
  lair_damage=max(0,int(lair_hit.get('mutation',{}).get('damage',0)))
  confirmed_damage=0;observed_ai=False;retaliation=False;quiet_observed=False;initial_pos=target['position'];death=False
  for _ in range(max_shots):
   self.poll();target=self.actor(target_id)
   if target is None or target['dead']:death=bool(target and target['dead']);break
   if self.last['snapshot']['player'].get('dead') or self.last['snapshot']['player'].get('incapacitated'):break
   _,impact=self.shot(target)
   mutation=impact.get('mutation',{});before=mutation.get('before',{});after=mutation.get('after',{})
   confirmed_damage+=sum(max(0,int(a)-int(b)) for a,b in zip(before.get('ham',[]),after.get('ham',[])))
   current=self.actor(target_id)
   if current:observed_ai=observed_ai or math.dist(current['position'],initial_pos)>.05 or current.get('in_combat',False);death=current['dead']
   if confirmed_damage>0 and not death and not quiet_observed:
    quiet_observed=True;quiet_ham=self.last['snapshot']['player']['ham'].copy();quiet_target=current['ham'].copy()
    print(json.dumps({'phase':'native_retaliation_no_fire_window','seconds':10,'target_id':target_id}),flush=True)
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
     time.sleep(.5);self.poll();observed=self.actor(target_id);vitals=self.last['snapshot']['player']
     self.check(observed is not None and not observed['dead'] and all(a>=b for a,b in zip(observed['ham'],quiet_target)),'Living damaged target takes no further damage without a new shot')
     self.check(str(vitals.get('target_id'))=='0','No queued native player autoattack target during quiet window')
     retaliation=retaliation or any(a<b for a,b in zip(vitals['ham'],quiet_ham));quiet_ham=vitals['ham'].copy();quiet_target=observed['ham'].copy()
     if vitals.get('dead') or vitals.get('incapacitated'):break
   if death:break
  self.check(confirmed_damage>0,'Source native attack reduced real target HP')
  self.check(observed_ai,'Native creature AI moved or entered combat after attack')
  self.check(death,'Native creature reached authoritative dead posture')
  experience=self.last['snapshot']['player'].get('experience',{})
  self.check(any(float(experience.get(k,0))>float(v) for k,v in initial_xp.items()) or any(float(v)>0 and k not in initial_xp for k,v in experience.items()),'Native kill grants actual source XP')
  health={a['id']:a['health'] for a in self.last['snapshot']['actors'] if not a['dead']}
  time.sleep(min(weapon['fire_interval_seconds']+1,6));self.poll()
  self.check(all(a['health']==health[a['id']] for a in self.last['snapshot']['actors'] if a['id'] in health),'No queued player autofire damages remaining native actors')
  return {'target_id':target_id,'lair_id':lair_id,'confirmed_ham_damage':confirmed_damage,'lair_condition_damage':lair_damage,'los_runtime_tested':False,'los_policy':'Native CombatQueueCommand.doCombatAction invokes CollisionManager.checkLineOfSight; no reliable authored blocker at this outdoor fixture.','native_ai_observed':observed_ai,'no_autofire_live_target_tested':quiet_observed,'native_retaliation_net_ham_loss_in_no_fire_window':retaliation,'experience_before':initial_xp,'experience_after':experience,'player_final':self.last['snapshot']['player']}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--fixture',type=Path,default=ROOT/'runtime/server/ranged-test-fixture.json');parser.add_argument('--url',default='http://127.0.0.1:18080');parser.add_argument('--out',type=Path,default=ROOT/'runtime/evidence/live-combat-core3.json');parser.add_argument('--max-shots',type=int,default=32);parser.add_argument('--readiness-only',action='store_true');args=parser.parse_args()
 fixture=json.loads(args.fixture.read_text());assert fixture['account'].startswith('rangetest'),'Only authorized disposable ranged fixture may be mutated'
 test=Test(fixture,args.url);report={'server_mocked':False,'gpu_tested':False,'headset_tested':False,'fixture_character_id':fixture['id']}
 try:report.update(test.readiness() if args.readiness_only else test.run(args.max_shots));report['passed']=True
 except Exception as exc:report.update(passed=False,error=str(exc))
 finally:
  if test.session:
   try:test.request('stop')
   except Exception as exc:report['stop_error']=str(exc)
  report['checks']=test.checks;report['requests']=test.responses;args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ('requests','checks')}))
 return 0 if report.get('passed') else 1
if __name__=='__main__':raise SystemExit(main())
