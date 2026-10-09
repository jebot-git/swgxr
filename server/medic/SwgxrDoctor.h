#pragma once
#include "CoreCuMedicine.h"
#include "SwgxrMedicalItem.h"
// Native authority for exact-supply Doctor gestures and friendly medical-focus VATS.
// Tracking is client-reported input; the native side validates bounds, ownership,
// training, recipient, LOS and the original command's resources/consent/recovery.
class SwgxrDoctor {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static uint64 objectId(const Json& q,const char* field){
  const auto s=q.at(field).get<std::string>();
  if(s.empty() || s.size()>20 || s.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid medical object id");
  return std::stoull(s);
 }
 static Vector3 hand(const Json& p){
  if(!p.is_array() || p.size()!=3)throw std::runtime_error("Invalid medical hand pose");
  for(auto& n:p)if(!n.is_number() || !std::isfinite(n.get<double>()) || std::abs(n.get<double>())>10000)throw std::runtime_error("Invalid medical hand pose");
  return Vector3(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());
 }
 static bool medicalTool(SceneObject* o){if(!o)return false;auto name=o->getObjectTemplate()->getFullTemplateString();return name=="object/tangible/medicine/medikit_tool_basic.iff" || name=="object/tangible/medicine/medikit_tool_advanced.iff";}
 static const char* stateName(uint64 state){return state==CreatureState::STUNNED?"stunned":state==CreatureState::DIZZY?"dizzy":state==CreatureState::BLINDED?"blinded":state==CreatureState::INTIMIDATED?"intimidated":"";}
 static bool learned(CreatureObject* c,const std::string& name){
  if((name!="healstate" && name!="reviveplayer" && name!="extinguishfire") || !c->hasSkill("science_medic_novice"))return false;
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str()));
  return cmd && (cmd->getCharacterAbility().isEmpty() || c->getPlayerObject()->hasAbility(cmd->getCharacterAbility()));
 }
