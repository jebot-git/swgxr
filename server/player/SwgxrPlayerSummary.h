#ifndef SWGXR_PLAYER_SUMMARY_H
#define SWGXR_PLAYER_SUMMARY_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/tangible/wearables/ArmorObject.h"
#include "SwgxrArmour.h"
#include <set>
// Owner-only character sheet data. No area queries, inventory recursion or mutation.
class SwgxrPlayerSummary {
 using Json=JSONSerializationType;
 static std::string str(const String& s){return s.toCharArray();}
 static Json home(CreatureObject* c,uint64 id){
  Json out={{"id",std::to_string(id)},{"status",id?"unavailable":"unset"}};
  if(!id)return out;
  auto object=c->getZoneServer()->getObject(id);
  // Match CharacterSheetResponseMessage: only a resolvable object with a zone
  // supplies a location. Preserve a stale nonzero reference as unavailable.
  if(object==nullptr || object->getZone()==nullptr)return out;
  out["status"]="available";out["name"]=str(object->getDisplayedName());out["template"]=str(object->getObjectTemplate()->getFullTemplateString());
  out["zone"]=str(object->getZone()->getZoneName());
  out["position"]=Json::array({object->getPositionX(),object->getPositionZ(),object->getPositionY()});
  return out;
 }
public:
 static Json snapshot(CreatureObject* c){
  auto ghost=c->getPlayerObject();int status=c->getFactionStatus();
  Json out={{"version",1},{"character_id",std::to_string(c->getObjectID())},{"name",str(c->getFirstName())},
   {"ham",Json::array()},{"max_ham",Json::array()},{"wounds",Json::array()},{"shock_wounds",c->getShockWounds()},
   {"wallet",{{"cash",c->getCashCredits()},{"bank",c->getBankCredits()}}},
   {"faction",{{"allegiance",c->isImperial()?"imperial":c->isRebel()?"rebel":"neutral"},{"status",status},
    {"status_name",c->isNeutral()?"neutral":status==0?"on_leave":"combatant"},{"rank",int(c->getFactionRank())},
    {"pending_status",c->getFutureFactionStatus()},{"standings",{{"imperial",ghost->getFactionStanding("imperial")},{"rebel",ghost->getFactionStanding("rebel")}}}}},
   {"homepoints",{{"residence",home(c,ghost->getDeclaredResidence())},{"cloning",home(c,ghost->getCloningFacility())}}}};
  for(int attribute: {0,3,6}){out["ham"].push_back(std::max(0,c->getHAM(attribute)));out["max_ham"].push_back(c->getMaxHAM(attribute));out["wounds"].push_back(c->getWounds(attribute));}
  Json armour=SwgxrArmour::snapshot(c);armour["pieces"]=Json::array();std::set<uint64> seen;
  for(int i=0;i<c->getSlottedObjectsSize();++i){auto item=c->getSlottedObject(i);
   if(item==nullptr || !item->isArmorObject() || !seen.insert(item->getObjectID()).second)continue;
   auto a=static_cast<ArmorObject*>(item.get());
   Json row={{"id",std::to_string(a->getObjectID())},{"name",str(a->getDisplayedName())},{"template",str(a->getObjectTemplate()->getFullTemplateString())},{"slots",Json::array()},
    {"rating",a->getRating()},{"broken",a->isBroken()},{"shield",a->isPsgArmorObject()},
    {"protection_percent",{{"kinetic",a->getKinetic()},{"energy",a->getEnergy()},{"blast",a->getBlast()},{"stun",a->getStun()},
     {"lightsaber",a->getLightSaber()},{"heat",a->getHeat()},{"cold",a->getCold()},{"acid",a->getAcid()},{"electricity",a->getElectricity()}}},
    {"protection_score",Json::object()}};
   int arrangement=a->getContainmentType()-4;
   if(arrangement>=0 && arrangement<a->getArrangementDescriptorSize())for(int j=0;j<a->getArrangementDescriptor(arrangement)->size();++j)row["slots"].push_back(str(a->getArrangementDescriptor(arrangement)->get(j)));
   const char* labels[]={"kinetic","energy","heat","cold","acid","electricity"};const int channels[]={1,2,32,64,128,256};
   if(SwgxrArmour::reference(a))for(int k=0;k<6;++k)row["protection_score"][labels[k]]=a->getSwgxrProtectionScore(channels[k]);
   armour["pieces"].push_back(row);
  }
  out["armour"]=armour;return out;
 }
};
#endif
