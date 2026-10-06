#ifndef SWGXR_IMAGE_DESIGN_H
#define SWGXR_IMAGE_DESIGN_H
#include "server/zone/objects/player/sessions/ImageDesignSession.h"
#include "server/zone/objects/player/sessions/ImageDesignData.h"
#include "server/zone/objects/creature/commands/ImagedesignCommand.h"
#include <fstream>
#include <cstdlib>
#include <atomic>
#include <chrono>
// The bridge owns only a bounded, revisioned proposal. The original native
// session owns consented payment, customization, hair transfer and XP.
class SwgxrImageDesign {
 using Json=JSONSerializationType;
 class Data:public ImageDesignData {
 public:
  Data(const Json& draft,CreatureObject* designer,bool da,bool ta){
   requiredPayment=draft.value("price",0);offeredPayment=requiredPayment;
   designerAccepted=da;targetAccepted=ta;statMigrationRequested=0;
   hairTemplate=String(draft.value("hair_template",std::string()).c_str());
   holoEmote=String(draft.value("holoemote",std::string()).c_str());
   bodySkillMod=designer->getSkillMod("body");faceSkillMod=designer->getSkillMod("face");hairSkillMod=designer->getSkillMod("hair");markingsSkillMod=designer->getSkillMod("markings");
   for(auto it=draft.at("body").begin();it!=draft.at("body").end();++it)bodyAttributes.put(String(it.key().c_str()),it.value().get<float>());
   for(auto it=draft.at("colors").begin();it!=draft.at("colors").end();++it)colorAttributes.put(String(it.key().c_str()),it.value().get<uint32>());
  }
 };
 static std::string str(const String& s){return s.toCharArray();}
 static std::string id(SceneObject* c){return c?std::to_string(c->getObjectID()):"0";}
 static ManagedReference<ImageDesignSession*> active(CreatureObject* c){return c->getActiveSession(SessionFacadeType::IMAGEDESIGN).castTo<ImageDesignSession*>();}
 static std::string sid(ImageDesignSession* s){return s?str(s->getSwgxrSessionToken()):"";}
 static Json read(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_image_design","state");return raw.isEmpty()?Json::object():Json::parse(raw.toCharArray());}
 static void save(CreatureObject* c,const Json& value){c->getPlayerObject()->setScreenPlayData("swgxr_image_design","state",String(value.dump().c_str()));}
 static const Json& policy(){
  static Json value=[](){std::vector<std::string> paths;auto overridePath=std::getenv("SWGXR_IMAGE_DESIGN_POLICY");if(overridePath)paths.push_back(overridePath);for(auto p:{"../../../../runtime/assets/image_design/policy.json","runtime/assets/image_design/policy.json","/workspace/runtime/assets/image_design/policy.json"})paths.push_back(p);
   for(auto& path:paths){std::ifstream file(path);if(!file)continue;Json v;file>>v;if(v.value("schema_version",0)!=1 || !v.contains("races"))throw std::runtime_error("invalid_image_design_policy");return v;}throw std::runtime_error("original_image_design_policy_not_prepared");}();return value;
 }
 static std::string hair(CreatureObject* c){auto h=c->getSlottedObject("hair");return h?str(h->getObjectTemplate()->getFullTemplateString()):"";}
 static std::string custom(TangibleObject* object){String data;object->getCustomizationString(data);std::string out;const char* chars="0123456789abcdef";for(int i=0;i<data.length();++i){unsigned char b=data[i];out+=chars[b>>4];out+=chars[b&15];}return out;}
 static Json appearance(CreatureObject* c){
  Json out={{"template",str(c->getObjectTemplate()->getFullTemplateString())},{"height",c->getHeight(false)},{"customization_hex",custom(c)},{"hair_template",hair(c)},{"hair_customization_hex",""},{"equipment",Json::array()}};
  auto h=c->getSlottedObject("hair").castTo<TangibleObject*>();if(h)out["hair_customization_hex"]=custom(h);
  std::set<uint64> seen;for(int i=0;i<c->getSlottedObjectsSize() && out["equipment"].size()<32;++i){auto item=c->getSlottedObject(i).castTo<TangibleObject*>();if(!item || item==h || !seen.insert(item->getObjectID()).second)continue;auto name=str(item->getObjectTemplate()->getFullTemplateString());if(name.find("object/tangible/wearables/")!=0 && name.find("object/weapon/")!=0)continue;Json row={{"id",id(item)},{"template",name},{"customization_hex",custom(item)},{"equipped_slots",Json::array()}};int index=item->getContainmentType()-4;if(index>=0 && index<item->getArrangementDescriptorSize()){auto slots=item->getArrangementDescriptor(index);for(int n=0;n<slots->size();++n)row["equipped_slots"].push_back(str(slots->get(n)));}out["equipment"].push_back(row);}return out;
 }
 static Json designerContext(CreatureObject* c){Json skills=Json::array();auto s=c->getSkillList();for(int i=0;i<s->size();++i)skills.push_back(str(s->get(i)->getSkillName()));Json mods=Json::object();for(auto m:{"body","face","hair","markings"})mods[m]=c->getSkillMod(m);return {{"skills",skills},{"skill_mods",mods}};}
 static bool near(CreatureObject* d,CreatureObject* t){return d->isOnline() && t->isOnline() && d->getZone()!=nullptr && d->getZone()==t->getZone() && d->getParentID()==t->getParentID() && d->isInRange(t,8) && !d->isDead() && !d->isIncapacitated() && !d->isInCombat() && !t->isDead() && !t->isIncapacitated() && !t->isInCombat();}
 static Json validate(CreatureObject* d,CreatureObject* t,const Json& proposal){
  auto& all=policy();auto name=str(t->getObjectTemplate()->getFullTemplateString());if(!all["races"].contains(name))throw std::runtime_error("unsupported_image_design_species");auto& rules=all["races"][name];
  int price=proposal.value("price",0);if(price<0 || price>10000)throw std::runtime_error("invalid_image_design_price");
  auto attrs=proposal.value("attributes",Json::object());if(!attrs.is_object() || attrs.size()>128)throw std::runtime_error("invalid_image_design_attributes");
  Json body=Json::object(),colors=Json::object();
  for(auto it=attrs.begin();it!=attrs.end();++it){bool allowed=false;for(auto& rule:rules["controls"]){if(rule["id"]!=it.key())continue;auto mod=rule["mod"].get<std::string>();if(d->getSkillMod(String(mod.c_str()))<rule["required"].get<int>())break;
   int tier=0;auto branch=rule["branch"].get<std::string>();for(int n=1;n<=4;++n)if(d->hasSkill(String(("social_imagedesigner_"+branch+"_0"+std::to_string(n)).c_str())))tier=n;if(d->hasSkill("social_imagedesigner_master"))tier=5;
   if(!it.value().is_number())break;double v=it.value().get<double>();bool color=rule["type"]=="color";if(!std::isfinite(v) || v<0 || v>rule["maxima"][tier].get<double>() || (color && std::floor(v)!=v))break;(color?colors:body)[it.key()]=it.value();allowed=true;break;
  }if(!allowed)throw std::runtime_error("unlearned_image_design_control:"+it.key());}
  auto selected=proposal.value("hair_template",hair(t));bool learned=selected==hair(t) || (selected.empty() && rules["allow_bald"].get<bool>());
  for(auto& style:rules["hair"])if(style["template"]==selected && d->getSkillMod("hair")>=style["required"].get<int>())learned=true;if(!learned)throw std::runtime_error("unlearned_image_design_hair");
  auto holo=proposal.value("holoemote",std::string());bool known=holo.empty();for(auto& effect:all["holoemotes"])if(effect["name"]==holo && d->getSkillMod("hair")>=effect["required"].get<int>())known=true;if(!known)throw std::runtime_error("unlearned_image_design_holoemote");
  return {{"attributes",attrs},{"body",body},{"colors",colors},{"hair_template",selected},{"hair_changed",selected!=hair(t)},{"holoemote",holo},{"price",price}};
 }
 static Json view(CreatureObject* c,CreatureObject* d,CreatureObject* t,const Json& meta){
  auto draft=meta["draft"];draft.erase("body");draft.erase("colors");draft.erase("hair_changed");bool isDesigner=c==d;
  bool modified=!draft["attributes"].empty() || draft["hair_template"]!=hair(t) || !draft["holoemote"].get<std::string>().empty();
  return {{"active",true},{"session_id",meta["session_id"]},{"revision",meta["revision"]},{"role",isDesigner?"designer":"recipient"},{"designer_id",id(d)},{"recipient_id",id(t)},{"designer_name",str(d->getFirstName())},{"recipient_name",str(t->getFirstName())},{"designer_context",designerContext(d)},{"appearance",appearance(t)},{"draft",draft},{"remaining_seconds",0},{"can_accept",modified && near(d,t)},{"designer_accepted",meta["designer_accepted"]},{"recipient_accepted",meta["recipient_accepted"]},{"accepted",meta[isDesigner?"designer_accepted":"recipient_accepted"]},{"status","proposal"}};
 }
public:
 static Json ownAppearance(CreatureObject* c){return appearance(c);}
 static Json snapshot(CreatureObject* c){
  auto s=active(c);if(!s)return {{"active",false}};auto marker=read(c);if(marker.empty() || marker.value("session_id",std::string())!=sid(s))return {{"active",false},{"external_session",true}};
  auto d=c->getZoneServer()->getObject(std::stoull(marker["designer_id"].get<std::string>())).castTo<CreatureObject*>();if(!d)return {{"active",false}};Locker lock(d,c);auto meta=read(d);
  auto t=c->getZoneServer()->getObject(std::stoull(meta["recipient_id"].get<std::string>())).castTo<CreatureObject*>();if(!t || (c!=d && c!=t) || active(d)!=s || active(t)!=s)return {{"active",false}};Locker targetLock(t,c);
  if(!near(d,t)){s->cancelSession();save(d,Json::object());if(t!=d)save(t,Json::object());return {{"active",false},{"status","out_of_range"}};}
  return view(c,d,t,meta);
 }
 static Json run(CreatureObject* c,const Json& q){
  auto action=q.at("action").get<std::string>();Json mutation={{"success",true},{"operation",action}};
  if(action=="image_open"){
   auto t=c->getZoneServer()->getObject(std::stoull(q.at("target_id").get<std::string>())).castTo<CreatureObject*>();if(!t || !t->isPlayerCreature())throw std::runtime_error("image_design_player_required");Locker lock(t,c);
   if(!near(c,t))throw std::runtime_error("image_design_range_or_state");if(active(c) || active(t))throw std::runtime_error("image_design_session_already_active");
   auto draft=validate(c,t,Json::object());auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("imagedesign");if(!cmd || cmd->doQueueCommand(c,t->getObjectID(),UnicodeString())!=QueueCommand::SUCCESS)throw std::runtime_error("native_image_design_rejected_group_or_skill");auto s=active(c);if(!s || active(t)!=s)throw std::runtime_error("native_image_design_not_started");
   static std::atomic<uint64_t> serial{uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now().time_since_epoch()).count())};String token(std::to_string(serial.fetch_add(1)).c_str());s->setSwgxrSessionToken(token);
   Json meta={{"session_id",sid(s)},{"designer_id",id(c)},{"recipient_id",id(t)},{"revision",0},{"draft",draft},{"designer_accepted",false},{"recipient_accepted",false}};save(c,meta);if(t!=c)save(t,{{"session_id",sid(s)},{"designer_id",id(c)}});mutation["opened"]=true;return {{"state",view(c,c,t,meta)},{"mutation",mutation}};
  }
  auto current=snapshot(c);if(!current.value("active",false) || current["session_id"]!=q.at("session_id") || current["revision"]!=q.at("revision"))throw std::runtime_error("image_design_session_or_revision_changed");
  auto d=c->getZoneServer()->getObject(std::stoull(current["designer_id"].get<std::string>())).castTo<CreatureObject*>();Locker lock(d,c);auto meta=read(d);if(meta["revision"]!=q.at("revision"))throw std::runtime_error("image_design_revision_changed");auto t=c->getZoneServer()->getObject(std::stoull(meta["recipient_id"].get<std::string>())).castTo<CreatureObject*>();Locker targetLock(t,c);auto s=active(c);if(!s || active(d)!=s || active(t)!=s)throw std::runtime_error("native_image_design_session_changed");
  if(action=="image_cancel"){s->cancelSession();save(d,Json::object());if(t!=d)save(t,Json::object());mutation["cancelled"]=true;return {{"state",{{"active",false}}},{"mutation",mutation}};}
  if(!near(d,t))throw std::runtime_error("image_design_range_or_state");
  if(action=="image_propose"){
   if(c!=d)throw std::runtime_error("only_designer_may_propose");meta["draft"]=validate(d,t,q.at("draft"));meta["revision"]=meta["revision"].get<int>()+1;meta["designer_accepted"]=false;meta["recipient_accepted"]=false;save(d,meta);mutation["proposed"]=true;
  }else if(action=="image_accept"){
   auto draft=validate(d,t,meta["draft"]);if(draft["attributes"].empty() && !draft["hair_changed"].get<bool>() && draft["holoemote"].get<std::string>().empty())throw std::runtime_error("image_design_has_no_changes");
   meta[c==d?"designer_accepted":"recipient_accepted"]=true;if(d==t)meta["recipient_accepted"]=true;save(d,meta);
   bool da=meta["designer_accepted"].get<bool>(),ta=meta["recipient_accepted"].get<bool>();
   // Only the authenticated recipient can set its consent. No flags supplied
   // by clients are forwarded into the original image-design data packet.
   if(da && ta){int price=draft["price"].get<int>();if(int64(t->getCashCredits())+t->getBankCredits()<price)throw std::runtime_error("image_design_insufficient_credits");Data data(draft,d,true,true);s->updateImageDesign(c,d->getObjectID(),t->getObjectID(),0,draft["hair_changed"].get<bool>()?1:0,data);if(active(d)==s)throw std::runtime_error("native_image_design_commit_not_confirmed");save(d,Json::object());if(t!=d)save(t,Json::object());d->updateToDatabaseAllObjects(false);if(t!=d)t->updateToDatabaseAllObjects(false);mutation["committed"]=true;mutation["recipient_id"]=id(t);return {{"state",{{"active",false},{"status","committed"}}},{"mutation",mutation}};}
   mutation["accepted"]=true;
  }else throw std::runtime_error("unsupported_image_design_action");
  return {{"state",view(c,d,t,meta)},{"mutation",mutation}};
 }
};
#endif
