#include "../server/combat/CoreCuMedicalPolicy.h"
#include <cassert>
#include "../server/combat/CoreCuFoodPolicy.h"
#include "../server/smuggler/SwgxrSmugglerPolicy.h"
#include <iostream>
using namespace corecu::medicine;
int main(){int checks=0;
 for(int base:{100,300,1000,3000,10000})for(int skill:{0,25,50,100,250}){
  int low=injury(base,skill,.1),high=injury(base,skill,9);
  assert(low>0 && high>=low && high<=base*.28+1);checks++;
  assert(tend(base,skill)<emergency(base,skill) && emergency(base,skill)<=base*.40+1);checks++;
  assert(cost(base,.03)>=1 && cost(base,.03)<=base*.03+1);checks++;
  assert(enhancement(base,100000)<=base*.15 && enhancement(base,-1)==0);checks++;
  assert(wound(base,100000)<=base*.1);checks++;
 }
 for(int secondary:{0,300,600,1500,5000})for(int base:{0,1,20,100,1000}){
  auto adjusted=costAdjustment(secondary,base);assert(adjusted>=base*.75 && adjusted<=base);checks++;
 }
 assert(std::string(ability("healdamage").group)==ability("tenddamage").group);checks++;
 assert(retired("healWound") && retired("tendwound") && retired("diagnose") && !retired("healdamage"));checks++;
 assert(ability("quickheal").recovery==30000 && ability("reviveplayer").recovery==60000);checks++;
 for(int base:{300,1000,3000})for(int legacy:{-2000,-500,0,500,1000,2000}){assert(std::abs(spiceHam(base,legacy))<=base/4);assert(spiceHam(base,legacy)==-spiceHam(base,-legacy));checks+=2;}
 assert(spiceHealing(600)==900 && spiceHealing(0)==0);checks++;
 assert(std::abs(SwgxrSmugglerPolicy::lastDitch(900,3000,100,1000,30,1000)-4.335)<.00001);checks++;
 assert(SwgxrSmugglerPolicy::lastDitch(0,3000,0,1000,0,1000)==5);checks++;
 assert(SwgxrSmugglerPolicy::lastDitch(3000,3000,0,1000,0,1000)==3);checks++;
 assert(recovery(6000,0)==6000 && recovery(6000,100)==4500 && recovery(6000,500)==4500);checks++;
 assert(woundPack(3000,0,1)==90 && woundPack(3000,100,1)==240 && woundPack(3000,500,10)==300);checks++;
 assert(std::abs(regeneration(345,300)-1.15)<1e-8 && regeneration(3000,300)==1.25 && regeneration(0,300)==.75);checks++;
 assert(std::abs(costAdjustment(345,100)-96.25)<1e-8 && costAdjustment(600,100)==75);checks++;
 for(int i=0;i<9;++i){assert(woundAttribute(true,i)==(i==0));assert(woundAttribute(false,i));checks+=2;}
 for(auto stat:{"action","strength","constitution","quickness","stamina","mind","focus","willpower"})for(auto suffix:{".iff","_a.iff","_e.iff"}){
  assert(retiredMedicalTemplate(std::string("object/tangible/medicine/crafted/medpack_wound_")+stat+suffix));checks++;
 }
 for(auto family:{"poison","disease"})for(auto stat:{"health","action","mind","focus"})for(auto area:{"","area_"}){
  auto path=std::string("object/draft_schematic/chemistry/medpack_")+family+"_"+area+stat+"_b.iff";
  assert(retiredMedicalTemplate(path)==(std::string(stat)!=(std::string(family)=="disease"?"action":"health")));checks++;
 }
 for(auto path:{"object/tangible/medicine/medpack_wound_health.iff","object/draft_schematic/chemistry/shared_medpack_wound_health_e.iff","object/draft_schematic/droid/droid_wound_repair_kit_d.iff","object/draft_schematic/chemistry/medpack_cure_disease_a.iff","object/draft_schematic/chemistry/medpack_revive.iff","object/draft_schematic/chemistry/medpack_enhance_action_a.iff"}){assert(!retiredMedicalTemplate(path));checks++;}
 assert(diseaseDrain(1000,999999)==50 && diseaseDrain(1000,-50)==0 && diseaseDrain(1000,20)==20);checks++;
 assert(ability("healmind").recovery==15000 && std::string(ability("healmind").group)=="resource");checks++;
 for(int base:{300,1000,3000})for(int value:{0,35,375,1250,100000}){
  assert(corecu::food::attribute(base,value)<=base/10);checks++;
  assert(corecu::food::restore(base,value)<=base*.15+1);checks++;
  assert(revive(base,value)>=base*.1 && revive(base,value)<=base*.25+1);checks++;
 }
 assert(corecu::food::attribute(3000,375)<corecu::food::attribute(3000,625));checks++;
 assert(corecu::food::withinBudget(1000,100,100) && !corecu::food::withinBudget(1000,200,1));checks++;
 assert(corecu::food::skill(100000)==20 && corecu::food::skill(12)==12 && corecu::food::instant(-10)==0);checks++;
 assert(retiredMedicalTemplate("object/draft_schematic/chemistry/med_stimpack_state_stunned_b.iff"));checks++;
 assert(!retiredMedicalTemplate("object/tangible/medicine/medpack_wound_health.iff"));checks++;
 for(auto name:{"healpet","healdroiddamage"}){assert(ability(name).recovery==6000 && ability(name).action==.02 && ability(name).mind==.03 && std::string(ability(name).group)=="injury");checks++;}
 assert(ability("healdroidwound").recovery==5000 && std::string(ability("healdroidwound").group)=="wound");checks++;
 for(auto name:{"droid_stimpack_a","droid_stimpack_b","droid_stimpack_c","droid_stimpack_d","droid_vitapack_a","droid_vitapack_b","droid_vitapack_c"}){assert(retiredMedicalTemplate(std::string("object/draft_schematic/droid/")+name+".iff"));checks++;}
 for(auto name:{"droid_damage_repair_kit_a","droid_wound_repair_kit_d","pet_stimpack_a","pet_vitapack_c"}){assert(!retiredMedicalTemplate(std::string("object/draft_schematic/droid/")+name+".iff"));checks++;}
 std::cout<<"CoreCU medical policy: "<<checks<<" checks passed\n";
}
