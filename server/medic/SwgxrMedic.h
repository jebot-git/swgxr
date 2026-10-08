#ifndef SWGXR_MEDIC_H
#define SWGXR_MEDIC_H
#include "SwgxrPlanets.h"
#include "SwgxrGathering.h"
#include "HealDamageCommand.h"
#include "HealWoundCommand.h"
#include "SwgxrVitalFeedback.h"
#include "SwgxrSpice.h"
#include "SwgxrMedicDrag.h"
#include "CoreCuMedicine.h"
class SwgxrMedic {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static Json position(SceneObject* o){auto p=o->getWorldPosition();return Json::array({p.getX(),p.getZ(),p.getY()});}
 static bool medicalTool(SceneObject* o){if(!o)return false;auto t=o->getObjectTemplate()->getFullTemplateString();return t=="object/tangible/medicine/medikit_tool_basic.iff" || t=="object/tangible/medicine/medikit_tool_advanced.iff";}
 static bool learned(CreatureObject* c,const std::string& name){
  static const std::set<std::string> allowed{"tenddamage","firstaid","quickheal"};
  if(!allowed.count(name) || !c->hasSkill("science_medic_novice"))return false;
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str()));
  return cmd && (cmd->getCharacterAbility().isEmpty() || c->getPlayerObject()->hasAbility(cmd->getCharacterAbility()));
 }
 static double pending(CreatureObject* c,const char* name){auto t=c->getPendingTask(name);if(!t)return 0;AtomicTime next;if(!Core::getTaskManager()->getNextExecutionTime(t,next))return 0;return std::max(0.0,-next.miliDifference()/1000.0);}
 static double cooldown(CreatureObject* c,const std::string& name){auto t=c->getCooldownTime(String(("swgxr_medic_"+name).c_str()));double own=t?std::max(0.0,-t->miliDifference()/1000.0):0;return std::max(CoreCuMedicine::remaining(c,String(name.c_str())),std::max(own,pending(c,(name=="healdamage" || name=="healpet" || name=="healdroiddamage")?"injuryTreatment":(name=="healwound" || name=="healdroidwound")?"woundTreatment":"swgxr_no_task")));}
 static Json abilities(CreatureObject* c){
  Json out=Json::array();const char* names[]={"tenddamage","firstaid","quickheal"};const char* labels[]={"Tend Damage","First Aid","Quick Heal"};
  for(int i=0;i<3;++i){if(!learned(c,names[i]))continue;double range=6,area=0;std::string medicine;
   out.push_back({{"id",names[i]},{"source_command",names[i]},{"label",labels[i]},{"range_m",range},{"area_radius_m",area},{"medicine_id",medicine},{"cooldown_seconds",cooldown(c,names[i])},{"action_cost",CoreCuMedicine::cost(c,String(names[i]),3)},{"mind_cost",CoreCuMedicine::cost(c,String(names[i]),6)},{"recovery_group",corecu::medicine::ability(names[i]).group}});
  }return out;
 }
 static Json needs(CreatureObject* c){
  bool injury=c->getHAM(0)<c->getMaxHAM(0)-c->getWounds(0),wound=c->getWounds(0)>0;
  return {{"healdamage",injury},{"wound_medpack",wound},{"tenddamage",injury},{"quickheal",injury},{"firstaid",c->isBleeding()}};
 }
 static Json wounds(CreatureObject* c){Json out=Json::array();for(int i=0;i<9;++i)out.push_back(c->getWounds(i));return out;}
 static Json snapshot(CreatureObject* c){
  auto g=SwgxrGathering::load(c);auto hip=SwgxrGathering::object(c,g.value("hip_tool_id",std::string()));
  Json out={{"character_id",id(c)},{"zone",SwgxrPlanets::name(c)},{"source_kind","core3_medic"},{"abilities",abilities(c)},{"selected",std::string(c->getPlayerObject()->getScreenPlayData("swgxr_medic","selected").toCharArray())},{"inventory",SwgxrInventory::snapshot(c)},{"hip_tool",hip?SwgxrInventory::describe(hip,c):Json(nullptr)},{"players",Json::array()},{"position",position(c)},{"vital_feedback",SwgxrVitalFeedback::snapshot(c->getObjectID())}};
  out["medical_item_cooldowns"]=Json::object();for(auto name:{"healdamage","healwound","healenhance","healstate","curepoison","curedisease","extinguishfire","reviveplayer","healpet","healdroiddamage","healdroidwound"})out["medical_item_cooldowns"][name]=cooldown(c,name);
  out["wound_medpack_cooldown_seconds"]=cooldown(c,"healwound");
  out["drag"]=SwgxrMedicDrag::snapshot(c);out["drag_available"]=c->hasSkill("science_medic_injury_speed_02");
  out["self"]={{"id",id(c)},{"name",std::string(c->getDisplayedName().toCharArray())},{"position",position(c)},{"healable",!c->isDead()},{"dead",c->isDead()},{"states",c->getStateBitmask()},{"wounds",wounds(c)},{"needs",needs(c)}};
  out["focus_issued"]=!c->getPlayerObject()->getScreenPlayData("swgxr_medic","focus_id").isEmpty();
  SortedVector<TreeEntry*> objects(128,128);c->getZone()->getInRangeObjects(c->getWorldPositionX(),c->getWorldPositionZ(),c->getWorldPositionY(),80,&objects,true);
  for(int i=0;i<objects.size() && out["players"].size()<32;++i){auto o=static_cast<SceneObject*>(objects.get(i));if(!o->isPlayerCreature() || o==c)continue;auto p=o->asCreatureObject();Locker lock(p,c);if(p->getPlayerObject()->isOffline())continue;
   String custom;p->getCustomizationString(custom);std::string hex;const char* digits="0123456789abcdef";for(int n=0;n<custom.length();++n){unsigned char v=custom[n];hex+=digits[v>>4];hex+=digits[v&15];}
   out["players"].push_back({{"id",id(p)},{"name",std::string(p->getDisplayedName().toCharArray())},{"template",std::string(p->getObjectTemplate()->getFullTemplateString().toCharArray())},{"position",position(p)},{"heading_radians",p->getDirection()->getRadians()},{"customization_hex",hex},{"height",p->getHeight(false)},{"posture",int(p->getPosture())},{"feigning_death",SwgxrSmuggler::feigning(p)},{"dead",p->isDead()},{"states",p->getStateBitmask()},{"wounds",wounds(p)},{"needs",needs(p)},{"drag",SwgxrMedicDrag::snapshot(p)},{"healable",p->isHealableBy(c) && !p->isAttackableBy(c)}});
  }
  out["companions"]=Json::array();
  for(int i=0;i<objects.size() && out["companions"].size()<32;++i){auto o=static_cast<SceneObject*>(objects.get(i));if(!o->isPet())continue;auto p=o->asCreatureObject();if(!p)continue;Locker lock(p,c);
   out["companions"].push_back({{"id",id(p)},{"name",std::string(p->getDisplayedName().toCharArray())},{"position",position(p)},{"companion",true},{"droid",p->isDroidObject()},{"dead",p->isDead()},{"states",p->getStateBitmask()},{"wounds",wounds(p)},{"needs",needs(p)},{"healable",p->isHealableBy(c) && !p->isAttackableBy(c)}});
  }return out;
 }
