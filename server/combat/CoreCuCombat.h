#pragma once
#include "CoreCuPolicy.h"
#include "CoreCuProfessions.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/creature/commands/effect/CommandEffect.h"
#include "templates/params/creature/CreatureState.h"
#include "server/zone/objects/creature/buffs/Buff.h"
#include <array>
#include <string>

class CoreCuCombat {
public:
 static std::array<double,corecu::StatusCount> ratings(CreatureObject* c){
  std::array<double,corecu::StatusCount> strongest{},total{};
  if(!c)return total;
  if(c->isAiAgent()){total.fill(corecu::clamp(c->getLevel()*.5,0,100));return total;}
  if(!c->isPlayerCreature())return total;
  Vector<String> skills;c->getSkillList()->getStringList(skills);
  for(const auto& p:corecu::PROFESSIONS){
   double progress=0;
   for(int i=0;i<skills.size();++i){
    progress+=corecu::progressWeight(p.name,skills.get(i).toCharArray());
   }
   for(int i=0;i<corecu::StatusCount;++i){double value=p.ratings[i]*corecu::clamp(progress,0,1);total[i]+=value;strongest[i]=std::max(strongest[i],value);}
  }
  for(int i=0;i<corecu::StatusCount;++i)total[i]=corecu::combinedRating(strongest[i],total[i]-strongest[i]);
  return total;
 }
 static int stateIndex(int effect){
  switch(effect){case CommandEffect::STUN:return corecu::Stun;case CommandEffect::BLIND:return corecu::Blind;
   case CommandEffect::DIZZY:return corecu::Dizzy;case CommandEffect::INTIMIDATE:return corecu::Intimidate;
   case CommandEffect::KNOCKDOWN:case CommandEffect::POSTUREUP:case CommandEffect::POSTUREDOWN:return corecu::Knockdown;
   case CommandEffect::NEXTATTACKDELAY:return corecu::Snare;default:return -1;}
 }
 static int dotIndex(uint64 type){switch(type){case CreatureState::BLEEDING:return corecu::Bleed;case CreatureState::POISONED:return corecu::Poison;case CreatureState::DISEASED:return corecu::Disease;case CreatureState::ONFIRE:return corecu::Fire;default:return -1;}}
 static double trapBonus(CreatureObject* c){
  int scout=0,ranger=0;for(int i=1;i<=4;++i){scout+=c->hasSkill(String(("outdoors_scout_tools_0"+std::to_string(i)).c_str()))?1:0;ranger+=c->hasSkill(String(("outdoors_ranger_support_0"+std::to_string(i)).c_str()))?1:0;}
  return corecu::trapSuccessBonus(c->hasSkill("outdoors_scout_novice"),scout,ranger,c->hasSkill("outdoors_ranger_master"));
 }
 static double rating(CreatureObject* c,int index,double existing=0){
  if(index<0 || !c)return existing;
  double debuff=0;auto trap=c->getBuff(STRING_HASHCODE("throw_trap_state_def_1"));
  static const char* mods[]={"stun_defense","blind_defense","dizzy_defense","intimidate_defense","knockdown_defense"};
  if(trap!=nullptr && index<5)debuff=trap->getSkillModifierValue(mods[index]);
  return corecu::weakenedRating(existing,ratings(c)[index],debuff);
 }
 static JSONSerializationType snapshot(CreatureObject* c){
  static const char* names[]={"stun","blind","dizzy","intimidate","knockdown","snare","bleed","poison","disease","fire"};
  auto values=ratings(c);JSONSerializationType out={{"name","CoreCU"},{"version",corecu::VERSION},{"revision",corecu::REVISION}};
  for(int i=0;i<corecu::StatusCount;++i)out["profession_resistance"][names[i]]={{"rating",values[i]},{"chance_reduction",corecu::statusReduction(values[i])},{"duration_reduction",corecu::statusReduction(values[i])}};
  return out;
 }
};
