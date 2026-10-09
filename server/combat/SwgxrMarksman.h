#pragma once
#include "MarksmanPolicy.h"
#include "SwgxrBountyHunter.h"
#include "CoreCuCombat.h"
#include "CombatQueueCommand.h"
#include "SwgxrSpice.h"
#include "SwgxrPistoleer.h"
#include "SwgxrCarbineer.h"
class SwgxrMarksman {
 using Json=JSONSerializationType;
public:
 static bool bleedImproved(CreatureObject* c){return c->hasSkill("combat_pistol_novice") && c->getPlayerObject() && c->getPlayerObject()->hasAbility("healthShot2");}
 static bool bountyBleed(CreatureObject* c){return !bleedImproved(c) && SwgxrBountyHunter::learned(c,"bleeding_shot");}
 static double bleedFraction(CreatureObject* c){return corecu::bountyhunter::bleedFraction(bleedImproved(c),bountyBleed(c),c->getPlayerObject() && c->getPlayerObject()->hasAbility("torsoShot"));}
 static int actionCost(CreatureObject* c,const std::string& id){return id=="bleeding_shot" && bountyBleed(c)?55:corecu::marksman::ability(id).action;}
 static double damage(CreatureObject* c,const std::string& id){return id=="bleeding_shot" && bleedImproved(c)?1.:corecu::marksman::ability(id).damage;}
 static bool learned(CreatureObject* c,const std::string& id){if(id=="suppression_fire" && SwgxrCarbineer::compatible(c) && SwgxrCarbineer::suppressionTrained(c))return true;auto a=corecu::marksman::ability(id);return *a.skill && c->hasSkill("combat_marksman_novice") && c->hasSkill(a.skill);}
 static bool compatible(CreatureObject* c,const std::string& id){auto w=c->getWeapon();return w && w->isCertifiedFor(c) && !w->isBroken() && corecu::marksman::compatible(id,w->isRangedWeapon(),w->isPistolWeapon(),w->isCarbineWeapon());}
 static bool targetReady(CreatureObject* a,const std::string& id){
  if(!a || !a->isAiAgent() || a->asAiAgent()->isPet() || a->isDead() || a->isIncapacitated())return false;
  if(corecu::marksman::ability(id).control && !a->checkCooldownRecovery("corecu_control_recovery"))return false;
  if(id=="warning_shot")return !CoreCuCombat::boss(a) && !a->hasEffectImmunity(CommandEffect::NEXTATTACKDELAY) && !a->hasAttackDelay() && a->checkCooldownRecovery("nextAttackDelayRecovery");
  if(id=="suppression_fire")return !a->hasEffectImmunity(CommandEffect::BLIND) && !a->hasBuff(STRING_HASHCODE("swgxr_suppression_fire"));
  if(id=="bleeding_shot")return !a->isDroidObject() && !a->hasDotImmunity(CreatureState::BLEEDING);
  return corecu::marksman::contains(id);
 }
 static double interval(CreatureObject* c,const std::string& id){return corecu::marksman::ability(id).cooldown*SwgxrSpice::cooldownScale(c);}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("swgxr_smuggler_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static Json abilities(CreatureObject* c){
  Json out=Json::array();auto w=c->getWeapon();auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));if(!source)return out;
  for(auto id:{"suppression_fire","warning_shot","controlled_burst","bleeding_shot"}){
   if(!learned(c,id) || !compatible(c,id))continue;auto a=corecu::marksman::ability(id);std::string key=id;const bool boosted=SwgxrPistoleer::active(c);
   Json row={{"id",id},{"label",a.label},{"activation","native_ranged"},{"ultimate",false},{"source_command","attack"},{"native_authority",true},{"sac_policy","fixed"},{"base_sac",{{"health",0},{"action",corecu::pistoleer::cost(actionCost(c,id),boosted,id)},{"mind",corecu::pistoleer::cost(a.mind,boosted,id)}}},{"conditions_met",source->checkStateMask(c) && source->checkInvalidLocomotions(c)},{"max_range_m",w->getMaxRange()},{"min_range_m",0},{"damage_multiplier",damage(c,id)},{"interval_seconds",SwgxrPistoleer::interval(c,id)},{"hit_count",a.blows},{"cooldown_seconds",interval(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"requires_control_available",a.control},{"excludes_bosses",key=="warning_shot"}};
   row["weapon_requirement"]=key=="controlled_burst"?"Certified carbine; Marksman Carbine II.":key=="bleeding_shot"?"Certified pistol; Marksman Pistol IV.":"Certified ranged weapon; Marksman support training.";
   row["description"]=key=="suppression_fire"?"Light hit and -20 enemy accuracy for up to 6 seconds, resisted as Blind. Single target; shared control recovery applies.":key=="warning_shot"?"Merged Threaten/Warning Shot: light hit and a resisted attack hesitation, 2 seconds at Support I or 3 at Support III. Retains enemy threat; bosses immune. Shared control recovery applies.":key=="controlled_burst"?"One aimed contact resolves three 0.65x native damage hits against the selected enemy. Each retains normal dodge/block; Action, Mind and cooldown are paid once. No blind, dizzy or stun.":"Moderate hit and a resisted Health bleed budget of 30% of landed damage over at most 12 seconds. Shares the non-stacking Fencer bleed channel; stronger remaining budget wins. Droids immune.";
   if(key=="suppression_fire" && SwgxrCarbineer::compatible(c) && SwgxrCarbineer::suppressionTrained(c)){row["carbineer_upgrade"]=true;row["weapon_requirement"]="Certified carbine; Carbineer Suppression Fire II. Marksman support training is optional.";row["description"]="Carbineer upgrade: light hit and -25 enemy accuracy for up to 6 seconds, resisted as Blind. Same Suppression Fire cooldown and shared control recovery.";}
   if(key=="bleeding_shot"){row["bleed_budget_fraction"]=bleedFraction(c);row["bountyhunter_upgrade"]=bountyBleed(c);if(bountyBleed(c))row["anatomical_part"]="abdomen";if(bountyBleed(c)){row["label"]=c->getPlayerObject()->hasAbility("torsoShot")?"Torso Shot":"Bleeding Shot";row["description"]="Bounty Hunter: 0.8x direct damage and a resisted 40–45% landed-damage Health bleed budget, sharing the existing non-stacking bleed channel.";}row["pistoleer_upgrade"]=bleedImproved(c);if(bleedImproved(c))row["description"]="Pistoleer Health Shot II upgrade: 1.0x direct damage plus a resisted 40% Health bleed budget over at most 12 seconds. Same Bleeding Shot cooldown and shared Fencer channel; stronger remaining budget wins.";}
   out.push_back(row);
  }return out;
 }
 static void effects(CreatureObject* c,CreatureObject* a,const std::string& id,int damage){
  if(damage<=0 || !targetReady(a,id) || id=="controlled_burst")return;
  const bool bleed=id=="bleeding_shot",suppression=id=="suppression_fire";
  auto spec=corecu::marksman::ability(id);
  int existing=a->getSkillMod(bleed?"bleeding_defense":suppression?"blind_defense":"warcry_defense");
  double rating=CoreCuCombat::rating(a,bleed?corecu::Bleed:suppression?corecu::Blind:corecu::Snare,existing);
  if(spec.control)a->addCooldown("corecu_control_recovery",8000);
  if(System::random(99)>=(spec.control?SwgxrCarbineer::chance(c,rating):(bountyBleed(c)?SwgxrBountyHunter::chance(c,id,rating):corecu::statusChance(85,rating))))return;
  if(bleed){
   // Reuse the bounded shared channel, including native cures, absorption and tick-preserving refresh.
   int budget=int(std::max(0,damage)*bleedFraction(c));
   if(budget>0)a->addDotState(c,CreatureState::BLEEDING,STRING_HASHCODE("swgxr_fencer_bleed"),budget,0,corecu::marksman::BleedSeconds,-1,existing);
  }else if(suppression){
   ManagedReference<Buff*> buff=new Buff(a,STRING_HASHCODE("swgxr_suppression_fire"),corecu::statusDuration(corecu::marksman::SuppressionSeconds,rating),BuffType::STATE);Locker lock(buff,a);buff->setSkillModifier("private_accuracy_bonus",-(SwgxrCarbineer::compatible(c) && SwgxrCarbineer::suppressionTrained(c)?25:corecu::marksman::AccuracyPenalty));a->addBuff(buff);
  }else a->setNextAttackDelay(c,"swgxr_warning_shot",0,corecu::statusDuration(corecu::marksman::hesitationSeconds(c->hasSkill("combat_marksman_support_03")),rating));
 }
};