public:
 static Json run(CreatureObject* c,const Json& request){
  SwgxrPlanets::require(c,request);
  if(!c || !c->getPlayerObject() || !c->getZone())throw std::runtime_error("Native player required");
  auto verb=request.value("action",std::string("status"));Json mutation={{"success",true},{"action",verb}};
  // Movement is a separate live update. Medical commands never capture locomotion,
  // change posture, teleport to a stale request position or wait for an animation.
  if(request.contains("pose"))SwgxrMedicDrag::observe(c,request.at("pose"));
  if(verb=="drag")return {{"backend","core3"},{"zone",SwgxrPlanets::name(c)},{"source_kind","core3_medic"},{"character_id",id(c)},{"mutation",SwgxrMedicDrag::run(c,request)},{"state",snapshot(c)}};
  if(verb!="status"){
   if(c->isDead() || c->isIncapacitated())throw std::runtime_error("Player cannot act");
   auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_medic","receipts");Json receipts=raw.isEmpty()?Json::array():Json::parse(raw.toCharArray());const auto key=request.at("request_id").get<std::string>();bool replay=false;
   if(key.size()<8 || key.size()>64)throw std::runtime_error("Invalid request id");
   for(auto& r:receipts)if(r["key"]==key){if(r["request"]!=request)throw std::runtime_error("Request id reused");mutation=r["mutation"];mutation["replayed"]=true;replay=true;break;}
   if(!replay){
    if(verb=="medical_item" || verb=="wound_pack"){
     if(!request.contains("pose") || !request.at("pose").value("tracked",false))throw std::runtime_error("Tracked medical item use required");
     auto pack=c->getZoneServer()->getObject(std::stoull(request.at("item_id").get<std::string>())).castTo<PharmaceuticalObject*>();
     if(!SwgxrMedicalItem::owned(c,pack))throw std::runtime_error("Owned medical supply required");
     const String name=SwgxrMedicalItem::command(pack);
     if(name.isEmpty() || (verb=="wound_pack" && name!="healwound") || pack->getUseCount()<=0)throw std::runtime_error("Usable medical supply required");
     auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(name);
     if(!SwgxrMedicalItem::trained(c,pack) || !cmd || (name!="healwound" && !cmd->getCharacterAbility().isEmpty() && !c->getPlayerObject()->hasAbility(cmd->getCharacterAbility())))throw std::runtime_error("Required medical training not learned");
     auto target=c->getZoneServer()->getObject(std::stoull(request.at("target_id").get<std::string>())).castTo<CreatureObject*>();
     if(!target || !SwgxrMedicalItem::recipient(pack,target) || target->getZone()!=c->getZone())throw std::runtime_error("Valid medical recipient required");
     Locker recipientLock(target,c);
     if(target->isAttackableBy(c) || !target->isHealableBy(c) || !c->isInRange(target,SwgxrMedicalItem::range(pack,c)) || !SwgxrMedicalItem::needed(pack,target) || target->isRidingMount())throw std::runtime_error("Recipient does not need this treatment or is out of range");
     bool touching=false;for(auto side:{"left","right"}){auto p=request.at("pose").at(side);Vector3 hand(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());if(hand.distanceTo(c->getWorldPosition())<=2.2f && (pack->isRangedStimPack() || hand.distanceTo(target->getWorldPosition())<=2.2f))touching=true;}
     if(!touching || (target!=c && !CollisionManager::checkLineOfSight(c,target)))throw std::runtime_error("Hold the supply near its recipient, or aim a ranged stim with clear line of sight");
     String arguments=SwgxrMedicalItem::arguments(pack);const auto itemId=id(pack);
     if(cmd->doQueueCommand(c,target->getObjectID(),UnicodeString(arguments))!=QueueCommand::SUCCESS)throw std::runtime_error("Medical item rejected: location, state, consent, recovery or resources");
     mutation["target_id"]=id(target);mutation["item_id"]=itemId;mutation["command"]=std::string(name.toCharArray());
    }else if(verb=="bandage"){
     if(!learned(c,"firstaid") || !request.contains("pose") || !request.at("pose").value("tracked",false))throw std::runtime_error("Tracked First Aid required");
     auto target=c->getZoneServer()->getObject(std::stoull(request.at("target_id").get<std::string>())).castTo<CreatureObject*>();
     if(!target || !target->isPlayerCreature() || target->getZone()!=c->getZone() || target->isDead() || !target->isBleeding() || target->isAttackableBy(c) || !target->isHealableBy(c) || !c->isInRange(target,2.5f))throw std::runtime_error("Nearby bleeding recipient required");
     bool touching=false;for(auto side:{"left","right"}){auto p=request.at("pose").at(side);Vector3 hand(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());if(hand.distanceTo(target->getWorldPosition())<=2.2f && hand.distanceTo(c->getWorldPosition())<=2.2f)touching=true;}
     if(target!=c && !CollisionManager::checkLineOfSight(c,target))throw std::runtime_error("Bandaging recipient is obstructed");
     if(!touching)throw std::runtime_error("Bandaging hand must be near recipient");
     auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("firstaid");
     if(!cmd || cmd->doQueueCommand(c,target->getObjectID(),UnicodeString(""))!=QueueCommand::SUCCESS)throw std::runtime_error("First Aid rejected");
     mutation["target_id"]=id(target);
    }else if(verb=="provision"){
     if(!c->hasSkill("science_medic_novice"))throw std::runtime_error("Medic skill required");
     auto saved=c->getPlayerObject()->getScreenPlayData("swgxr_medic","focus_id");if(!saved.isEmpty())throw std::runtime_error("Medical focus already issued");
     auto root=c->getSlottedObject("inventory");if(!root || root->getCountableObjectsRecursive()>=root->getContainerVolumeLimit())throw std::runtime_error("Inventory full");
     auto tool=c->getZoneServer()->createObject(STRING_HASHCODE("object/tangible/medicine/medikit_tool_basic.iff"),1);if(!tool || !root->transferObject(tool,-1,true))throw std::runtime_error("Cannot create medical focus");c->getPlayerObject()->setScreenPlayData("swgxr_medic","focus_id",String(id(tool).c_str()));tool->sendTo(c,true);
    }else{
     auto g=SwgxrGathering::load(c);auto tool=SwgxrGathering::ownedTool(c,g,request.at("item_id").get<std::string>());if(!medicalTool(tool))throw std::runtime_error("Owned medical tool required");
     if(verb=="holster" || verb=="return_tool"){auto q=request;q["tool_id"]=id(tool);SwgxrGathering::execute(c,g,q);SwgxrGathering::save(c,g);}
     else {
      const auto name=request.at("ability").get<std::string>();if(!learned(c,name))throw std::runtime_error("Healing ability not learned");
      if(verb=="select")c->getPlayerObject()->setScreenPlayData("swgxr_medic","selected",String(name.c_str()));
      else if(verb=="heal"){
       if(std::string(c->getPlayerObject()->getScreenPlayData("swgxr_medic","selected").toCharArray())!=name)throw std::runtime_error("Select the medical ability first");
       if(cooldown(c,name)>0)throw std::runtime_error("Healing ability recovering");
       auto target=c->getZoneServer()->getObject(std::stoull(request.at("target_id").get<std::string>())).castTo<CreatureObject*>();
       if(!target || !target->isPlayerCreature() || target->getZone()!=c->getZone() || target->isDead() || target->isAttackableBy(c) || !target->isHealableBy(c))throw std::runtime_error("Invalid healing target");
       auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str()));
       int result=cmd->doQueueCommand(c,target->getObjectID(),UnicodeString(""));if(result!=QueueCommand::SUCCESS)throw std::runtime_error("Core3 rejected healing: supply, range, state, environment or HAM requirement");
       c->addCooldown(String(("swgxr_medic_"+name).c_str()),int(std::max(0.f,cmd->getCommandDuration(c,UnicodeString("")))*1000*SwgxrSpice::cooldownScale(c)));mutation["target_id"]=id(target);
      }else throw std::runtime_error("Unsupported medical action");
     }
    }
    receipts.push_back({{"key",key},{"request",request},{"mutation",mutation}});while(receipts.size()>32)receipts.erase(receipts.begin());c->getPlayerObject()->setScreenPlayData("swgxr_medic","receipts",String(receipts.dump().c_str()));
   }
  }
  return {{"backend","core3"},{"zone",SwgxrPlanets::name(c)},{"source_kind","core3_medic"},{"character_id",id(c)},{"state",snapshot(c)},{"mutation",mutation}};
 }
};
#endif