public:
 static bool revivable(CreatureObject* c,CreatureObject* target){
  if(!target || !target->isPlayerCreature() || target==c || !target->isDead() || !target->isResuscitable() || target->getZone()!=c->getZone() || target->isAttackableBy(c) || !target->isHealableBy(c))return false;
  auto group=c->getGroup();
  return (group && group->hasMember(target)) || target->getPlayerObject()->hasInConsentList(c->getFirstName().toLowerCase());
 }
 static Json needs(CreatureObject* c,CreatureObject* target){
  bool eligible=target && !target->isDead() && !target->isRidingMount() && !target->isAttackableBy(c) && target->isHealableBy(c) && (target->isPlayerCreature() || (target->isPet() && target->isCreature() && !target->isDroidObject()));
  bool state=false;if(eligible)for(auto mask:{CreatureState::STUNNED,CreatureState::DIZZY,CreatureState::BLINDED,CreatureState::INTIMIDATED})state=state || target->hasState(mask);
  return {{"reviveplayer",revivable(c,target)},{"extinguishfire",eligible && target->hasState(CreatureState::ONFIRE)},{"healstate",state}};
 }
 static Json snapshot(CreatureObject* c,const Json& inventory){
  Json result=Json::object();
  for(auto name:{"reviveplayer","extinguishfire","healstate"}){
   result[name]={{"learned",learned(c,name)},{"range_m",std::string(name)=="healstate"?6.:2.5},{"cooldown_seconds",CoreCuMedicine::remaining(c,String(name))},{"action_cost",CoreCuMedicine::cost(c,String(name),3)},{"mind_cost",CoreCuMedicine::cost(c,String(name),6)},{"requires_medical_focus",std::string(name)=="healstate"},{"supplies",Json::array()}};
  }
  for(auto& item:inventory.at("items")){
   auto pack=c->getZoneServer()->getObject(objectId(item,"id")).castTo<PharmaceuticalObject*>();
   if(!pack || !SwgxrMedicalItem::owned(c,pack) || !SwgxrMedicalItem::trained(c,pack) || pack->getUseCount()<=0)continue;
   std::string command=SwgxrMedicalItem::command(pack).toCharArray();if(!result.contains(command))continue;
   Json supply={{"item_id",id(pack)},{"charges",pack->getUseCount()},{"label",std::string(pack->getDisplayedName().toCharArray())}};
   if(pack->isStatePack()){
    auto state=static_cast<StatePack*>(pack.get())->getState();auto name=stateName(state);if(!*name)continue;
    supply["state"]=name;supply["state_mask"]=state;
   }
   result[command]["supplies"].push_back(supply);
  }
  result["healing_multiplier"]=corecu::doctorcare::multiplier(CoreCuMedicine::doctorStage(c));
  result["emergency_healing_multiplier"]=corecu::doctorcare::emergencyMultiplier(CoreCuMedicine::doctorStage(c));
  result["wound_healing_multiplier"]=corecu::doctorcare::woundMultiplier(CoreCuMedicine::doctorStage(c));
  result["wound_fraction_cap"]=.10*corecu::doctorcare::woundMultiplier(CoreCuMedicine::doctorStage(c));
  return result;
 }
 static Json run(CreatureObject* c,const Json& q){
  const auto name=q.at("ability").get<std::string>();
  if(!learned(c,name) || c->isDead() || c->isIncapacitated())throw std::runtime_error("Medical ability not learned or healer cannot act");
  const auto& pose=q.at("pose");if(!pose.value("tracked",false))throw std::runtime_error("Tracked medical action required");
  auto left=hand(pose.at("left")),right=hand(pose.at("right"));
  if(left.distanceTo(c->getWorldPosition())>2.2f || right.distanceTo(c->getWorldPosition())>2.2f)throw std::runtime_error("Medical hands exceed tracked reach");
  auto pack=c->getZoneServer()->getObject(objectId(q,"item_id")).castTo<PharmaceuticalObject*>();
  if(!pack || !SwgxrMedicalItem::owned(c,pack) || !SwgxrMedicalItem::trained(c,pack) || pack->getUseCount()<=0 || SwgxrMedicalItem::command(pack)!=String(name.c_str()))throw std::runtime_error("Exact usable owned treatment supply required");
  if(name=="healstate"){
   auto focus=c->getZoneServer()->getObject(objectId(q,"focus_id"));
   if(!medicalTool(focus) || !SwgxrMedicalItem::owned(c,focus))throw std::runtime_error("Owned medical focus required for friendly VATS");
   if(!*stateName(static_cast<StatePack*>(pack.get())->getState()))throw std::runtime_error("Unsupported stabilization state");
  }
  auto target=c->getZoneServer()->getObject(objectId(q,"target_id")).castTo<CreatureObject*>();
  if(!target || target->getZone()!=c->getZone() || !SwgxrMedicalItem::recipient(pack,target))throw std::runtime_error("Invalid medical recipient");
  Locker targetLock(target,c);
  if(!needs(c,target).at(name).get<bool>() || !SwgxrMedicalItem::needed(pack,target) || !c->isInRange(target,name=="healstate"?6.f:2.5f) || (target!=c && !CollisionManager::checkLineOfSight(c,target)))throw std::runtime_error("Recipient unavailable, does not need this supply, or is obstructed");
  if(name!="healstate"){
   bool leftNear=left.distanceTo(target->getWorldPosition())<=2.2f,rightNear=right.distanceTo(target->getWorldPosition())<=2.2f;
   if(name=="reviveplayer"?!(leftNear && rightNear):!(leftNear || rightNear))throw std::runtime_error("Medical gesture must contact the patient");
  }
  if(!CoreCuMedicine::check(c,String(name.c_str())))throw std::runtime_error("Medical action recovering or insufficient resources");
  auto command=c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str()));
  auto itemId=id(pack);
  if(command->doQueueCommand(c,target->getObjectID(),UnicodeString(SwgxrMedicalItem::arguments(pack)))!=QueueCommand::SUCCESS)throw std::runtime_error("Doctor treatment rejected: supplies, state, consent, recovery or resources");
  return {{"success",true},{"action","doctor"},{"ability",name},{"command",name},{"item_id",itemId},{"target_id",id(target)}};
 }
};
