#ifndef SWGXR_CRAFTING_VIEW_H
#define SWGXR_CRAFTING_VIEW_H
#include "SwgxrCraftingState.h"
#include "server/zone/objects/draftschematic/DraftSchematic.h"
#include "server/zone/objects/tangible/tool/CraftingTool.h"
#include "server/zone/objects/resource/ResourceContainer.h"
#include "server/zone/objects/factorycrate/FactoryCrate.h"
#include "templates/manager/TemplateManager.h"
class SwgxrCraftingView : public SwgxrCraftingState {
public:
 static std::string text(const String& s){return s.toCharArray();}
 static Json draft(DraftSchematic* d,int index){
  Json out={{"index",index},{"id",id(d)},{"name",text(d->getCustomName())},{"name_table",text(d->getObjectNameStringIdFile())},{"name_key",text(d->getObjectNameStringIdName())},{"template",text(TemplateManager::instance()->getTemplateFile(d->getTanoCRC()))},{"complexity",d->getComplexity()},{"slots",Json::array()},{"weights",Json::array()}};
  for(int i=0;i<d->getDraftSlotCount();++i){auto slot=d->getDraftSlot(i);out["slots"].push_back({{"index",i},{"name_table",text(slot->getStringIdFile())},{"name_key",text(slot->getStringIdName())},{"type",text(slot->getResourceType())},{"quantity",slot->getQuantity()},{"kind",slot->getSlotType()},{"optional",slot->getSlotType()>=3}});}
  for(int i=0;i<d->getResourceWeightCount();++i){auto w=d->getResourceWeight(i);if(w->isFiller())continue;Json weights=Json::array();for(int j=0;j<w->getPropertyListSize();++j)weights.push_back({{"property",w->getTypeAndWeight(j)>>4},{"weight",w->getPropertyPercentage(j)}});out["weights"].push_back({{"name",text(w->getPropertyName())},{"group",text(w->getExperimentalTitle())},{"weights",weights}});}
  return out;
 }
 static int quantity(TangibleObject* o){if(o->isResourceContainer())return cast<ResourceContainer*>(o)->getQuantity();if(o->isFactoryCrate()){auto f=cast<FactoryCrate*>(o);return f->getUseCount()*std::max(1,f->getPrototypeUseCount());}return std::max(1,o->getUseCount());}
 static bool fits(TangibleObject* o,DraftSlot* slot){
  if(slot->getSlotType()==0){auto r=dynamic_cast<ResourceContainer*>(o);return r && r->getSpawnObject()!=nullptr && r->getSpawnObject()->isType(slot->getResourceType());}
  auto t=o;if(o->isFactoryCrate())t=cast<FactoryCrate*>(o)->getPrototype();
  return t && !t->isResourceContainer() && t->getConditionDamage()==0 && t->getObjectTemplate()->isDerivedFrom(slot->getResourceType()) && (!t->isCraftingTool() || cast<CraftingTool*>(t)->isReady());
 }
};
#endif
