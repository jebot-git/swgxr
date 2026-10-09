#!/usr/bin/env python3
"""Compile current production policies and write a read-only Combat Medic balance report.

The ignored report contains theoretical arithmetic, not measured server encounters.
No production, inventory, database, service, client or headset state is changed.
"""
import hashlib
import json
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'runtime/evidence/combat-medic/arithmetic.json'
RECIPES=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/medicine/crafted'
SOURCES=[
 'server/combat/CoreCuPolicy.h','server/combat/CoreCuMedicalPolicy.h',
 'server/combat/CoreCuResources.h','server/combat/FencerPolicy.h',
 'server/combat/PikemanPolicy.h','server/combat/CarbineerPolicy.h',
 'server/medic/CombatMedicPolicy.h','server/medic/CombatMedicHealingPolicy.h',
 'server/medic/CoreCuMedicine.h','server/medic/SwgxrCombatMedicEffects.h',
 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/HealMindCommand.h',
 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/damageovertime/DamageOverTime.cpp',
 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/damageovertime/DamageOverTime.h',
]

CXX=r'''
#include "server/combat/CoreCuPolicy.h"
#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "server/combat/PikemanPolicy.h"
#include "server/combat/CarbineerPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include "server/medic/CombatMedicHealingPolicy.h"
#include <nlohmann/json.hpp>
#include <iostream>
using Json=nlohmann::json;
// Exact pure production resource-rate method is inserted by the driver.
struct ResourceRate { public: RESOURCE_RATE_METHOD };
int main(){
 Json inputs;std::cin>>inputs;Json out;
 using namespace corecu;
 const double regen=1000*ResourceRate::regen(3,true);
 out["application_threshold_percent"]=Json::array();
 for(double rating:{65.,90.,100.,125.}){
  out["application_threshold_percent"].push_back({{"defender_rating",rating},
   {"combat_medic_master_best",combatmedic::chance(combatmedic::rawPotency(100,1),rating)},
   {"fencer_master_flawless",fencer::chance(rating,1,false,true)},
   {"fencer_master_precision",fencer::chance(rating,1,true,false)},
   {"fencer_master_passive",fencer::chance(rating,1,false,false)},
   {"pikeman_master",pikeman::chance(rating,1)},
   {"carbineer_rank2_braced",carbineer::chance(rating,true,true)},
   {"ranger_master_trap",trapStatusChance(rating,trapSuccessBonus(true,4,4,true))},
   {"generic_95",statusChance(95,rating)}});
 }
 out["baseline_standing_combat_action_regeneration_per_second"]=regen;
 out["hostile_supplies"]=Json::array();
 for(const auto& item:inputs["hostile"]){
  bool disease=item["disease"],area=item["area"];
  for(int skill:{5,100})for(int bound:{0,1}){
   double power=item["ranges"]["power"][bound],durationInput=item["ranges"]["duration"][bound],potencyInput=item["ranges"]["potency"][bound];
   int seconds=combatmedic::duration(disease,skill,durationInput);
   int amount=disease?combatmedic::diseasePulse(1000,skill,power,area):combatmedic::poisonBudget(3000,3000,skill,power,area,durationInput);
   int interval=combatmedic::interval(disease);
   int pulse=disease?amount:combatmedic::pulse(amount,seconds,interval);
   Json row={{"template",item["template"]},{"family",item["family"]},{"tier",item["tier"]},{"skill_rating",skill},
    {"recipe_corner",bound?"all_experimental_maxima":"all_experimental_minima"},
    {"raw_effectiveness",power},{"raw_duration",durationInput},{"raw_potency",potencyInput},
    {"application_potency",combatmedic::rawPotency(skill,combatmedic::applicationQuality(potencyInput))},
    {"authored_duration_seconds",seconds},{"pulse_interval_seconds",interval},
    {"unabsorbed_pulse",pulse},{"total_health_budget",disease?Json(nullptr):Json(amount)},
    {"target_cap",area?combatmedic::TargetCap:1},{"outcomes",Json::array()}};
   for(double rating:{0.,65.,90.,100.,125.})for(double absorption:{0.,10.}){
    int duration=statusDuration(seconds,rating);
    int ticks=combatmedic::pulseCount(duration,interval);
    int remaining=amount,total=0;
    for(int n=0;n<ticks;++n){
     int raw=disease?pulse:std::min(remaining,pulse);
     if(!disease)remaining-=raw;
     total+=disease?diseaseTick(1000,raw,absorption):int(std::floor(raw*(1-absorption/100.)));
    }
    int actualPulse=disease?diseaseTick(1000,pulse,absorption):int(std::floor(pulse*(1-absorption/100.)));
    Json effect={{"defender_rating",rating},{"absorption_percent",absorption},{"duration_seconds",duration},
     {"ideal_scheduled_pulses",ticks},{"total_before_regeneration_or_cures",total},
     {"gross_average_per_second",double(total)/duration}};
    if(disease){effect["steady_pulse_drain_per_second"]=double(actualPulse)/interval;effect["steady_net_pressure_vs_baseline_regen_per_second"]=double(actualPulse)/interval-regen;}
    row["outcomes"].push_back(effect);
   }
   out["hostile_supplies"].push_back(row);
  }
 }
 out["healing_progression"]=Json::array();
 for(int skill:{5,20,35,50,75,100}){
  Json row={{"skill_rating",skill},{"supplies",Json::array()}};
  double seconds=medicine::recovery(medicine::ability("healdamage").recovery,std::max(75,skill))/1000.;
  row["injury_cooldown_seconds"]=seconds;
  row["action_cost"]=medicine::cost(1000,medicine::ability("healdamage").action);
  row["mind_cost"]=medicine::cost(1000,medicine::ability("healdamage").mind);
  for(const auto& item:inputs["healing"]){
   auto spec=combatmedichealing::stim(item["template"]);
   int low=combatmedichealing::heal(3000,spec,item["ranges"]["power"][0],skill);
   int high=combatmedichealing::heal(3000,spec,item["ranges"]["power"][1],skill);
   int recipients=spec.area?combatmedichealing::AreaTargetCap:1;
   row["supplies"].push_back({{"template",item["template"]},{"family",item["family"]},{"tier",item["tier"]},
    {"health_low_quality",low},{"health_high_quality",high},{"recipient_cap",recipients},
    {"ideal_max_group_health_per_charge",high*recipients},
    {"ideal_high_quality_health_per_second_per_recipient",high/seconds}});
  }
  out["healing_progression"].push_back(row);
 }
 out["mind_transfer"]["progression"]=Json::array();
 for(int skill:{5,20,35,50,75,100})out["mind_transfer"]["progression"].push_back({{"skill_rating",skill},{"capacity",combatmedichealing::mindCapacity(1000,skill)}});
 out["mind_transfer"]["action_fee"]=medicine::cost(1000,medicine::ability("healmind").action);
 out["mind_transfer"]["cooldown_seconds"]=medicine::recovery(medicine::ability("healmind").recovery,75)/1000.;
 out["mind_transfer"]["examples"]=Json::array();
 for(int reserve:{1,2,3,100,1000})for(int missing:{1,100,1000})for(bool spice:{false,true}){
  int limit=combatmedichealing::transferLimit(combatmedichealing::mindCapacity(1000,100),missing,reserve);
  int input=combatmedichealing::transferInput(limit,spice);
  int gained=spice?medicine::spiceHealing(input):input;
  out["mind_transfer"]["examples"].push_back({{"healer_mind",reserve},{"recipient_missing_mind",missing},{"healing_spice_active",spice},
   {"transfer_limit",limit},{"native_healing_input",input},{"recipient_gain",gained},{"healer_payment",gained},
   {"healer_remaining",reserve-gained},{"net_party_mind_creation",0}});
 }
 std::cout<<out.dump(2)<<"\n";
}
'''


