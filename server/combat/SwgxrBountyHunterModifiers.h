#pragma once
#include "BountyHunterPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/creature/variables/Skill.h"
#include "server/zone/managers/skill/SkillModManager.h"
#include <map>
class SwgxrBountyHunterModifiers {
 static bool prefix(const std::string& s,const std::string& p){return s.rfind(p,0)==0;}
 static int capped(int value){auto manager=SkillModManager::instance();int lo=manager->getMinSkill(SkillModManager::SKILLBOX),hi=manager->getMaxSkill(SkillModManager::SKILLBOX);return lo && hi?(value>=0?std::min(value,hi):std::max(value,lo)):value;}
public:
 static int branch(CreatureObject* c,const String& mod){int sum=0;const auto list=c->getSkillList();for(int i=0;i<list->size();++i){auto skill=list->get(i);std::string name=skill->getSkillName().toCharArray();if(prefix(name,"combat_bountyhunter_") && name!="combat_bountyhunter_novice"){auto mods=skill->getSkillModifiers();if(mods->contains(mod))sum+=mods->get(mod);}}return sum;}
 static int modifier(CreatureObject* c,const String& mod,bool speed){
  const int original=c->getSkillMod(mod);if(!c->hasSkill("combat_bountyhunter_novice"))return original;
  std::string key=mod.toCharArray();if(key!=(speed?"pistol_speed":"pistol_accuracy") && key!=(speed?"carbine_speed":"carbine_accuracy") && key!=(speed?"heavy_rifle_lightning_speed":"heavy_rifle_lightning_accuracy"))return original;
  int base=0,bh=0;std::map<std::string,int> advanced;const auto list=c->getSkillList();
  for(int i=0;i<list->size();++i){auto skill=list->get(i);auto mods=skill->getSkillModifiers();if(!mods->contains(mod))continue;int value=mods->get(mod);std::string name=skill->getSkillName().toCharArray();
   if(prefix(name,"combat_bountyhunter_")){if(name!="combat_bountyhunter_novice")bh+=value;}
   else if(speed && prefix(name,"combat_") && !prefix(name,"combat_marksman_")){auto end=name.find('_',7);advanced[name.substr(0,end)]+=value;}
   else base+=value;
  }
  int strongest=0;for(const auto& entry:advanced)strongest=std::max(strongest,entry.second);
  int replacement=speed?corecu::bountyhunter::effectiveSpeed(base,strongest,corecu::bountyhunter::advancedSpeed(bh)):base;
  return original-capped(c->getSkillModOfType(mod,SkillModManager::SKILLBOX))+capped(replacement);
 }
 static bool nonBountyAbility(CreatureObject* c,const String& ability){if(!c->hasSkill("combat_bountyhunter_novice"))return c->getPlayerObject() && c->getPlayerObject()->hasAbility(ability);const auto list=c->getSkillList();for(int i=0;i<list->size();++i){auto skill=list->get(i);if(prefix(skill->getSkillName().toCharArray(),"combat_bountyhunter_"))continue;if(skill->getAbilities()->contains(ability))return true;}return false;}
 static double incoming(CreatureObject* defender,TangibleObject* attacker){if(!defender || !attacker || !defender->hasBuff(STRING_HASHCODE("swgxr_duelist_stance")))return 1.;auto ghost=defender->getPlayerObject();if(!ghost)return 1.;return ghost->getScreenPlayData("swgxr_bountyhunter","duelist_target")==String::valueOf(attacker->getObjectID())?corecu::bountyhunter::DuelistScale:1.;}
};
