#ifndef SWGXR_SPICE_MEDICINE_H
#define SWGXR_SPICE_MEDICINE_H
#include "SwgxrSpice.h"
#include "CoreCuMedicalPolicy.h"
#include "SwgxrVitalFeedback.h"
#include "server/zone/Zone.h"
#include "server/zone/packets/object/PlayClientEffectObjectMessage.h"
#include "templates/params/creature/CreatureAttribute.h"
#include <limits>
// Explicit medical scopes exclude regeneration, equipment refunds and buff HAM
// changes. The native healer remains authoritative for both HAM and feedback.
class SwgxrSpiceMedicine {
public:
 static CreatureObject* actor(TangibleObject* healer){return healer && healer->isCreatureObject()?healer->asCreatureObject():nullptr;}
 static bool inverted(CreatureObject* healer){return SwgxrSpice::withdrawing(healer,"crash_n_burn");}
 static int power(TangibleObject* healer,int amount){auto c=actor(healer);if(amount>0 && SwgxrVitalFeedback::medical() && SwgxrSpice::active(c,"crash_n_burn"))return corecu::medicine::spiceHealing(amount);return amount;}
 static bool reverse(CreatureObject* target,TangibleObject* healer,int attribute,int amount,bool notify){
  auto c=actor(healer);if(amount<=0 || !SwgxrVitalFeedback::medical() || !inverted(c))return false;
  const int pool=target->isPlayerCreature()?0:attribute-attribute%3;
  target->inflictDamage(healer,pool,amount,true,notify,false);
  // The actor retains the healing presentation, even for self-treatment. The
  // recipient's real damage event and actual HAM are never hidden from others.
  if(c->isPlayerCreature())SwgxrVitalFeedback::record(c->getObjectID(),true);
  if(c!=target && target->isPlayerCreature()){
   StringBuffer message;message << c->getDisplayedName() << "'s treatment causes " << amount << " " << CreatureAttribute::getName(pool) << " damage.";
   target->sendSystemMessage(message.toString());
  }
  return true;
 }
 static void effect(CreatureObject* healer,CreatureObject* target,const String& name){
  if(!inverted(healer)){target->playEffect(name,"");return;}
  healer->sendMessage(new PlayClientEffectObjectMessage(target,name,""));
  auto zone=target->getZone();if(!zone)return;
  SortedVector<TreeEntry*> nearby(128,128);auto pos=target->getWorldPosition();
  zone->getInRangeObjects(pos.getX(),pos.getZ(),pos.getY(),64,&nearby,true);
  for(int i=0;i<nearby.size();++i){auto o=static_cast<SceneObject*>(nearby.get(i));if(o!=healer && o->isPlayerCreature())o->asCreatureObject()->sendMessage(new PlayClientEffectObjectMessage(target,"clienteffect/dot_bleeding.cef",""));}
 }
};
#endif
