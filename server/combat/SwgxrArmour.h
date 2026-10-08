#ifndef SWGXR_ARMOUR_H
#define SWGXR_ARMOUR_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/tangible/wearables/ArmorObject.h"
#include "server/zone/objects/tangible/wearables/ArmourReferences.h"
#include <set>
#include <map>

class SwgxrArmour {
public:
 static const swgxr::armour::ArmourReference* reference(SceneObject* item) {
  if(!item || item->isPsgArmorObject())return nullptr;
  static const auto references=[](){
   std::map<uint32,const swgxr::armour::ArmourReference*> result;
   for(const auto& ref:swgxr::armour::REFERENCES)result.emplace(String(ref.path).hashCode(),&ref);
   return result;
  }();
  const auto found=references.find(item->getServerObjectCRC());
  return found==references.end()?nullptr:found->second;
 }
 static bool trained(CreatureObject* c,int kind){
  if(!c)return false;
  static const char* recon[]={"combat_pistol_master","combat_rifleman_master","combat_smuggler_master"};
  static const char* battle[]={"combat_carbine_master","combat_1hsword_master","combat_2hsword_master","combat_polearm_master","science_combatmedic_master","science_doctor_master","outdoors_creaturehandler_master","outdoors_ranger_master"};
  static const char* assault[]={"combat_bountyhunter_master","combat_commando_master","outdoors_squadleader_master"};
  if(kind==1){for(auto skill:recon)if(c->hasSkill(skill))return true;}
  else if(kind==2){for(auto skill:assault)if(c->hasSkill(skill))return true;}
  else {for(auto skill:battle)if(c->hasSkill(skill))return true;}
  return false;
 }
 // Restore only obsolete secondary-stat deductions. Do not invoke fixHAM on
 // equip: its general repair path also removes some force buffs.
 static void reconcileEncumbrance(CreatureObject* c){
  int remaining[3]={0,0,0};std::set<uint64> seen;
  for(int i=0;i<c->getSlottedObjectsSize();++i){
   auto item=c->getSlottedObject(i);
   if(item==nullptr || !item->isArmorObject() || reference(item) || !seen.insert(item->getObjectID()).second)continue;
   auto armor=static_cast<ArmorObject*>(item.get());
   remaining[0]+=std::max(0,armor->getHealthEncumbrance());
   remaining[1]+=std::max(0,armor->getActionEncumbrance());
   remaining[2]+=std::max(0,armor->getMindEncumbrance());
  }
  for(int pool=0;pool<3;++pool){
   const int delta=c->getEncumbrance(pool)-remaining[pool];
   if(delta==0)continue;
   c->setEncumbrance(pool,remaining[pool],true);
   for(int offset=1;offset<=2;++offset){
    const int stat=pool*3+offset;
    c->addMaxHAM(stat,delta,true);
    if(delta>0)c->healDamage(c,stat,delta,true);
    else c->inflictDamage(c,stat,-delta,true);
   }
  }
 }
 static double scale(CreatureObject* c,int kind){
  if(!c || !c->isPlayerCreature())return 1;
  double penalty=0;std::set<uint64> seen;
  for(int i=0;i<c->getSlottedObjectsSize();++i){
   auto item=c->getSlottedObject(i);const auto ref=reference(item);
   if(!ref || !item->isArmorObject() || !seen.insert(item->getObjectID()).second)continue;
   auto armor=static_cast<ArmorObject*>(item.get());
   if(armor->isBroken())continue;
   penalty=std::max(penalty,double(armor->getSwgxrHindrance(kind))*(trained(c,ref->kind)?.5:1));
  }
  return 1-penalty;
 }
 static JSONSerializationType snapshot(CreatureObject* c){return {
  {"version",1},{"revision",swgxr::armour::REVISION},
  {"movement_scale",scale(c,0)},{"output_scale",scale(c,1)},{"recovery_scale",scale(c,2)}};}
};
#endif
