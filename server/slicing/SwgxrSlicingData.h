#ifndef SWGXR_SLICING_DATA_H
#define SWGXR_SLICING_DATA_H
#include "engine/util/JSONSerializationType.h"
#include "server/zone/objects/tangible/TangibleObject.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include <chrono>
class SwgxrSlicingData {
 static uint64& settling(){static thread_local uint64 value=0;return value;}
public:
 struct Settlement {uint64 previous;explicit Settlement(SceneObject* o):previous(settling()){settling()=o->getObjectID();}~Settlement(){settling()=previous;}};
 using Json=JSONSerializationType;
 static double now(){return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static Json data(SceneObject* o){if(!o || !o->isTangibleObject())return Json::object();auto raw=o->asTangibleObject()->getLuaStringData("swgxr_slice");if(raw.isEmpty())return Json::object();try{return Json::parse(raw.toCharArray());}catch(...){return Json::object();}}
 static Json bonuses(SceneObject* o){return data(o).value("bonuses",Json::object());}
 static double bonus(SceneObject* o,const char* key){return bonuses(o).value(key,0.0);}
 static Json skillMods(SceneObject* o){return data(o).value("skill_mods",Json::array());}
 static int tier(CreatureObject* c){if(c->hasSkill("combat_smuggler_master"))return 5;for(int i=4;i>=1;--i)if(c->hasSkill(String("combat_smuggler_slicing_0")+String::valueOf(i)))return i;return c->hasSkill("combat_smuggler_novice")?0:-1;}
 static std::string kind(SceneObject* o){if(!o || !o->isTangibleObject())return "";auto t=o->asTangibleObject();auto previous=data(o).value("kind",std::string());if(!previous.empty())return previous;std::string path=o->getObjectTemplate()->getFullTemplateString().toCharArray();if(o->getGameObjectType()==SceneObjectType::PLAYERLOOTCRATE)return "container";if(o->isWeaponObject() && t->isSliceable())return "weapon";if(o->isArmorObject() && t->isSliceable())return path.find("shield")!=std::string::npos?"shield":"armor";if(o->isWearableObject() && path.find("/wearables/")!=std::string::npos && path.find("/armor/")==std::string::npos && path.find("/hair/")==std::string::npos && path.find("/backpack/")==std::string::npos)return "clothing";return "";}
 static int required(const std::string& k){return k=="weapon"?2:k=="armor" || k=="shield"?3:k=="clothing"?1:0;}
 static bool tool(SceneObject* o){return o && o->getObjectTemplate()->getFullTemplateString()=="object/tangible/slicing/slicing_laser_knife.iff";}
 static bool locked(SceneObject* o,int depth=0){if(!o || o->isCreatureObject() || o->isBuildingObject() || depth>10 || o->getObjectID()==settling())return false;if(o->isTangibleObject()){auto d=data(o);if(d.value("lease_until",0.0)>now())return true;}for(int i=0;i<o->getContainerObjectsSize();++i)if(locked(o->getContainerObject(i),depth+1))return true;return false;}
 static std::string reason(SceneObject* o,CreatureObject* c){auto k=kind(o);if(k.empty())return "unsupported_item";if(k!="container" && (o->asTangibleObject()->getCraftersID()==0 || o->asTangibleObject()->getSerialNumber().isEmpty()))return "crafted_item_required";if(tier(c)<required(k))return "slicing_skill_required";if(o->asTangibleObject()->isSliced() || data(o).value("burned",false))return "already_sliced";if(locked(o))return "slicing_in_progress";return "";}
 static void describe(Json& out,SceneObject* o,CreatureObject* c){auto k=kind(o);out["slice_crafted"]=o && o->isTangibleObject() && o->asTangibleObject()->getCraftersID()!=0 && !o->asTangibleObject()->getSerialNumber().isEmpty();out["slice_kind"]=k;out["slice_required_tier"]=required(k);out["slice_block_reason"]=reason(o,c);out["sliceable"]=!k.empty() && reason(o,c).empty();out["slicing_locked"]=locked(o);auto d=data(o);out["slice_bonuses"]=d.value("bonuses",Json::object());out["slice_skill_mods"]=d.value("skill_mods",Json::array());}
};
#endif
