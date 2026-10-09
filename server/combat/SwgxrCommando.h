#pragma once
#include "VolleyFirePolicy.h"
#include "CommandoPolicy.h"
#include "PistoleerPolicy.h"
#include "CombatQueueCommand.h"
#include "CoreCuCombat.h"
#include "SwgxrBlastSight.h"
#include <chrono>
#include <map>
#include <vector>
class SwgxrCommandoStrike : public CombatQueueCommand {
 double cap;bool projectile;
public:
 SwgxrCommandoStrike(const CombatQueueCommand& source,WeaponObject* w,double damage,double scale,double range,bool contact=false):CombatQueueCommand(source),cap(damage*scale*1.5),projectile(contact){
  setMinDamage(damage);setMaxDamage(damage);setDamageMultiplier(scale);setWeaponType(w->getWeaponBitmask());setRange(int(std::ceil(range)));
  setAreaAction(false);setConeAction(false);setPoolsToDamage(1);setHealthCostMultiplier(0);setActionCostMultiplier(0);setMindCostMultiplier(0);setForceCostMultiplier(0);
  Vector<DotEffect> empty;setDotEffects(empty);
 }
 bool usesClientProjectileContact() const override{return projectile;}
 bool usesPhysicalContactAccuracy() const override{return true;}
 bool usesNormalizedWeaponDamage() const override{return true;}
 bool allowsWeaponDots() const override{return false;}
 double getPhysicalDamageCap() const override{return cap;}
 int doQueueCommand(CreatureObject* c,const uint64& target,const UnicodeString& arguments) const override{return doCombatAction(c,target,arguments);}
};
class SwgxrCommando {
 using Json=JSONSerializationType;using Vec=corecu::commando::Vec;using Family=corecu::commando::Family;
 struct Candidate {ManagedReference<TangibleObject*> target;double weight,distance;};
 struct Receipt {ManagedReference<WeaponObject*> weapon;std::string session,ability,target;Vec origin{},direction{};double time=0,range=0,damage=0,blast=0,minDamage=0,maxDamage=0;int damageType=0,armorPiercing=0;uint64 zone=0,cell=0;bool spent=false;};
 // Accessed only under SwgxrLiveCombat's process-wide engine-cross-lock mutex.
 static std::map<uint64,std::map<std::string,Receipt>>& receipts(){static std::map<uint64,std::map<std::string,Receipt>> value;return value;}
 static long long wallMillis(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static void recoverAfter(CreatureObject* c,const std::string& id,int milliseconds){c->addCooldown(String(("swgxr_commando_"+id).c_str()),milliseconds);c->getPlayerObject()->setScreenPlayData("swgxr_commando",String((id+"_until").c_str()),String(std::to_string(wallMillis()+milliseconds).c_str()));}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static Vec position(SceneObject* o){auto p=o->getWorldPosition();return {{p.getX(),p.getZ(),p.getY()}};}
 static uint64 cell(SceneObject* o){auto parent=o->getParent().get();return parent && parent->isCellObject()?parent->getObjectID():0;}
 static const CombatQueueCommand* command(CreatureObject* c){auto q=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));if(!q || !q->checkStateMask(c) || !q->checkInvalidLocomotions(c))throw std::runtime_error("native_commando_attack_unavailable");return q;}
 static bool eligible(CreatureObject* c,TangibleObject* a){return a && a!=c && a->getZone()==c->getZone() && (cell(a)==cell(c) || corecu::volley::guaranteed(c->getObjectID(),a->getObjectID())) && !a->isDestroyed() && a->isAttackableBy(c) && (a->isLairObject() || (a->isAiAgent() && !a->asAiAgent()->isPet() && !a->asAiAgent()->isDead() && !a->asAiAgent()->isIncapacitated()));}
 static Vec centre(TangibleObject* a){auto p=position(a);p[1]+=a->isCreatureObject()?std::max(.25,std::min(1.,double(a->asCreatureObject()->getHeight(false))*.65)):.8;return p;}
 static double radius(TangibleObject* a){return a->isCreatureObject()?std::max(.15,std::min(.6,double(a->asCreatureObject()->getHeight(false))*.3)):.6;}
 static std::vector<Candidate> targets(CreatureObject* c,const Vec& o,const Vec& d,double range,double cone,double beam,double blast,const std::string& bound){
  std::vector<Candidate> out;auto p=c->getWorldPosition();SortedVector<TreeEntry*> nearby(128,128);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range+blast+4,&nearby,true);
  for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent() && !obj->isLairObject())continue;auto a=obj->asTangibleObject();Locker lock(a,c);
   if(!bound.empty() && std::to_string(a->getObjectID())!=bound)continue;if(!eligible(c,a) || (!corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()) && !(blast>0?SwgxrBlastSight::clear(c,a,o):CollisionManager::checkLineOfSight(c,a))))continue;
   auto point=centre(a);double distance=corecu::commando::magnitude(corecu::commando::delta(point,o));double weight=blast>0?corecu::commando::blastWeight(distance,blast):corecu::commando::weight(o,d,point,range,cone,beam,radius(a));
   if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))weight=1.;
   if(weight>0)out.push_back({a,weight,distance});
  }
  std::sort(out.begin(),out.end(),[&](const Candidate& a,const Candidate& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a.target->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b.target->getObjectID());if(av!=bv)return av;return a.distance==b.distance?a.target->getObjectID()<b.target->getObjectID():a.distance<b.distance;});
  if(out.size()>corecu::commando::TargetCap)out.resize(corecu::commando::TargetCap);return out;
 }
 static void burn(CreatureObject* c,TangibleObject* target,int damage){
  if(!target->isCreatureObject() || damage<=0)return;auto a=target->asCreatureObject();if(a->isDead() || a->isIncapacitated() || a->hasDotImmunity(CreatureState::ONFIRE) || (a->isAiAgent() && (a->asAiAgent()->getCreatureBitmask()&ObjectFlag::NODOT)))return;
  int budget=corecu::commando::burnBudget(damage);if(budget>0)a->addDotState(c,STRING_HASHCODE("swgxr_commando_burn"),CreatureState::ONFIRE,budget,CreatureAttribute::HEALTH,6,95,a->getSkillMod("resistance_fire"));
 }
 static Json resolve(CreatureObject* c,WeaponObject* w,const CombatQueueCommand* source,std::vector<Candidate>& chosen,double damage,double range,bool flame,const Vec* blastOrigin=nullptr){
  Json out={{"targets",Json::array()},{"hit",false},{"damage",0}};std::vector<double> requested;for(const auto& a:chosen)requested.push_back(a.weight);auto weights=corecu::commando::weights(requested);int total=0;
  for(unsigned i=0;i<chosen.size();++i){auto a=chosen[i].target;Locker lock(a,c);if(!eligible(c,a) || (!corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()) && !(blastOrigin?SwgxrBlastSight::clear(c,a,*blastOrigin):CollisionManager::checkLineOfSight(c,a))))continue;
   int before=a->isCreatureObject()?a->asCreatureObject()->getHAM(0):a->getMaxCondition()-a->getConditionDamage();SwgxrCommandoStrike strike(*source,w,damage,weights[i],range+8,blastOrigin!=nullptr);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);
   int after=a->isCreatureObject()?a->asCreatureObject()->getHAM(0):a->getMaxCondition()-a->getConditionDamage();int dealt=code==QueueCommand::SUCCESS?std::max(0,before-after):0;if(flame)burn(c,a,dealt);total+=dealt;out["targets"].push_back({{"target_id",std::to_string(a->getObjectID())},{"damage",dealt},{"native_result",code}});
  }
  out["damage"]=total;out["hit"]=total>0;return out;
 }
 static void pay(CreatureObject* c,WeaponObject* w,Family family,const std::string& ability){
  auto spec=corecu::commando::weapon(family);bool over=ability=="overdrive",focus=ability=="focused_discharge",spray=ability=="acid_spray";
  int action=over?80:corecu::commando::action(family,training(c),active(c),focus,spray),mind=over?40:corecu::commando::mind(family,focus,spray);
  Locker lock(w,c);if(c->getWeapon()!=w || !compatible(c) || (spec.charged && !over && w->getUseCount()<1))throw std::runtime_error("native_commando_empty_or_changed_weapon");
  if(c->getHAM(3)<=action || c->getHAM(6)<=mind)throw std::runtime_error("native_commando_insufficient_sac");
  c->inflictDamage(c,3,action,false,true,false);c->inflictDamage(c,6,mind,false,true,false);
  if(spec.charged && !over){w->setUseCount(w->getUseCount()-1,true);if(w->getUseCount()==0){ManagedReference<WeaponObject*> empty=w;Core::getTaskManager()->scheduleTask([empty](){Locker lock(empty);if(empty->getUseCount()==0){empty->destroyObjectFromWorld(true);empty->destroyObjectFromDatabase(true);}},"SwgxrCommandoEmptyWeapon",9000);}}
  if(!ability.empty())recoverAfter(c,ability,1000*(over?corecu::commando::OverdriveCooldown:focus?corecu::commando::FocusCooldown:corecu::commando::SprayCooldown));
  recoverAfter(c,"fire",int(1000*(over?.25:interval(c,family))));
 }
