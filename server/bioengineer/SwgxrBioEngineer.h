#ifndef SWGXR_BIO_ENGINEER_H
#define SWGXR_BIO_ENGINEER_H
#include "server/zone/objects/creature/ai/Creature.h"
#include "server/zone/managers/collision/CollisionManager.h"

// VR entry into the original SampleDNACommand/SampleDnaTask, not a reward path.
class SwgxrBioEngineer {
 using Json=JSONSerializationType;
 static constexpr int RECOVERY_MS=11000; // Original task: BEGIN + ten ticks + END.
 static Vector3 point(const Json& p){
  if(!p.is_array() || p.size()!=3)throw std::runtime_error("Finite sampling hand position required");
  for(auto& v:p)if(!v.is_number() || v.is_boolean() || !std::isfinite(v.get<double>()) || std::abs(v.get<double>())>10000)throw std::runtime_error("Invalid sampling hand position");
  return Vector3(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());
 }
public:
 static bool learned(CreatureObject* c){
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("sampledna");
  return c->hasSkill("outdoors_bio_engineer_novice") && cmd && (cmd->getCharacterAbility().isEmpty() || c->getPlayerObject()->hasAbility(cmd->getCharacterAbility()));
 }
 static double cooldown(CreatureObject* c){
  auto time=c->getCooldownTime("swgxr_sample_dna");
  return time?std::max(0.0,double(time->getMiliTime())/1000.0-std::time(nullptr)):0;
 }
 static bool eligible(CreatureObject* c,SceneObject* o){
  auto target=dynamic_cast<Creature*>(o);
  return target && target!=c && target->getZone()==c->getZone() && target->getParent().get()==c->getParent().get() && !target->isDead() && !target->isIncapacitated() && !target->isBaby() && !target->isPet() && !target->isInCombat() && target->isAttackableBy(c) && target->canCollectDna(c) && target->hasSkillToSampleMe(c);
 }
 static void status(CreatureObject* c,Json& s){
  s["sample_dna_available"]=learned(c);s["sample_dna_pending"]=c->getPendingTask("sampledna")!=nullptr;
  s["sample_dna_cooldown"]=cooldown(c);s["sample_dna_recovery"]=RECOVERY_MS/1000.0;
 }
 static void discard(CreatureObject* c){
  if(!learned(c))throw std::runtime_error("Sample DNA not learned");
  if(cooldown(c)<RECOVERY_MS/1000.0)c->addCooldown("swgxr_sample_dna",RECOVERY_MS);
 }
 static void run(CreatureObject* c,const Json& q){
  if(!learned(c) || c->isDead() || c->isIncapacitated() || c->isInCombat() || c->isRidingMount() || c->getPendingTask("sampledna")!=nullptr || cooldown(c)>0)throw std::runtime_error("DNA sampling unavailable or recovering");
  auto key=q.at("target_id").get<std::string>();
  if(key.empty() || key.size()>20 || key.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid sampling target");
  auto target=c->getZoneServer()->getObject(std::stoull(key));
  if(target==nullptr)throw std::runtime_error("Sampling creature no longer exists");
  auto hand=point(q.at("hand_position"));
  {
   Locker lock(target,c);
   if(!eligible(c,target))throw std::runtime_error("Core3 creature DNA or skill requirements not met");
   if(hand.distanceTo(c->getWorldPosition())>3.5 || !CollisionManager::checkLineOfSight(c,target))throw std::runtime_error("Sampling hand or creature out of reach/obstructed");
   // Validate contact against the source appearance; the client uses the tighter
   // rendered original mesh bounds. Never invent a generic creature hit volume.
   auto appearance=target->getAppearanceTemplate();auto volume=appearance?appearance->getBoundingVolume():nullptr;
   if(volume==nullptr)throw std::runtime_error("Original creature contact bounds unavailable");
   const auto& sphere=volume->getBoundingSphere();const auto& local=sphere.getCenter();
   double scale=target->asCreatureObject()->getHeight(false),angle=target->getDirectionAngle()*M_PI/180.0;
   double x=local.getX()*scale,z=local.getZ()*scale;
   auto center=target->getWorldPosition()+Vector3(x*cos(angle)+z*sin(angle),-x*sin(angle)+z*cos(angle),local.getY()*scale);
   double radius=sphere.getRadius()*scale;
   if(!std::isfinite(radius) || radius<=0 || radius>128 || hand.distanceTo(center)>radius+0.20)throw std::runtime_error("Hold the sampling hand over the creature");
  }
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("sampledna");
  if(cmd->doQueueCommand(c,target->getObjectID(),UnicodeString())!=QueueCommand::SUCCESS || c->getPendingTask("sampledna")==nullptr)throw std::runtime_error("Core3 rejected DNA sampling");
  c->addCooldown("swgxr_sample_dna",RECOVERY_MS);
 }
};
#endif
