#ifndef SWGXR_TRAINERS_H
#define SWGXR_TRAINERS_H
#include "SwgxrTrainerCatalog.h"
#include "SwgxrSkillForgetting.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/objects/creature/ai/CreatureTemplate.h"
#include "server/zone/managers/skill/SkillManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
// Presentation of the original trainer catalogue and native SkillManager rules.
// Mirrors skillTrainer.lua and trainerConvHandler.handleConfirmLearnScreen;
// never grants prerequisites or bypasses XP, species or skill-point checks.
class SwgxrTrainers {
 using Json=JSONSerializationType;
 static std::string str(const String& s){return s.toCharArray();}
public:
 static std::string type(SceneObject* o){
  if(o==nullptr || !o->isAiAgent())return "";
  auto source=o->asAiAgent()->getCreatureTemplate();if(source==nullptr)return "";
  auto name=str(source->getTemplateName());return swgxrTrainerCatalog().count(name)?name:"";
 }
 static Json experience(CreatureObject* c){Json out=Json::object();auto xp=c->getPlayerObject()->getExperienceList();for(int i=0;i<xp->size();++i)out[str(xp->getKeyAt(i))]=xp->get(xp->getKeyAt(i));return out;}
 static Json skills(CreatureObject* c){Json out=Json::array();auto list=c->getSkillList();for(int i=0;i<list->size();++i)out.push_back(str(list->get(i)->getSkillName()));return out;}
 static void validate(CreatureObject* c,SceneObject* npc){
  if(type(npc).empty() || npc->getZone()!=c->getZone() || npc->getParentID()!=c->getParentID())throw std::runtime_error("trainer_type_cell_or_distance");
  auto a=c->getPosition(),b=npc->getPosition();if((c->getParentID()?a.squaredDistanceTo(b):a.squaredDistanceTo2d(b))>25)throw std::runtime_error("trainer_type_cell_or_distance");
  if(npc->asAiAgent()->isDead() || npc->asAiAgent()->isIncapacitated() || !CollisionManager::checkLineOfSight(npc,c))throw std::runtime_error("trainer_unavailable_or_obstructed");
 }
 static Json row(CreatureObject* c,const std::string& name){
  auto manager=SkillManager::instance();String skillName(name.c_str());auto s=manager->getSkill(skillName);if(s==nullptr)throw std::runtime_error("native_trainer_skill_missing");auto ghost=c->getPlayerObject();
  int persuasion=c->getSkillMod("force_persuade");double raw=s->getMoneyRequired();if(persuasion>0)raw-=raw*persuasion/100.0;int cost=int(raw);auto xp=ghost->getExperience(s->getXpType());bool learned=c->hasSkill(skillName);std::string reason;
  if(learned)reason="Already learned.";
  else if(!manager->fulfillsSkillPrerequisites(skillName,c))reason="Required skills or species prerequisites are not met.";
  else if(xp<s->getXpCost())reason="Not enough experience of the required type.";
  else if(ghost->getSkillPoints()<s->getSkillPointsRequired())reason="Not enough available skill points.";
  else if(int64(c->getCashCredits())+c->getBankCredits()<raw)reason="Not enough carried and bank credits.";
  else if(!manager->canLearnSkill(skillName,c,false))reason="The original skill requirements are not met.";
  Json required=Json::array();auto prereq=s->getSkillsRequired();for(int i=0;i<prereq->size();++i)required.push_back(str(prereq->get(i)));
  return {{"id",name},{"name","@skl_n:"+name},{"description","@skl_d:"+name},{"learned",learned},{"eligible",reason.empty()},{"blocked_reason",reason},{"credit_cost",cost},{"skill_point_cost",s->getSkillPointsRequired()},{"xp_type",str(s->getXpType())},{"xp_name","@exp_n:"+str(s->getXpType())},{"xp_cost",s->getXpCost()},{"xp_available",xp},{"prerequisites",required}};
 }
 static void describe(CreatureObject* c,SceneObject* npc,Json& view){
  auto trainer=type(npc);view["trainer_type"]=trainer;view["profession"]=trainer.substr(8);view["trainer_text"]="@skill_teacher:"+trainer;view["skill_points"]=c->getPlayerObject()->getSkillPoints();view["skills"]=Json::array();bool complete=true;
  for(const auto& name:swgxrTrainerCatalog().at(trainer)){auto entry=row(c,name);if(!entry["learned"].get<bool>())complete=false;view["skills"].push_back(entry);}if(complete)view["trainer_text"]="@skill_teacher:topped_out";
 }
 static Json train(CreatureObject* c,SceneObject* npc,const std::string& name){
  validate(c,npc);auto list=swgxrTrainerCatalog().at(type(npc));if(std::find(list.begin(),list.end(),name)==list.end())throw std::runtime_error("skill_not_taught_by_trainer");auto skill=row(c,name);if(!skill["eligible"].get<bool>())throw std::runtime_error(skill["blocked_reason"].get<std::string>());
  int price=skill["credit_cost"].get<int>();if(!SkillManager::instance()->awardSkill(String(name.c_str()),c,true,false,false))throw std::runtime_error("native_skill_training_rejected");
  int cash=std::min(price,c->getCashCredits());c->subtractCashCredits(cash);if(price>cash)c->subtractBankCredits(price-cash);
  return {{"skill_id",name},{"credits_paid",price},{"xp_spent",skill["xp_cost"]},{"skill_points_spent",skill["skill_point_cost"]},{"message","@skill_teacher:msg3_2"}};
 }
};
#endif
