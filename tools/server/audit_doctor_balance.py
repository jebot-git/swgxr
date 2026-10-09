#!/usr/bin/env python3
"""Report Doctor tuning from production policies; no server or character mutations."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = r'''
#include "server/combat/CoreCuPolicy.h"
#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/combat/DoctorPolicy.h"
#include "server/combat/CoreCuRegenPolicy.h"
#include "server/medic/DoctorCarePolicy.h"
#include <nlohmann/json.hpp>
#include <iostream>
using Json=nlohmann::json;
Json sustain(int actionCost,int mindCost,int recovery,double metabolic){
 int action=1000,mind=1000,casts=0,next=0,firstDelay=-1;
 double actionCarry=0,mindCarry=0;
 for(int time=0;time<=180000;++time){
  if(time && time%1000==0){
   action+=corecu::regeneration::tick(10*(1+metabolic),actionCarry,1000-action);
   mind+=corecu::regeneration::tick(8*(1+metabolic),mindCarry,1000-mind);
  }
  if(time<next)continue;
  if(action<=actionCost || mind<=mindCost){if(firstDelay<0)firstDelay=time;continue;}
  action-=actionCost;mind-=mindCost;++casts;next=time+recovery;
 }
 return {{"casts_in_180_seconds",casts},{"first_resource_delayed_cast_seconds",firstDelay<0?Json(nullptr):Json(firstDelay/1000.)},{"remaining_action",action},{"remaining_mind",mind}};
}
int main(){
 Json out={{"schema",1},{"scope","Production policy arithmetic, not encounter or live-server validation"},{"baseline",{{"health",3000},{"action",1000},{"mind",1000}}}};
 out["assumptions"]={"No wounds, battle fatigue, food, spices or preparations unless named","Master Medic prerequisite supplies injury proficiency 100 and injury speed 75","Tier rows describe potency only; original medicine-use requirements still gate availability","Potency is before overheal clipping; supplies are unlimited in the resource stress model","Standing combat recovery uses nominal 10 Action/s and 8 Mind/s; no attacks or other treatments"};
 for(auto name:{"healdamage","tenddamage","quickheal","healwound","healstate","healpet","healdroiddamage"}){
  auto p=corecu::medicine::ability(name);
  out["costs"][name]={{"action",corecu::medicine::cost(1000,p.action)},{"mind",corecu::medicine::cost(1000,p.mind)},{"base_recovery_seconds",p.recovery/1000.}};
 }
 for(int stage:{0,1,5,6}){
  Json profile={{"direct_multiplier",corecu::doctorcare::multiplier(stage)},{"quick_multiplier",corecu::doctorcare::emergencyMultiplier(stage)},{"wound_multiplier",corecu::doctorcare::woundMultiplier(stage)},
   {"tend_hp",corecu::doctorcare::potency(corecu::medicine::tend(3000,100),stage)},{"quick_hp",corecu::doctorcare::emergencyPotency(corecu::medicine::emergency(3000,100),stage)}};
  const double low[]={75,75,100,150,200},high[]={100,200,400,700,1000};
  for(int tier=0;tier<5;++tier){
   profile["crafted_stims"][std::string(1,'A'+tier)]={{"low_quality_hp",corecu::doctorcare::potency(corecu::doctorcare::stim(3000,tier,low[tier],100),stage)},{"high_quality_hp",corecu::doctorcare::potency(corecu::doctorcare::stim(3000,tier,high[tier],100),stage)}};
  }
  out["profiles"][stage==0?"master_medic":stage==1?"novice_doctor":stage==5?"doctor_wound_iv":"master_doctor"]=profile;
 }
 for(double rating:{0.,20.,60.,65.,90.,100.,125.,150.,1000.})out["resistance"].push_back({{"rating",rating},{"chance_duration_reduction",corecu::statusReduction(rating)},{"application_chance_from_95_percent",corecu::statusChance(95,rating)}});
 for(double metabolic:{0.,.05,.10,.15}){
  int action=0,mind=0;double a=0,m=0;
  for(int second=0;second<10;++second){action+=corecu::regeneration::tick(10*(1+metabolic),a,1000-action);mind+=corecu::regeneration::tick(8*(1+metabolic),m,1000-mind);}
  out["combat_regeneration_over_10_seconds"].push_back({{"metabolic_bonus",metabolic},{"action",action},{"mind",mind},{"health",0}});
 }
 const auto stim=corecu::medicine::ability("healdamage");int recovery=corecu::medicine::recovery(stim.recovery,75);
 out["stim_recovery_seconds"]=recovery/1000.;
 out["sustained_stims"]["old_cost_no_metabolic"]=sustain(20,30,recovery,0);
 out["sustained_stims"]["current_no_metabolic"]=sustain(corecu::medicine::cost(1000,stim.action),corecu::medicine::cost(1000,stim.mind),recovery,0);
 out["sustained_stims"]["current_max_metabolic"]=sustain(corecu::medicine::cost(1000,stim.action),corecu::medicine::cost(1000,stim.mind),recovery,.15);
 std::cout<<out.dump(2)<<"\n";
}
'''


def audit():
    with tempfile.TemporaryDirectory(prefix='swgxr-doctor-balance-') as temporary:
        folder = Path(temporary)
        source, binary = folder/'audit.cpp', folder/'audit'
        source.write_text(SOURCE)
        subprocess.run(['c++', '-std=c++17', '-O2', '-I'+str(ROOT), str(source), '-o', str(binary)], check=True)
        return json.loads(subprocess.check_output([str(binary)], text=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps({'output': str(args.output), 'scope': result['scope']}))
    else:
        print(json.dumps(result, indent=2))
