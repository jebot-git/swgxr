#pragma once
#include <algorithm>
#include <cmath>
#include <string>
// SWGXR Doctor preparation balance. Original item power remains the quality input.
namespace corecu { namespace doctor {
inline double clamp(double x,double lo,double hi){return std::isfinite(x)?std::max(lo,std::min(hi,x)):lo;}
inline int canonical(int a){return a==1 || a==4 || a==5?2:a;}
inline bool general(int a){a=canonical(a);return a==0 || a==2 || a==3;}
inline bool protection(int a){return a==9 || a==10;}
inline const char* family(int a){a=canonical(a);return a==0?"vitality":a==3?"endurance":a==2?"metabolic":a==9?"poison_prophylaxis":a==10?"disease_prophylaxis":"unknown";}
inline const char* label(int a){a=canonical(a);return a==0?"Vitality Preparation":a==3?"Endurance Preparation":a==2?"Metabolic Preparation":a==9?"Poison Prophylaxis":a==10?"Disease Prophylaxis":"Unknown Preparation";}
inline int tier(const std::string& path){auto n=path.size();return n>6 && path[n-6]=='_' && path[n-5]>='a' && path[n-5]<='d'?path[n-5]-'a':0;}
inline double quality(int a,int t,double power){t=std::max(0,std::min(protection(a)?2:3,t));double low=protection(a)?(t?17:12):10.*(t+1);double high=protection(a)?(t?160:60):(t==0?100:t==1?200:t==2?400:800);return clamp((power-low)/(high-low),0,1);}
inline double percent(int a,int t,double q,double skill=100,double rating=100,double fatigue=1){
 t=std::max(0,std::min(protection(a)?2:3,t));q=clamp(q,0,1);
 const double low=protection(a)?10.+5.*t:5.+2.*t;
 const double high=protection(a)?15.+5.*t:t==3?15.:8.+2.*t;
 // Supplies retain the dominant share of potency; clinical skill/rating cannot erase tier/quality progression.
 double blend=protection(a)?q:.7*q+.2*clamp(skill/100.,0,1)+.1*clamp(rating/100.,0,1);
 return (low+(high-low)*blend)*clamp(fatigue,0,1);
}
inline int amount(int a,int base,double pct){a=canonical(a);return a==2?int(std::round(clamp(pct,0,15)*100)):protection(a)?int(std::round(clamp(pct,0,25))):int(std::floor(std::max(1,base)*clamp(pct,0,15)/100.));}
inline double appliedPercent(int a,int base,int value){return canonical(a)==2?value/100.:protection(a)?value:100.*value/std::max(1,base);}
inline int absorption(int a,int t,double legacy){return protection(a) && t==2?int(std::round(clamp(legacy/25.,0,1)*10)):0;}
inline double regen(int basisPoints){return 1.+clamp(basisPoints,0,1500)/10000.;}
inline bool retiredRecipe(const std::string& path){if(path.find("draft_schematic/chemistry/")==std::string::npos)return false;for(auto name:{"strength","quickness","stamina"})if(path.find(std::string("medpack_enhance_")+name+"_")!=std::string::npos)return true;return false;}
inline std::string schematicGroup(const std::string& path,const std::string& original){
 if(path.find("medpack_enhance_constitution_")!=std::string::npos){int t=tier(path);return t==0?"craftMedpackBEnhanceGroupA":t==1?"craftMedpackBGroupC":t==2?"craftMedpackBGroupD":"craftMedpackBGroupE";}
 if(path.find("medpack_enhance_poison_")!=std::string::npos || path.find("medpack_enhance_disease_")!=std::string::npos){int t=tier(path);return t==0?"craftMedpackBEnhanceGroupB":t==1?"craftMedpackBEnhanceGroupC":"craftMedpackBEnhanceGroupD";}
 return original;
}
} }
