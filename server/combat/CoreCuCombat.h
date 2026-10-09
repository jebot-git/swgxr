#pragma once
#include "CoreCuPolicy.h"
#include "SwgxrSquadLeader.h"
#include "CoreCuProfessions.h"
#include "TkaPolicy.h"
#include "SwordsmanPolicy.h"
#include "FencerPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/objects/tangible/weapon/WeaponObject.h"
#include "server/zone/objects/creature/commands/effect/CommandEffect.h"
#include "templates/params/creature/CreatureState.h"
#include "server/zone/objects/creature/buffs/Buff.h"
#include "server/zone/objects/creature/buffs/BuffCRC.h"
#include "server/zone/managers/skill/SkillModManager.h"
#include <array>
#include <string>

class CoreCuCombat {
public:
 static bool boss(CreatureObject* c){
  if(!c)return false;if(corecu::swordsman::boss(c->getLevel(),c->getSkillMod("swgxr_boss")>0))return true;
  auto ai=c->isAiAgent()?c->asAiAgent():nullptr;auto t=ai?ai->getCreatureTemplate():nullptr;
  return t && corecu::swordsman::namedBoss(t->getTemplateName().toCharArray());
 }
 static double bodyResistance(CreatureObject* c,int channel,double resistance){return corecu::swordsman::fracturedResistance(resistance,channel,c && c->hasBuff(STRING_HASHCODE("swgxr_fractured_armour")));}
 static bool tkaFocus(CreatureObject* c){return c && c->getWeapon() && c->getWeapon()->isUnarmedWeapon() && c->getWeapon()->isCertifiedFor(c) && c->hasSkill("combat_unarmed_master") && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_indomitable_focus"));}
 static int centerDefense(CreatureObject* c){return corecu::tka::center(c->getSkillMod("private_center_of_being"),c->getSkillMod("unarmed_center_of_being_efficacy"),tkaFocus(c));}
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
  for(int i=0;i<corecu::StatusCount;++i)total[i]=corecu::tka::resistance(corecu::combinedRating(strongest[i],total[i]-strongest[i]),tkaFocus(c));
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
 // Read the actual active medical modifier even before saved-buff migration.
 // Strip its full legacy value from native defenses, then bound the independent bonus.
 static int preparationContribution(CreatureObject* c,int index){
  if(!c || (index!=corecu::Poison && index!=corecu::Disease))return 0;
  auto buff=c->getBuff(BuffCRC::getMedicalBuff(index==corecu::Poison?9:10));
  return buff?std::max(0,buff->getSkillModifierValue(index==corecu::Poison?"resistance_poison":"resistance_disease")):0;
 }
 static double preparation(CreatureObject* c,int index){return corecu::clamp(preparationContribution(c,index),0,25);}
 // Producer contract: addDotState's defense is raw native defense EXCLUDING the
 // Doctor contribution. Each matching modifier is stripped at its read site.
 static int rawModifier(CreatureObject* c,const String& name){
  if(!c)return 0;int value=c->getSkillMod(name),own=0;
  if(name=="resistance_poison")own=preparationContribution(c,corecu::Poison);
  else if(name=="resistance_disease")own=preparationContribution(c,corecu::Disease);
  if(own>0){
   // The native BUFF bucket is capped (normally +/-125). Recalculate that
   // bucket without this buff rather than subtracting its uncapped saved value.
   auto manager=SkillModManager::instance();int low=manager->getMinSkill(SkillModManager::BUFF),high=manager->getMaxSkill(SkillModManager::BUFF);
   auto bounded=[&](int amount){return low && high?(amount>=0?std::min(amount,high):std::max(amount,low)):amount;};
   int bucket=c->getSkillModOfType(name,SkillModManager::BUFF);
   value=value-bounded(bucket)+bounded(bucket-own);
  }
  return value;
 }
 static double nativeDefense(CreatureObject* c,int index){
  if(!c)return 0;
  static const char* mods[]={"stun_defense","blind_defense","dizzy_defense","intimidate_defense","knockdown_defense","resistance_states","combat_bleeding_defense","resistance_poison","resistance_disease","resistance_fire"};
  if(index<0 || index>=corecu::StatusCount)return 0;
  double value=rawModifier(c,mods[index]);
  if(index==corecu::Poison || index==corecu::Disease)value+=c->getSkillMod("poison_disease_resist");
  if(index==corecu::Bleed)value=std::max(value,double(c->getSkillMod("bleeding_defense")));
  if(index==corecu::Snare)value=std::max(value,double(c->getSkillMod("warcry_defense")));
  return value;
 }
 static double baseline(CreatureObject* c,int index,double existing=0){
  if(index<0 || index>=corecu::StatusCount || !c)return corecu::statusBaseline(existing);
  double debuff=0;auto trap=c->getBuff(STRING_HASHCODE("throw_trap_state_def_1"));
  static const char* mods[]={"stun_defense","blind_defense","dizzy_defense","intimidate_defense","knockdown_defense"};
  if(trap!=nullptr && index<5)debuff=trap->getSkillModifierValue(mods[index]);
  // Scripted and command DoTs also receive canonical native protection, even
  // when their producer supplied zero or a different defense modifier.
  if(index==corecu::Poison || index==corecu::Disease)existing=std::max(existing,nativeDefense(c,index));
  existing=corecu::tka::resistance(corecu::statusBaseline(existing),tkaFocus(c));
  return SwgxrSquadLeader::statusRating(c,corecu::fencer::exposed(corecu::weakenedRating(existing,ratings(c)[index],debuff),index,c->hasBuff(STRING_HASHCODE("swgxr_exposed_thrust"))));
 }
 static double rating(CreatureObject* c,int index,double existing=0){
  return corecu::preparedRating(baseline(c,index,existing),preparation(c,index));
 }
 static JSONSerializationType snapshot(CreatureObject* c){
  static const char* names[]={"stun","blind","dizzy","intimidate","knockdown","snare","bleed","poison","disease","fire"};
  auto values=ratings(c);JSONSerializationType out={{"name","CoreCU"},{"version",corecu::VERSION},{"revision",corecu::REVISION}};
  out["status_curve"]={{"denominator",150},{"reduction_cap",.50},{"baseline_rating_cap",100},{"preparation_rating_cap",25}};
  for(int i=0;i<corecu::StatusCount;++i){
   out["profession_resistance"][names[i]]={{"rating",values[i]},{"chance_reduction",corecu::statusReduction(values[i])},{"duration_reduction",corecu::statusReduction(values[i])}};
   double native=nativeDefense(c,i),base=baseline(c,i,native),bonus=preparation(c,i),effective=corecu::preparedRating(base,bonus);
   out["effective_resistance"][names[i]]={{"defense_context","standard_native_modifiers"},{"profession_rating",values[i]},{"native_rating",corecu::statusBaseline(native)},{"baseline_rating",base},{"preparation_rating",bonus},{"rating",effective},{"chance_reduction",corecu::statusReduction(effective)},{"duration_reduction",corecu::statusReduction(effective)}};
  }
  return out;
 }
};
