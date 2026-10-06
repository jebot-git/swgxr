#ifndef SWGXR_VENDOR_COMMERCE_H
#define SWGXR_VENDOR_COMMERCE_H
#include "SwgxrVendorPlacement.h"
#include "templates/creature/VendorCreatureTemplate.h"
#include <algorithm>
class SwgxrVendorCommerce {
 using Json=JSONSerializationType;
 static VendorDataComponent* data(SceneObject* o){auto d=o?o->getDataObjectComponent():nullptr;return o && o->isVendor() && d && d->get() && d->get()->isVendorData()?cast<VendorDataComponent*>(d->get()):nullptr;}
 static ManagedReference<SceneObject*> owned(CreatureObject* c,const Json& r){
  auto key=r.at("vendor_id").get<std::string>();if(key.empty() || key.size()>20 || key.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid_vendor_id");auto o=c->getZoneServer()->getObject(std::stoull(key));auto d=data(o);
  if(!d || d->getOwnerId()!=c->getObjectID() || !d->isInitialized() || d->isSwgxrStored() || o->getZone()!=c->getZone() || o->getParentID()!=c->getParentID() || !c->isInRange(o,3))throw std::runtime_error("owned_nearby_placed_vendor_required");return o;
 }
public:
 static Json controls(SceneObject* o){
  Json out=Json::array();auto t=dynamic_cast<VendorCreatureTemplate*>(o->getObjectTemplate());if(!t)return out;
  for(int i=0;i<t->getCustomizationStringNamesSize() && i<t->getCustomizationValuesSize() && out.size()<128;++i){auto names=t->getCustomizationStringName(i);auto values=t->getCustomizationValues(i);if(values.isEmpty())continue;Json allowed=Json::array();for(int j=0;j<values.size();++j)allowed.push_back(values.get(j));int comma=names.indexOf(',');
   auto add=[&](const String& name){out.push_back({{"id",std::string(name.toCharArray())},{"allowed",allowed},{"pair",comma<0?std::string():std::string((name==names.subString(0,comma)?names.subString(comma+1):names.subString(0,comma)).toCharArray())}});};
   if(comma>=0){if(std::find(allowed.begin(),allowed.end(),Json(0))==allowed.end())allowed.push_back(0);add(names.subString(0,comma));add(names.subString(comma+1));}else add(names);
  }return out;
 }
 static Json mutate(CreatureObject* c,const Json& r){
  auto o=owned(c,r);Locker lock(o,c);auto d=data(o);auto action=r.at("action").get<std::string>();
  if(action=="vendor_customize"){
   auto values=r.at("customization");if(!values.is_object() || values.size()>128)throw std::runtime_error("invalid_vendor_customization");auto rules=controls(o);
   for(auto it=values.begin();it!=values.end();++it){bool valid=false;for(auto& rule:rules)if(rule["id"]==it.key() && it.value().is_number_integer())for(auto& allowed:rule["allowed"])if(allowed==it.value()){valid=true;break;}if(!valid)throw std::runtime_error("unsupported_vendor_customization");}
   auto creature=dynamic_cast<CreatureObject*>(o.get());if(!creature)throw std::runtime_error("vendor_has_no_appearance_controls");
   auto t=dynamic_cast<VendorCreatureTemplate*>(o->getObjectTemplate());
   // Enforce original mutually exclusive morph pairs in the complete draft.
   for(int i=0;i<t->getCustomizationStringNamesSize();++i){auto names=t->getCustomizationStringName(i);int comma=names.indexOf(',');if(comma<0)continue;std::string a=names.subString(0,comma).toCharArray(),b=names.subString(comma+1).toCharArray();if(values.contains(a) && values.at(a).get<int>()!=0)values[b]=0;}
   for(auto it=values.begin();it!=values.end();++it)creature->setCustomizationVariable(String(it.key().c_str()),it.value().get<int>(),true);
  }else if(action=="vendor_recover"){
   auto inv=c->getInventory();String error;if(inv==nullptr || inv->canAddObject(o,-1,error)!=0)throw std::runtime_error("vendor_inventory_full");
   auto zone=o->getZone();if(d->isRegistered())zone->unregisterObjectWithPlanetaryMap(o);bool searched=d->isVendorSearchEnabled();d->setSwgxrStored(true);d->setVendorSearchEnabled(false);d->cancelVendorCheckTask();
   if(!c->getZoneServer()->getObjectController()->transferObject(o,inv,-1,true)){d->setSwgxrStored(false);d->setVendorSearchEnabled(searched);d->scheduleVendorCheckTask(VendorDataComponent::VENDORCHECKINTERVAL);if(d->isRegistered())zone->registerObjectWithPlanetaryMap(o);throw std::runtime_error("vendor_recovery_failed");}
  }else throw std::runtime_error("unsupported_vendor_operation");
  o->updateToDatabaseAllObjects(false);return {{"vendor_id",std::to_string(o->getObjectID())},{"recovered",action=="vendor_recover"},{"customized",action=="vendor_customize"}};
 }
};
#endif
