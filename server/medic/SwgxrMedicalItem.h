#pragma once
#include "CoreCuMedicalPolicy.h"
#include "server/zone/objects/tangible/pharmaceutical/StimPack.h"
#include "server/zone/objects/tangible/pharmaceutical/RangedStimPack.h"
#include "server/zone/objects/tangible/pharmaceutical/WoundPack.h"
#include "server/zone/objects/tangible/pharmaceutical/CurePack.h"
#include "server/zone/objects/tangible/pharmaceutical/StatePack.h"
#include "server/zone/objects/tangible/pharmaceutical/EnhancePack.h"
#include "server/zone/objects/tangible/pharmaceutical/RevivePack.h"
#include "server/zone/objects/creature/BuffAttribute.h"
// Item type selects the command and attribute on the server, never in a client payload.
class SwgxrMedicalItem {
public:
 static String command(PharmaceuticalObject* p){
  if(!p || corecu::medicine::retiredMedicalTemplate(p->getObjectTemplate()->getFullTemplateString().toCharArray()))return "";
  if(p->isPetStimPack())return "healpet";
  if(p->isDroidRepairKit())return "healdroiddamage";
  if(p->isDroidReconstructionKit())return "healdroidwound";
  if(p->isStimPack() || p->isRangedStimPack())return "healdamage";
  if(p->isWoundPack())return "healwound";
  if(p->isEnhancePack())return "healenhance";
  if(p->isStatePack())return "healstate";
  if(p->isRevivePack())return "reviveplayer";
  if(p->isCurePack()){
   auto state=static_cast<CurePack*>(p)->getState();
   return state==CreatureState::POISONED?"curepoison":state==CreatureState::DISEASED?"curedisease":state==CreatureState::ONFIRE?"extinguishfire":"";
  }return "";
 }
 static String arguments(PharmaceuticalObject* p){
  String prefix;
  if(p->isWoundPack() && !p->isDroidReconstructionKit())prefix=CreatureAttribute::getName(static_cast<WoundPack*>(p)->getAttribute())+"|";
  if(p->isEnhancePack())prefix=BuffAttribute::getName(static_cast<EnhancePack*>(p)->getAttribute())+"|";
  if(p->isStatePack())prefix=CreatureState::instance()->getName(static_cast<StatePack*>(p)->getState())+"|";
  return prefix+String::valueOf(p->getObjectID());
 }
 static bool owned(CreatureObject* c,SceneObject* p){
  // Inventory and worn backpacks, excluding bank, datapad, factories and crates.
  if(!c || !p || p->isFactoryCrate())return false;
  auto root=c->getSlottedObject("inventory");
  auto parent=p->getParent().get();
  for(int n=0;parent && parent!=c && n<12;++n){
   if(parent->isFactoryCrate() || parent->isCraftingTool() || parent->isManufactureSchematic())return false;
   if(parent==root || (parent->isWearableContainerObject() && parent->getParent().get()==c))return true;
   parent=parent->getParent().get();
  }return false;
 }
 static float range(PharmaceuticalObject* p,CreatureObject* c){return p->isRangedStimPack()?static_cast<RangedStimPack*>(p)->getRange()+c->getSkillMod("healing_range")*.14f:2.5f;}
 static bool trained(CreatureObject* c,PharmaceuticalObject* p){
  if(p->isDroidReconstructionKit())return c->hasSkill("crafting_droidengineer_novice");
  if(p->isDroidRepairKit() || p->isPetStimPack())return true; // Native kits require no Medic profession.
  return c->hasSkill("science_medic_novice") && c->getSkillMod(p->isRangedStimPack()?"combat_healing_ability":"healing_ability")>=p->getMedicineUseRequired();
 }
 static bool recipient(PharmaceuticalObject* p,CreatureObject* target){
  if(p->isDroidRepairKit() || p->isDroidReconstructionKit())return target->isPet() && target->isDroidObject();
  if(p->isPetStimPack())return target->isPet() && target->isCreature() && !target->isDroidObject();
  if(p->isRevivePack())return target->isPlayerCreature();
  return target->isPlayerCreature() || (target->isPet() && target->isCreature() && !target->isDroidObject());
 }
 static bool needed(PharmaceuticalObject* p,CreatureObject* target){
  if(!recipient(p,target))return false;
  if(p->isDroidReconstructionKit())return !target->isDead() && target->getWounds(0)>0;
  if(p->isRevivePack())return target->isDead();
  if(target->isDead())return false;
  if(p->isWoundPack())return target->getWounds(static_cast<WoundPack*>(p)->getAttribute())>0;
  if(p->isCurePack())return target->hasState(static_cast<CurePack*>(p)->getState());
  if(p->isStatePack())return target->hasState(static_cast<StatePack*>(p)->getState());
  return p->isEnhancePack() || target->hasDamage(0);
 }
};