public:
 static Family family(WeaponObject* w){return w?corecu::commando::classify(w->getObjectTemplate()->getFullTemplateString().toCharArray()):corecu::commando::None;}
 static bool supported(WeaponObject* w){return family(w)!=corecu::commando::None;}
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && supported(w) && c->hasSkill("combat_commando_novice") && w->isCertifiedFor(c) && !w->isBroken();}
 static double training(CreatureObject* c){Vector<String> list;c->getSkillList()->getStringList(list);double value=0;for(int i=0;i<list.size();++i)value+=corecu::progressWeight("combat_commando",list.get(i).toCharArray());return corecu::clamp(value,0,1);}
 static bool learned(CreatureObject* c,const std::string& id){if(!c->hasSkill("combat_commando_novice"))return false;if(id.empty() || id=="focused_discharge")return true;if(id=="overdrive")return c->hasSkill("combat_commando_master");return id=="acid_spray" && c->getPlayerObject() && (c->getPlayerObject()->hasAbility("fireAcidCone1") || c->getPlayerObject()->hasAbility("fireAcidCone2"));}
 static bool active(CreatureObject* c){return compatible(c) && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_overdrive"));}
 static void refresh(CreatureObject* c){if(!compatible(c) || c->isDead() || c->isIncapacitated())c->removeBuff(STRING_HASHCODE("swgxr_overdrive"));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("swgxr_commando_"+id).c_str()));double remaining=t?std::max(0.,-t->miliDifference()/1000.):0.;auto ghost=c->getPlayerObject();if(ghost){auto saved=ghost->getScreenPlayData("swgxr_commando",String((id+"_until").c_str()));if(!saved.isEmpty())try{remaining=std::max(remaining,corecu::clamp((std::stoll(saved.toCharArray())-wallMillis())/1000.,0,120));}catch(...){}}return remaining;}
 static double interval(CreatureObject* c,Family f){return corecu::commando::cadence(f,training(c))/SwgxrArmour::scale(c,1);}
 static bool conditions(CreatureObject* c,const std::string& id){auto w=c->getWeapon();return compatible(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && (id!="acid_spray" || family(w)==corecu::commando::AcidRifle) && (id!="overdrive" || !active(c)) && (id=="overdrive" || !corecu::commando::weapon(family(w)).charged || w->getUseCount()>0);}
 static Json profile(CreatureObject* c){auto w=c->getWeapon();auto f=family(w);if(f==corecu::commando::None)return Json::object();auto s=corecu::commando::weapon(f);double q=corecu::commando::quality(f,w->getMinDamage(),w->getMaxDamage());return {{"native_family","commando"},{"commando_family",s.name},{"class_key",std::string("commando_")+s.name},{"delivery",s.delivery},{"fire_interval_seconds",interval(c,f)},{"special_interval_seconds",interval(c,f)},{"max_range_m",std::min(s.range,double(w->getMaxRange()))},{"projectile_speed",corecu::commando::ProjectileSpeed},{"cone_angle_degrees",s.cone},{"beam_radius_m",s.radius},{"area_radius_m",s.blast},{"target_cap",corecu::commando::TargetCap},{"area_budget_multiplier",corecu::commando::AggregateBudget},{"charges",s.charged?int(w->getUseCount()):-1},{"charge_limited",s.charged},{"action_cost",corecu::commando::action(f,training(c),active(c))},{"mind_cost",corecu::commando::mind(f)},{"normalized_damage",corecu::commando::damage(f,q,false,false,training(c))},{"craft_quality_multiplier",q},{"reference_conversion_scale",corecu::commando::referenceProfile(f).damageScale},{"proficiency_damage_scale",corecu::commando::proficiency(training(c),q)},{"handling_damage_scale",corecu::commando::handling(f)},{"requires_two_hands",f!=corecu::commando::PistolLauncher},{"conditions_met",conditions(c,"")},{"cooldown_remaining_seconds",cooldown(c,"fire")}};}
 static Json snapshot(CreatureObject* c){refresh(c);Json out=Json::object();auto f=family(c->getWeapon());for(auto id:{"focused_discharge","acid_spray","overdrive"}){bool over=std::string(id)=="overdrive",focus=std::string(id)=="focused_discharge";out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",over?120:focus?12:6},{"action_cost",over?80:corecu::commando::action(f,training(c),active(c),focus,!focus)},{"mind_cost",over?40:corecu::commando::mind(f,focus,!focus)},{"interval_seconds",over?.25:interval(c,f)}};}
 auto buff=c->getBuff(STRING_HASHCODE("swgxr_overdrive"));out["overdrive"]["active"]=active(c);out["overdrive"]["active_remaining_seconds"]=active(c)&&buff?std::max(0.f,buff->getTimeLeft()):0.;out["overdrive"]["duration_seconds"]=6;return out;}
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);auto f=family(c->getWeapon());for(auto id:{"focused_discharge","acid_spray","overdrive"}){if(!learned(c,id) || (std::string(id)=="acid_spray" && f!=corecu::commando::AcidRifle))continue;bool over=std::string(id)=="overdrive",focus=std::string(id)=="focused_discharge";auto row=state[id];row["id"]=id;row["label"]=over?"Overdrive":focus?"Focused Discharge":"Acid Spray";row["native_family"]="commando";row["activation"]=over?"commando_ultimate":"native_ranged";row["ultimate"]=over;row["native_authority"]=true;row["source_command"]="attack";row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",row["action_cost"]},{"mind",row["mind_cost"]}};row["damage_multiplier"]=focus?1.15:over?1.25:.70;row["max_range_m"]=std::string(id)=="acid_spray"?14:profile(c)["max_range_m"].get<double>();row["min_range_m"]=0;row["ammo_cost"]=over?0:1;row["target_cap"]=focus?1:6;
 row["weapon_requirement"]="Certified equipped Commando special weapon; support with both hands except the pistol launcher.";row["description"]=over?"For 6 seconds, direct special-weapon damage increases 25% and its Action cost increases 50%. Charges, cadence, area caps and burn strength remain unchanged. Cooldown 120 seconds.":focus?"Concentrate one supported discharge on the designated enemy for 15% more direct damage, sacrificing all area coverage. Normal charges and weapon recovery; 12-second cooldown.":"Aim a 30-degree acid spray up to 14 metres at the designated enemy. Up to six enemies share bounded 70% direct damage with falloff; no armour debuff. Six-second cooldown.";
 if(over){row["self_only"]=true;row["required_profession_skill"]="combat_commando_master";row["profession_requirement"]="Master Commando";row["trigger_description"]="Support the special weapon, release both triggers, then press both together.";}out.push_back(row);}return out;}
 static bool pending(CreatureObject* c,const Json& request){auto& all=receipts();auto found=all.find(c->getObjectID());if(found==all.end())return false;auto shot=found->second.find(request.at("shot_id").get<std::string>());return shot!=found->second.end() && shot->second.session==request.at("session_id").get<std::string>();}
 static Json run(CreatureObject* c,const Json& request){
  refresh(c);auto verb=request.at("action").get<std::string>(),ability=request.value("ability_id",std::string()),shotID=request.at("shot_id").get<std::string>();double stamp=now();auto& shots=receipts()[c->getObjectID()];for(auto it=shots.begin();it!=shots.end();)if(stamp-it->second.time>30)it=shots.erase(it);else ++it;
  if(verb=="impact"){
   auto found=shots.find(shotID);if(found==shots.end() || found->second.session!=request.at("session_id").get<std::string>() || found->second.spent)throw std::runtime_error("unknown_or_spent_commando_shot");auto& shot=found->second;shot.spent=true;
   Vec hit{};const auto& h=request.at("hit_position");if(!h.is_array() || h.size()!=3)throw std::runtime_error("invalid_commando_impact");for(int i=0;i<3;++i){if(!h[i].is_number())throw std::runtime_error("invalid_commando_impact");hit[i]=h[i].get<double>();}
   if(stamp-shot.time>8 || (!corecu::volley::target(c->getObjectID()) && !corecu::commando::validImpact(shot.origin,shot.direction,hit,shot.range,request.value("projectile_age_seconds",-1.),stamp-shot.time)) || c->getZone()->getObjectID()!=shot.zone || cell(c)!=shot.cell)throw std::runtime_error("invalid_commando_impact");
   if(shot.weapon->getMinDamage()!=shot.minDamage || shot.weapon->getMaxDamage()!=shot.maxDamage || shot.weapon->getDamageType()!=shot.damageType || shot.weapon->getArmorPiercing()!=shot.armorPiercing)throw std::runtime_error("launch_weapon_changed");
   auto target=request.at("target_id").get<std::string>();if(!shot.target.empty() && target!=shot.target)throw std::runtime_error("ability_target_mismatch");
   auto chosen=targets(c,hit,shot.direction,shot.range,0,0,shot.blast,shot.target);if(!shot.target.empty()){
    auto object=c->getZoneServer()->getObject(std::stoull(target));if(!object || !object->isTangibleObject())throw std::runtime_error("invalid_commando_target");auto a=object->asTangibleObject();Locker lock(a,c);if(!eligible(c,a) || corecu::commando::magnitude(corecu::commando::delta(centre(a),hit))>radius(a)+2.)throw std::runtime_error("invalid_commando_target");chosen={{a,1,0}};
   }
   auto out=resolve(c,shot.weapon,command(c),chosen,shot.damage,shot.range+shot.blast,false,&hit);out["operation"]="impact";out["shot_id"]=shotID;out["ability_id"]=shot.ability;out["success"]=true;out["contact_authority"]="client";return out;
  }
  if(shots.count(shotID))throw std::runtime_error("duplicate_shot");if(shots.size()>=128)throw std::runtime_error("shot_budget");auto w=c->getWeapon();auto f=family(w);auto spec=corecu::commando::weapon(f);
  if(!conditions(c,ability) || !learned(c,ability) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_commando_unavailable");
  if(cooldown(c,"fire")>0 || (!ability.empty() && cooldown(c,ability)>0))throw std::runtime_error("native_commando_cooldown");
  bool over=ability=="overdrive",focus=ability=="focused_discharge",spray=ability=="acid_spray";
  if(verb=="fire"?(spec.delivery!=std::string("rocket") || over || spray):(spec.delivery==std::string("rocket") && !over))throw std::runtime_error("native_commando_delivery_mismatch");
  if((f!=corecu::commando::PistolLauncher || over) && !request.value("two_hands",false))throw std::runtime_error("native_commando_requires_support");
  if(request.contains("volley_id") || request.contains("volley_index"))throw std::runtime_error("unexpected_volley_fields");
  Vec o{},d{};for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_commando_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_commando_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}if(!corecu::pistoleer::validPose(o,d,position(c)))throw std::runtime_error("invalid_commando_pose");double length=corecu::commando::magnitude(d);for(auto& x:d)x/=length;
  auto bound=request.value("target_id",std::string());if((focus || spray)?bound.empty():!bound.empty())throw std::runtime_error("invalid_commando_target");auto source=command(c);
  double range=std::min(spray?14.:spec.range,double(w->getMaxRange())),cone=spray?30:focus?0:spec.cone,beam=focus?.15:spec.radius;
  auto chosen=targets(c,o,d,range,cone,beam,0,focus?bound:std::string());if(focus || spray){auto target=c->getZoneServer()->getObject(std::stoull(bound));if(!target || !target->isTangibleObject())throw std::runtime_error("native_commando_target_unavailable");auto a=target->asTangibleObject();Locker lock(a,c);if(!eligible(c,a) || (!corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()) && (!CollisionManager::checkLineOfSight(c,a) || corecu::commando::magnitude(corecu::commando::delta(centre(a),o))>range+radius(a))))throw std::runtime_error("native_commando_target_unavailable");if(verb!="fire" && std::none_of(chosen.begin(),chosen.end(),[&](const Candidate& v){return v.target==a;}))throw std::runtime_error("native_commando_target_unavailable");if(focus && !chosen.empty())chosen[0].weight=1.;}
  bool boosted=active(c);double q=corecu::commando::quality(f,w->getMinDamage(),w->getMaxDamage()),damage=corecu::commando::damage(f,q,focus,spray,training(c))*(boosted?corecu::commando::OverdriveDamage:1.);pay(c,w,f,ability);
  Receipt receipt;receipt.weapon=w;receipt.session=request.at("session_id").get<std::string>();receipt.ability=ability;receipt.target=focus?bound:std::string();receipt.origin=o;receipt.direction=d;receipt.time=stamp;receipt.range=range;receipt.damage=damage;receipt.minDamage=w->getMinDamage();receipt.maxDamage=w->getMaxDamage();receipt.damageType=w->getDamageType();receipt.armorPiercing=w->getArmorPiercing();receipt.blast=focus?0:spec.blast;receipt.zone=c->getZone()->getObjectID();receipt.cell=cell(c);receipt.spent=verb!="fire";shots.emplace(shotID,receipt);
  Json out={{"success",true},{"operation",verb},{"shot_id",shotID},{"ability_id",ability},{"interval_seconds",over?.25:interval(c,f)},{"ham_cost_committed",true},{"charge_committed",spec.charged && !over},{"hit",false},{"damage",0},{"delivery",spec.delivery}};
  if(over){ManagedReference<Buff*> buff=new Buff(c,STRING_HASHCODE("swgxr_overdrive"),6,BuffType::STATE);Locker lock(buff,c);c->addBuff(buff);return out;}if(verb=="fire")return out;
  // Overdrive increases direct damage only; fire receives the unboosted initiating budget.
  auto resolved=resolve(c,w,source,chosen,damage,range,false);if(f==corecu::commando::Flame)for(auto& row:resolved["targets"]){auto object=c->getZoneServer()->getObject(std::stoull(row["target_id"].get<std::string>()));if(object && object->isTangibleObject()){Locker lock(object,c);burn(c,object->asTangibleObject(),int(row["damage"].get<int>()/(boosted?corecu::commando::OverdriveDamage:1.)));}}
  for(auto it=resolved.begin();it!=resolved.end();++it)out[it.key()]=it.value();out["contact_authority"]="native_shape";return out;
 }
};
