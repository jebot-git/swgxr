#pragma once
#include "RiflemanPolicy.h"
#include "PistoleerPolicy.h"
#include "CoreCuLoadoutPolicy.h"
class SwgxrRifleman {
 using Json=JSONSerializationType;
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isRifleWeapon() && !w->isHeavyWeapon() && !w->isLightningRifle() && !w->isHeavyAcidRifle() && !w->isFlameThrower() && w->isCertifiedFor(c) && !w->isBroken();}
 static bool learned(CreatureObject* c,const std::string& id){
  if(!corecu::rifleman::contains(id) || !c->hasSkill("combat_rifleman_novice") || !c->getPlayerObject())return false;
  if(id=="rifleman_focus")return c->hasSkill("combat_rifleman_speed_02");
  if(id=="sniper_shot" && !c->hasSkill("combat_rifleman_master"))return false;
  return c->getPlayerObject()->hasAbility(corecu::rifleman::ability(id).grant) || (id=="lethal_shot" && c->getPlayerObject()->hasAbility("headShot3")) || (id=="flurry_shot" && c->getPlayerObject()->hasAbility("flurryShot2"));
 }
 static bool headUpgrade(CreatureObject* c){return compatible(c) && learned(c,"lethal_shot");}
 static bool targetReady(CreatureObject* a){return a && a->isAiAgent() && !a->asAiAgent()->isPet() && !a->isDead() && !a->isIncapacitated();}
 static bool active(CreatureObject* c){return compatible(c) && learned(c,"rifleman_focus") && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_rifleman_focus"));}
 static void refresh(CreatureObject* c){if(!compatible(c) || !learned(c,"rifleman_focus") || c->isDead() || c->isIncapacitated())c->removeBuff(STRING_HASHCODE("swgxr_rifleman_focus"));}
 static bool conditions(CreatureObject* c,const std::string& id){return compatible(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && (id!="rifleman_focus" || !active(c));}
 static double focusScale(CreatureObject* c,const std::string& id){return active(c) && id!="rifleman_focus" && corecu::ultimateProfession(id).empty()?corecu::rifleman::FocusMultiplier:1.;}
 static double damage(CreatureObject* c,const std::string& id){return corecu::rifleman::damage(id,c->getPlayerObject() && c->getPlayerObject()->hasAbility(id=="lethal_shot"?"headShot3":"flurryShot2"));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("swgxr_smuggler_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const std::string& id){double native=c->getWeapon()?double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)):1.5;return id=="rifleman_focus"?.25:id=="lethal_shot"?2*native:id=="sniper_shot"?std::max(2.5,native):native;}
 static Json snapshot(CreatureObject* c){refresh(c);Json out=Json::object();for(auto id:{"lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot","rifleman_focus"}){auto a=corecu::rifleman::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",a.action},{"mind_cost",a.mind},{"interval_seconds",interval(c,id)}};}
  auto buff=c->getBuff(STRING_HASHCODE("swgxr_rifleman_focus"));auto& row=out["rifleman_focus"];row["active"]=active(c);row["active_remaining_seconds"]=active(c) && buff?std::max(0.f,buff->getTimeLeft()):0.;row["duration_seconds"]=corecu::rifleman::FocusSeconds;row["damage_multiplier"]=corecu::rifleman::FocusMultiplier;return out;
 }
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);auto w=c->getWeapon();for(auto id:{"lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot","rifleman_focus"}){if(!learned(c,id))continue;auto a=corecu::rifleman::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["activation"]=a.gesture?"rifleman_gesture":"native_ranged";row["ultimate"]=a.ultimate;row["native_authority"]=true;row["source_command"]=key=="lethal_shot"?"overchargeshot2":"attack";row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",a.action},{"mind",a.mind}};row["damage_multiplier"]=damage(c,id)*focusScale(c,id);row["hit_count"]=key=="flurry_shot"?3:1;row["max_range_m"]=w->getMaxRange();row["min_range_m"]=0;row["ammo_cost"]=a.gesture?0:1;row["weapon_requirement"]="Certified ordinary rifle and corresponding Rifleman training. Movement spread, support and posture benefits remain unchanged.";
   row["description"]=key=="lethal_shot"?"Heavy single-target Head Shot; improves with Head Shot III. Shares the Lethal Shot slot and cooldown, with twice normal weapon recovery.":key=="piercing_shot"?"A 2.0x hit that halves current Kinetic/Energy body resistance for this projectile after Fractured Armour; shields, other channels and defenses are unchanged.":key=="flurry_shot"?"Three separately aimed 0.8x projectiles at one designated enemy, spaced 0.25 seconds apart; Flurry Shot II improves each to 0.9x. Costs and cooldown commit once.":key=="surprise_shot"?"A 2.0x hit, increased to 3.0x if the enemy has at least 80% effective Health when the projectile impacts.":key=="sniper_shot"?"One physical 6.0x projectile at a designated enemy, retaining normal defenses. Rifleman's Focus does not increase ultimate damage.":"For 8 seconds, ordinary rifle fire and compatible regular rifle specials deal 20% more damage. No stacking or refresh; ultimates remain unchanged.";
   if(key=="lethal_shot"){row["rifleman_upgrade"]=true;row["anatomical_part"]="head";}
   if(key=="flurry_shot"){row["volley_shots"]=3;row["volley_interval_seconds"]=corecu::pistoleer::VolleySpacing;row["interval_seconds"]=corecu::pistoleer::VolleySpacing;}
   if(a.gesture){row["category"]="gesture";row["self_only"]=true;row["required_profession_skill"]="combat_rifleman_speed_02";row["trigger_description"]="Release both triggers. Keep the rifle held, release the support hand, grasp beside its receiver, pull the bolt rearward and push it forward, then regrip the fore-end.";}
   if(a.ultimate){row["required_profession_skill"]="combat_rifleman_master";row["profession_requirement"]="Master Rifleman";row["trigger_description"]="Support the rifle, release both triggers, then press both together while aiming at the designated enemy.";}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){auto id=request.at("ability_id").get<std::string>();refresh(c);auto w=c->getWeapon();if(id!="rifleman_focus" || !learned(c,id) || !conditions(c,id) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_rifleman_unavailable");
  if(!request.contains("two_hands") || !request["two_hands"].is_boolean() || !request["two_hands"].get<bool>())throw std::runtime_error("native_rifleman_requires_support");if(request.contains("target_id") || request.contains("volley_id") || request.contains("volley_index"))throw std::runtime_error("invalid_rifleman_target");if(cooldown(c,id)>0)throw std::runtime_error("native_rifleman_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_rifleman_attack_unavailable");auto p=c->getWorldPosition();std::array<double,3> feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_rifleman_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_rifleman_pose");}for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}if(!corecu::pistoleer::validPose(o,d,feet))throw std::runtime_error("invalid_rifleman_pose");
  auto a=corecu::rifleman::ability(id);if(c->getHAM(3)<=a.action || c->getHAM(6)<=a.mind)throw std::runtime_error("native_rifleman_insufficient_sac");c->inflictDamage(c,3,a.action,false,true,false);c->inflictDamage(c,6,a.mind,false,true,false);c->addCooldown(String(("swgxr_smuggler_"+id).c_str()),a.cooldown*1000);ManagedReference<Buff*> buff=new Buff(c,STRING_HASHCODE("swgxr_rifleman_focus"),corecu::rifleman::FocusSeconds,BuffType::STATE);Locker lock(buff,c);c->addBuff(buff);
  return {{"success",true},{"operation","rifleman"},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",.25},{"ham_cost_committed",true},{"hit",false},{"damage",0}};
 }
};
