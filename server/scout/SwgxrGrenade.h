#pragma once
#include "SwgxrVolleyFire.h"
#include "GrenadePolicy.h"
#include "SwgxrTka.h"
#include "SwgxrBlastSight.h"
#include "SwgxrGathering.h"
#include <chrono>
class SwgxrGrenadeStrike : public SwgxrTkaStrike {
 double cap;
public:
 SwgxrGrenadeStrike(const CombatQueueCommand& source,double damage):SwgxrTkaStrike(source,1),cap(damage){setMinDamage(damage/1.5);setMaxDamage(damage/1.5);setRange(128);}
 bool usesClientProjectileContact() const override {return true;}
 bool usesNormalizedWeaponDamage() const override {return true;}
 bool allowsWeaponDots() const override {return false;}
 double getPhysicalDamageCap() const override {return cap;}
};
// All acceptance and settlement occurs under the existing native character lock.
// The pending record is terminal before damage, so reconnect/task races cannot
// replay an explosion. A crash can lose an accepted explosion, never duplicate it.
class SwgxrGrenade {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static Json load(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_grenade","state");return raw.isEmpty()?Json{{"cooldown_until_ms",0},{"families",Json::object()},{"pending",Json::array()}}:Json::parse(raw.toCharArray());}
 static void save(CreatureObject* c,const Json& s){c->getPlayerObject()->setScreenPlayData("swgxr_grenade","state",String(s.dump().c_str()));}
 static double distance(CreatureObject* a,const Json& p){auto q=a->getWorldPosition();double x=q.getX()-p[0].get<double>(),y=q.getZ()-p[1].get<double>(),z=q.getY()-p[2].get<double>();return std::sqrt(x*x+y*y+z*z);}
 static bool blastSight(CreatureObject* c,CreatureObject* a,const Json& p){return SwgxrBlastSight::clear(c,a,{{p[0].get<double>(),p[1].get<double>(),p[2].get<double>()}});}
 static void control(CreatureObject* c,CreatureObject* a,const corecu::grenade::Spec& spec,int speed){
  if(spec.control==corecu::grenade::None || a->isDead() || a->isIncapacitated() || a->hasEffectImmunity(CommandEffect::NEXTATTACKDELAY) || !a->checkCooldownRecovery("corecu_control_recovery"))return;
  a->addCooldown("corecu_control_recovery",8000);double rating=CoreCuCombat::rating(a,corecu::Snare,a->getSkillMod("resistance_states"));
  if(System::random(99)>=corecu::grenade::chance(speed,rating))return;
  int duration=corecu::statusDuration(spec.duration,rating);
  bool glop=spec.control==corecu::grenade::Restrain;ManagedReference<Buff*> buff=new Buff(a,glop?STRING_HASHCODE("swgxr_glop"):STRING_HASHCODE("swgxr_cryoban"),duration,BuffType::STATE);Locker lock(buff,a);buff->setSkillModifier(glop?"private_commando_glop":"private_commando_cryo",glop?100:25);a->addBuff(buff);
 }
 static void clean(CreatureObject* c,const Json& row){auto object=c->getZoneServer()->getObject(std::stoull(row.at("item_id").get<std::string>()));auto w=object && object->isWeaponObject()?static_cast<WeaponObject*>(object.get()):nullptr;if(!w)return;Locker lock(w,c);if(w->getUseCount()==0){w->destroyObjectFromWorld(true);w->destroyObjectFromDatabase(true);}}
 static void explode(CreatureObject* c,const Json& row){
  if(!c->getZone() || c->getZone()->getZoneName().toCharArray()!=row.at("zone").get<std::string>() || c->getParentID()!=row.at("parent_id").get<uint64>() || c->isDead() || corecu::grenade::expired(now(),row.at("detonation_at_ms").get<long long>()))return;
  auto object=c->getZoneServer()->getObject(std::stoull(row.at("item_id").get<std::string>()));auto w=object && object->isWeaponObject()?static_cast<WeaponObject*>(object.get()):nullptr;
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("throwgrenade"));if(!w || !source)return;
  auto spec=corecu::grenade::spec(row.at("template").get<std::string>());auto point=row.at("landing_position");std::vector<ManagedReference<CreatureObject*>> targets;
  uint64 forced=0;if(row.value("volley_guaranteed",false)){auto marked=c->getZoneServer()->getObject(std::stoull(row.at("target_id").get<std::string>()));if(marked && marked->isCreatureObject()){auto a=marked->asCreatureObject();Locker lock(a,c);if(a->getZone()==c->getZone() && !a->isDead() && !a->isIncapacitated() && a->isAttackableBy(c)){forced=a->getObjectID();targets.push_back(a);}}}
  corecu::volley::Scope volley(c->getObjectID(),forced);
  SortedVector<TreeEntry*> nearby(64,64);c->getZone()->getInRangeObjects(point[0].get<float>(),point[1].get<float>(),point[2].get<float>(),spec.radius+2,&nearby,true);
  for(int i=0;i<nearby.size();++i){auto o=static_cast<SceneObject*>(nearby.get(i));if(!o->isCreatureObject())continue;auto a=o->asCreatureObject();Locker lock(a,c);if(a->getObjectID()!=forced && eligible(c,a) && distance(a,point)<=spec.radius && blastSight(c,a,point))targets.push_back(a);}
  std::sort(targets.begin(),targets.end(),[&](const ManagedReference<CreatureObject*>& a,const ManagedReference<CreatureObject*>& b){if((a->getObjectID()==forced)!=(b->getObjectID()==forced))return a->getObjectID()==forced;double da=distance(a,point),db=distance(b,point);return da==db?a->getObjectID()<b->getObjectID():da<db;});if(targets.size()>corecu::grenade::TargetCap)targets.resize(corecu::grenade::TargetCap);
  // Volley guarantees only the marked direct packet. Collateral and effects
  // stay at the accepted landing point; moving enemies never move the blast.
  auto weight=[&](CreatureObject* a){return a->getObjectID()==forced?1.:corecu::grenade::falloff(distance(a,point),spec.radius);};
  double sum=0;for(auto& a:targets)sum+=weight(a);double scale=corecu::grenade::aggregateScale(sum),remaining=row.at("packet").get<double>()*corecu::grenade::AggregateMultiplier;
  for(auto& a:targets){Locker lock(a,c);if(!eligible(c,a) || (!corecu::volley::guaranteed(c->getObjectID(),a->getObjectID())&&!blastSight(c,a,point)))continue;double damage=std::min(remaining,row.at("packet").get<double>()*weight(a)*scale);if(damage<=0)continue;remaining-=damage;SwgxrGrenadeStrike strike(*source,damage);int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);if(code==QueueCommand::SUCCESS && a->getHAM(0)<before)control(c,a,spec,row.at("thrown_speed").get<int>());}
 }
