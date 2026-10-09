#pragma once
#include "SquadLeaderPolicy.h"
#include "PistoleerPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/group/GroupObject.h"
#include "server/zone/objects/tangible/weapon/WeaponObject.h"
#include "server/zone/objects/creature/buffs/Buff.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include <chrono>
#include <vector>
class SwgxrSquadLeader {
 using Json=JSONSerializationType;using Vec=std::array<double,3>;
 static long long wallMillis(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static Vec position(CreatureObject* c){auto p=c->getWorldPosition();return {{p.getX(),p.getZ(),p.getY()}};}
 static uint64 cell(CreatureObject* c){auto p=c->getParent().get();return p && p->isCellObject()?p->getObjectID():0;}
 static String key(const std::string& id){return String(("swgxr_squad_"+id).c_str());}
 static void recoverAfter(CreatureObject* c,const std::string& id,int seconds){c->addCooldown(key(id),seconds*1000);c->getPlayerObject()->setScreenPlayData("swgxr_squad",String((id+"_until").c_str()),String(std::to_string(wallMillis()+seconds*1000).c_str()));}
 static int boxes(CreatureObject* c,const char* branch){int n=0;for(int i=1;i<=4;++i)n+=c->hasSkill(String((std::string("outdoors_squadleader_")+branch+"_0"+std::to_string(i)).c_str()))?1:0;return n;}
 static bool local(CreatureObject* c,CreatureObject* member){return sameParty(c,member) && cell(c)==cell(member) && c->isInRange(member,corecu::squadleader::Range) && CollisionManager::checkLineOfSight(c,member);}
 static bool affected(CreatureObject* c,const std::string& id){
  if(!validParty(c) || !c->hasBuff(key(id).hashCode()))return false;
  auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_squad",String((id+"_source").c_str()));if(raw.isEmpty())return false;
  uint64 source=0;try{source=std::stoull(raw.toCharArray());}catch(...){return false;}
  auto group=c->getGroup();for(int i=0;i<group->getGroupSize();++i){ManagedReference<CreatureObject*> member=group->getGroupMember(i);if(member && member->getObjectID()==source){auto epoch=c->getPlayerObject()->getScreenPlayData("swgxr_squad",String((id+"_source_epoch").c_str()));return sameParty(c,member) && learned(member,id) && epoch==member->getPlayerObject()->getScreenPlayData("swgxr_squad","membership_epoch");}}
  return false;
 }
 static void apply(CreatureObject* source,CreatureObject* member,const corecu::squadleader::Ability& a){
  if(std::string(a.id)=="form_up"){if(member->isDizzied())member->removeStateBuff(CreatureState::DIZZY);if(member->isStunned())member->removeStateBuff(CreatureState::STUNNED);}
  ManagedReference<Buff*> buff=new Buff(member,key(a.id).hashCode(),a.seconds,BuffType::STATE);Locker lock(buff,member);member->addBuff(buff);
  member->getPlayerObject()->setScreenPlayData("swgxr_squad",String((std::string(a.id)+"_source").c_str()),String(std::to_string(source->getObjectID()).c_str()));member->getPlayerObject()->setScreenPlayData("swgxr_squad",String((std::string(a.id)+"_source_epoch").c_str()),source->getPlayerObject()->getScreenPlayData("swgxr_squad","membership_epoch"));recoverAfter(member,std::string(a.id)+"_received",a.cooldown);
 }
public:
 static void leave(CreatureObject* c){if(!c || !c->getPlayerObject())return;auto previous=c->getPlayerObject()->getScreenPlayData("swgxr_squad","membership_epoch");uint64 epoch=0;try{epoch=std::stoull(previous.toCharArray());}catch(...){}c->getPlayerObject()->setScreenPlayData("swgxr_squad","membership_epoch",String(std::to_string(epoch+1).c_str()));for(auto id:{"steady_aim","rally","form_up","boost_morale","retreat"})c->removeBuff(key(id).hashCode());}
 static bool online(CreatureObject* c){return c && c->isPlayerCreature() && c->getPlayerObject() && c->isOnline() && c->getZone() && !c->isDead() && !c->isIncapacitated();}
 static bool sameParty(CreatureObject* c,CreatureObject* other){auto group=c?c->getGroup():nullptr;return online(c) && online(other) && group && c->getGroupID()!=0 && other->getGroupID()==c->getGroupID() && other->getZone()==c->getZone() && group->hasMember(c) && group->hasMember(other) && other->isHealableBy(c);}
 static bool validParty(CreatureObject* c){if(!online(c) || !c->getGroup())return false;auto group=c->getGroup();if(!group->hasMember(c))return false;for(int i=0;i<group->getGroupSize();++i){ManagedReference<CreatureObject*> m=group->getGroupMember(i);if(m && m!=c && sameParty(c,m))return true;}return false;}
 static bool learned(CreatureObject* c,const std::string& id){const auto a=corecu::squadleader::ability(id);return c && a && c->getPlayerObject() && c->hasSkill("outdoors_squadleader_novice") && c->hasSkill(a->skill) && c->getPlayerObject()->hasAbility(a->grant);}
 static bool equipped(CreatureObject* c){auto w=c?c->getWeapon():nullptr;return w && w->isASubChildOf(c) && !w->isBroken() && w->isCertifiedFor(c);}
 static corecu::squadleader::Bonuses passives(CreatureObject* c){
  corecu::squadleader::Bonuses out;if(!validParty(c))return out;auto group=c->getGroup();
  for(int i=0;i<group->getGroupSize();++i){ManagedReference<CreatureObject*> member=group->getGroupMember(i);if(!sameParty(c,member) || !member->hasSkill("outdoors_squadleader_novice"))continue;out.merge(corecu::squadleader::bonuses(boxes(member,"offense"),boxes(member,"movement"),member->getSkillMod("group_melee_defense"),member->getSkillMod("group_ranged_defense"),member->hasSkill("outdoors_squadleader_master")));}return out;
 }
 static double outputDamageScale(CreatureObject* c){return corecu::squadleader::output(passives(c).output,affected(c,"steady_aim"));}
 static double receivedDamageScale(CreatureObject* c){return corecu::squadleader::received(affected(c,"rally"));}
 static int defenseBonus(CreatureObject* c,bool ranged){auto p=passives(c);return ranged?p.ranged:p.melee;}
 static double regenerationScale(CreatureObject* c,int attribute){return corecu::squadleader::regeneration(passives(c).regen,affected(c,"boost_morale"),attribute);}
 static double movementScale(CreatureObject* c){return corecu::squadleader::movement(affected(c,"retreat"));}
 static double statusRating(CreatureObject* c,double base){return corecu::squadleader::status(base,affected(c,"form_up"));}
 static double cooldown(CreatureObject* c,const std::string& id){if(!c || !c->getPlayerObject())return 0;auto t=c->getCooldownTime(key(id));double remaining=t?std::max(0.,-t->miliDifference()/1000.):0.;auto saved=c->getPlayerObject()->getScreenPlayData("swgxr_squad",String((id+"_until").c_str()));if(!saved.isEmpty())try{remaining=std::max(remaining,corecu::squadleader::bounded((std::stoll(saved.toCharArray())-wallMillis())/1000.,120));}catch(...){}return remaining;}
 static Json snapshot(CreatureObject* c){
  Json out={{"group_id",std::to_string(c->getGroupID())},{"abilities",Json::array()},{"targets",Json::array()}};auto p=passives(c);out["passives"]={{"active",validParty(c)},{"scope","same_planet"},{"damage_bonus",p.output},{"action_mind_regen_bonus",p.regen},{"melee_defense",p.melee},{"ranged_defense",p.ranged}};
  // Migrate lingering pre-CU buffs. Their raw accuracy, slope and burst-run
  // modifiers are neither used nor advertised by the CU implementation.
  for(auto legacy:{"squadleader","rally","steadyaim","retreat"})if(c->hasBuff(String(legacy).hashCode()))c->removeBuff(String(legacy).hashCode());
  for(auto id:{"steady_aim","rally","form_up","boost_morale","retreat"}){const auto a=corecu::squadleader::ability(id);if(!learned(c,id))continue;auto buff=c->getBuff(key(id).hashCode());out["abilities"].push_back({{"id",id},{"label",a->label},{"category","support"},{"activation","squadleader_support"},{"friendly_target",true},{"native_authority",true},{"ultimate",false},{"learned",true},{"conditions_met",validParty(c) && equipped(c) && !c->isRidingMount()},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a->cooldown},{"duration_seconds",a->seconds},{"range_m",corecu::squadleader::Range},{"max_range_m",corecu::squadleader::Range},{"action_cost",a->action},{"mind_cost",a->mind},{"active",affected(c,id)},{"active_remaining_seconds",affected(c,id) && buff?std::max(0.f,buff->getTimeLeft()):0.},{"description",std::string(id)=="steady_aim"?"Nearby group: +15% direct attack damage for 12 seconds; no raw accuracy bonus.":std::string(id)=="rally"?"Nearby group: take 15% less direct attack damage for 12 seconds.":std::string(id)=="form_up"?"Nearby group: clear stun and dizzy; +20 status resistance rating for 6 seconds within the existing baseline cap.":std::string(id)=="boost_morale"?"Nearby group: +50% existing Action and Mind regeneration for 15 seconds. No immediate healing or wound redistribution.":"Nearby group: +20% voluntary movement speed for 8 seconds. Tracking-driven movement is unchanged."},{"scope","nearby_group"}});}
  if(!validParty(c) || !c->hasSkill("outdoors_squadleader_novice"))return out;auto group=c->getGroup();for(int i=0;i<group->getGroupSize();++i){ManagedReference<CreatureObject*> m=group->getGroupMember(i);if(!m || m==c)continue;Locker lock(m,c);if(!local(c,m))continue;out["targets"].push_back({{"id",std::to_string(m->getObjectID())},{"name",std::string(m->getFirstName().toCharArray())},{"position",position(m)},{"height_m",double(m->getHeight(false))},{"eligible",true},{"dead",false},{"incapacitated",false}});}return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();const auto a=corecu::squadleader::ability(id);auto w=c->getWeapon();if(!a || !learned(c,id) || !validParty(c) || !equipped(c) || c->isRidingMount() || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>())throw std::runtime_error("native_squadleader_unavailable");
  auto shot=request.at("shot_id").get<std::string>();if(shot.size()<8 || shot.size()>80)throw std::runtime_error("invalid_shot_id");Json accepted=Json::array();auto saved=c->getPlayerObject()->getScreenPlayData("swgxr_squad","accepted_shots");if(!saved.isEmpty())try{accepted=Json::parse(saved.toCharArray());}catch(...){}if(!accepted.is_array())accepted=Json::array();for(const auto& old:accepted)if(old==shot)throw std::runtime_error("duplicate_shot");if(cooldown(c,id)>0 || cooldown(c,"command")>0)throw std::runtime_error("native_squadleader_cooldown");
  Vec o{},d{};for(auto field:{"origin","direction"}){const auto& v=request.at(field);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_squadleader_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_squadleader_pose");}for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}if(!corecu::pistoleer::validPose(o,d,position(c)))throw std::runtime_error("invalid_squadleader_pose");double norm=std::sqrt(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);for(auto& component:d)component/=norm;
  auto targetId=request.at("target_id").get<std::string>();auto group=c->getGroup();ManagedReference<CreatureObject*> target=nullptr;for(int i=0;i<group->getGroupSize();++i){auto m=group->getGroupMember(i);if(m && m!=c && std::to_string(m->getObjectID())==targetId){target=m;break;}}if(!target)throw std::runtime_error("native_squadleader_target_unavailable");
  {Locker lock(target,c);if(!local(c,target))throw std::runtime_error("native_squadleader_target_unavailable");auto center=position(target);center[1]+=std::max(.5,double(target->getHeight(false))*.5);double along=0,len=0;for(int i=0;i<3;++i){double x=center[i]-o[i];along+=x*d[i];len+=x*x;}if(along<=0 || len-along*along>2.25)throw std::runtime_error("native_squadleader_target_outside_aim");}
  std::vector<ManagedReference<CreatureObject*>> recipients;for(int i=0;i<group->getGroupSize();++i){ManagedReference<CreatureObject*> m=group->getGroupMember(i);if(!m)continue;Locker lock(m,c);if(local(c,m) && cooldown(m,id+"_received")<=0)recipients.push_back(m);}bool other=false;for(const auto& m:recipients)other=other || m!=c;if(!other)throw std::runtime_error("native_squadleader_no_eligible_recipients");
  if(!validParty(c) || c->getGroup()!=group || !equipped(c) || c->getWeapon()!=w)throw std::runtime_error("native_squadleader_context_changed");if(c->getHAM(3)<=a->action || c->getHAM(6)<=a->mind)throw std::runtime_error("native_squadleader_insufficient_sac");
  accepted.push_back(shot);while(accepted.size()>64)accepted.erase(accepted.begin());c->getPlayerObject()->setScreenPlayData("swgxr_squad","accepted_shots",String(accepted.dump().c_str()));recoverAfter(c,id,a->cooldown);recoverAfter(c,"command",2);c->inflictDamage(c,3,a->action,false,true,false);c->inflictDamage(c,6,a->mind,false,true,false);
  Json affectedIds=Json::array();for(auto m:recipients){Locker lock(m,c);if(!local(c,m) || cooldown(m,id+"_received")>0)continue;apply(c,m,*a);affectedIds.push_back(std::to_string(m->getObjectID()));}
  return {{"success",true},{"operation","squadleader"},{"ability_id",id},{"shot_id",shot},{"target_id",targetId},{"affected_ids",affectedIds},{"ham_cost_committed",true},{"hit",false},{"damage",0},{"interval_seconds",2}};
 }
};
