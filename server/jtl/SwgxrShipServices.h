#pragma once
#include "InstallShipComponentCommand.h"
#include "server/zone/objects/ship/components/ShipChassisComponent.h"
#include "server/zone/objects/tangible/deed/ship/ShipDeed.h"
// Native hull purchase/registration and component commands, exposed at originals.
class SwgxrShipServices {
 using Json=JSONSerializationType;
 static std::string text(const String& s){return s.toCharArray();}
 static std::string id(SceneObject* o){return std::to_string(o->getObjectID());}
 static uint64 oid(const Json& r,const char* key){auto v=r.at(key).get<std::string>();if(v.empty() || v.size()>20 || v.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("ship_service_invalid_object");return std::stoull(v);}
 static ShipObject* ship(CreatureObject* c,const Json& request){
  auto o=c->getZoneServer()->getObject(oid(request,"ship_id"));auto s=o?o->asShipObject():nullptr;
  auto d=s?c->getZoneServer()->getObject(s->getControlDeviceID()):nullptr;
  if(!s || s->getOwnerID()!=c->getObjectID() || !d || !d->isShipControlDevice() || !d->isASubChildOf(c) || s->isShipLaunched())throw std::runtime_error("owned_stored_ship_required");return s;
 }
public:
 static bool dealer(SceneObject* npc){
  if(!npc || !npc->isAiAgent())return false;auto mobile=npc->asAiAgent()->getCreatureTemplate();if(!mobile)return false;
  auto t=CreatureTemplateManager::instance()->getConversationTemplate(mobile->getConversationTemplate());return t && t->getLuaClassHandler()=="chassisDealerConvoHandler";
 }
 static void describeDealer(CreatureObject* c,Json& view){
  view["options"]=Json::array();auto inv=c->getInventory();if(!inv)return;
  for(int i=0;i<inv->getContainerObjectsSize();++i){auto o=inv->getContainerObject(i);auto chassis=dynamic_cast<ShipChassisComponent*>(o.get());
   if(chassis){auto cert=chassis->getCertificationRequired();int cost=chassis->getDealerFee() * (!cert.isEmpty() && !c->getPlayerObject()->hasAbility(cert)?ShipManager::NO_CERT_COST_MULTI:1);view["options"].push_back({{"name","Redeem "+text(o->getDisplayedName())+" · "+std::to_string(cost)+" credits"},{"item_id",id(o)},{"price",cost},{"operation","ship_chassis_redeem"},{"item_name",text(o->getDisplayedName())}});}
   else if(o->isShipDeedObject())view["options"].push_back({{"name","Register "+text(o->getDisplayedName())},{"item_id",id(o)},{"operation","ship_register"},{"item_name",text(o->getDisplayedName())}});
  }
 }
 static void describeComponents(CreatureObject* c,const Json& request,Json& view){
  auto s=ship(c,request);Locker shipLock(s,c);auto install=dynamic_cast<const InstallShipComponentCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("installshipcomponent"));if(!install)throw std::runtime_error("native_ship_component_command_missing");
  view["kind"]="ship_outfit";view["ship_id"]=id(s);view["name"]=text(s->getDisplayedName());view["options"]=Json::array();view["mass"]=s->getChassisMass();view["maximum_mass"]=s->getChassisMaxMass();auto inventory=c->getInventory();
  for(int slot=0;slot<=Components::FIGHTERSLOTMAX;++slot){
   auto installed=s->getComponentObject(slot);std::string slotName=text(Components::shipComponentSlotToString(slot));
   if(installed){view["options"].push_back({{"name","Remove "+slotName+": "+text(installed->getDisplayedName())},{"operation","ship_component_remove"},{"slot",slot},{"slot_name",slotName},{"item_name",text(installed->getDisplayedName())},{"component_id",id(installed)}});continue;}
   for(int i=0;inventory && i<inventory->getContainerObjectsSize();++i){auto o=inventory->getContainerObject(i);auto component=dynamic_cast<ShipComponent*>(o.get());
    if(component && install->isSlotCompatibleWithComponent(s,component,slot))view["options"].push_back({{"name","Install "+slotName+": "+text(component->getDisplayedName())},{"operation","ship_component_install"},{"slot",slot},{"slot_name",slotName},{"item_name",text(component->getDisplayedName())},{"component_id",id(component)},{"mass",component->getMass()}});
   }
  }
 }
 static void run(CreatureObject* c,SceneObject* terminal,const Json& request){
  auto action=request.at("action").get<std::string>();
  if(action=="ship_chassis_redeem" || action=="ship_register"){
   if(!dealer(terminal) || !c->isInRange(terminal,5) || !CollisionManager::checkLineOfSight(c,terminal))throw std::runtime_error("native_chassis_dealer_required");
   auto item=c->getZoneServer()->getObject(oid(request,"item_id"));if(!item || !SwgxrEquipment::inInventory(item,c))throw std::runtime_error("owned_ship_blueprint_or_deed_required");Locker itemLock(item,c);
   if(action=="ship_chassis_redeem"){
    auto chassis=dynamic_cast<ShipChassisComponent*>(item.get());if(!chassis)throw std::runtime_error("native_crafted_chassis_required");
    auto cert=chassis->getCertificationRequired();int price=chassis->getDealerFee() * (!cert.isEmpty() && !c->getPlayerObject()->hasAbility(cert)?ShipManager::NO_CERT_COST_MULTI:1);
    if(request.at("price").get<int>()!=price)throw std::runtime_error("ship_dealer_price_changed");
    if(!ShipManager::instance()->createDeedFromChassis(c,chassis,terminal->asCreatureObject()))throw std::runtime_error("native_chassis_redemption_rejected");
   }else{
    auto deed=dynamic_cast<ShipDeed*>(item.get());if(!deed || deed->getGeneratedObjectTemplate().hashCode()==388127163 || deed->handleObjectMenuSelect(c,20)!=0 || item->isASubChildOf(c))throw std::runtime_error("native_ship_registration_rejected");
   }
  }else{
   if(!SwgxrJtl::starshipTerminal(terminal) || !CollisionManager::checkLineOfSight(c,terminal))throw std::runtime_error("native_starship_terminal_required");
   auto s=ship(c,request);Locker shipLock(s,c);if(action=="ship_manage")return;
   int slot=request.at("slot").get<int>();if(slot<0 || slot>Components::FIGHTERSLOTMAX)throw std::runtime_error("native_ship_slot_invalid");
   auto component=c->getZoneServer()->getObject(oid(request,"component_id"));if(!component)throw std::runtime_error("native_ship_component_missing");
   bool installing=action=="ship_component_install";auto old=s->getComponentObject(slot);
   if(installing && (old || !SwgxrEquipment::inInventory(component,c)))throw std::runtime_error("empty_slot_and_owned_component_required");
   if(!installing && old!=component)throw std::runtime_error("installed_component_changed");
   auto inv=c->getInventory();if(!installing && (!inv || inv->getCountableObjectsRecursive()>=inv->getContainerVolumeLimit()))throw std::runtime_error("inventory_space_required");
   auto q=c->getZoneServer()->getObjectController()->getQueueCommand(installing?"installshipcomponent":"uninstallshipcomponent");
   std::string args=id(s)+" "+std::to_string(slot)+(installing?" "+id(component):"");
   if(!q || q->doQueueCommand(c,0,UnicodeString(String(args.c_str())))!=QueueCommand::SUCCESS || (installing?s->getComponentObject(slot)!=component:s->getComponentObject(slot)!=nullptr || !component->isASubChildOf(c)))throw std::runtime_error("native_ship_component_change_rejected");
   s->updateToDatabaseAllObjects(false);component->updateToDatabaseAllObjects(false);
  }
  c->updateToDatabaseAllObjects(false);
 }
};
