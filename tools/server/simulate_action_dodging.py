#!/usr/bin/env python3
"""Offline dodge/slow-to-fire assessment using the native attack footprints.

Simulated shots measure timing opportunities only: no RPG damage, aiming accuracy,
crowd collision, player head/hand tracking or multi-mob pressure is reproduced.
"""
import argparse,math,random,json
from pathlib import Path
DT=1/120

def hit(role,x,z,angle,extra=0):
    # Same source-space footprints as server/combat/ActionCombatPolicy.h.
    radius=.35+extra; distance=math.hypot(x,z); along=x*math.sin(angle)+z*math.cos(angle)
    if distance>(24 if role=='ranged' else 3)+radius:return False
    if role=='ranged':return along>=-radius and abs(x*math.cos(angle)-z*math.sin(angle))<=.45+radius
    return distance<=radius or along>=.5*max(0,distance-radius)

def trial(role,rate,lock,strategy,rtt,seed,lane_speed_cap=None):
    rng=random.Random(seed);latency=rtt/2+rng.uniform(0,.06)
    reaction=.2+rng.uniform(0,.15)+latency
    delivery=1.2 if role=='ranged' else 1.
    active=delivery+(1/3 if role=='ranged' else 0)
    end=active+(.2 if role=='ranged' else .25)
    distance=rng.uniform(8,16) if role=='ranged' else rng.uniform(2.1,2.9)
    x=0.;z=distance;velocity=0.;angle=0.;history=[];contact=False;shot=None;slow_at=None;slow_until=-1;shot_started=False;steady=0
    latest_angle=0.;max_turn=0.;safety_delay=0
    recovery_end=max(end+.65,max(end,delivery+(.5 if role=='melee' else 1))+(1.4 if role=='melee' else 1.8))
    for frame in range(int(recovery_end/DT)):
        t=frame*DT
        if t<delivery-lock:
            desired=math.atan2(x,z);turn_rate=math.radians(rate)
            if lane_speed_cap is not None:turn_rate=min(turn_rate,lane_speed_cap/max(.1,math.hypot(x,z)))
            step=turn_rate*DT
            angle+=max(-step,min(step,desired-angle))
        history.append((t,angle))
        while safety_delay+1<len(history) and history[safety_delay+1][0]<=t-latency:safety_delay+=1
        latest_angle=history[safety_delay][1]
        if t>=reaction and not shot_started:
            if strategy=='shoot_early':ready=t>=reaction+.35
            elif strategy=='dodge_then_shoot':ready=t>=delivery-lock+latency and not hit(role,x,z,latest_angle,.2)
            else:ready=False
            if ready:shot_started=True;slow_at=t;slow_until=t+.55
        target=0 if strategy=='stationary' or t<reaction else .6 if t<slow_until else 3.5
        velocity+=max(-10*DT,min(10*DT,target-velocity))
        x+=velocity*DT*(1 if role=='ranged' else math.sqrt(.5))
        if role=='melee':z+=velocity*DT*math.sqrt(.5)
        # A shot opportunity requires at least 150 ms below 1 m/s.
        if shot_started and shot is None:
            if velocity<=1:steady+=DT
            else:steady=0
            if steady>=.15:shot=t
        if active<=t<=end:contact|=hit(role,x,z,angle)
        max_turn=max(max_turn,abs(angle))
    return dict(hit=contact,shot=shot,shot_before_delivery=shot is not None and shot<=delivery,
                shot_before_recovery=shot is not None and shot<=recovery_end,max_turn_degrees=math.degrees(max_turn))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,default=Path(__file__).resolve().parents[2]/"runtime/action-prototype/dodge-assessment/results.json")
    args=parser.parse_args()
    rows=[]
    for role in ['melee','ranged']:
     for rate,lock,lane_cap in [(0,.3,None),(8,.3,None),(12,.3,None),(20,.3,None),(12,0,None),(12,.3,2.)]:
      for strategy in ['stationary','shoot_early','dodge_then_shoot']:
       for rtt in [0,.05,.1,.2]:
        cases=[trial(role,rate,lock,strategy,rtt,seed,lane_cap) for seed in range(200)]
        times=sorted(x['shot'] for x in cases if x['shot'] is not None)
        rows.append(dict(role=role,turn_degrees_per_second=rate,final_lock_seconds=lock,lane_speed_cap=lane_cap,strategy=strategy,rtt_ms=rtt*1000,trials=len(cases),hit_percent=100*sum(x['hit'] for x in cases)/len(cases),shots_before_recovery_percent=100*sum(x['shot_before_recovery'] for x in cases)/len(cases),shot_time_median=times[len(times)//2] if times else None,max_turn_degrees=max(x['max_turn_degrees'] for x in cases)))
    report=dict(kind='offline kinematic policy simulation, not native damage or full-stage client execution',
     assumptions=dict(trials=sum(row["trials"] for row in rows),player_speed=3.5,shooting_speed=.6,acceleration=10,shot_slowdown_seconds=.55,steady_aim_seconds=.15,reaction_seconds=[.2,.35],added_one_way_jitter=[0,.06],tick_hz=120,shot_damage_simulated=False,mobs_per_trial=1,melee_dodge='diagonal retreat',ranged_dodge='lateral strafe',geometry='matches ActionCombatPolicy.h'),rows=rows)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(report,indent=2)+'\n')
    for r in rows:
     if r['rtt_ms']==100:print(r)

if __name__=="__main__":main()
