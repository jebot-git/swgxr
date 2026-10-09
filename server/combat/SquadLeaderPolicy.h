#pragma once
#include <algorithm>
#include <cmath>
#include <string>
namespace corecu { namespace squadleader {
constexpr double Range=48.;
struct Ability {const char* id;const char* label;const char* grant;const char* skill;int seconds,cooldown,action,mind;};
inline const Ability* ability(const std::string& id){
 static const Ability all[]={{"steady_aim","Steady Aim","steadyaim","outdoors_squadleader_offense_01",12,45,60,30},{"rally","Rally","rally","outdoors_squadleader_support_01",12,60,70,40},{"form_up","Form Up","formup","outdoors_squadleader_defense_01",6,45,60,40},{"boost_morale","Boost Morale","boostmorale","outdoors_squadleader_defense_04",15,90,40,60},{"retreat","Retreat","retreat","outdoors_squadleader_support_03",8,60,80,30}};
 for(const auto& a:all)if(id==a.id)return &a;return nullptr;
}
inline double bounded(double x,double hi){return std::isfinite(x)?std::max(0.,std::min(hi,x)):0.;}
struct Bonuses {double output=0,regen=0;int melee=0,ranged=0;void merge(const Bonuses& b){output=std::max(output,b.output);regen=std::max(regen,b.regen);melee=std::max(melee,b.melee);ranged=std::max(ranged,b.ranged);}};
// Original branch grants become bounded useful group benefits. No direct combat
// expertise is granted to an ungrouped Squad Leader.
inline Bonuses bonuses(int offense,int mobility,int melee,int ranged,bool master){Bonuses b;b.output=std::min(.10,.02*bounded(offense,4)+(master?.02:0));b.regen=std::min(.10,.02*bounded(mobility,4)+(master?.02:0));b.melee=int(std::ceil(bounded(melee,30)*.5));b.ranged=int(std::ceil(bounded(ranged,30)*.5));return b;}
inline double output(double passive,bool steady){return 1.+bounded(passive,.10)+(steady?.15:0.);}
inline double received(bool rally){return rally?.85:1.;}
inline double regeneration(double passive,bool morale,int attribute){return attribute==3 || attribute==6?1.+bounded(passive,.10)+(morale?.50:0.):1.;}
inline double movement(bool retreat){return retreat?1.20:1.;}
inline double status(double base,bool formup){return bounded(base+(formup?20:0),100);}
} }
