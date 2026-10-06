#ifndef SWGXR_CREATURE_HANDLER_H
#define SWGXR_CREATURE_HANDLER_H
#include "SwgxrPets.h"
#include "SwgxrTrainers.h"
#include "server/zone/objects/creature/ai/Creature.h"
#include "server/zone/managers/creature/CreatureManager.h"
#include <chrono>
// Native commands and original PetMenu/PetManager rules remain authoritative.
// Gestures are an input method; no gesture duration grants skills or pets.
class SwgxrCreatureHandler {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static std::string str(const String& s){return s.toCharArray();}
 static double now(){return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static Json position(SceneObject* o){auto p=o->getWorldPosition();return Json::array({p.getX(),p.getZ(),p.getY()});}
 static bool near(CreatureObject* c,CreatureObject* p,double range){return p && p->getZone()==c->getZone() && p->getParentID()==c->getParentID() && c->isInRange(p,range) && CollisionManager::checkLineOfSight(c,p);}
 static std::string tameReason(CreatureObject* c,Creature* p){
  if(!c->hasSkill("outdoors_creaturehandler_novice"))return "creature_handler_novice_required";
  if(!p || !p->canTameMe(c) || !p->isAttackableBy(c))return "eligible_wild_baby_required";
  if(!near(c,p,8))return "tame_range_or_line_of_sight";
  if(c->getPendingTask("tame_pet")!=nullptr || c->getPendingTask("call_pet")!=nullptr)return "pet_task_pending";
  auto source=p->getCreatureTemplate();if(!source || source->getLevel()>c->getSkillMod("tame_level") || (p->isVicious() && c->getSkillMod("tame_aggro")<1) || p->getChanceToTame(c)<=0)return "original_taming_skill_required";
  auto pad=c->getSlottedObject("datapad");if(!pad || pad->getContainerObjectsSize()>=pad->getContainerVolumeLimit())return "datapad_full";
  int stored=0,maxStored=c->getZoneServer()->getPlayerManager()->getBaseStoredCreaturePets()+c->getSkillMod("stored_pets");
  for(int i=0;i<pad->getContainerObjectsSize();++i){auto d=pad->getContainerObject(i).castTo<PetControlDevice*>();if(d && d->getPetType()==PetManager::CREATUREPET)++stored;}
  if(stored>=maxStored)return "stored_pet_capacity";
  auto ghost=c->getPlayerObject();int active=0,levels=0;
  for(int i=0;i<ghost->getActivePetsSize();++i){auto pet=ghost->getActivePet(i);if(!pet)continue;auto d=pet->getControlDevice().get().castTo<PetControlDevice*>();if(!d || d->getPetType()!=PetManager::CREATUREPET)continue;++active;levels+=pet->getLevel();}
  if(active>=c->getSkillMod("keep_creature") || (active>0 && levels+p->getLevel()>=c->getSkillMod("tame_level")))return "active_pet_control_capacity";
  return "";
 }
 static const char* trainingSkill(int n){switch(n){case 1:case 2:case 3:return "novice";case 16:return "training_01";case 4:return "training_02";case 9:case 22:case 23:return "training_03";case 10:case 11:return "training_04";case 7:return "healing_01";case 8:return "healing_03";case 15:return "support_01";case 6:return "support_02";case 5:return "support_03";case 12:return "taming_03";case 13:return "taming_04";case 14:case 18:return "master";default:return "";}}
 static bool trainable(CreatureObject* c,AiAgent* p,int n){auto suffix=trainingSkill(n);if(!*suffix || !c->hasSkill(String((std::string("outdoors_creaturehandler_")+suffix).c_str())))return false;return (n!=12 || p->hasSpecialAttack(1)) && (n!=13 || p->hasSpecialAttack(2)) && (n!=14 || p->hasRangedWeapon());}
 static bool buffable(CreatureObject* c,AiAgent* p,const char* name){auto ghost=c->getPlayerObject();bool emb=std::string(name)=="emboldenpets";return ghost->hasAbility(name) && !p->isDead() && !p->isIncapacitated() && p->getZone()==c->getZone() && c->isInRange(p,50) && !p->hasBuff(emb?STRING_HASHCODE("emboldenPet"):STRING_HASHCODE("enragePet")) && p->getCooldownTimerMap()!=nullptr && p->getCooldownTimerMap()->isPast(emb?"emboldenPetsCooldown":"enragePetsCooldown") && c->getHAM(CreatureAttribute::MIND)>c->calculateCostAdjustment(CreatureAttribute::FOCUS,100);}
 static ManagedReference<PetControlDevice*> owned(CreatureObject* c,const Json& q){auto d=c->getZoneServer()->getObject(std::stoull(q.at("device_id").get<std::string>())).castTo<PetControlDevice*>();if(!d || d->getPetType()!=PetManager::CREATUREPET || d->getParent().get()!=c->getSlottedObject("datapad") || !d->getControlledObject() || !d->getControlledObject()->isAiAgent())throw std::runtime_error("owned_creature_pet_required");return d;}
 static void invoke(CreatureObject* c,const char* name,uint64 target=0){auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(name);if(!cmd || cmd->doQueueCommand(c,target,UnicodeString())!=QueueCommand::SUCCESS)throw std::runtime_error("native_creature_handler_command_rejected");}
public:
 static Json petState(CreatureObject* c,PetControlDevice* d){
  Json out={{"embolden",false},{"enrage",false},{"train_mount",false},{"trained_as_mount",d->isTrainedAsMount()},{"train_commands",Json::array()}};
  if(d->getPetType()!=PetManager::CREATUREPET || !d->getControlledObject() || !d->getControlledObject()->isAiAgent())return out;auto p=d->getControlledObject()->asAiAgent();
  out["body_bounds"]=SwgxrPets::bodyBounds(p);
  bool ready=!c->isDead() && !c->isIncapacitated() && !p->isDead() && !p->isIncapacitated() && p->getLinkedCreature().get()==c;
  out["emboldened"]=p->hasBuff(STRING_HASHCODE("emboldenPet"));out["enraged"]=p->hasBuff(STRING_HASHCODE("enragePet"));
  out["embolden"]=ready && buffable(c,p,"emboldenpets");out["enrage"]=ready && buffable(c,p,"enragepets");
  int eligibility=c->getZoneServer()->getPetManager()->checkMountEligibility(d);out["mount_scale_status"]=eligibility;
  out["train_mount"]=ready && !c->isInCombat() && !p->isInCombat() && near(c,p,8) && c->hasSkill("outdoors_creaturehandler_support_04") && !d->isTrainedAsMount() && eligibility==PetManager::CANBEMOUNTTRAINED;
  const char* labels[]={"","Follow me","Store","Attack","Guard","Friend","Follow target","Trick 1","Trick 2","Patrol","Wedge formation","Column formation","Special attack 1","Special attack 2","Ranged attacks","Group","Stay","","Transfer","","","","Mark patrol point","Clear patrol points"};
  if(ready && !c->isInCombat() && !p->isInCombat() && near(c,p,8))for(int n=1;n<=23;++n)if(!d->hasTrainedCommand(n) && trainable(c,p,n))out["train_commands"].push_back({{"command_id",n},{"label",labels[n]}});
  return out;
 }
 static Json snapshot(CreatureObject* c){
  Json out={{"skills",SwgxrTrainers::skills(c)},{"experience",SwgxrTrainers::experience(c)},{"commands",Json::array()},{"candidates",Json::array()},{"taming",Json::object()}};auto ghost=c->getPlayerObject();for(auto name:{"tame","emboldenpets","enragepets","trainmount"})if(ghost->hasAbility(name))out["commands"].push_back(name);
  auto saved=ghost->getScreenPlayData("swgxr_ch","taming");if(!saved.isEmpty()){
   auto progress=Json::parse(saved.toCharArray());auto terminal=progress.value("state",std::string());
   if(terminal!="succeeded" && terminal!="failed"){
    // Native storage clears the creature link. The real owned control device,
    // not active world presence, establishes successful persistent taming.
    ManagedReference<PetControlDevice*> confirmed;auto pad=c->getSlottedObject("datapad");auto target=std::stoull(progress.at("target_id").get<std::string>());
    if(pad)for(int i=0;i<pad->getContainerObjectsSize();++i){auto d=pad->getContainerObject(i).castTo<PetControlDevice*>();if(d && d->getPetType()==PetManager::CREATUREPET && d->getControlledObject() && d->getControlledObject()->getObjectID()==target){confirmed=d;break;}}
    bool pending=c->getPendingTask("tame_pet")!=nullptr;progress["state"]=confirmed?"succeeded":pending?"pending":"failed";progress["device_id"]=confirmed?id(confirmed):"0";
    if(confirmed || !pending){progress["completed_at"]=now();ghost->setScreenPlayData("swgxr_ch","taming",String(progress.dump().c_str()));}
   }
   progress["elapsed_seconds"]=std::max(0.0,progress.value("completed_at",now())-progress.value("started",now()));progress["duration_seconds"]=30;out["taming"]=progress;
  }
  if(!c->hasSkill("outdoors_creaturehandler_novice"))return out;
  SortedVector<TreeEntry*> objects(32,32);auto origin=c->getWorldPosition();c->getZone()->getInRangeObjects(origin.getX(),origin.getZ(),origin.getY(),8,&objects,true);
  for(int i=0;i<objects.size() && out["candidates"].size()<32;++i){auto o=static_cast<SceneObject*>(objects.get(i));if(!o->isCreature())continue;auto p=static_cast<Creature*>(o);if(p->isPet() || p->isDead() || !p->isBaby() || p->getParentID()!=c->getParentID())continue;Locker lock(p,c);auto reason=tameReason(c,p);Json row={{"id",id(p)},{"name",str(p->getDisplayedName())},{"template",str(p->getObjectTemplate()->getFullTemplateString())},{"position",position(p)},{"baby",p->isBaby()},{"level",p->getCreatureTemplate()?p->getCreatureTemplate()->getLevel():p->getLevel()},{"eligible",reason.empty()},{"can_tame",reason.empty()},{"reason",reason},{"height",p->getHeight(false)},{"radius",p->getTemplateRadius()}};
   auto appearance=p->getAppearanceTemplate();auto volume=appearance?appearance->getBoundingVolume():nullptr;if(volume){auto sphere=volume->getBoundingSphere();auto center=sphere.getCenter();row["bounds_center"]=Json::array({center.getX(),center.getY(),center.getZ()});row["bounds_radius"]=sphere.getRadius();row["bounds_source"]="original_appearance_sphere";}else{auto bounds=SwgxrPets::bodyBounds(p);if(!bounds.empty()){row["bounds_center"]=bounds["center"];row["bounds_radius"]=bounds["radius"];row["bounds_source"]=bounds["source"];row["body_bounds"]=bounds;}}out["candidates"].push_back(row);
  }return out;
 }
 static void execute(CreatureObject* c,const Json& q,Json& mutation){
  auto action=q.at("action").get<std::string>();if(action=="ch_status")return;auto ghost=c->getPlayerObject();auto key=q.at("request_id").get<std::string>();if(key.size()<8 || key.size()>64)throw std::runtime_error("creature_handler_request_id_required");auto proposal=q;for(auto field:{"position","building_id","cell_index","zone","planet","hand"})proposal.erase(field);auto saved=ghost->getScreenPlayData("swgxr_ch","receipts");auto receipts=saved.isEmpty()?Json::array():Json::parse(saved.toCharArray());for(auto& receipt:receipts)if(receipt["id"]==key){if(receipt["request"]!=proposal)throw std::runtime_error("creature_handler_request_id_reused");mutation=receipt["mutation"];mutation["replayed"]=true;return;}
  if(c->isDead() || c->isIncapacitated())throw std::runtime_error("living_handler_required");
  if(action=="ch_tame"){
   auto p=c->getZoneServer()->getObject(std::stoull(q.at("target_id").get<std::string>())).castTo<Creature*>();if(!p)throw std::runtime_error("wild_creature_required");Locker lock(p,c);auto reason=tameReason(c,p);if(!reason.empty())throw std::runtime_error(reason);invoke(c,"tame",p->getObjectID());if(c->getPendingTask("tame_pet")==nullptr)throw std::runtime_error("native_taming_not_started");Json progress={{"target_id",id(p)},{"request_id",key},{"started",now()}};ghost->setScreenPlayData("swgxr_ch","taming",String(progress.dump().c_str()));mutation["pending"]=true;mutation["target_id"]=id(p);
  }else if(action=="ch_embolden" || action=="ch_enrage"){
   const char* cmd=action=="ch_embolden"?"emboldenpets":"enragepets";if(!ghost->hasAbility(cmd))throw std::runtime_error("learned_pet_buff_required");std::vector<ManagedReference<AiAgent*>> eligible;
   for(int i=0;i<ghost->getActivePetsSize();++i){auto p=ghost->getActivePet(i);if(!p)continue;auto d=p->getControlDevice().get().castTo<PetControlDevice*>();if(d && d->getPetType()==PetManager::CREATUREPET && p->getLinkedCreature().get()==c && buffable(c,p,cmd))eligible.push_back(p);}
   if(eligible.empty())throw std::runtime_error("no_pet_eligible_for_native_buff");invoke(c,cmd);Json applied=Json::array();for(auto& p:eligible)if(p->hasBuff(action=="ch_embolden"?STRING_HASHCODE("emboldenPet"):STRING_HASHCODE("enragePet")))applied.push_back(id(p));if(applied.empty())throw std::runtime_error("native_pet_buff_not_applied");mutation["pet_ids"]=applied;
  }else if(action=="ch_train_mount" || action=="ch_train_command"){
   auto d=owned(c,q);auto p=d->getControlledObject()->asAiAgent();Locker lock(p,c);if(c->isInCombat() || p->isDead() || p->isIncapacitated() || p->isInCombat() || p->getLinkedCreature().get()!=c || !near(c,p,8))throw std::runtime_error("nearby_living_owned_pet_required");auto state=petState(c,d);
   if(action=="ch_train_mount"){if(!state["train_mount"].get<bool>())throw std::runtime_error("native_mount_training_requirements");auto hand=q.at("hand");Vector3 point(hand.at(0).get<float>(),hand.at(2).get<float>(),hand.at(1).get<float>());if(!SwgxrPets::touches(c,p,point))throw std::runtime_error("touch_owned_pet_to_train_mount");Locker dl(d,p);d->trainAsMount(c);if(!d->isTrainedAsMount())throw std::runtime_error("native_mount_training_failed");mutation["trained_as_mount"]=true;
   }else{int n=q.at("command_id").get<int>();if(!trainable(c,p,n) || d->hasTrainedCommand(n))throw std::runtime_error("unlearned_pet_training_or_already_trained");{Locker dl(d,p);d->setTrainingCommand(n);}c->getZoneServer()->getPetManager()->handleChat(c,p,String(("swgxr command "+std::to_string(n)).c_str()));mutation["learned"]=d->hasTrainedCommand(n);mutation["command_id"]=n;}
   d->updateToDatabase();p->updateToDatabase();mutation["device_id"]=id(d);mutation["pet_id"]=id(p);
  }else throw std::runtime_error("unsupported_creature_handler_action");
  mutation["request_id"]=key;receipts.push_back({{"id",key},{"request",proposal},{"mutation",mutation}});while(receipts.size()>64)receipts.erase(receipts.begin());ghost->setScreenPlayData("swgxr_ch","receipts",String(receipts.dump().c_str()));
 }
};
#endif
