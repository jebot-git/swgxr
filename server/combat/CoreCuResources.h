#pragma once
#include <set>
#include "CoreCuMedicalPolicy.h"
#include "SwgxrSpice.h"
#include "server/zone/objects/factorycrate/FactoryCrate.h"
#include "server/zone/objects/manufactureschematic/ManufactureSchematic.h"
#include "server/zone/managers/skill/SkillManager.h"
// CU-style Health/resource split with pre-CU skill progression. The numerical
// baseline is provisional SWGXR tuning; no combat-level gates are introduced.
class CoreCuResources {
public:
 static int base(int attribute){return attribute==0?3000:attribute==3 || attribute==6?1000:300;}
 static double regen(int attribute,bool combat){return attribute==0?(combat?0.:.02):(combat?(attribute==3?.01:.008):.04);}
 // Remove retired owned supplies lazily when the character enters gameplay. Templates
 // remain registered so legacy DB objects deserialize safely. No Health pack is removed.
 static void cleanSupplies(SceneObject* container){
  if(!container)return;
  for(int i=container->getContainerObjectsSize()-1;i>=0;--i){
   ManagedReference<SceneObject*> item=container->getContainerObject(i);if(!item)continue;
   SceneObject* content=item;
   if(auto crate=dynamic_cast<FactoryCrate*>(item.get())){if(crate->getPrototype())content=crate->getPrototype();}
   if(auto blueprint=dynamic_cast<ManufactureSchematic*>(item.get())){if(blueprint->getPrototype())content=blueprint->getPrototype();}
   if(corecu::medicine::retiredMedicalTemplate(content->getObjectTemplate()->getFullTemplateString().toCharArray())){
    item->destroyObjectFromWorld(true);item->destroyObjectFromDatabase(true);
   }else cleanSupplies(item);
  }
 }
 static void normalizeCompanion(CreatureObject* c){
  if(!c || !c->isPet())return;
  for(int i=1;i<9;++i)if(c->getWounds(i))c->setWounds(i,0);
  // Old pet food and Doctor buffs are clamped without extending their clocks.
  auto buffs=c->getBuffList();
  for(int i=buffs->getBuffListSize()-1;i>=0;--i){
   Reference<Buff*> old=buffs->getBuffByIndex(i);if(!old || (old->getBuffType()!=BuffType::FOOD && old->getBuffType()!=BuffType::MEDICAL))continue;
   int amounts[9];bool changed=false;
   for(int a=0;a<9;++a){int value=old->getAttributeModifierValue(a);int cap=int(c->getBaseHAM(a)*(old->getBuffType()==BuffType::FOOD?.10:.15));amounts[a]=std::max(-cap,std::min(cap,value));changed|=amounts[a]!=value;}
   if(!changed)continue;
   int ham[9];for(int a=0;a<9;++a)ham[a]=c->getHAM(a);
   auto crc=old->getBuffCRC();auto type=old->getBuffType();float left=old->getTimeLeft();c->removeBuff(crc);
   if(left>0){Reference<Buff*> buff=new Buff(c,crc,left,type);buff->setFillAttributesOnBuff(false);for(int a=0;a<9;++a)buff->setAttributeModifier(a,amounts[a]);auto skills=old->getSkillModifiers();for(int a=0;a<skills->size();++a)buff->setSkillModifier(skills->elementAt(a).getKey(),skills->elementAt(a).getValue());c->addBuff(buff);}
   for(int a=0;a<9;++a)c->setHAM(a,std::min(ham[a],c->getMaxHAM(a)-c->getWounds(a)));
  }
 }
 static void normalize(CreatureObject* c){
  if(!c || !c->isPlayerCreature() || c->isDead() || c->isIncapacitated() || SwgxrSpice::pinnedHam(c))return;
  for(auto name:{"diagnose","healWound","tendWound"})SkillManager::instance()->removeAbility(c->getPlayerObject(),name,true);
  // Clear obsolete wounds before the old baseline-version early return. No resource refill.
  for(int i=1;i<9;++i)if(c->getWounds(i)!=0)c->setWounds(i,0);
  // Includes equipped backpacks as well as inventory, bank and datapad.
  std::set<uint64> visited;for(int i=0;i<c->getSlottedObjectsSize();++i){auto slot=c->getSlottedObject(i);if(slot && visited.insert(slot->getObjectID()).second)cleanSupplies(slot);}
  auto selected=c->getPlayerObject()->getScreenPlayData("swgxr_medic","selected");
  if(corecu::medicine::retired(selected.toCharArray()))c->getPlayerObject()->setScreenPlayData("swgxr_medic","selected","");
  if(c->getPlayerObject()->getScreenPlayData("corecu_food","version")!="1"){
   auto buffs=c->getBuffList();bool removed=false;
   for(int i=buffs->getBuffListSize()-1;i>=0;--i){auto buff=buffs->getBuffByIndex(i);if(buff && buff->getBuffType()==BuffType::FOOD){c->removeBuff(buff->getBuffCRC());removed=true;}}
   if(removed)c->sendSystemMessage("Food balance updated: consume food or drink to apply the new bonuses.");
   c->getPlayerObject()->setScreenPlayData("corecu_food","version","1");
  }
  if(selected=="healdamage")c->getPlayerObject()->setScreenPlayData("swgxr_medic","selected","");
  if(c->getPlayerObject()->getScreenPlayData("corecu_resources","version")=="1")return;
  SwgxrSpice::HamAdjustment scope;
  JSONSerializationType original=JSONSerializationType::array();double fullness[9];
  for(int i=0;i<9;++i){
   int oldBase=std::max(1,c->getBaseHAM(i)),oldWounds=c->getWounds(i),effective=std::max(1,c->getMaxHAM(i)-oldWounds);
   fullness[i]=std::max(0.,std::min(1.,double(c->getHAM(i))/effective));original.push_back(oldBase);
   int next=base(i),maximum=std::max(1,c->getMaxHAM(i)+next-oldBase);
   c->setBaseHAM(i,next);c->setMaxHAM(i,maximum);c->setWounds(i,std::min(next-1,int(std::round(double(oldWounds)*next/oldBase))));
  }
  // Only old Doctor HAM enhancements are rebased. Spices, entertainer buffs,
  // food, status modifiers and their expiry clocks remain untouched.
  for(int i=0;i<9;++i){
   static const char* names[]={"health","strength","constitution","action","quickness","stamina","mind","focus","willpower"};
   String name=String("medical_enhance_")+names[i];
   Reference<Buff*> old=c->getBuff(name.hashCode());if(old==nullptr)continue;
   int amount=old->getAttributeModifierValue(i),bounded=corecu::medicine::enhancement(c->getBaseHAM(i),amount);
   if(amount<=bounded)continue;
   float remaining=old->getTimeLeft();c->removeBuff(name.hashCode());
   if(remaining>0){Reference<Buff*> buff=new Buff(c,name.hashCode(),remaining,BuffType::MEDICAL);buff->setAttributeModifier(i,bounded);buff->setFillAttributesOnBuff(false);c->addBuff(buff);}
  }
  for(int i=0;i<9;++i)c->setHAM(i,std::max(1,int(std::round(fullness[i]*std::max(1,c->getMaxHAM(i)-c->getWounds(i))))));
  c->getPlayerObject()->setScreenPlayData("corecu_resources","original_base",String(original.dump().c_str()));
  c->getPlayerObject()->setScreenPlayData("corecu_resources","version","1");
 }
};
