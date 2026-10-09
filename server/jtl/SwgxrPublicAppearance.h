#pragma once
#include <set>
class SwgxrPublicAppearance {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
public:
 static std::string customization(TangibleObject* o){
  String data;o->getCustomizationString(data);static const char* digits="0123456789abcdef";std::string encoded;
  for(int i=0;i<data.length();++i){unsigned char value=data[i];encoded+=digits[value>>4];encoded+=digits[value&15];}return encoded;
 }
 static Json publicAppearance(CreatureObject* c){
  Json out={{"template",std::string(c->getObjectTemplate()->getFullTemplateString().toCharArray())},{"client_crc",c->getClientObjectCRC()},{"customization_hex",customization(c)},{"height",c->getHeight(false)},{"hair_template",""},{"hair_customization_hex",""},{"equipment",Json::array()},{"equipment_complete",true}};
  std::set<uint64> seen;
  for(int i=0;i<c->getSlottedObjectsSize();++i){auto item=c->getSlottedObject(i);if(item==nullptr || !item->isTangibleObject() || item->getParent().get()!=c || !seen.insert(item->getObjectID()).second)continue;
   std::string name=item->getObjectTemplate()->getFullTemplateString().toCharArray();auto tangible=item->asTangibleObject();
   if(name.find("object/tangible/hair/")==0){out["hair_template"]=name;out["hair_client_crc"]=item->getClientObjectCRC();out["hair_customization_hex"]=customization(tangible);continue;}
   if(name.find("object/tangible/wearables/")!=0 && name.find("object/weapon/")!=0)continue;
   if(out["equipment"].size()>=32){out["equipment_complete"]=false;break;}
   Json row={{"id",id(item)},{"template",name},{"client_crc",item->getClientObjectCRC()},{"customization_hex",customization(tangible)},{"equipped_slots",Json::array()}};
   int index=item->getContainmentType()-4;if(index>=0 && index<item->getArrangementDescriptorSize()){auto slots=item->getArrangementDescriptor(index);for(int n=0;n<slots->size();++n)row["equipped_slots"].push_back(std::string(slots->get(n).toCharArray()));}
   out["equipment"].push_back(row);
  }return out;
 }
};
