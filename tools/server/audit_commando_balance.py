#!/usr/bin/env python3
"""Production-header arithmetic and explicit single-target loadout simulations.

This is an authored balance benchmark, not a live encounter or headset test.
No services, items or persistent characters are changed.
"""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'runtime/evidence/commando/balance.json'
DT=.01
BALANCE=json.loads((ROOT/'client/combat/balance.json').read_text())
PROGRESS={.1:{'speed':35,'grenade_speed':0,'head':4.,'pierce':False,'flurry':False,'surprise':False,'focus':False,'ultimate':False},.55:{'speed':65,'grenade_speed':20,'head':4.25,'pierce':True,'flurry':True,'surprise':False,'focus':True,'ultimate':False},1.:{'speed':95,'grenade_speed':40,'head':4.25,'pierce':True,'flurry':True,'surprise':True,'focus':True,'ultimate':True}}
def source_hash(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def compiled():
 with tempfile.TemporaryDirectory(prefix='swgxr-commando-audit-') as directory:
  binary=Path(directory)/'balance'
  subprocess.run(['c++','-std=c++17','-O2','-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(ROOT/'tests/commando_policy.cpp'),'-o',str(binary)],check=True)
  return json.loads(subprocess.check_output([str(binary),'json']))
def rifle(policy,progress,q,defender,duration,reload=True):
 state=PROGRESS[progress];mean=140+105*q;period=max(1,(1-state['speed']/100)*(10.5-4*q));ham=[1000.,1000.];total=0.;nextfire=0.;focusuntil=-1.;ready={k:0. for k in policy['rifle']};counts={};profile=dict(BALANCE['classes'][BALANCE['weapons']['rifle_t21']['class']],**BALANCE['weapons']['rifle_t21']);capacity=profile['capacity'];ammo=capacity;reload_seconds=profile['reload_seconds'];reloads=0
 for tick in range(round(duration/DT)):
  t=tick*DT;ham[0]=min(1000,ham[0]+10*DT);ham[1]=min(1000,ham[1]+8*DT)
  if t+1e-8<nextfire:continue
  selected='ordinary'
  order=['rifleman_focus','lethal_shot','flurry_shot','piercing_shot','surprise_shot','sniper_shot']
  available={'rifleman_focus':state['focus'],'lethal_shot':True,'flurry_shot':state['flurry'],'piercing_shot':state['pierce'],'surprise_shot':state['surprise'],'sniper_shot':state['ultimate']}
  for k in order:
   s=policy['rifle'][k]
   if available[k] and ready[k]<=t+1e-8 and ham[0]>s['action'] and ham[1]>s['mind'] and not(k=='sniper_shot' and t<focusuntil):selected=k;break
  blows=3 if selected=='flurry_shot' else 0 if selected=='rifleman_focus' else 1
  if reload and ammo<blows:nextfire=t+reload_seconds;ammo=capacity;reloads+=1;continue
  multiplier=1.;recovery=period
  if selected!='ordinary':
   s=policy['rifle'][selected];ham[0]-=s['action'];ham[1]-=s['mind'];ready[selected]=t+s['cooldown'];multiplier=s['damage']
   if selected=='lethal_shot':multiplier=state['head'];recovery=2*period
   elif selected=='flurry_shot':multiplier*=3;recovery=period+.5
   elif selected=='sniper_shot':recovery=max(2.5,period)
   elif selected=='rifleman_focus':focusuntil=t+8;recovery=.25;multiplier=0
  # Surprise's extra>=80%Health opening bonus is excluded from sustained output.
  scale=policy['rifle_mitigation'][defender+('_piercing' if selected=='piercing_shot' else '')]
  total+=mean*1.5*multiplier*scale*(1.2 if t<focusuntil and selected!='sniper_shot' else 1)
  nextfire=t+recovery;ammo-=blows;counts[selected]=counts.get(selected,0)+1
  if reload and ammo==0:nextfire=max(nextfire,t+reload_seconds);ammo=capacity;reloads+=1
 return {'damage':round(total,3),'dps':round(total/duration,6),'remaining_action':round(ham[0],3),'remaining_mind':round(ham[1],3),'attacks':counts,'reloads':reloads}
def heavy(policy,row,defender,duration,reload=True,priority=False):
 progress=row['progression'];q=row['source_quality'];family=row['family'];classes=BALANCE['classes'];cl=classes['commando_'+family]
 grenade=next(g for g in policy['grenade'] if g['speed']==PROGRESS[progress]['grenade_speed'] and g['quality']==q)
 ham=[1000.,1000.];total=0.;nextfire=0.;overuntil=-1.;nextover=0.;nextfocus=0.;nextgrenade=0.;counts={};ammo=cl['capacity'];reloads=0;nextburn=math.inf;burnuntil=-1.;budget=0;pulse=0;burn_total=0;shots=0
 for tick in range(round(duration/DT)):
  t=tick*DT;ham[0]=min(1000,ham[0]+10*DT);ham[1]=min(1000,ham[1]+8*DT)
  if t+1e-8>=nextburn and t<burnuntil and budget>0:
   dealt=min(budget,pulse);total+=dealt;burn_total+=dealt;budget-=dealt;nextburn+=3
  # Optimistic throw/regrip: no extra weapon downtime; native grenade cooldown,
  # two-second detonation and60Action/20Mind still constrain each blast.
  if t+1e-8>=nextgrenade and t+2<duration and ham[0]>60+(100 if priority else 0) and ham[1]>20:
   total+=grenade['packet']*grenade['mitigation'][defender];ham[0]-=60;ham[1]-=20;nextgrenade=t+grenade['cooldown'];counts['grenade']=counts.get('grenade',0)+1
  if t+1e-8<nextfire:continue
  if progress==1 and t+1e-8>=nextover and ham[0]>80 and ham[1]>40:
   ham[0]-=80;ham[1]-=40;nextover=t+120;overuntil=t+6;nextfire=t+.25;counts['overdrive']=counts.get('overdrive',0)+1;continue
  focused=t+1e-8>=nextfocus and (not priority or ham[0]>160);over=t<overuntil;a=row[('focused_' if focused else '')+('overdrive_' if over else '')+'action'];m=row['focused_mind' if focused else 'mind']
  if (ham[0]<=a or ham[1]<=m) and focused:
   focused=False;a=row[('overdrive_' if over else '')+'action'];m=row['mind']
  if ham[0]<=a or ham[1]<=m:continue
  ham[0]-=a;ham[1]-=m;damage=row['focused_damage' if focused else 'damage']*1.5*row['mitigation'][defender];total+=damage*(1.25 if over else 1);nextfire=t+row['cadence'];shots+=1
  if focused:nextfocus=t+12
  if family=='flame':
   # Upper envelope: successful applications, no fire absorption. Shared max
   # remaining budget,3-second pending tick; rapid refresh cannot add budgets.
   if t>=burnuntil:nextburn=t+3
   incoming=math.floor(damage*.1);budget=max(budget,incoming);pulse=max(pulse,math.ceil(incoming/2));burnuntil=t+6
  counts['focused_discharge' if focused else 'ordinary']=counts.get('focused_discharge' if focused else 'ordinary',0)+1
  ammo-=1
  if reload and ammo==0:nextfire=max(nextfire,t+cl['reload_seconds']);ammo=cl['capacity'];reloads+=1
 return {'damage':round(total,3),'dps':round(total/duration,6),'remaining_action':round(ham[0],3),'remaining_mind':round(ham[1],3),'attacks':counts,'reloads_or_replacements':reloads,'heavy_charges_used':shots if row['charged'] else 0,'minimum_heavy_items':math.ceil(shots/40) if row['charged'] else 1,'grenade_charges':counts.get('grenade',0),'burn_upper_envelope_damage':burn_total}
def main():
 policy=compiled();records=[]
 for row in policy['heavy']:
  if row['progression']==.1 and row['family'] in ['particle','acid_beam','lightning']:continue
  for defender in ['unarmoured','body50','body50_element50']:
   for duration in ([30,120,300,600] if row['progression']==1 and row['source_quality']==1 and defender=='unarmoured' else [30,120]):
    reference=rifle(policy,row['progression'],row['source_quality'],defender,duration);result=heavy(policy,row,defender,duration,priority=duration>120)
    records.append({'family':row['family'],'progression':row['progression'],'quality':row['source_quality'],'defender':defender,'duration_seconds':duration,'rifleman':reference,'commando':result,'ratio':round(result['dps']/reference['dps'],6)})
 full=[r for r in records if r['progression']==1 and r['defender']=='unarmoured' and r['duration_seconds']==120]
 files=['server/combat/CommandoPolicy.h','server/combat/SwgxrCommando.h','server/combat/RiflemanPolicy.h','server/combat/SwgxrRifleman.h','server/combat/ArmourModel.h','server/combat/CoreCuResources.h','server/scout/GrenadePolicy.h','server/scout/SwgxrGrenade.h','client/combat/balance.json','tests/commando_policy.cpp','tools/server/audit_commando_balance.py','vendor/Core3/MMOCoreORB/bin/scripts/commands/attack.lua','vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/rifle/rifle_t21.lua','vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/grenade/grenade_fragmentation.lua']
 report={'scope':'compiled production arithmetic; deterministic authored loadout benchmark, not live encounter validation','production_policy_checks':policy['checks'], 'assumptions':[
 'Characters begin with 1,000 Action and 1,000 Mind and recover 10/8 per second in combat. No incoming damage or medical help; ordinary rifle attacks cost no resources, as specified in attack.lua.',
 'Both builds have Master Marksman. Rifleman has 35 rifle speed at Novice, 65 in the balanced intermediate build, and 95 at mastery. The intermediate build has Accuracy II, Concealment II, Ability II and Support III.',
 'Commando uses authored profession-weighted proficiency in place of uneven legacy weapon bonuses. The intermediate build has Field Tactics II, Heavy Support III, Flame II and Acid II. Unavailable novice heavy beam certifications are excluded.',
 'Source quality interpolates the original T21 mean of 140 to 245 and speed of 10.5 to 6.5 seconds. Commando damage quality maps the same proportional band. Grenade quality follows the original fragmentation recipe.',
 'All contacts land on a stationary eligible PvE target. There are no secondary defenses. The simulation uses the on-axis peak damage envelope; cone and beam distance/angular falloff reduce practical output.',
 'Rifleman uses a neutral 1.0 ProjectileContactPolicy range/posture multiplier. This is a numerical reference, not a same-position matchup: the original T21 range curve spans 0.3 at zero distance to 1.1 at maximum range before crafted modifiers. The separate sensitivity table rescales only Rifleman output; it does not assert that heavy peak geometry is achievable at every rifle distance.',
 'Fixed original-family AP and channel conversion taxes are normalized when authoring Commando packets. The compiled ArmourModel still applies the actual elemental split, penetration budget, body protection and shields.',
 'Client magazine capacities and reload durations are read from balance.json, including the T21 repeater class. Depleted heavy weapons require another 40-charge item with an ideal three-second replacement gap. Reload never restores native charges.',
 'Grenades consume 60 Action and 20 Mind, use the native 12-to-9-second shared recovery and detonate after two seconds. The model adds no throw or regrip delay, making this an optimistic whole-kit envelope.',
 'Focused Discharge, Overdrive and learned Rifleman abilities pay their costs and cooldowns. Surprise Shot has no sustained high-Health bonus. Flurry launches three projectiles with 0.25-second spacing, followed by ordinary recovery.',
 'Flame burn uses an upper envelope in which all applications succeed, without absorption. It preserves the shared maximum remaining budget and pending three-second tick. Resistance and cures reduce damage.',
 'At 30/120 seconds the player uses grenades on cooldown when affordable and selects Focused Discharge when affordable, falling back to ordinary fire. At 300/600 seconds grenades preserve 100 Action and Focused Discharge requires more than 160 Action, prioritizing continued weapon use.',
 'This benchmark excludes armor output penalties, spices, slicing, powerups, aim variation and headset performance. Different armor profiles and Rifleman skill-branch choices alter the ratios.'
 ],'master_120s_unarmoured_ratio_range':[min(r['ratio'] for r in full),max(r['ratio'] for r in full)],'rifle_range_pose_sensitivity':[{ 'rifle_multiplier':multiplier,'master_120s_unarmoured_ratio_range':[round(min(r['ratio'] for r in full)/multiplier,6),round(max(r['ratio'] for r in full)/multiplier,6)]} for multiplier in [.3,1.,1.1]],'records':records,'source_sha256':{p:source_hash(p) for p in files}}
 OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'records':len(records),'checks':policy['checks'],'master_ratio_range':report['master_120s_unarmoured_ratio_range'],'evidence':str(OUT)}))
if __name__=='__main__':main()
