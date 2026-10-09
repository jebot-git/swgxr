#ifndef SWGXR_SKILL_FORGETTING_H
#define SWGXR_SKILL_FORGETTING_H
#include "server/zone/managers/skill/SkillManager.h"
#include <set>
// The original skill graph, modifiers, certificates and point accounting remain
// SkillManager-owned. Never recursively surrender prerequisites or refund XP.
class SwgxrSkillForgetting {
 using Json=JSONSerializationType;
 static std::string text(const String& name){return name.toCharArray();}
 static bool supported(Skill* skill){
  if(!skill || skill->isHidden() || skill->isGodOnly())return false;
  std::set<std::string> seen;auto parent=SkillManager::instance()->getSkill(skill->getParentName());
  while(parent && seen.insert(text(parent->getSkillName())).second){if(parent->isSkill())return !parent->isHidden() && !parent->isGodOnly();parent=SkillManager::instance()->getSkill(parent->getParentName());}
  return false;
 }
 static bool depends(Skill* skill,const std::string& target,std::set<std::string>& seen){
  if(!skill || !seen.insert(text(skill->getSkillName())).second)return false;
  auto requirements=skill->getSkillsRequired();
  for(int i=0;i<requirements->size();++i){auto required=requirements->get(i);if(text(required)==target || depends(SkillManager::instance()->getSkill(required),target,seen))return true;}
  return false;
 }
public:
 static Json row(CreatureObject* c,const std::string& name){
  Json blockers=Json::array();auto skill=SkillManager::instance()->getSkill(String(name.c_str()));std::string reason;
  if(!supported(skill))reason="This skill cannot be forgotten here.";
  else if(!c->hasSkill(String(name.c_str())))reason="This skill is not learned.";
  else {
   auto learned=c->getSkillList();for(int i=0;i<learned->size();++i){auto other=learned->get(i);if(other==skill)continue;std::set<std::string> seen;if(depends(other,name,seen))blockers.push_back(text(other->getSkillName()));}
   if(!blockers.empty())reason="Forget the learned skills that depend on this skill first.";
   else if(c->isDead() || c->isIncapacitated() || c->isInCombat())reason="Leave combat before forgetting a skill.";
  }
  return {{"skill_id",name},{"eligible",reason.empty()},{"reason",reason},{"refunded_points",skill?skill->getSkillPointsRequired():0},{"blocking_skills",blockers}};
 }
 static Json snapshot(CreatureObject* c){
  Json out=Json::array();auto list=c->getSkillList();for(int i=0;i<list->size();++i){auto name=text(list->get(i)->getSkillName());if(supported(list->get(i)))out.push_back(row(c,name));}return out;
 }
 static Json forget(CreatureObject* c,const std::string& name){
  auto eligibility=row(c,name);if(!eligibility["eligible"].get<bool>())throw std::runtime_error(eligibility["reason"].get<std::string>());
  auto ghost=c->getPlayerObject();int before=ghost->getSkillPoints();
  if(!SkillManager::instance()->surrenderSkill(String(name.c_str()),c,true,true,true) || c->hasSkill(String(name.c_str())))throw std::runtime_error("native_skill_forgetting_rejected");
  return {{"skill_id",name},{"refunded_points",ghost->getSkillPoints()-before},{"skill_points",ghost->getSkillPoints()},{"message","Skill forgotten. Skill points returned; training credits and experience are not refunded."}};
 }
};
#endif
