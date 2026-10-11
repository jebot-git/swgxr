#pragma once
#include "GroundActionPolicy.h"
#include "server/zone/Zone.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/objects/creature/commands/CombatQueueCommand.h"
#include "server/zone/packets/scene/AttributeListMessage.h"
#include <fstream>
#include <mutex>
#include <memory>
#include <atomic>

// Ordinary ground AI retains target/ability selection, navigation and lifecycle.
// Registry locks protect lookup only. Native object and strike locks use Engine
// cross-locking; no registry mutex is held while acquiring an object lock.
class SwgxrGroundCombat {
 using Json=JSONSerializationType;using Vec=corecu::action::Vec;using Attack=corecu::action::Attack;using Role=corecu::action::Role;using Shape=corecu::action::Shape;
 struct Peer {ManagedWeakReference<CreatureObject*> actor;double expires=0;};
 struct Victim {ManagedWeakReference<CreatureObject*> actor;corecu::ground::Victim state;Vec sample{};bool lineClear=false;};
 struct Strike {
  Mutex mutex;ManagedWeakReference<AiAgent*> actor;ManagedWeakReference<CreatureObject*> target;
  ManagedReference<WeaponObject*> weapon,heldWeapon;const CombatQueueCommand* command=nullptr;std::shared_ptr<CreatureAttackData> data;double attackReach=0;bool special=false,targeted=false,impactCentered=false,animationFallback=false;
  Attack attack;corecu::ground::Pressure pressure;std::string cancelReason;Json profile,event;uint64 cell=0,revision=0;double published=0,release=0;bool done=false,paid=false;
  std::map<uint64,Victim> victims;
 };
 struct Pursuit {ManagedWeakReference<AiAgent*> actor;corecu::ground::Pressure pressure;double seen=0;};
 static std::map<uint64,Pursuit>& pursuits(){static std::map<uint64,Pursuit> p;return p;}
 static std::mutex& mutex(){static std::mutex m;return m;}
 static Json& analytics(){static Json v=Json::array();return v;}
 static std::map<uint64,Peer>& peers(){static std::map<uint64,Peer> p;return p;}
 static std::map<uint64,std::shared_ptr<Strike>>& strikes(){static std::map<uint64,std::shared_ptr<Strike>> s;return s;}
 static std::shared_ptr<Strike> find(uint64 actor){std::lock_guard<std::mutex> l(mutex());auto i=strikes().find(actor);return i==strikes().end()?nullptr:i->second;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static Vec point(CreatureObject* c){auto p=c->getWorldPosition();return {{p.getX(),p.getZ(),p.getY()}};}
 static void face(AiAgent* actor,const Vec& aim){double yaw=std::atan2(aim[0],aim[2]);auto root=actor->getRootParent();if(root&&root->isBuildingObject())yaw-=root->getDirectionAngle()*3.141592653589793/180.;actor->setDirection(yaw);}
 static bool alive(CreatureObject* c){return c&&c->getZone()&&!c->isDead()&&!c->isIncapacitated();}
 static std::string mode(){const char* e=std::getenv("SWGXR_GROUND_ACTIONS");return e?e:"off";}
 static bool enabled(){return mode()=="mos_eisley"||mode()=="global";}
 static bool inScope(AiAgent* actor){if(!alive(actor)||actor->isPet())return false;auto h=actor->getHomeLocation()->getWorldPosition();return corecu::ground::inScope(mode(),actor->getZone()->getZoneName().toCharArray(),{{h.getX(),h.getZ(),h.getY()}},point(actor));}
 // Only engaged, living players keep pursuit alive. Bystanders never extend it.
 static double nearestEngaged(AiAgent* actor,bool& playerEncounter){
  double nearest=std::numeric_limits<double>::infinity();playerEncounter=false;
  std::vector<ManagedReference<CreatureObject*>> targets;const auto defenders=actor->getDefenderList();
  for(int i=0;i<defenders->size();++i){auto o=defenders->getSafe(i);if(o&&o->isCreatureObject())targets.push_back(o->asCreatureObject());}
  auto follow=actor->getFollowObject().get();if(follow&&follow->isCreatureObject())targets.push_back(follow->asCreatureObject());
  for(auto& c:targets){Locker other(c,actor);if(!c->isPlayerCreature()){if(alive(c)){playerEncounter=false;return 0;}continue;}playerEncounter=true;
   if(alive(c)&&c->isOnline()&&c->getZone()==actor->getZone()&&c->getParentID()==actor->getParentID())nearest=std::min(nearest,corecu::action::distance(point(c),point(actor)));
  }return nearest;
 }
 static bool pursuitExpired(AiAgent* actor){
  if(!inScope(actor)||!actor->isInCombat()||(actor->getMovementState()==AiAgent::LEASHING)){std::lock_guard<std::mutex> l(mutex());pursuits().erase(actor->getObjectID());return false;}
  bool playerEncounter=false;double nearest=nearestEngaged(actor,playerEncounter);auto h=actor->getHomeLocation()->getWorldPosition();double homeDistance=corecu::action::distance(point(actor),{{h.getX(),h.getZ(),h.getY()}});auto w=actor->getWeapon();double range=w?w->getMaxRange():3;
  std::lock_guard<std::mutex> l(mutex());if(!playerEncounter){pursuits().erase(actor->getObjectID());return false;}double stamp=now();static double pruned=0;if(stamp-pruned>10){pruned=stamp;for(auto i=pursuits().begin();i!=pursuits().end();)if(stamp-i->second.seen>60)i=pursuits().erase(i);else ++i;}
  auto& p=pursuits()[actor->getObjectID()];p.actor=actor;p.seen=stamp;return p.pressure.disengage(stamp,homeDistance,nearest,range,playerEncounter);
 }
 static const Json& catalog(){static Json c=[](){try{const char* p=std::getenv("SWGXR_GROUND_ACTION_CATALOG");std::ifstream f(p?p:"/workspace/runtime/assets/combat_actions/catalog.json");Json j;f>>j;if(j.at("schema")!=2||(mode()=="global"&&!j.at("scope").value("global_enabled",false)))return Json();return j;}catch(...){return Json();}}();return c;}
 static bool capable(uint64 id){std::lock_guard<std::mutex> l(mutex());auto i=peers().find(id);return i!=peers().end()&&i->second.expires>now();}
 static bool eligible(CreatureObject* c,AiAgent* actor,uint64 cell){return alive(c)&&c->isPlayerCreature()&&c->isOnline()&&!c->getPlayerObject()->isOnLoadScreen()&&c->getZone()==actor->getZone()&&c->getParentID()==cell&&c->isAttackableBy(actor)&&capable(c->getObjectID());}
 static std::string slot(WeaponObject* w){if(!w)return "";if(w->isPistolWeapon())return "pistol";if(w->isRifleWeapon())return "rifle";if(w->isCarbineWeapon())return "carbine";if((w->isOneHandMeleeWeapon()||w->isJediOneHandedWeapon()))return "onehand";if((w->isTwoHandMeleeWeapon()||w->isJediTwoHandedWeapon()))return "twohand";if((w->isPolearmWeaponObject()||w->isJediPolearmWeapon()))return "polearm";if(w->isUnarmedWeapon())return "unarmed";return "";}
 static void sync(Victim& v,const Attack& a){v.state.attack.aim=a.aim;v.state.attack.aimRevision=a.aimRevision;v.state.attack.aimLocked=a.aimLocked;v.state.attack.geometryOrigin=a.geometryOrigin;}
 static void publish(AiAgent* actor,Strike& s,const char* phase){
  auto& a=s.attack;auto spec=a.settings();s.published=now();++s.revision;
  Json victims=Json::array();for(auto& v:s.victims)victims.push_back(std::to_string(v.first));
  s.event={{"protocol",2},{"id",std::to_string(actor->getObjectID())},{"encounter_id",std::to_string(actor->getObjectID())},{"attack_id",std::to_string(a.id)},{"target_id",s.event.value("target_id",std::string("1"))},{"cell_id",std::to_string(s.cell)},{"phase",phase},{"role",a.role==Role::Ranged?"ranged":"melee"},{"hit_policy",s.profile.at("hit_policy")},{"eligible_victim_ids",victims},{"origin",a.origin},{"direction",a.aim},{"start",a.start},{"server_now",now()},{"delivery_at",a.deliveryAt()},{"active_at",a.activeAt()},{"end_at",a.endAt()},{"animation_end_at",a.animationEndAt()},{"recover_at",s.release},{"animation",s.profile.at("animation")},{"range",spec.range},{"radius",spec.radius},{"cosine",spec.cosine},{"aim_revision",a.aimRevision},{"aim_locked",a.aimLocked},{"lock_at",a.lockAt()},{"state_revision",s.revision},{"sequence",s.revision},{"age_ms",0},{"enemy_cl",actor->getLevel()},{"tracking_degrees_per_second",12*a.trackingScale},{"tracking_metres_per_second",2*a.trackingScale},{"weapon_template",s.heldWeapon?std::string(s.heldWeapon->getObjectTemplate()->getFullTemplateString().toCharArray()):""}};
  s.event["shape"]=a.shape==Shape::Circle?"circle":a.shape==Shape::Targeted?"targeted":a.shape==Shape::Cone?"cone":"lane";
  s.event["geometry_origin"]=a.shape==Shape::Circle?a.geometryOrigin:a.origin;s.event["special"]=s.special;s.event["animation_fallback"]=s.animationFallback;s.event["target_required"]=s.targeted;s.event["command"]=std::string(s.command->getQueueCommandName().toCharArray());
  if(!s.cancelReason.empty())s.event["cancel_reason"]=s.cancelReason;
  auto message=new AttributeListMessage(actor->getObjectID());message->insertAttribute("swgxr.action.event",String(s.event.dump().c_str()));actor->broadcastMessage(message,true);
 }
 static void cancel(AiAgent* actor,Strike& s,const char* reason="interrupted"){if(s.attack.cancelled)return;s.cancelReason=reason;s.done=true;s.attack.cancelled=true;publish(actor,s,"cancelled");}
 static void schedule(const std::shared_ptr<Strike>& s){Core::getTaskManager()->scheduleTask([s](){auto actor=s->actor.get();if(!actor){std::lock_guard<std::mutex> l(mutex());for(auto i=strikes().begin();i!=strikes().end();++i)if(i->second==s){strikes().erase(i);break;}return;}Locker l(actor);Locker guard(&s->mutex,actor);try{tick(actor,s);}catch(const std::exception&){cancel(actor,*s);}},"CoreCUGroundAttack",50);}
 static void tick(AiAgent* actor,const std::shared_ptr<Strike>& s){
  double stamp=now();auto& a=s->attack;
  if(stamp>s->release+1){std::lock_guard<std::mutex> l(mutex());auto i=strikes().find(actor->getObjectID());if(i!=strikes().end()&&i->second==s)strikes().erase(i);return;}
  if(s->done){schedule(s);return;}
  if(!alive(actor)||!actor->isInCombat()||actor->isKnockedDown()||actor->isStunned()||actor->getParentID()!=s->cell||!inScope(actor)||corecu::action::distance(point(actor),a.origin)>.5||actor->getWeapon()!=s->heldWeapon){cancel(actor,*s);schedule(s);return;}
  if(pursuitExpired(actor)){cancel(actor,*s,"disengaged");actor->leash(true);schedule(s);return;}
  auto target=s->target.get();
  if(!a.aimLocked){
   bool engaged=false;double nearest=nearestEngaged(actor,engaged);
   if(s->pressure.cancelPreparation(stamp,a.lockAt(),a.aimLocked,nearest,(s->impactCentered?s->attackReach+a.settings().range:std::max(s->attackReach,a.settings().range)),a.role==Role::Ranged)){cancel(actor,*s,"targets_out_of_reach");actor->addCooldown("corecu_ground_reposition",400);actor->activateAiBehavior();schedule(s);return;}
   auto follow=actor->getFollowObject().get();if(!target||!follow||follow->getObjectID()!=target->getObjectID()){cancel(actor,*s);schedule(s);return;}Locker other(target,actor);
   if(!eligible(target,actor,s->cell)||!actor->isInCombat()){cancel(actor,*s);schedule(s);return;}
   if(s->impactCentered&&stamp<a.lockAt()){
    auto desired=point(target);double d=corecu::action::distance(a.geometryOrigin,desired);double dt=std::min(.1,std::max(0.,stamp-std::max(a.start,a.trackedAt)));double fraction=d>.001?std::min(1.,2*a.trackingScale*dt/d):0;
    if(fraction>0){for(int axis=0;axis<3;++axis)a.geometryOrigin[axis]+=(desired[axis]-a.geometryOrigin[axis])*fraction;++a.aimRevision;}
   }
   a.prepare(stamp,point(target));face(actor,a.aim);
  }
  for(auto& v:s->victims){sync(v.second,a);if(stamp>=a.activeAt()&&stamp<=a.endAt()){auto c=v.second.actor.get();if(c){Locker other(c,actor);if(eligible(c,actor,s->cell)&&CollisionManager::checkLineOfSight(actor,c))v.second.lineClear=true;}}}
  if(stamp>=a.deliveryAt()&&!s->paid){
   s->paid=CombatManager::instance()->applyProjectileLaunchCost(actor,s->weapon,*s->data);
   if(!s->paid){cancel(actor,*s);schedule(s);return;}publish(actor,*s,"active");
  }else if(stamp-s->published>=.1)publish(actor,*s,s->paid?"active":"windup");
  bool ready=stamp>=a.endAt();for(auto& v:s->victims)ready=ready&&v.second.state.ready(stamp);
  if(ready){
   std::vector<std::pair<double,uint64>> hits;
   for(auto& item:s->victims){auto c=item.second.actor.get();auto& v=item.second.state;
    if(!c){v.waived=true;continue;}Locker other(c,actor);
    if(!eligible(c,actor,s->cell)){v.waived=true;continue;}
    bool hit=v.resolve();{std::lock_guard<std::mutex> l(mutex());analytics().push_back({{"actor_id",std::to_string(actor->getObjectID())},{"attack_id",std::to_string(a.id)},{"delivered",false},{"damage",0},{"warned",v.warned},{"victim_id",std::to_string(item.first)},{"contact",hit},{"waived",v.waived},{"acknowledged",v.acknowledged},{"reported",v.attack.reported}});if(analytics().size()>512)analytics().erase(analytics().begin());}
    if(hit)hits.push_back({(item.second.sample[0]-a.origin[0])*a.aim[0]+(item.second.sample[2]-a.origin[2])*a.aim[2],item.first});
   }
   std::sort(hits.begin(),hits.end());if(s->profile.at("hit_policy")=="first_contact"&&hits.size()>1)hits.resize(1);
   corecu::ground::ResolveScope once(actor->getObjectID());
   for(auto& hit:hits){auto c=s->victims[hit.second].actor.get();if(!c)continue;Locker other(c,actor);corecu::action::ContactScope confirmed(actor->getObjectID(),c->getObjectID());int before=c->getHAM(0);int native=CombatManager::instance()->doCombatAction(actor,s->weapon,c,*s->data);{std::lock_guard<std::mutex> l(mutex());for(auto& row:analytics())if(row["attack_id"]==std::to_string(a.id)&&row["victim_id"]==std::to_string(c->getObjectID())){row["delivered"]=native>=0;row["native_result"]=native;row["damage"]=std::max(0,before-c->getHAM(0));break;}}}
   s->done=true;a.settled=true;publish(actor,*s,"recovery");
  }
  schedule(s);
 }
public:
 static bool updatePursuit(AiAgent* actor){
  if(!pursuitExpired(actor))return false;
  auto s=find(actor->getObjectID());if(s){Locker guard(&s->mutex,actor);cancel(actor,*s,"disengaged");}
  actor->leash(true);return true;
 }
 static bool held(AiAgent* actor){auto s=find(actor->getObjectID());if(!s)return false;Locker guard(&s->mutex,actor);return !s->attack.cancelled&&now()<s->release;}
 static bool begin(AiAgent* actor,CreatureObject* target,WeaponObject* weapon,const CreatureAttackData& data){
  const auto command=data.getCommand();
  if(!enabled()||!inScope(actor)||(actor->getMovementState()==AiAgent::LEASHING)||!target||!target->isPlayerCreature()||!command||!capable(target->getObjectID()))return false;
  if(held(actor))return true;
  const auto& cat=catalog();if(cat.is_null())return false;
  auto name=std::string(actor->getObjectTemplate()->getFullTemplateString().toCharArray());if(!cat.at("templates").contains(name))return false;
  auto profiles=cat.at("templates").at(name).at("profiles");auto key=slot(weapon);if(key=="unarmed"&&profiles.contains("creature"))key="creature";if(weapon&&weapon->isRangedWeapon()&&profiles.contains("ranged"))key="ranged";if(!profiles.contains(key)){key=profiles.contains("unarmed")?"unarmed":profiles.contains("rifle")?"rifle":key;}if(!profiles.contains(key))return false;
  if(!actor->checkCooldownRecovery("corecu_ground_reposition"))return true;
  auto s=std::make_shared<Strike>();s->actor=actor;s->target=target;s->weapon=weapon;s->heldWeapon=actor->getWeapon();s->command=command;s->data=std::make_shared<CreatureAttackData>(data);s->profile=profiles.at(key);s->cell=actor->getParentID();s->event["target_id"]=std::to_string(target->getObjectID());
  s->special=command->getNameCRC()!=String("attack").hashCode()&&command->getNameCRC()!=String("defaultattack").hashCode()&&command->getNameCRC()!=String("defaultdroidattack").hashCode();
  auto family=cat.at("templates").at(name).at("family").get<std::string>();auto binding=key+":"+std::string(command->getQueueCommandName().toCharArray());
  if(s->special&&cat.contains("special_bindings")&&cat.at("special_bindings").contains(family)&&cat.at("special_bindings").at(family).contains(binding)){auto profile=cat.at("special_bindings").at(family).at(binding).get<std::string>();s->profile=cat.at("special_profiles").at(profile);}
  s->animationFallback=s->profile.value("visual_fallback",false)||(s->special&&s->profile.at("animation").get<std::string>().find("action_ground_special_")!=0);
  s->targeted=(data.isForceAttack()||data.isStateOnlyAttack())&&!command->isAreaAction()&&!command->isConeAction();
  auto& a=s->attack;static std::atomic<uint64> serial{uint64(System::getMiliTime())};a.id=++serial;a.start=now()+.15;a.origin=point(actor);a.aim=corecu::action::direction(a.origin,point(target));a.role=s->profile.at("role")=="ranged"?Role::Ranged:Role::Melee;a.customized=true;a.trackingScale=corecu::ground::trackingScale(actor->getLevel());
  double range=std::min(96.,std::max(1.,double(data.getRange()>0?data.getRange():weapon->getMaxRange())));s->attackReach=range;
  a.shape=a.role==Role::Ranged?Shape::Lane:Shape::Cone;double cosine=.5;
  if(command->isConeAction()){a.shape=Shape::Cone;range=std::min(96.,std::max(1.,double(data.getConeRange()>0?data.getConeRange():range)));cosine=std::cos(std::min(360,std::max(1,data.getConeAngle()))*3.141592653589793/360.);s->profile["hit_policy"]="cleave";}
  else if(command->isAreaAction()){a.shape=Shape::Circle;range=std::min(96.,std::max(1.,double(data.getAreaRange()>0?data.getAreaRange():range)));s->impactCentered=data.isSplashDamage()||weapon->isThrownWeapon()||weapon->isHeavyWeapon();a.geometryOrigin=s->impactCentered?point(target):a.origin;s->profile["hit_policy"]="cleave";}
  else if(s->targeted){a.shape=Shape::Targeted;s->profile["hit_policy"]="targeted";}
  double commandSeconds=command->getSpeed()>0?command->getSpeed():CombatManager::instance()->calculateWeaponAttackSpeed(actor,weapon,data.getSpeedMultiplier());
  if(s->special)s->profile["windup"]=std::max(s->profile.at("windup").get<double>(),std::min(4.,commandSeconds*.6));
  a.profile={s->profile.at("windup").get<double>(),s->profile.at("contact_window").get<double>(),s->profile.at("recovery").get<double>(),range,.45,cosine,0};a.clipDuration=s->profile.at("duration");a.contactDelay=s->profile.at("contact_offset");a.lockLead=s->profile.at("lock_lead");
  s->release=std::max(a.recoveredAt(),a.start+commandSeconds);
  std::vector<Peer> candidates;{std::lock_guard<std::mutex> l(mutex());for(auto& p:peers())if(p.second.expires>now())candidates.push_back(p.second);}
  for(auto& p:candidates){auto c=p.actor.get();if(!c)continue;Locker other(c,actor);if((!s->targeted||c==target)&&eligible(c,actor,s->cell)&&corecu::action::distance(point(c),a.origin)<=s->attackReach+range+8){Victim v;v.actor=c;v.state.attack=a;s->victims[c->getObjectID()]=v;}}
  if(s->victims.empty())return false;
  {std::lock_guard<std::mutex> l(mutex());strikes()[actor->getObjectID()]=s;}actor->setCurrentSpeed(0);publish(actor,*s,"windup");schedule(s);return true;
 }
 static Json run(CreatureObject* c,const Json& q){
  double received=now();const auto op=q.at("action").get<std::string>();
  if(op=="negotiate"){
   bool ok=enabled()&&!catalog().is_null()&&q.value("protocol",0)==2&&q.value("catalog_revision",std::string())==catalog().value("revision",std::string("missing"));
   if(ok){std::lock_guard<std::mutex> l(mutex());for(auto i=peers().begin();i!=peers().end();)if(i->second.expires<now())i=peers().erase(i);else ++i;if(peers().size()>=256&&!peers().count(c->getObjectID()))throw std::runtime_error("ground_capacity");peers()[c->getObjectID()]={c,now()+15};}
   return {{"success",ok},{"protocol",2},{"server_received",received},{"server_sent",now()},{"scope",mode()}};
  }
  if(op!="batch"||!q.contains("receipts")||!q.at("receipts").is_array()||q.at("receipts").size()>32)throw std::runtime_error("ground_batch_invalid");
  if(!capable(c->getObjectID()))throw std::runtime_error("ground_capability_required");
  {std::lock_guard<std::mutex> l(mutex());peers()[c->getObjectID()].expires=now()+15;}
  Json results=Json::array();
  for(const auto& row:q.at("receipts")){
   Json result={{"actor_id",row.at("actor_id")},{"attack_id",row.at("attack_id")},{"kind",row.at("kind")},{"accepted",false}};
   auto s=find(std::stoull(row.at("actor_id").get<std::string>()));
   if(s){Locker guard(&s->mutex,c);auto v=s->victims.find(c->getObjectID());
    if(std::to_string(s->attack.id)==row.at("attack_id").get<std::string>()&&v!=s->victims.end()&&!s->attack.cancelled){
     auto& state=v->second.state;sync(v->second,s->attack);auto rev=row.at("aim_revision").get<uint64>();
     if(row.at("kind")=="warning")result["accepted"]=state.warning(now());
     else if(row.at("kind")=="lock")result["accepted"]=state.acknowledge(now(),rev);
     else{
      Vec feet=row.at("sample_position").get<Vec>();bool plausible=corecu::action::finite(feet)&&corecu::action::distance(feet,point(c))<=4;
      bool hit=row.at("contact").get<bool>();if(hit)plausible=plausible&&v->second.lineClear&&s->attack.contact(feet);
      if(plausible){bool first=!state.attack.reported;result["accepted"]=state.receipt(now(),hit,row.at("coverage_start"),row.at("coverage_end"),rev);if(first&&result["accepted"]==true)v->second.sample=feet;}
     }
    }
   }
   results.push_back(result);
  }
  std::vector<std::shared_ptr<Strike>> active;{std::lock_guard<std::mutex> l(mutex());for(auto& s:strikes())active.push_back(s.second);}
  Json events=Json::array();for(auto& s:active){Locker guard(&s->mutex,c);if(s->victims.count(c->getObjectID())&&events.size()<64){auto event=s->event;event["age_ms"]=(now()-event.at("server_now").get<double>())*1000;events.push_back(event);}}
  Json outcomes=Json::array();{std::lock_guard<std::mutex> l(mutex());for(auto& row:analytics())if(row.at("victim_id")==std::to_string(c->getObjectID()))outcomes.push_back(row);while(outcomes.size()>128)outcomes.erase(outcomes.begin());}
  return {{"success",true},{"outcomes",outcomes},{"protocol",2},{"server_received",received},{"server_sent",now()},{"receipts",results},{"action_events",events}};
 }
};
