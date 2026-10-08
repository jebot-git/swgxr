#pragma once
#include "TauntPolicy.h"
#include "TauntCommand.h"
#include "server/zone/managers/collision/CollisionManager.h"

class SwgxrTaunt {
 using Json=JSONSerializationType;
 static const TauntCommand* command(CreatureObject* c){return dynamic_cast<const TauntCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("taunt"));}
 static bool learned(CreatureObject* c){return c->getPlayerObject()!=nullptr && c->hasSkill("combat_brawler_novice") && c->getPlayerObject()->hasAbility("taunt");}
 static double cooldown(CreatureObject* c){auto t=c->getCooldownTime("corecu_taunt");return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static bool eligible(CreatureObject* c,AiAgent* a,double range){return a && a->getZone()==c->getZone() && !a->isDead() && !a->isIncapacitated() && !a->isPet() && a->isTauntable() && a->isAttackableBy(c) && a->getThreatMap()!=nullptr && !a->getThreatMap()->hasState(ThreatStates::TAUNTED) && c->isInRange(a,range) && CollisionManager::checkLineOfSight(c,a);}
 static double entry(AiAgent* a,const corecu::taunt::Vec& origin,const corecu::taunt::Vec& direction,double range){
  auto p=a->getWorldPosition();double radius=.4,height=1.8;
  auto appearance=a->getAppearanceTemplate();auto volume=appearance?appearance->getBoundingVolume():nullptr;
  if(volume!=nullptr){double size=volume->getBoundingSphere().getRadius()*a->getHeight(false);if(std::isfinite(size) && size>0){radius=std::min(1.5,size);height=std::min(4.,size*2);}}
  return corecu::taunt::reticleEntry(origin,direction,{{p.getX(),p.getZ(),p.getY()}},radius,height,range);
 }
public:
 static Json snapshot(CreatureObject* c){auto cmd=command(c);return {{"learned",cmd!=nullptr && learned(c)},{"range_m",cmd?cmd->getRange():0},{"cooldown_remaining_seconds",cooldown(c)},{"interval_seconds",cmd && c->getWeapon()!=nullptr?std::max(1.,double(cmd->getCommandDuration(c,""))):1.}};}
 static Json run(CreatureObject* c,const Json& request){
  auto cmd=command(c);if(cmd==nullptr || !learned(c))throw std::runtime_error("native_taunt_not_learned");
  if(cooldown(c)>0)throw std::runtime_error("native_taunt_cooldown");
  if(c->getWeapon()==nullptr || !c->getWeapon()->isCertifiedFor(c) || !cmd->checkStateMask(c) || !cmd->checkInvalidLocomotions(c) || c->isDead() || c->isIncapacitated() || c->isRidingMount() || c->getPosture()!=0)throw std::runtime_error("native_taunt_unavailable");
  corecu::taunt::Vec o{},d{};double norm=0,headDistance=0;auto player=c->getWorldPosition();double center[]={player.getX(),player.getZ(),player.getY()};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_taunt_pose");for(int i=0;i<3;++i)if(!v[i].is_number() || !std::isfinite(v[i].get<double>()))throw std::runtime_error("invalid_taunt_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();norm+=d[i]*d[i];headDistance+=(o[i]-center[i])*(o[i]-center[i]);}
  if(headDistance>6.25 || std::abs(norm-1)>.05)throw std::runtime_error("invalid_taunt_pose");for(double& axis:d)axis/=std::sqrt(norm);
  double range=std::max(0,std::min(64,cmd->getRange()));
  SortedVector<TreeEntry*> nearby(64,64);c->getZone()->getInRangeObjects(player.getX(),player.getZ(),player.getY(),range+2,&nearby,true);
  ManagedReference<AiAgent*> chosen=nullptr;double closest=1e9;
  for(int i=0;i<nearby.size();++i){auto object=static_cast<SceneObject*>(nearby.get(i));if(!object->isAiAgent())continue;auto a=object->asAiAgent();Locker lock(a,c);if(!eligible(c,a,range))continue;double distance=entry(a,o,d,range);if(distance>=0 && distance<closest){closest=distance;chosen=a;}}
  if(chosen==nullptr)throw std::runtime_error("no_eligible_taunt_target");
  Locker lock(chosen,c);
  if(!learned(c) || !eligible(c,chosen,range) || entry(chosen,o,d,range)<0)throw std::runtime_error("taunt_target_changed");
  // Persist timing on the creature so reconnecting cannot clear this ability's recovery.
  double interval=std::max(1.,double(cmd->getCommandDuration(c,"")));c->addCooldown("corecu_taunt",int(interval*1000));
  c->setTargetID(0,true);int code=cmd->doQueueCommand(c,chosen->getObjectID(),UnicodeString());c->setTargetID(0,true);
  bool applied=code==QueueCommand::SUCCESS && chosen->getThreatMap()->hasState(ThreatStates::TAUNTED) && chosen->getThreatMap()->getHighestThreatAttacker()==c;
  Json out={{"success",code==QueueCommand::SUCCESS},{"native_result",code},{"shot_id",request.at("shot_id")},{"target_id",std::to_string(chosen->getObjectID())},{"taunted",applied},{"interval_seconds",interval}};
  if(code!=QueueCommand::SUCCESS)out["error_code"]="native_taunt_rejected";return out;
 }
};
