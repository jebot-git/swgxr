#ifndef SWGXR_PETS_H
#define SWGXR_PETS_H
#include "server/zone/objects/intangible/PetControlDevice.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/managers/creature/PetManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "templates/creature/SharedCreatureObjectTemplate.h"
#include <fstream>
#include <chrono>
#include <cstdlib>
#include <sys/stat.h>

// Only trained source commands are exposed. Their native handlers retain all
// power, module, combat, group, transfer and creature-handler restrictions.
class SwgxrPets {
 using Json=JSONSerializationType;
 struct Command {int id;const char* label;const char* name;const char* target;const char* args;bool owner;};
 static const std::vector<Command>& definitions(){
  static const std::vector<Command> all={
   {1,"Follow me","petfollow","","owner",true},{2,"Store","petstore","","",false},
   {3,"Attack","petattack","hostile","owner",false},{4,"Guard","petguard","friendly","target",true},
   {5,"Friend","petfriend","player","",false},{6,"Follow target","petfollow","friendly","owner",false},
   {7,"Trick 1","pettrick","","1",true},{8,"Trick 2","pettrick","","2",true},
   {9,"Patrol","petpatrol","","",false},{10,"Wedge formation","petformation","","wedge",true},
   {11,"Column formation","petformation","","column",true},{12,"Special attack 1","petspecialattack","hostile","1 owner",false},
   {13,"Special attack 2","petspecialattack","hostile","2 owner",false},{14,"Toggle ranged attacks","petrangedattack","","",true},
   {15,"Group","petgroup","","",false},{16,"Stay","petstay","","",false},
   {17,"Recharge droid","petrechargeother","droid","",false},{18,"Transfer ownership","pettransfer","player","",false},
   {19,"Repair droid","petrepair","droid","",false},{20,"Throw trap","petthrow","hostile","",false},
   {21,"Harvest","petharvest","corpse","owner",false},{22,"Mark patrol point here","petgetpatrolpoint","","",true},
   {23,"Clear patrol points","petclearpatrolpoints","","",true}};
  return all;
 }
 static const Command& definition(int id){for(auto& entry:definitions())if(entry.id==id)return entry;throw std::runtime_error("Unknown pet command");}
 static bool supports(PetControlDevice* device,const Command& entry){
  if(!device->hasTrainedCommand(entry.id))return false;
  auto pet=device->getControlledObject();if(pet==nullptr)return false;
  if(entry.id==18 && device->getPetType()!=PetManager::CREATUREPET)return false;
  if((entry.id==17 || entry.id==19 || entry.id==20 || entry.id==21) && !pet->asCreatureObject()->isDroidObject())return false;
  return pet->getZoneServer()->getObjectController()->getQueueCommand(entry.name)!=nullptr;
 }
 static void targetCheck(CreatureObject* owner,AiAgent* pet,SceneObject* target,const Command& command){
  if(!target || target==pet || target->getZone()!=owner->getZone() || target->getParent().get()!=owner->getParent().get() || !owner->isInRange(target,64) || (target!=owner && !CollisionManager::checkLineOfSight(owner,target)))throw std::runtime_error("Pet command target out of range or obstructed");
  auto creature=target->isCreatureObject()?target->asCreatureObject():nullptr;auto tangible=target->isTangibleObject()?target->asTangibleObject():nullptr;std::string kind=command.target;
  bool alive=creature && !creature->isDead() && !creature->isIncapacitated();
  if(kind=="hostile" && (!tangible || !tangible->isAttackableBy(pet) || (creature && !alive)))throw std::runtime_error("Attackable pet target required");
  if(kind=="friendly" && (!alive || creature->isAttackableBy(owner)))throw std::runtime_error("Friendly living target required");
  if(kind=="player" && (!alive || !creature->isPlayerCreature() || creature==owner || creature->isAttackableBy(owner)))throw std::runtime_error("Eligible other player required");
  if(kind=="droid" && (!alive || !creature->isDroidObject()))throw std::runtime_error("Living droid target required");
  if(kind=="corpse" && (!creature || !creature->isDead() || !creature->isCreature()))throw std::runtime_error("Harvestable creature corpse required");
 }
public:
 static bool supported(PetControlDevice* device){
  auto pet=device->getControlledObject();return pet && pet->isAiAgent() && (pet->asCreatureObject()->isDroidObject() || device->getPetType()==PetManager::CREATUREPET);
 }
 static Json sourceBodyBounds(CreatureObject* pet){
  // This is a server-owned, hash-proven conversion catalogue, never client data.
  // Vehicle RPC serialization also serializes this bounded/reloadable cache.
  static Json catalog=Json::object();static std::string loaded;static time_t modified=0;static double checked=0;
  double stamp=std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
  if(stamp-checked>2){checked=stamp;const char* env=std::getenv("SWGXR_PET_BOUNDS_CATALOG_PATH");std::vector<std::string> paths=env && *env?std::vector<std::string>{env}:std::vector<std::string>{"../../../../runtime/assets/pets/body_bounds.json","runtime/assets/pets/body_bounds.json","/workspace/runtime/assets/pets/body_bounds.json"};
   for(auto& path:paths){struct stat info;if(::stat(path.c_str(),&info)!=0 || info.st_size<=0 || info.st_size>2097152)continue;if(path==loaded && info.st_mtime==modified)break;
    try{std::ifstream file(path);Json data;file>>data;if(data.value("coordinate_system",std::string())!="original_x_y_up_z" || !data.contains("templates") || !data["templates"].is_object() || data["templates"].size()>1024)continue;catalog=std::move(data["templates"]);loaded=path;modified=info.st_mtime;}catch(...){catalog=Json::object();}break;
   }
  }
  std::string key=pet->getObjectTemplate()->getFullTemplateString().toCharArray();auto found=catalog.find(key);if(found==catalog.end())return Json::object();auto row=*found;
  if(!row.is_object() || row.value("model_sha256",std::string()).size()!=64)return Json::object();
  for(auto key:{"bounds_min","bounds_max","head_position"}){if(!row.contains(key) || !row[key].is_array() || row[key].size()!=3)return Json::object();for(auto& n:row[key])if(!n.is_number() || !std::isfinite(n.get<double>()) || std::abs(n.get<double>())>128)return Json::object();}
  Json center=Json::array();double radius2=0;for(int i=0;i<3;++i){double a=row["bounds_min"][i].get<double>(),b=row["bounds_max"][i].get<double>();if(a>=b)return Json::object();center.push_back((a+b)*.5);radius2+=(b-a)*(b-a)*.25;}
  return {{"source","original_converted_creature_mesh"},{"min",row["bounds_min"]},{"max",row["bounds_max"]},{"center",center},{"radius",std::sqrt(radius2)},{"head_position",row["head_position"]},{"head_bone",row.value("head_bone",std::string())},{"model_sha256",row["model_sha256"]},{"scale",pet->getHeight(false)}};
 }
 static Json bodyBounds(CreatureObject* pet){
  auto source=sourceBodyBounds(pet);if(!source.empty())return source;
  // Core3 does not decode skeletal SAT appearance bounds. The original shared
  // creature template still supplies its authored collision dimensions/offsets.
  auto t=dynamic_cast<const SharedCreatureObjectTemplate*>(pet->getObjectTemplate());if(!t)return Json::object();
  double r=t->getCollisionRadius(),h=t->getCollisionHeight(),length=t->getCollisionLength(),x=t->getCollisionOffsetX(),z=t->getCollisionOffsetZ();
  if(!std::isfinite(r) || !std::isfinite(h) || !std::isfinite(length) || !std::isfinite(x) || !std::isfinite(z) || r<=0 || h<=0 || r>64 || h>128 || std::abs(x)>128 || std::abs(z)>128 || length>128)return Json::object();
  // Source zero/negative length denotes the circular horizontal footprint.
  double depth=length>0?std::max(r,length*.5):r;
  return {{"source","original_creature_collision_template"},{"min",Json::array({x-r,0,z-depth})},{"max",Json::array({x+r,h,z+depth})},{"center",Json::array({x,h*.5,z})},{"radius",std::sqrt(r*r+h*h*.25+depth*depth)},{"scale",pet->getHeight(false)}};
 }
 static double worldHeading(CreatureObject* pet){double angle=pet->getDirection()->getRadians();auto parent=pet->getParent().get();auto root=pet->getRootParent();if(parent && parent->isCellObject() && root)angle+=root->getDirection()->getRadians();return angle;}
 static bool touches(CreatureObject* owner,CreatureObject* pet,const Vector3& hand){
  if(hand.distanceTo(owner->getWorldPosition())>3.5)return false;
  auto appearance=pet->getAppearanceTemplate();auto volume=appearance?appearance->getBoundingVolume():nullptr;
  if(!volume){auto bounds=bodyBounds(pet);if(bounds.empty())return false;double scale=bounds["scale"].get<double>();if(!std::isfinite(scale) || scale<=0 || scale>16)return false;auto delta=hand-pet->getWorldPosition();double a=worldHeading(pet);double local[]={(delta.getX()*cos(a)-delta.getY()*sin(a))/scale,delta.getZ()/scale,(delta.getX()*sin(a)+delta.getY()*cos(a))/scale};for(int i=0;i<3;++i)if(local[i]<bounds["min"][i].get<double>()-.2/scale || local[i]>bounds["max"][i].get<double>()+.2/scale)return false;return true;}
  const auto& sphere=volume->getBoundingSphere();const auto& p=sphere.getCenter();
  double scale=pet->getHeight(false),a=worldHeading(pet),x=p.getX()*scale,z=p.getZ()*scale,r=sphere.getRadius()*scale;
  auto center=pet->getWorldPosition()+Vector3(x*cos(a)+z*sin(a),-x*sin(a)+z*cos(a),p.getY()*scale);
  return std::isfinite(r) && r>0 && r<128 && hand.distanceTo(center)<=r+.2;
 }
 static Json commands(PetControlDevice* device){
  Json out=Json::array();if(!supported(device))return out;

  for(auto& e:definitions())if(supports(device,e))out.push_back({{"id","pet_"+std::to_string(e.id)},{"command_id",e.id},{"label",e.label},{"source_command",(e.id==1 || e.id==4 || e.id==6)?"follow":e.id==2?"store":e.id==16?"stopfollow":(e.id==10 || e.id==11)?"formation":(e.id==5 || e.id==15)?"group":e.id==21?"harvestcorpse":(e.id==17 || e.id==19)?"vrepairother":"animalattack"},{"target_kind",e.target},{"requires_target",std::string(e.target)!=""},{"range_m",64}});
  return out;
 }
 static void execute(CreatureObject* owner,const Json& q,Json& mutation){
  // Receipt identity intentionally excludes changing hand/body poses.
  auto ghost=owner->getPlayerObject();auto key=q.at("request_id").get<std::string>();
  if(key.size()<8 || key.size()>64)throw std::runtime_error("Stable pet request ID required");
  Json proposal={{"device_id",q.at("device_id")},{"command_id",q.at("command_id")},{"target_id",q.value("target_id",std::string())}};
  auto saved=ghost->getScreenPlayData("swgxr_pets","receipts");auto receipts=saved.isEmpty()?Json::array():Json::parse(saved.toCharArray());
  for(auto& receipt:receipts)if(receipt["id"]==key){if(receipt["proposal"]!=proposal)throw std::runtime_error("Pet request ID reused");mutation=receipt["mutation"];mutation["replayed"]=true;return;}
  auto object=owner->getZoneServer()->getObject(std::stoull(q.at("device_id").get<std::string>()));
  if(!object || !object->isPetControlDevice() || object->getParent().get()!=owner->getSlottedObject("datapad"))throw std::runtime_error("Owned pet control device required");
  auto device=static_cast<PetControlDevice*>(object.get());
  if(!supported(device))throw std::runtime_error("Droid or creature pet required");
  auto pet=device->getControlledObject()->asAiAgent();Locker lock(pet,owner);
  if(owner->isDead() || owner->isIncapacitated() || pet->isDead() || pet->isIncapacitated() || pet->getLinkedCreature().get()!=owner || pet->getZone()!=owner->getZone() || pet->getRootParent()!=owner->getRootParent() || !owner->isInRange(pet,64) || !CollisionManager::checkLineOfSight(owner,pet))throw std::runtime_error("Called, living owned pet in command range required");
  auto& command=definition(q.at("command_id").get<int>());
  {Locker deviceLock(device,pet);if(!supports(device,command))throw std::runtime_error("Pet has not learned that command");}
  uint64 targetId=owner->getObjectID();std::string requested=q.value("target_id",std::string());
  if(std::string(command.target)!=""){
   if(requested.empty())throw std::runtime_error("Pet command target required");
   auto target=owner->getZoneServer()->getObject(std::stoull(requested));
   if(!target)throw std::runtime_error("Pet target no longer exists");
   Locker targetLock(target,pet);targetCheck(owner,pet,target,command);targetId=target->getObjectID();
  }else if(!requested.empty())throw std::runtime_error("Unexpected target for untargeted pet command");
  std::string args=command.args;auto ownerId=std::to_string(owner->getObjectID());
  if(args=="owner")args=ownerId;else if(args=="1 owner")args="1 "+ownerId;else if(args=="2 owner")args="2 "+ownerId;else if(args=="target")args="vr_target "+std::to_string(targetId);
  auto handler=owner->getZoneServer()->getObjectController()->getQueueCommand(command.name);
  if(command.id==2 && (owner->isInCombat() || pet->isInCombat() || !owner->checkCooldownRecovery("petCallOrStoreCooldown")))throw std::runtime_error("Pet cannot be stored during combat or call/store recovery");
  uint32 previousCommand;ManagedReference<SceneObject*> previousCommander;
  {Locker deviceLock(device,pet);previousCommand=device->getLastCommand();previousCommander=device->getLastCommander();device->setLastCommander(owner);if(command.id!=15)device->setLastCommand(command.id);}
  // Commands consume an explicit captured target, never the owner's weapon aim.
  int result=handler->doQueueCommand(pet,command.owner?owner->getObjectID():targetId,UnicodeString(String(args.c_str())));
  if(result!=QueueCommand::SUCCESS){Locker deviceLock(device,pet);device->setLastCommand(previousCommand);device->setLastCommander(previousCommander);throw std::runtime_error("Core3 rejected pet command: power, state, target or module requirements");}
  if(command.id==1 || command.id==6)pet->eraseBlackboard("formationOffset");
  if(pet->getZone()!=nullptr){pet->activateAiBehavior(true);pet->activateRecovery();}
  device->updateToDatabase();mutation["command_id"]=command.id;mutation["pet_id"]=std::to_string(pet->getObjectID());mutation["request_id"]=key;mutation["accepted"]=true;
  receipts.push_back({{"id",key},{"proposal",proposal},{"mutation",mutation}});while(receipts.size()>32)receipts.erase(receipts.begin());ghost->setScreenPlayData("swgxr_pets","receipts",String(receipts.dump().c_str()));
 }
};
#endif
