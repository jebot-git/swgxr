#pragma once
#include "DoctorPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/creature/buffs/Buff.h"
#include "server/zone/objects/creature/buffs/BuffCRC.h"
#include "server/zone/objects/creature/BuffAttribute.h"
// Native single-group replacement and migration; never refills current HAM.
class SwgxrDoctorPreparation {
public:
 static int strength(Buff* buff,int attribute){if(!buff)return 0;attribute=corecu::doctor::canonical(attribute);return attribute==2?buff->getSkillModifierValue("private_swgxr_metabolic_regen"):corecu::doctor::protection(attribute)?buff->getSkillModifierValue(BuffAttribute::getProtectionString(attribute)):buff->getAttributeModifierValue(attribute);}
 static int bounded(CreatureObject* c,int a,int value){a=corecu::doctor::canonical(a);return std::max(0,std::min(value,a==2?1500:corecu::doctor::protection(a)?25:int(c->getBaseHAM(a)*.15)));}
 static void apply(CreatureObject* c,int a,int value,float duration,int absorption=0){
  a=corecu::doctor::canonical(a);if(!c || (!corecu::doctor::general(a) && !corecu::doctor::protection(a)) || duration<=0)return;
  value=bounded(c,a,value);int ham[9];for(int i=0;i<9;++i)ham[i]=c->getHAM(i);
  Reference<Buff*> next=new Buff(c,BuffCRC::getMedicalBuff(a),duration,BuffType::MEDICAL);
  next->setFillAttributesOnBuff(false);next->setSkillModifier("private_swgxr_preparation_version",1);
  if(a==2)next->setSkillModifier("private_swgxr_metabolic_regen",value);
  else if(corecu::doctor::protection(a)){next->setSkillModifier(BuffAttribute::getProtectionString(a),value);next->setSkillModifier(BuffAttribute::getAbsorptionString(a),std::max(0,std::min(10,absorption)));}
  else next->setAttributeModifier(a,value);
  // All command validation precedes this transaction. Different families are intentional replacements.
  for(int i=0;i<11;++i)if(corecu::doctor::protection(a)?corecu::doctor::protection(i):corecu::doctor::general(i))c->removeBuff(BuffCRC::getMedicalBuff(i));
  c->addBuff(next);
  for(int i=0;i<9;++i)c->setHAM(i,std::min(ham[i],std::max(1,c->getMaxHAM(i)-c->getWounds(i))));
 }
 static void normalize(CreatureObject* c){
  if(!c || !(c->isPlayerCreature() || c->isPet()))return;
  for(int group=0;group<2;++group){int count=0,best=-1,value=0,absorption=0;double score=-1;float remaining=0;bool legacy=false;
   for(int a=0;a<11;++a){if(group? !corecu::doctor::protection(a):!corecu::doctor::general(a))continue;auto old=c->getBuff(BuffCRC::getMedicalBuff(a));if(!old)continue;++count;
    bool current=old->getSkillModifierValue("private_swgxr_preparation_version")>0;legacy|=!current;int canonical=corecu::doctor::canonical(a);
    int amount=current?strength(old,a):corecu::doctor::protection(a)?old->getSkillModifierValue(BuffAttribute::getProtectionString(a)):old->getAttributeModifierValue(a);
    if(!current && canonical==2)amount=int(std::round(10000.*amount/std::max(1,c->getBaseHAM(a))));
    amount=bounded(c,canonical,amount);double rank=corecu::doctor::appliedPercent(canonical,c->getBaseHAM(group?0:canonical),amount);
    if(rank>score || (rank==score && old->getTimeLeft()>remaining)){score=rank;best=canonical;value=amount;remaining=old->getTimeLeft();absorption=group?old->getSkillModifierValue(BuffAttribute::getAbsorptionString(a)):0;}
   }
   if(best>=0 && (legacy || count>1) && remaining>0)apply(c,best,value,remaining,absorption);
  }
 }
};
