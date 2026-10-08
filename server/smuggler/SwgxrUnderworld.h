#ifndef SWGXR_UNDERWORLD_H
#define SWGXR_UNDERWORLD_H
#include "SwgxrUnderworldState.h"
#include "SwgxrUnderworldEncounters.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/managers/collision/CollisionManager.h"
// Ground PvE adaptation: five original Underworld brokers and reputation tiers,
// using Core3's real persistent parcel objectives and existing dialogue panels.
class SwgxrUnderworld {
 using Json=JSONSerializationType;
 struct Tier {const char* name;const char* planet;int minimum;int maximum;int front;int credits;int faction;float x;float y;};
 static const Tier* tier(SceneObject* o){
  static const Tier rows[]={
   {"Barak","tatooine",-3000,1000,500,5000,50,-1039,-3537},
   {"Ogden","naboo",1000,1500,1000,5000,25,1907,2352},
   {"Baldwin","lok",1500,2000,2000,10000,25,400,5226},
   {"Harding","endor",2000,2500,3000,15000,25,-838,1617},
   {"Russell","dathomir",2500,5001,18000,50000,25,542,3053}};
  if(!o || !o->isAiAgent() || !o->getZone())return nullptr;
  // The dedicated screenplay creates neutral original deliver_npc mobiles.
  auto source=o->asAiAgent()->getCreatureTemplate();if(!source || source->getTemplateName()!="deliver_npc")return nullptr;
  for(const auto& row:rows)if(o->getDisplayedName()==String(row.name) && o->getZone()->getZoneName()==row.planet && std::abs(o->getPositionX()-row.x)<3 && std::abs(o->getPositionY()-row.y)<3)return &row;
  return nullptr;
 }
 static std::string reason(CreatureObject* c,const Tier* t){
  if(!c->hasSkill("combat_smuggler_novice"))return "Novice Smuggler is required.";
  if(c->isDead() || (c->isIncapacitated() && !c->isFeigningDeath()) || c->isFeigningDeath())return "Stand upright before accepting a delivery.";
  auto s=SwgxrUnderworldState::load(c);if(!s.value("mission_id",std::string()).empty())return "Finish or cancel your current Underworld mission first.";
  auto reputation=s.value("reputation",0);if(reputation<t->minimum || reputation>=t->maximum)return "Your Underworld reputation belongs to another broker's tier.";
  if(int64(c->getCashCredits())+c->getBankCredits()<t->front)return "Not enough credits for the front money.";
  return "";
 }
public:
 static bool broker(SceneObject* o){return tier(o)!=nullptr;}
 static Json snapshot(CreatureObject* c){
  auto s=SwgxrUnderworldState::load(c);auto m=SwgxrUnderworldState::mission(c);
  if(m!=nullptr && s.value("deadline_ms",uint64(0))<=System::getMiliTime()){SwgxrUnderworldState::fail(c,"expired");s=SwgxrUnderworldState::load(c);}
  SwgxrUnderworldEncounters::ensure(c);
  return {{"encounter_status",SwgxrUnderworldEncounters::status(c)},{"encounter_count",s.value("encounter_count",0)},{"reputation",s.value("reputation",0)},{"active_mission_id",s.value("mission_id",std::string())},{"deadline_ms",s.value("deadline_ms",uint64(0))},{"travel_blocked",SwgxrUnderworldState::active(c)},{"last_result",s.value("last_result",std::string())},{"eligible",c->hasSkill("combat_smuggler_novice")},{"mode","ground_pve"},{"duration_seconds",SwgxrUnderworldState::DURATION_MS/1000}};
 }
 static void describe(CreatureObject* c,SceneObject* npc,Json& view){
  auto t=tier(npc);if(!t)throw std::runtime_error("underworld_broker_required");auto blocked=reason(c,t);
  view["kind"]="underworld";view["dialogue"]="I have a parcel to move quietly. Pay the front money, collect it from my contact and deliver it within 30 minutes. No shuttle travel. Incapacitation or death loses the job, deposit and 10 Underworld reputation.";
  view["confirm_action"]="underworld_accept";view["front_money"]=t->front;view["reward_credits"]=t->credits;view["reward_faction"]=t->faction;view["reputation"]=SwgxrUnderworldState::load(c).value("reputation",0);view["eligible"]=blocked.empty();view["blocked_reason"]=blocked;view["tier_minimum"]=t->minimum;view["tier_maximum"]=t->maximum;view["duration_seconds"]=SwgxrUnderworldState::DURATION_MS/1000;
 }
 static Json accept(CreatureObject* c,SceneObject* npc){
  auto t=tier(npc);if(!t || npc->getZone()!=c->getZone() || npc->getParentID()!=c->getParentID() || !c->isInRange(npc,5) || !CollisionManager::checkLineOfSight(c,npc) || npc->asAiAgent()->isDead())throw std::runtime_error("underworld_broker_cell_range_or_sight");
  snapshot(c);auto blocked=reason(c,t);if(!blocked.empty())throw std::runtime_error(blocked);
  auto m=c->getZoneServer()->getMissionManager()->swgxrCreateUnderworldMission(c,t->credits);if(m==nullptr)throw std::runtime_error("native_underworld_route_unavailable_or_mission_limit");
  auto state=SwgxrUnderworldState::load(c);state["mission_id"]=SwgxrUnderworldState::id(m);state["deadline_ms"]=System::getMiliTime()+SwgxrUnderworldState::DURATION_MS;state["front_money"]=t->front;state["reward_faction"]=t->faction;state["broker"]=t->name;state["last_result"]="active";state["encounter_count"]=0;state["encounter_ids"]=Json::array();state["next_encounter_ms"]=System::getMiliTime()+120000;state["encounter_x"]=c->getPositionX();state["encounter_y"]=c->getPositionY();
  int cash=std::min(t->front,c->getCashCredits());c->subtractCashCredits(cash);if(t->front>cash)c->subtractBankCredits(t->front-cash);SwgxrUnderworldState::save(c,state);c->updateToDatabaseAllObjects(false);SwgxrUnderworldEncounters::ensure(c);
  return {{"success",true},{"operation","underworld_accept"},{"mission_id",SwgxrUnderworldState::id(m)},{"front_money",t->front},{"deadline_ms",state["deadline_ms"]}};
 }
};
#endif
