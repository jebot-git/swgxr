#pragma once
#include "CoreCuMedicalPolicy.h"
#include "SwgxrSpice.h"
// Native command policy, shared by ordinary Core3 commands and the VR bridge.
class CoreCuMedicine {
public:
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
 static int injury(CreatureObject* healer,CreatureObject* target,int nativePower){
  if(!healer->isPlayerCreature() || !(target->isPlayerCreature() || target->isPet()))return nativePower;
  return corecu::medicine::injury(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment"),nativePower/(600.*std::max(.001,double(target->calculateBFRatio()))))*target->calculateBFRatio();
 }
 static int tend(CreatureObject* healer,CreatureObject* target,int nativePower){return healer->isPlayerCreature() && (target->isPlayerCreature() || target->isPet())?corecu::medicine::tend(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment"))*target->calculateBFRatio():nativePower;}
 static int emergency(CreatureObject* healer,CreatureObject* target,int nativePower){return healer->isPlayerCreature() && (target->isPlayerCreature() || target->isPet())?corecu::medicine::emergency(target->getMaxHAM(0)-target->getWounds(0),healer->getSkillMod("healing_injury_treatment"))*target->calculateBFRatio():nativePower;}
};
