#pragma once
#include "CoreCuMedicalPolicy.h"
#include "DoctorCarePolicy.h"
#include "CombatMedicHealingPolicy.h"
#include "SwgxrSpice.h"
#include "server/zone/objects/tangible/pharmaceutical/StimPack.h"
// Native command policy, shared by ordinary Core3 commands and the VR bridge.
class CoreCuMedicine {
public:
 static int doctorStage(CreatureObject* c){
  if(!c || !c->isPlayerCreature() || !c->hasSkill("science_doctor_novice"))return 0;
  if(c->hasSkill("science_doctor_master"))return 6;
  int stage=1;for(auto node:{"science_doctor_wound_01","science_doctor_wound_02","science_doctor_wound_03","science_doctor_wound_04"})if(c->hasSkill(node))++stage;
  return std::min(5,stage);
 }
 static int recovery(CreatureObject* c,const String& name){
  auto p=corecu::medicine::ability(name.toCharArray());
  int speed=(name=="healwound" || name=="healenhance")?c->getSkillMod("healing_wound_speed"):name=="healdamage"?std::max(c->getSkillMod("healing_injury_speed"),c->getSkillMod("healing_range_speed")):c->getSkillMod("healing_injury_speed");
  int recovery=corecu::medicine::recovery(p.recovery,speed);
  auto food=c->getBuff(BuffCRC::FOOD_HEAL_RECOVERY);
  if(food)recovery=int(std::ceil(recovery*(1.-std::max(0,std::min(20,food->getSkillModifierValue("heal_recovery")))/100.)));
  return recovery;
 }
 static String key(const String& name){auto p=corecu::medicine::ability(name.toCharArray());return String("corecu_medical_")+p.group;}
 static double remaining(CreatureObject* c,const String& name){
  if(!c || !c->isPlayerCreature())return 0;
  auto t=c->getCooldownTime(key(name));double own=t?std::max(0.,-t->miliDifference()/1000.):0;
  if(name=="quickheal"){auto shared=c->getCooldownTime("corecu_medical_injury");if(shared)own=std::max(own,std::max(0.,-shared->miliDifference()/1000.));}
  return own;
 }
 static int cost(CreatureObject* c,const String& name,int pool){
  if(name=="healmind" && pool==6)return 0; // Variable transfer payment equals actual Mind restored.
  auto p=corecu::medicine::ability(name.toCharArray());
  return corecu::medicine::cost(c->getBaseHAM(pool),pool==3?p.action:p.mind);
 }
 static int mind(CreatureObject* c,const String& name,int legacy){return c->isPlayerCreature() && corecu::medicine::ability(name.toCharArray()).recovery>0?cost(c,name,6):legacy;}
 static bool check(CreatureObject* c,const String& name){
  auto p=corecu::medicine::ability(name.toCharArray());if(!c->isPlayerCreature() || p.recovery==0)return true;
  if(remaining(c,name)>0){c->sendSystemMessage("Medical ability recovering.");return false;}
  if(c->getHAM(3)<=cost(c,name,3) || c->getHAM(6)<=cost(c,name,6)){c->sendSystemMessage("Insufficient Action or Mind for treatment.");return false;}
  return true;
 }
 // Called only after the native command succeeds; its existing Mind payment
 // remains in place. Shared timers prevent alternating redundant heal commands.
 static void commit(CreatureObject* c,const String& name){
  auto p=corecu::medicine::ability(name.toCharArray());if(!c->isPlayerCreature() || p.recovery==0)return;
  SwgxrSpice::HamAdjustment scope;
  c->inflictDamage(c,3,cost(c,name,3),false);
  c->addCooldown(key(name),int(recovery(c,name)*SwgxrSpice::cooldownScale(c)));
  if(name=="quickheal")c->addCooldown("corecu_medical_injury",int(recovery(c,"healdamage")*SwgxrSpice::cooldownScale(c)));
 }
 static int injury(CreatureObject* healer,CreatureObject* target,int nativePower,bool direct=true,bool applyBattleFatigue=true){
  if(!healer->isPlayerCreature() || !(target->isPlayerCreature() || target->isPet()))return nativePower;
  double fatigue=applyBattleFatigue?target->calculateBFRatio():1.;
  return corecu::doctorcare::potency(corecu::medicine::injury(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment"),nativePower/(600.*std::max(.001,fatigue))),direct?doctorStage(healer):0)*fatigue;
 }
 static int stim(CreatureObject* healer,CreatureObject* target,StimPack* pack,bool applyBattleFatigue=true){
  if(!pack)return 0;
  int nativePower=pack->calculatePower(healer,target,applyBattleFatigue);
  if(!healer->isPlayerCreature() || !(target->isPlayerCreature() || target->isPet()))return nativePower;
  if(pack->isPetStimPack() || pack->isDroidRepairKit())return nativePower;
  if(pack->isRangedStimPack())return combatStim(healer,target,pack,applyBattleFatigue);
  int tier=corecu::doctorcare::stimTier(pack->getObjectTemplate()->getFullTemplateString().toCharArray());
  if(tier<0)return injury(healer,target,nativePower,true,applyBattleFatigue);
  int amount=corecu::doctorcare::stim(target->getMaxHAM(0)-target->getWounds(0),tier,pack->getEffectiveness(),healer->getSkillMod("healing_injury_treatment"));
  return corecu::doctorcare::potency(amount,doctorStage(healer))*(applyBattleFatigue?target->calculateBFRatio():1.);
 }
 static int combatStim(CreatureObject* healer,CreatureObject* target,StimPack* pack,bool applyBattleFatigue=true){
  if(!pack)return 0;
  auto spec=corecu::combatmedichealing::stim(pack->getObjectTemplate()->getFullTemplateString().toCharArray());
  if(!healer->isPlayerCreature() || !(target->isPlayerCreature() || target->isPet()) || spec.tier<0)
   return injury(healer,target,pack->calculatePower(healer,target,applyBattleFatigue),false,applyBattleFatigue);
  int amount=corecu::combatmedichealing::heal(target->getMaxHAM(0)-target->getWounds(0),spec,pack->getEffectiveness(),healer->getSkillMod("combat_medic_effectiveness"));
  return amount*(applyBattleFatigue?target->calculateBFRatio():1.);
 }
 static double combatStimRange(CreatureObject* healer,StimPack* pack){return pack?pack->getRange()+14.*healer->getSkillMod("healing_range")/100.:0.;}
 static int mindTransferCapacity(CreatureObject* healer,CreatureObject* target,bool applyBattleFatigue=true){
  if(!healer || !target)return 0;
  return corecu::combatmedichealing::mindCapacity(target->getMaxHAM(6)-target->getWounds(6),healer->getSkillMod("combat_medic_effectiveness"))*(applyBattleFatigue?target->calculateBFRatio():1.);
 }
 static int mindTransferAvailable(CreatureObject* healer,CreatureObject* target){
  if(!healer || !target || healer==target)return 0;
  return corecu::combatmedichealing::transferLimit(mindTransferCapacity(healer,target),target->getMaxHAM(6)-target->getWounds(6)-target->getHAM(6),healer->getHAM(6));
 }
 static int mindTransferInput(CreatureObject* healer,CreatureObject* target){
  return corecu::combatmedichealing::transferInput(mindTransferAvailable(healer,target),SwgxrSpice::active(healer,"crash_n_burn"));
 }
 static int tend(CreatureObject* healer,CreatureObject* target,int nativePower){return healer->isPlayerCreature() && (target->isPlayerCreature() || target->isPet())?corecu::doctorcare::potency(corecu::medicine::tend(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment")),doctorStage(healer))*target->calculateBFRatio():nativePower;}
 static int emergency(CreatureObject* healer,CreatureObject* target,int nativePower){return healer->isPlayerCreature() && (target->isPlayerCreature() || target->isPet())?corecu::doctorcare::emergencyPotency(corecu::medicine::emergency(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment")),doctorStage(healer))*target->calculateBFRatio():nativePower;}
 static int woundPack(CreatureObject* healer,CreatureObject* target,int attribute,double quality){
  return corecu::doctorcare::woundPotency(corecu::medicine::woundPack(target->getBaseHAM(attribute),healer->getSkillMod("healing_wound_treatment"),quality),doctorStage(healer))*target->calculateBFRatio();
 }
};