public:
 static long long now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static bool supported(SceneObject* o){return o && o->isWeaponObject() && static_cast<WeaponObject*>(o)->isThrownWeapon() && corecu::grenade::supported(o->getObjectTemplate()->getFullTemplateString().toCharArray());}
 static bool eligible(CreatureObject* c,SceneObject* o){auto a=o?o->asCreatureObject():nullptr;return a && a!=c && a->getZone()==c->getZone() && (a->getParentID()==c->getParentID() || corecu::volley::guaranteed(c->getObjectID(),a->getObjectID())) && !a->isDead() && !a->isIncapacitated() && a->isAttackableBy(c);}
 static void settle(CreatureObject* c){auto s=load(c);Json due=Json::array(),pending=Json::array();for(auto& row:s["pending"]){if(corecu::grenade::due(now(),row.at("detonation_at_ms").get<long long>()))due.push_back(row);else pending.push_back(row);}if(due.empty())return;s["pending"]=pending;save(c,s);for(auto& row:due){try{explode(c,row);}catch(...){clean(c,row);throw;}clean(c,row);}}
 static void status(CreatureObject* c,Json& state){settle(c);auto s=load(c);state["server_time_ms"]=now();state["grenade_cooldown"]=std::max(0.,(s.value("cooldown_until_ms",0LL)-now())/1000.);state["grenade_pending"]=Json::array();for(auto& row:s["pending"]){auto visible=row;for(auto key:{"template","zone","parent_id","packet","thrown_speed"})visible.erase(key);state["grenade_pending"].push_back(visible);}}
 static void acceptNative(CreatureObject* c,WeaponObject* w,CreatureObject* target,const Json& request,Json& mutation){
  settle(c);Locker targetLock(target,c);auto spec=corecu::grenade::spec(w->getObjectTemplate()->getFullTemplateString().toCharArray());auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("throwgrenade"));
  if(!supported(w) || !w->isCertifiedFor(c) || w->isBroken() || w->getUseCount()<1 || !source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c) || c->isRidingMount())throw std::runtime_error("grenade_equipment_or_training_required");
  if(!eligible(c,target) || !c->isInRange(target,corecu::grenade::Range) || (!corecu::volley::guaranteed(c->getObjectID(),target->getObjectID())&&!CollisionManager::checkLineOfSight(c,target)))throw std::runtime_error("grenade_target_unavailable");
  auto p=target->getWorldPosition();auto throwZone=c->getZone();auto throwParent=c->getParentID();targetLock.release();
  Locker itemLock(w,c);auto gathering=SwgxrGathering::load(c);if(SwgxrGathering::ownedTool(c,gathering,id(w)).get()!=w)throw std::runtime_error("grenade_ownership_changed");
  if(c->getZone()!=throwZone || c->getParentID()!=throwParent || c->isDead() || c->isIncapacitated() || c->isRidingMount() || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c) || !w->isCertifiedFor(c) || w->isBroken() || w->getUseCount()<1)throw std::runtime_error("grenade_equipment_or_state_changed");
  if(distance(c,Json::array({p.getX(),p.getZ(),p.getY()}))>corecu::grenade::Range)throw std::runtime_error("grenade_target_unavailable");
  auto s=load(c);auto stamp=now();if(s.value("cooldown_until_ms",0LL)>stamp || s["families"].value(spec.kind,0LL)>stamp)throw std::runtime_error("grenade_cooldown");
  int action=std::max(1,int(std::ceil(c->getBaseHAM(3)*.06))),mind=std::max(1,int(std::ceil(c->getBaseHAM(6)*.02)));if(c->getHAM(3)<=action || c->getHAM(6)<=mind)throw std::runtime_error("grenade_insufficient_sac");
  int speed=c->getSkillMod("thrown_speed");Json row={{"request_id",request.at("request_id")},{"item_id",id(w)},{"target_id",id(target)},{"landing_position",Json::array({p.getX(),p.getZ(),p.getY()})},{"fuse_seconds",corecu::grenade::FuseSeconds},{"detonation_at_ms",stamp+2000},{"radius_m",spec.radius},{"throwable_kind",spec.kind},{"template",std::string(w->getObjectTemplate()->getFullTemplateString().toCharArray())},{"zone",std::string(c->getZone()->getZoneName().toCharArray())},{"parent_id",c->getParentID()},{"packet",corecu::grenade::packet(spec,speed,corecu::grenade::quality(spec,w->getMinDamage(),w->getMaxDamage()))},{"thrown_speed",speed}};
  if(corecu::volley::guaranteed(c->getObjectID(),target->getObjectID()))row["volley_guaranteed"]=true;
  // Reserve the item immediately, including its last charge. Zero-charge remains
  // alive until settlement so the final throw retains weapon and visual metadata.
  w->setUseCount(w->getUseCount()-1,true);c->inflictDamage(c,3,action,false,true,false);c->inflictDamage(c,6,mind,false,true,false);s["cooldown_until_ms"]=stamp+int(corecu::grenade::recovery(speed)*1000);s["families"][spec.kind]=stamp+int(spec.familyCooldown*1000);s["pending"].push_back(row);save(c,s);
  mutation.update(row);for(auto key:{"template","zone","parent_id","packet","thrown_speed"})mutation.erase(key);mutation["charge_consumed"]=true;
  ManagedReference<CreatureObject*> player=c;Core::getTaskManager()->scheduleTask([player](){Locker lock(player);SwgxrGrenade::settle(player);},"SwgxrGrenadeDetonation",2001);
 }
 static void accept(CreatureObject* c,WeaponObject* w,CreatureObject* target,const Json& request,Json& mutation){
  if(!request.contains("volley_mark_id")&&!request.contains("volley_target_id")){acceptNative(c,w,target,request,mutation);return;}
  mutation=SwgxrVolleyFire::attack(c,request,corecu::grenade::Range,[&](TangibleObject* marked){if(marked!=target)throw std::runtime_error("native_volley_target_mismatch");Json result=Json::object();acceptNative(c,w,target,request,result);result["volley_deferred"]=true;return result;});
 }

};
