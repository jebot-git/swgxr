#!/usr/bin/env python3
"""Traverse all original squadron dialogues through mastery with simulated objective success.
No ship physics, combat damage, earned XP or live headset validation is claimed.
"""
import sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_runtime import PilotRuntimeTests
tracks={
'tatooineImperial':['tatooine_imperial_trainer_1','tatooine_imperial_trainer_2','tatooine_imperial_trainer_2b','nym_technician_1','nym_technician_2','nym_technician_3','tatooine_imperial_tier3','tatooine_imperial_tier4','imperial_master_trainer'],
'nabooImperial':['naboo_imperial_trainer_1','naboo_imperial_trainer_2','naboo_imperial_tier3','naboo_imperial_tier3_barlow','naboo_imperial_tier4','imperial_master_trainer'],
'corelliaImperial':['corellia_imperial_trainer_1','corellia_imperial_trainer_2','corellia_imperial_tier3','corellia_imperial_tier4','imperial_master_trainer'],
'corelliaPrivateer':['corellia_privateer_trainer','corellia_privateer_trainer_2','corellia_privateer_tier3','corellia_privateer_tier4'],
'nabooPrivateer':['naboo_privateer_trainer_1','naboo_privateer_trainer_2','naboo_privateer_tier3','naboo_privateer_tier4'],
'tatooinePrivateer':['tatooine_privateer_trainer_1','tatooine_privateer_trainer_2','tatooine_privateer_trainer_shamdon','tatooine_privateer_tier3','tatooine_privateer_tier4'],
'corelliaRebel':['corellia_rebel_trainer_1','lok_rebel_trainer_2','lok_rebel_trainer_2_smuggler','corellia_rebel_tier3','corellia_rebel_tier4','rebel_master_trainer'],
'nabooRebel':['naboo_rebel_trainer_1','naboo_rebel_tier1_kiizete','dantooine_rebel_trainer_2','naboo_rebel_tier3','naboo_rebel_tier4','rebel_master_trainer'],
'tatooineRebel':['tatooine_rebel_trainer_1','yavin_rebel_trainer_2','tatooine_rebel_tier3','tatooine_rebel_tier4','rebel_master_trainer']}
failures=[];summary=[]
for track,names in tracks.items():
 if 'Privateer' in track:names=names+['imperial_master_trainer','rebel_master_trainer']
 t=PilotRuntimeTests();t.setUp();g=t.g
 p=g.newPlayer(g.FACTIONIMPERIAL if 'Imperial' in track else g.FACTIONREBEL if 'Rebel' in track else 0)
 if 'Privateer' in track:
  p.skills['pilot_neutral_novice']=True;p.ship=True
  g.PilotSource.api['space_flags.setSpaceTrack'](None,p,track)
 p.xp=10000000;p.capacity=500;p.standing['imperial']=10000;p.standing['rebel']=10000
 def score(p):return len(list(p.skills))*100000+len(list(p.won))*1000+sum(int(v) if str(v).isdigit() else 1 for k,v in p.store.items() if 'conversation.' not in k and not k.startswith('pilot_source:script.') and v!='')+int(p.ship)+len(set(v.template for v in p["items"].values()))*2
 history=[];progress_seen=set()
 def fingerprint(p):return (tuple(sorted(p.skills.keys())),tuple(sorted(p.won.keys())),tuple(sorted((k,v) for k,v in p.store.items() if 'conversation.' not in k and not k.startswith('pilot_source:script.') and v!='')),tuple(sorted(set(v.template for v in p['items'].values()))),p.ship)
 def finish(p,key,seen):
  if key in seen:return
  seen.add(key);q=g.PilotQuests.definitions[key]
  if q is None:raise Exception('Undefined quest '+key)
  p.active[key]=None;p.won[key]=True
  child=q.sourceTrigger.target
  if child and q.sourceTrigger.condition!='failure':finish(p,child,seen)
 for iteration in range(150):
  progress_seen.add(fingerprint(p));best=(score(p),None,None,None);errs=[]
  for name in names:
   queue=[(g.clone(p),None,[])];visited=set()
   while queue and len(visited)<150:
    candidate,response,path=queue.pop(0)
    try:
     if name in ('tatooine_imperial_trainer_2','tatooine_imperial_trainer_2b') and g.PilotSource.transferForm(candidate):g.PilotSource.signTransfer(candidate)
     view=g.step(name,candidate,response)
    except Exception as e:errs.append((name,str(e)));continue
    # Simulate genuine success of all objectives; no XP/kill/flight claim.
    if any('_duty:' in k for k in candidate.active.keys()):continue
    for key in list(candidate.active.keys()):finish(candidate,key,set())
    rank=score(candidate)
    if rank>best[0] or (rank==best[0] and best[1] is None and fingerprint(candidate) not in progress_seen):best=(rank,candidate,name,path)
    state=(view.message,tuple(sorted(candidate.store.items())),tuple(sorted(candidate.skills.keys())),tuple(sorted(candidate.won.keys())),candidate.ship)
    if state in visited:continue
    visited.add(state)
    for i,choice in sorted(view.responses.items()):queue.append((g.clone(candidate),choice.split(':')[-1],path+[choice]))
  if best[1] is None:
   print(track,'STALLED',iteration,'skills',sorted(p.skills.keys()),'won',len(list(p.won)),'errors',errs[:5],flush=True);failures.append(track);break
  p=best[1];history.append({'trainer':best[2],'path':best[3],'skills':list(p.skills),'won':list(p.won),'store':dict(p.store)})
  if any(k.endswith('_master') for k in p.skills):print(track,'MASTER',iteration,len(list(p.won)),flush=True);break
 (ROOT/'runtime/evidence').mkdir(parents=True,exist_ok=True)
 (ROOT/('runtime/evidence/pilot-progress-'+track+'.json')).write_text(json.dumps(history,indent=2)+'\n')
 master=any(k.endswith('_master') for k in p.skills)
 if not master and track not in failures:failures.append(track)
 summary.append({'track':track,'master':master,'missions':len(list(p.won)),'skills':len(list(p.skills))})
(ROOT/'runtime/evidence/pilot-progression.json').write_text(json.dumps({'passed':not failures,'simulated_objective_success':True,'native_flight':False,'tracks':summary},indent=2)+'\n')
if failures:raise SystemExit('Progression incomplete: '+', '.join(failures))
