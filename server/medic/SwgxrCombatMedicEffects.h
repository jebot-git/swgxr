#pragma once
#include "CombatMedicPolicy.h"
#include "CoreCuCombat.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "SwgxrMedicalItem.h"
#include "SwgxrSpice.h"
#include "server/zone/objects/tangible/pharmaceutical/DotPack.h"

class SwgxrCombatMedicEffects {
public:
 static String command(DotPack* p){return !p?"":p->isPoisonDeliveryUnit()?"applypoison":p->isDiseaseDeliveryUnit()?"applydisease":"";}
 static bool eligible(CreatureObject* c,CreatureObject* target,DotPack* p){
  if(!c || !target || !p || target==c || target->getZone()!=c->getZone() || target->isDead() || !target->isAttackableBy(c) || target->hasDotImmunity(p->getDotType()))return false;
  auto ai=target->isAiAgent()?target->asAiAgent():nullptr;
  return !(ai && (ai->getCreatureBitmask() & ObjectFlag::NODOT)) && CollisionManager::checkLineOfSight(c,target);
 }
 static bool learned(CreatureObject* c,bool disease){return c && c->isPlayerCreature() && c->hasSkill("science_combatmedic_novice") && (!disease || c->hasSkill("science_combatmedic_healing_range_02"));}
 static bool compatible(CreatureObject* c,DotPack* p,bool disease){
  return learned(c,disease) && p && SwgxrMedicalItem::owned(c,p) && p->getUseCount()>0
   && !corecu::medicine::retiredMedicalTemplate(p->getObjectTemplate()->getFullTemplateString().toCharArray())
   && c->getSkillMod("combat_healing_ability")>=p->getMedicineUseRequired()
   && (disease?p->isDiseaseDeliveryUnit():p->isPoisonDeliveryUnit())
   && p->getPool()==(disease?CreatureAttribute::ACTION:CreatureAttribute::HEALTH);
 }
 static double progression(CreatureObject* c){return corecu::combatmedic::progress(c->getSkillMod("combat_medic_effectiveness"));}
 static double applicationQuality(DotPack* p){return corecu::combatmedic::applicationQuality(p->getPotency());}
 static double rawPotency(CreatureObject* c,DotPack* p){return corecu::combatmedic::rawPotency(c->getSkillMod("combat_medic_effectiveness"),applicationQuality(p));}
 static int duration(CreatureObject* c,DotPack* p){return corecu::combatmedic::duration(p->isDiseaseDeliveryUnit(),c->getSkillMod("combat_medic_effectiveness"),p->getDuration());}
 static double range(CreatureObject* c,DotPack* p){return corecu::combatmedic::range(p->getRange(),c->getSkillMod("healing_range"));}
 static double radius(DotPack* p){return p->isArea()?corecu::combatmedic::radius(p->getArea()):0.;}
 static int recovery(CreatureObject* c){auto b=c->getBuff(BuffCRC::FOOD_HEAL_RECOVERY);return corecu::combatmedic::recovery(c->getSkillMod("healing_range_speed"),b?b->getSkillModifierValue("heal_recovery"):0,SwgxrSpice::cooldownScale(c));}
 static const char* key(){return "corecu_combat_medicine";}
 static double remaining(CreatureObject* c){auto t=c->getCooldownTime(key());return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static int actionCost(CreatureObject* c){return corecu::combatmedic::cost(c->getBaseHAM(CreatureAttribute::ACTION),.06);}
 static int mindCost(CreatureObject* c){return corecu::combatmedic::cost(c->getBaseHAM(CreatureAttribute::MIND),.08);}
 static bool resources(CreatureObject* c){return c->getHAM(CreatureAttribute::ACTION)>actionCost(c) && c->getHAM(CreatureAttribute::MIND)>mindCost(c);}
 static int strength(CreatureObject* c,CreatureObject* target,DotPack* p){return p->isDiseaseDeliveryUnit()
  ?corecu::combatmedic::diseasePulse(target->getBaseHAM(CreatureAttribute::ACTION),c->getSkillMod("combat_medic_effectiveness"),p->getEffectiveness(),p->isArea())
  :corecu::combatmedic::poisonBudget(target->getMaxHAM(CreatureAttribute::HEALTH)-target->getWounds(CreatureAttribute::HEALTH),c->getBaseHAM(CreatureAttribute::HEALTH),c->getSkillMod("combat_medic_effectiveness"),p->getEffectiveness(),p->isArea(),p->getDuration());}
};
