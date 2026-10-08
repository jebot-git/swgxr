#pragma once
#include "CoreCuLoadoutPolicy.h"
#include "SwgxrSmuggler.h"
class SwgxrCombatLoadout {
 using Json=JSONSerializationType;
public:
 static std::string family(CreatureObject* c){
  auto w=c->getWeapon();if(!w)return "unarmed";
  if(w->isUnarmedWeapon())return "unarmed";
  if(w->isPistolWeapon())return "pistols";
  if(w->isCarbineWeapon())return "carbines";
  if(w->isHeavyWeapon() || w->isFlameThrower() || w->isLightningRifle() || w->isHeavyAcidRifle())return "heavy";
  if(w->isRifleWeapon())return "rifles";
  if(w->isJediOneHandedWeapon())return "1h_lightsaber";
  if(w->isJediTwoHandedWeapon())return "2h_lightsaber";
  if(w->isJediPolearmWeapon())return "polearm_lightsaber";
  if(w->isOneHandMeleeWeapon())return "1h_melee";
  if(w->isTwoHandMeleeWeapon())return "2h_melee";
  if(w->isPolearmWeaponObject())return "polearms";
  return "other";
 }
 static Json empty(){return {{"slots",Json::array({"","","",""})},{"ultimate",""},{"revision",0}};}
 static Json saved(CreatureObject* c){
  auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_combat_loadout",String(family(c).c_str()));
  return raw.isEmpty()?empty():Json::parse(raw.toCharArray());
 }
 static corecu::CombatLoadout selection(const Json& value){
  corecu::CombatLoadout result;
  if(!value.at("slots").is_array() || value.at("slots").size()!=4)throw std::runtime_error("loadout_requires_four_slots");
  for(int i=0;i<4;++i)result.slots[i]=value.at("slots")[i].get<std::string>();
  result.ultimate=value.at("ultimate").get<std::string>();return result;
 }
 static Json snapshot(CreatureObject* c,const Json& catalog){
  auto out=saved(c);out["family"]=family(c);
  // Lost skills leave empty usable slots; stored preferences never grant skills.
  std::set<std::string> regular,ultimate;
  for(const auto& row:catalog)(row.value("ultimate",false)?ultimate:regular).insert(row.at("id").get<std::string>());
  for(auto& id:out["slots"])if(!regular.count(id.get<std::string>()))id="";
  if(!ultimate.count(out["ultimate"].get<std::string>()))out["ultimate"]="";
  return out;
 }
 static Json equipped(CreatureObject* c,const Json& catalog){
  auto selected=selection(snapshot(c,catalog));Json out=Json::array();
  for(const auto& row:catalog)if(selected.contains(row.at("id").get<std::string>()))out.push_back(row);
  return out;
 }
 static bool allows(CreatureObject* c,const std::string& id){
  return id.empty() || selection(snapshot(c,SwgxrSmuggler::abilities(c))).contains(id);
 }
 static Json change(CreatureObject* c,const Json& request){
  auto w=c->getWeapon();const auto& q=request.at("loadout");
  if(!w || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || family(c)!=q.at("family").get<std::string>())throw std::runtime_error("loadout_weapon_changed");
  if(c->isDead() || c->isIncapacitated())throw std::runtime_error("native_player_unavailable");
  auto old=saved(c);if(q.at("revision")!=old.at("revision"))throw std::runtime_error("loadout_revision_changed");
  auto selected=selection(q);std::set<std::string> regular,ultimate;
  for(const auto& row:SwgxrSmuggler::abilities(c))(row.value("ultimate",false)?ultimate:regular).insert(row.at("id").get<std::string>());
  if(!selected.valid(regular,ultimate))throw std::runtime_error("loadout_ability_not_eligible");
  Json value={{"slots",q.at("slots")},{"ultimate",selected.ultimate},{"revision",old.at("revision").get<uint64>()+1}};
  c->getPlayerObject()->setScreenPlayData("swgxr_combat_loadout",String(family(c).c_str()),String(value.dump().c_str()));
  return {{"success",true},{"operation","loadout"}};
 }
};
