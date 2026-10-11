#pragma once
#include <map>
#include <set>
// Original JunkDealer Lua buying masks and TangibleObject prices. Services own
// authenticated receipts; no caller supplies eligibility, a price or a wallet delta.
class SwgxrJunkDealers {
 using Json=JSONSerializationType;
 static std::string text(const String& s){return s.toCharArray();}
 static std::string handler(SceneObject* npc){
  if(!npc || !npc->isAiAgent())return "";
  auto conversation=CreatureTemplateManager::instance()->getConversationTemplate(npc->asAiAgent()->getConvoTemplateCRC());
  return conversation?text(conversation->getLuaClassHandler()):"";
 }
 static int mask(SceneObject* npc){
  static const std::map<std::string,int> masks={
   {"JunkDealerGenericConvoHandler",1},{"JunkDealerArmsConvoHandler",4},{"JunkDealerFineryConvoHandler",2},
   {"JunkDealerDenderConvoHandler",128},{"JunkDealerLilaConvoHandler",4},{"JunkDealerMalikConvoHandler",256},
   {"JunkDealerNadoConvoHandler",1},{"JunkDealerNathanConvoHandler",64},{"JunkDealerOlloboConvoHandler",4},
   {"JunkDealerQuichConvoHandler",32},{"JunkDealerReggiConvoHandler",4},{"JunkDealerSheaniConvoHandler",2},
   {"JunkDealerSnegConvoHandler",4},{"JunkDealerJawaConvoHandler",1},{"JunkDealerJawaArmsConvoHandler",4},
   {"JunkDealerJawaFineryConvoHandler",2},{"JunkDealerJawaTuskenConvoHandler",16}};
  auto found=masks.find(handler(npc));return found==masks.end()?0:found->second;
 }
 static bool eligible(CreatureObject* c,SceneObject* npc,SceneObject* item){
  if(!item || !item->isTangibleObject() || item->getParent().get()!=c->getInventory())return false;
  auto t=item->asTangibleObject();
  return (t->getJunkDealerNeeded()&mask(npc)) && t->getCraftersName().isEmpty() && !t->isBroken() && !t->isSliced() && !t->isNoTrade() && item->getContainerObjectsSize()==0 && t->getJunkValue()>0;
 }
 static bool language(CreatureObject* c,SceneObject* npc){return handler(npc).find("JunkDealerJawa")!=0 || c->hasSkill("combat_smuggler_underworld_01");}
 static void validate(CreatureObject* c,SceneObject* npc){
  if(!supports(npc) || c->isDead() || c->isIncapacitated() || npc->asAiAgent()->isDead() || c->getZone()!=npc->getZone() || c->getParentID()!=npc->getParentID() || !c->isInRange(npc,5) || !CollisionManager::checkLineOfSight(c,npc))throw std::runtime_error("junk_dealer_out_of_reach");
  if(!language(c,npc))throw std::runtime_error("Your underworld language skill is insufficient to trade with this Jawa.");
 }
public:
 static bool supports(SceneObject* npc){return mask(npc)!=0;}
 static void describe(CreatureObject* c,SceneObject* npc,Json& out){
  out["options"]=Json::array();out["dialogue"]=language(c,npc)?"Sell unwanted loot for the original dealer prices. Crafted, sliced, broken, no-trade, equipped and nonempty container items are excluded. Move items out of your backpack to offer them.":"You do not understand this Jawa. Underworld language skill is required.";
  if(!language(c,npc))return;
  auto inventory=c->getInventory();if(!inventory)return;
  Json quote=Json::array();int64 total=0;
  for(int i=0;i<inventory->getContainerObjectsSize();++i){
   auto item=inventory->getContainerObject(i);if(!eligible(c,npc,item))continue;
   int price=item->asTangibleObject()->getJunkValue();
   Json entry={{"item_id",std::to_string(item->getObjectID())},{"price",price}};quote.push_back(entry);total+=price;
   out["options"].push_back({{"operation","junk_sell"},{"item_name",text(item->getDisplayedName())},{"price",price},{"items",Json::array({entry})}});
  }
  if(!quote.empty() && total<=2000000000)out["options"].push_back({{"operation","junk_sell"},{"all",true},{"count",quote.size()},{"price",total},{"items",quote}});
  if(quote.empty())out["dialogue"]="You have no items that this junk dealer wishes to buy. Move eligible loot out of your backpack to offer it.";
 }
 static Json sell(CreatureObject* c,SceneObject* npc,const Json& r){
  validate(c,npc);const auto& quote=r.at("items");if(!quote.is_array() || quote.empty() || quote.size()>100)throw std::runtime_error("junk_sale_selection_required");
  std::set<uint64> ids;Vector<ManagedReference<SceneObject*>> items;int64 total=0;
  for(const auto& entry:quote){
   auto key=entry.at("item_id").get<std::string>();if(key.empty() || key.size()>20 || key.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid_junk_item");
   uint64 id=std::stoull(key);if(!ids.insert(id).second)throw std::runtime_error("duplicate_junk_item");
   auto item=c->getZoneServer()->getObject(id);if(!eligible(c,npc,item))throw std::runtime_error("junk_item_no_longer_eligible");
   int price=item->asTangibleObject()->getJunkValue();if(entry.at("price").get<int>()!=price)throw std::runtime_error("junk_price_changed");
   total+=price;items.add(item);
  }
  if(total<=0 || int64(c->getCashCredits())+total>2147483647)throw std::runtime_error("junk_cash_balance_limit");
  // Character lock serializes native inventory mutations. Remove synchronously,
  // unlike the legacy SUI's delayed deletion, so another request cannot resell.
  for(int i=0;i<items.size();++i){auto item=items.get(i);Locker lock(item,c);item->destroyObjectFromWorld(true);item->destroyObjectFromDatabase(true);}
  c->addCashCredits(int(total),true);
  return {{"sold_count",items.size()},{"credits",total},{"message","Junk sold for "+std::to_string(total)+" credits."}};
 }
};