def recipe_rows():
 rows=[]
 for family,prefix,tiers,disease,area in [
  ('poison','medpack_poison_health_','abc',False,False),
  ('area_poison','medpack_poison_area_health_','abc',False,True),
  ('disease','medpack_disease_action_','abc',True,False),
  ('area_disease','medpack_disease_area_action_','abc',True,True),
  ('ranged_stim','medpack_grenade_damage_','abcde',False,False),
  ('area_stim','medpack_grenade_area_','abc',False,True)]:
  for tier in tiers:
   path=RECIPES/(prefix+tier+'.lua');text=path.read_text()
   def array(name):
    return [v.strip().strip('"') for v in re.search(r'\b'+name+r'\s*=\s*\{([^}]+)\}',text)[1].split(',')]
   ranges={name:[float(low),float(high)] for name,low,high in zip(array('experimentalSubGroupTitles'),array('experimentalMin'),array('experimentalMax')) if name in ('power','duration','potency','range','area','skillmodmin','charges')}
   rows.append({'family':family,'tier':tier.upper(),'disease':disease,'area':area,
    'template':'object/tangible/medicine/crafted/'+prefix+tier+'.iff','ranges':ranges,
    'source':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 return rows


def audit():
 recipes=recipe_rows()
 inputs={'hostile':[r for r in recipes if 'stim' not in r['family']],
         'healing':[r for r in recipes if 'stim' in r['family']]}
 resource_source=(ROOT/'server/combat/CoreCuResources.h').read_text()
 rate=re.search(r'static double regen\([^\n]+',resource_source)[0]
 with tempfile.TemporaryDirectory(prefix='swgxr-cm-arithmetic-') as directory:
  path=Path(directory);source=path/'audit.cpp';binary=path/'audit'
  source.write_text(CXX.replace('RESOURCE_RATE_METHOD',rate))
  subprocess.run(['c++','-std=c++17','-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(source),'-o',str(binary)],check=True,capture_output=True,text=True,timeout=60)
  run=subprocess.run([str(binary)],input=json.dumps(inputs),check=True,capture_output=True,text=True,timeout=10)
  result=json.loads(run.stdout)
 report={
  'scope':'Read-only theoretical arithmetic compiled from current production policy headers and the exact production resource-rate method. Not native server execution, crafted inventory output, or measured combat.',
  'generated_utc':datetime.now(timezone.utc).isoformat(),
  'assumptions':{'health':3000,'action':1000,'mind':1000,'healer_health':3000,'inherited_medic_injury_speed':75,'battle_fatigue_multiplier':1,'spice_food':'Absent except explicitly labeled Mind-transfer examples.','standing':True,'shared_recovery':'CM hostile supplies share one timer; ranged/area healing share injury recovery; Mind transfer has separate resource recovery.'},
  'source_hashes':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES},
  'recipe_ranges':recipes,
  'calculated':result,
  'interpretation':{
   'application':'Percentages are application formula thresholds before integer RNG discretization. CM is strongest at matched defense ratings; Fencer best includes its temporary ultimate, Carbineer includes Brace and rank2 Wild Shot, Ranger includes full Scout/Ranger training.',
   'duration':'Master CM extends authored duration by up to30%; duration quality contributes75–100%. Poison total budget uses the same quality factor and is divided among authored pulses before resistance shortens duration. A remaining-budget cap prevents extra poison damage from rounding or extended duration.',
   'poison':'One shared CM channel across all supply tiers, normal/area variants and attackers. Stronger/equal applications replace; weaker do not add another stack. Generic non-CM DoTs are separate and unchanged. Target Health basis is capped at four times healer base Health.',
   'disease':'One shared CM disease channel. Three-second temporary Action pulses apply to players, organic pets and NPCs without adding wounds or shock. Gross drain is not the same as net pressure: the table subtracts10 Action/s only as a steady missing-pool reference.',
   'doctor_protection':'Matching prophylaxis adds up to25 resistance once and10% absorption. Resistance affects chance and duration; absorption floors each pulse. Cures can partially reduce or clear existing DoT strength.',
   'healing':'Actual new ranged and area tier quality formulas, with CM proficiency. Single-target E maximum780 Health; area C maximum360 Health per recipient and five-recipient cap, before target battle fatigue/spice. Doctor direct-care bonus does not apply.',
   'mind_transfer':'Capacity is bounded by target missing Mind and healer Mind minus one. Native command charges the measured recipient Mind increase, making transfer conserve party Mind. The fixed Action fee remains. Healing spice is capped by lowering input first; it does not create extra transfer capacity. Withdrawal may harm Health while returning a visual heal amount; measured zero Mind gain means zero Mind payment. Nominal legacy .10 Mind policy is overridden to variable payment in CoreCuMedicine.'},
  'limitations':[
   'Recipe endpoints are declared experimental ranges; simultaneous endpoint values are arithmetic corners, not proof that a crafted item with every maximum can be produced. Components and persisted/default values may differ, but runtime policy clamps them.',
   'Ideal pulse counts assume timely scheduling and no expiry delay, cure, dispel, death, incapacitation, partial remaining resource, target immunity or reapplication. The separate production lifecycle fixture covers bounds; these totals are not guaranteed encounter damage.',
   'Application, DoT ticks and AoE eligibility each still depend on real target state. Multiplying probability by aggregate maxima is not a measured DPS estimate.',
   'AoE maxima assume every allowed recipient is eligible and needs the effect. A healthy friendly center cannot trigger current area healing.',
   'Heal-per-second values assume full missing Health and sustained resources/supplies. Resource costs, recharge, movement, targeting and other actions limit sustained use.',
   'Baseline10 Action/s regeneration excludes posture, secondary attributes, spice and Doctor Metabolic preparation. NPC combat regeneration and AI ability spending differ; no NPC encounter was simulated.',
   'A reserve/spice Mind-transfer example with zero native input is rejected; no Action fee should be inferred from that arithmetic row.',
   'Initial actions.json is preserved as the pre-rebalance static audit and does not describe the new policy.'
  ]
 }
 OUTPUT.parent.mkdir(parents=True,exist_ok=True);OUTPUT.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'report':str(OUTPUT.relative_to(ROOT)),'scope':'compiled production-policy arithmetic only','source_headers':len(SOURCES),'recipe_templates':len(recipes),'hostile_supply_rows':len(result['hostile_supplies'])}))
 return report


if __name__=='__main__':audit()
