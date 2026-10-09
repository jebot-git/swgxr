// JSON audit values come from the compiled production policies, not copied tuning.
#include "server/combat/SquadLeaderPolicy.h"
#include "server/combat/VolleyFirePolicy.h"
#include "server/combat/DoctorPolicy.h"
#include "server/combat/CoreCuPolicy.h"
#include "corecu_resource_reference.inc"
#include <nlohmann/json.hpp>
#include <iostream>
using Json=nlohmann::json;
int main(){
 using namespace corecu::squadleader;
 Json out;out["support_cast_range_m"]=Range;out["abilities"]=Json::array();double action=0,mind=0;
 for(auto id:{"steady_aim","rally","form_up","boost_morale","retreat"}){const auto a=ability(id);double frequency=1./a->cooldown;action+=a->action*frequency;mind+=a->mind*frequency;out["abilities"].push_back({{"id",a->id},{"duration_seconds",a->seconds},{"cooldown_seconds",a->cooldown},{"action",a->action},{"mind",a->mind},{"ideal_duty_cycle",a->seconds*frequency},{"action_per_second",a->action*frequency},{"mind_per_second",a->mind*frequency}});}
 const auto master=bonuses(4,4,30,30,true);double steadyDuty=double(ability("steady_aim")->seconds)/ability("steady_aim")->cooldown,rallyDuty=double(ability("rally")->seconds)/ability("rally")->cooldown,moraleDuty=double(ability("boost_morale")->seconds)/ability("boost_morale")->cooldown;
 const double baseOutput=output(master.output,false),peakOutput=output(master.output,true),baseRegen=regeneration(master.regen,false,3),peakRegen=regeneration(master.regen,true,3),meanRegen=baseRegen+(peakRegen-baseRegen)*moraleDuty;
 double doctor=corecu::doctor::regen(corecu::doctor::amount(2,CoreCuResources::base(3),corecu::doctor::percent(2,3,1)));
 out["master"]={{"passive_damage_bonus",master.output},{"passive_action_mind_regeneration_bonus",master.regen},{"melee_npc_defense",master.melee},{"ranged_npc_defense",master.ranged},{"peak_direct_damage_multiplier",peakOutput},{"ideal_mean_direct_damage_multiplier",baseOutput+(peakOutput-baseOutput)*steadyDuty},{"peak_direct_mitigation",1-received(true)},{"ideal_mean_direct_mitigation",(1-received(true))*rallyDuty},{"peak_direct_effective_health_multiplier",1/received(true)},{"ideal_mean_direct_effective_health_multiplier",1/(1-(1-received(true))*rallyDuty)},{"peak_action_mind_regeneration_multiplier",peakRegen},{"ideal_mean_action_mind_regeneration_multiplier",meanRegen},{"health_regeneration_multiplier",regeneration(master.regen,true,0)},{"doctor_metabolic_regeneration_multiplier",doctor},{"doctor_and_sl_peak_action_mind_regeneration_multiplier",doctor*peakRegen},{"doctor_and_sl_ideal_mean_action_mind_regeneration_multiplier",doctor*meanRegen},{"peak_voluntary_movement_multiplier",movement(true)},{"form_up_rating_at_zero",status(0,true)},{"form_up_baseline_rating_cap",status(1000,true)},{"form_up_and_doctor_preparation_cap",corecu::preparedRating(status(1000,true),1000)}};
 const double volleyAction=corecu::volley::Action/corecu::volley::Cooldown,volleyMind=corecu::volley::Mind/corecu::volley::Cooldown;
 out["volley_fire"]={{"duration_seconds",corecu::volley::Duration},{"cooldown_seconds",corecu::volley::Cooldown},{"cast_range_m",corecu::volley::CastRange},{"action",corecu::volley::Action},{"mind",corecu::volley::Mind},{"action_per_second",volleyAction},{"mind_per_second",volleyMind}};
 double actionRegen=CoreCuResources::base(3)*CoreCuResources::regen(3,true),mindRegen=CoreCuResources::base(6)*CoreCuResources::regen(6,true);
 out["resource_burden"]={{"five_shouts_action_per_second",action},{"five_shouts_mind_per_second",mind},{"five_shouts_and_volley_action_per_second",action+volleyAction},{"five_shouts_and_volley_mind_per_second",mind+volleyMind},{"baseline_in_combat_action_regeneration_per_second",actionRegen},{"baseline_in_combat_mind_regeneration_per_second",mindRegen},{"action_share_of_unbuffed_regeneration",(action+volleyAction)/actionRegen},{"mind_share_of_unbuffed_regeneration",(mind+volleyMind)/mindRegen},{"unbuffed_action_left_per_second",actionRegen-action-volleyAction},{"unbuffed_mind_left_per_second",mindRegen-mind-volleyMind}};
 out["progression"]=Json::array();for(int offense=0;offense<=4;++offense)for(int mobility=0;mobility<=4;++mobility){auto b=bonuses(offense,mobility,0,0,false);out["progression"].push_back({{"offense_boxes",offense},{"movement_boxes",mobility},{"damage_bonus",b.output},{"action_mind_regeneration_bonus",b.regen}});}
 out["defense_progression"]=Json::array();for(int original:{0,10,25,30}){auto b=bonuses(0,0,original,original,false);out["defense_progression"].push_back({{"original_group_defense",original},{"effective_npc_defense",b.melee}});}
 out["strongest_nonstacking"]=Json::array();for(int count:{1,2,8,20}){Bonuses merged;for(int i=0;i<count;++i)merged.merge(master);out["strongest_nonstacking"].push_back({{"squad_leaders",count},{"damage_bonus",merged.output},{"regeneration_bonus",merged.regen},{"melee_npc_defense",merged.melee},{"ranged_npc_defense",merged.ranged}});}
 std::cout<<out.dump(2)<<'\n';
}
