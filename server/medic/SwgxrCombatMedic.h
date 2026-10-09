#pragma once
#include "SwgxrCombatMedicEffects.h"

// Medical-focus input delegates all effects, costs and supply consumption to
// the same native command used by Core3. Tracking is client-reported input.
class SwgxrCombatMedic {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static uint64 objectId(const Json& q,const char* field){
  const auto s=q.at(field).get<std::string>();
  if(s.empty() || s.size()>20 || s.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid medical object id");
  auto value=std::stoull(s);if(!value)throw std::runtime_error("Invalid medical object id");return value;
 }
 static Vector3 hand(const Json& p){
  if(!p.is_array() || p.size()!=3)throw std::runtime_error("Invalid medical hand pose");
  for(auto& n:p)if(!n.is_number() || !std::isfinite(n.get<double>()) || std::abs(n.get<double>())>10000)throw std::runtime_error("Invalid medical hand pose");
  return Vector3(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());
 }
 static bool medicalTool(SceneObject* o){if(!o)return false;auto path=o->getObjectTemplate()->getFullTemplateString();return path=="object/tangible/medicine/medikit_tool_basic.iff" || path=="object/tangible/medicine/medikit_tool_advanced.iff";}
public:
 static Json snapshot(CreatureObject* c,const Json& inventory){
  Json result={{"abilities",Json::array()},{"supplies",Json::array()},{"targets",Json::array()}};
  for(bool disease:{false,true})result["abilities"].push_back({{"id",disease?"applydisease":"applypoison"},{"learned",SwgxrCombatMedicEffects::learned(c,disease)},{"cooldown_seconds",SwgxrCombatMedicEffects::remaining(c)},{"action_cost",SwgxrCombatMedicEffects::actionCost(c)},{"mind_cost",SwgxrCombatMedicEffects::mindCost(c)},{"recovery_group","combat_medicine"}});
  for(auto& item:inventory.at("items")){
   auto pack=c->getZoneServer()->getObject(objectId(item,"id")).castTo<DotPack*>();
   if(!pack)continue;
   const bool disease=pack->isDiseaseDeliveryUnit();
   if(!SwgxrCombatMedicEffects::compatible(c,pack,disease))continue;
   result["supplies"].push_back({{"item_id",id(pack)},{"ability",disease?"applydisease":"applypoison"},{"label",std::string(pack->getDisplayedName().toCharArray())},{"charges",pack->getUseCount()},{"range_m",SwgxrCombatMedicEffects::range(c,pack)},{"area_radius_m",SwgxrCombatMedicEffects::radius(pack)},{"potency",SwgxrCombatMedicEffects::rawPotency(c,pack)},{"duration_seconds",SwgxrCombatMedicEffects::duration(c,pack)},{"target_cap",pack->isArea()?corecu::combatmedic::TargetCap:1}});
  }
  return result;
 }
 static Json target(CreatureObject* c,CreatureObject* target,const Json& state){
  if(!target || target==c || target->isDead() || target->getZone()!=c->getZone() || !target->isAttackableBy(c))return Json(nullptr);
  Json available={{"applypoison",false},{"applydisease",false}};
  for(auto& row:state.at("supplies")){
   const auto name=row.at("ability").get<std::string>();
   if(available.at(name).get<bool>() || !c->isInRange(target,row.at("range_m").get<float>()))continue;
   auto pack=c->getZoneServer()->getObject(objectId(row,"item_id")).castTo<DotPack*>();
   if(SwgxrCombatMedicEffects::eligible(c,target,pack))available[name]=true;
  }
  if(!available["applypoison"].get<bool>() && !available["applydisease"].get<bool>())return Json(nullptr);
  auto p=target->getWorldPosition();double height=std::max(.5,std::min(6.,double(target->getHeight(false)))),radius=std::max(.25,std::min(4.,double(target->getTemplateRadius())));
  return {{"id",id(target)},{"name",std::string(target->getDisplayedName().toCharArray())},{"position",Json::array({p.getX(),p.getZ(),p.getY()})},{"eligible",true},{"dead",false},{"relation","hostile"},{"ability_available",available},{"bounds",{{"center",Json::array({0,height*.5,0})},{"size",Json::array({radius*2,height,radius*2})}}}};
 }
 static Json run(CreatureObject* c,const Json& q){
  const auto name=q.at("ability").get<std::string>();const bool disease=name=="applydisease";
  if((name!="applypoison" && !disease) || !SwgxrCombatMedicEffects::learned(c,disease) || c->isDead() || c->isIncapacitated())throw std::runtime_error("Combat Medic ability not learned or actor cannot act");
  const auto& pose=q.at("pose");if(!pose.value("tracked",false))throw std::runtime_error("Tracked medical focus required");
  if(hand(pose.at("left")).distanceTo(c->getWorldPosition())>2.2f || hand(pose.at("right")).distanceTo(c->getWorldPosition())>2.2f)throw std::runtime_error("Medical hands exceed tracked reach");
  auto focus=c->getZoneServer()->getObject(objectId(q,"focus_id"));
  if(!medicalTool(focus) || !SwgxrMedicalItem::owned(c,focus))throw std::runtime_error("Owned Doctor tool required");
  auto pack=c->getZoneServer()->getObject(objectId(q,"item_id")).castTo<DotPack*>();
  if(!SwgxrCombatMedicEffects::compatible(c,pack,disease))throw std::runtime_error("Exact usable trained delivery pack required");
  auto patient=c->getZoneServer()->getObject(objectId(q,"target_id")).castTo<CreatureObject*>();
  if(!patient)throw std::runtime_error("Living hostile target required");
  Locker targetLock(patient,c);
  if(!SwgxrCombatMedicEffects::eligible(c,patient,pack) || !c->isInRange(patient,SwgxrCombatMedicEffects::range(c,pack)))throw std::runtime_error("Hostile target unavailable, immune, obstructed or out of range");
  if(SwgxrCombatMedicEffects::remaining(c)>0 || !SwgxrCombatMedicEffects::resources(c))throw std::runtime_error("Combat medicine recovering or insufficient resources");
  auto command=c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str()));
  if(!command || (!command->getCharacterAbility().isEmpty() && !c->getPlayerObject()->hasAbility(command->getCharacterAbility())))throw std::runtime_error("Native Combat Medic command not learned");
  const auto item=id(pack);String args=String(disease?"action|":"health|")+String(item.c_str());
  if(command->doQueueCommand(c,patient->getObjectID(),UnicodeString(args))!=QueueCommand::SUCCESS)throw std::runtime_error("Native Combat Medic delivery rejected");
  return {{"success",true},{"action","combat_medic"},{"ability",name},{"command",name},{"item_id",item},{"focus_id",id(focus)},{"target_id",id(patient)}};
 }
};
