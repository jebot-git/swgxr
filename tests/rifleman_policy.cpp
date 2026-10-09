#include "server/combat/RiflemanPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include "server/combat/PistoleerPolicy.h"
#include <cassert>
#include <iostream>
int main(){int checks=0;auto check=[&](bool value){assert(value);++checks;};using namespace corecu::rifleman;
 for(auto id:{"lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot","rifleman_focus"}){auto a=ability(id);check(contains(id));check(a.action>0 && a.mind>0 && a.cooldown>0);}
 check(!contains("forward_check"));check(damage("lethal_shot",false)==4.);check(damage("lethal_shot",true)==4.25);check(damage("flurry_shot",false)==.8);check(damage("flurry_shot",true)==.9);check(ability("sniper_shot").damage==6.);
 check(surprise(800,1000)==1.5);check(surprise(799,1000)==1.);check(surprise(801,1001)==1.5);check(surprise(800,1001)==1.);check(surprise(0,0)==1.);check(surprise(1,-1)==1.);
 for(int channel:{1,2,4,8,16,32,64,128,256}){check(bodyResistance(.8,channel,false)==.8);check(bodyResistance(.8,channel,true)==(channel==1 || channel==2?.4:.8));}
 check(corecu::ultimateProfession("sniper_shot")=="combat_rifleman_master");check(!corecu::ultimateAllowed("sniper_shot",[](const std::string&){return false;}));check(corecu::ultimateAllowed("sniper_shot",[](const std::string& s){return s=="combat_rifleman_master";}));
 corecu::pistoleer::Volley v;v.ability="flurry_shot";v.item="rifle";v.target="enemy";v.revision=7;v.started=10;v.lastLaunch=10;v.reservation=12;
 check(!v.accepts("rifle","enemy",7,1,10.249,12));check(v.accepts("rifle","enemy",7,1,10.25,12));check(!v.accepts("rifle","other",7,1,10.25,12));check(!v.accepts("rifle","enemy",8,1,10.25,12));check(!v.accepts("rifle","enemy",7,2,10.25,12));check(!v.accepts("rifle","enemy",7,1,12.001,12));v.invalidated=true;check(!v.accepts("rifle","enemy",7,1,10.25,12));
 std::cout<<checks<<" Rifleman policy checks passed\n";
}
