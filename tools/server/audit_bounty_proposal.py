#!/usr/bin/env python3
"""Bounded arithmetic for a NOT IMPLEMENTED BH combat proposal. No services launched."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'runtime/evidence/bounty/proposal-balance.json'
sys.path.insert(0,str(ROOT))
sys.path.insert(0,str(ROOT/'tools/assets'))
from server.character_protocol import assets
from character_formats import datatable


def method(source,signature):
    start=source.index(signature);opening=source.index('{',start);depth=1;end=opening+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]


def totals(rows,prefix):
    out={}
    for row in rows:
        if not row['NAME'].startswith(prefix+'_'):continue
        for part in row['SKILL_MODS'].split(','):
            if '=' not in part:continue
            key,value=part.split('=');out[key]=out.get(key,0)+float(value)
    return out


def main():
    data=assets().read('datatables/skill/skills.iff');rows=datatable(data)
    prefixes=['combat_marksman','combat_pistol','combat_carbine','combat_bountyhunter']
    mods={p:totals(rows,p) for p in prefixes}
    templates={'scatter_pistol':'vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/pistol/pistol_scatter.lua','dh17_carbine':'vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/carbine/carbine_dh17.lua'}
    weapons=[]
    for name,path in templates.items():
        source=(ROOT/path).read_text();family='pistol' if name=='scatter_pistol' else 'carbine';specialist='combat_pistol' if family=='pistol' else 'combat_carbine';key=family+'_speed'
        base=mods['combat_marksman'][key];bh=mods['combat_bountyhunter'][key];advanced=mods[specialist][key]
        speed=float(re.search(r'^\s*attackSpeed\s*=\s*([0-9.]+)',source,re.M).group(1))
        builds=[('marksman',base),('current_bounty_hunter',base+bh),('current_specialist',base+advanced),('current_specialist_plus_bounty_hunter',base+advanced+bh),('proposed_bounty_hunter',base+min(bh,25)),('proposed_specialist_plus_bounty_hunter',base+max(advanced,min(bh,25)))]
        weapons.append({'weapon':name,'source_path':path,'source_attack_seconds':speed,'family':family,'specialist':specialist,'builds':[{'build':n,'speed_modifier':v} for n,v in builds]})
    native='vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp'
    cadence=method((ROOT/native).read_text(),'float CombatManager::calculateWeaponAttackSpeed(').replace('CombatManager::','')
    code='''#include <nlohmann/json.hpp>
#include "server/combat/CoreCuPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include <iostream>
using Json=nlohmann::json;
struct CreatureObject{int speed=0;int getSkillMod(const char*){return 0;}};
struct WeaponObject{float speed=0;float getAttackSpeed(){return speed;}bool isRangedWeapon(){return true;}};
struct SwgxrSpice{static float rangedRpmScale(CreatureObject*){return 1;}};
struct SwgxrArmour{static float scale(CreatureObject*,int){return 1;}};
struct Math{static float max(float a,float b){return std::max(a,b);}};
struct CombatManager{int getSpeedModifier(CreatureObject* c,WeaponObject*)const{return c->speed;}
'''+cadence+'''\n};
int main(){Json out=Json::object();CombatManager manager;CreatureObject c;WeaponObject w;
'''
    for weapon in weapons:
        for build in weapon['builds']:
            code+=f'w.speed={weapon["source_attack_seconds"]};c.speed={int(build["speed_modifier"])};out["cadence"]["{weapon["weapon"]}"]["{build["build"]}"]=manager.calculateWeaponAttackSpeed(&c,&w,1);\n'
    code+='''for(double rating:{0.,100.,125.})out["status"].push_back({{"rating",rating},{"bounty_hunter_entry_percent",corecu::learnedStatusChance(85,0,rating)},{"bounty_hunter_master_percent",corecu::learnedStatusChance(85,10,rating)},{"combat_medic_peak_percent",corecu::combatmedic::chance(125,rating)},{"eye_duration_seconds",corecu::statusDuration(6,rating)},{"confusion_duration_seconds",corecu::statusDuration(3,rating)},{"underhand_duration_seconds",corecu::statusDuration(2,rating)}});
out["fencer"]={{"entry_bleed_fraction",corecu::fencer::bleedScale(0,false)},{"master_bleed_fraction",corecu::fencer::bleedScale(1,false)},{"flawless_bleed_fraction",corecu::fencer::bleedScale(1,true)},{"duration_seconds",corecu::fencer::BleedDuration}};
std::cout<<out.dump();}'''
    with tempfile.TemporaryDirectory(prefix='swgxr-bh-proposal-') as directory:
        p=Path(directory);(p/'audit.cpp').write_text(code)
        subprocess.run(['c++','-std=c++17','-O2','-I'+str(ROOT),'-I'+str(ROOT/'server/combat'),str(p/'audit.cpp'),'-o',str(p/'audit')],check=True)
        values=json.loads(subprocess.check_output([str(p/'audit')],text=True))
    for weapon in weapons:
        reference=values['cadence'][weapon['weapon']]['current_specialist']
        for build in weapon['builds']:
            period=values['cadence'][weapon['weapon']][build['build']]
            build['cadence_seconds']=round(period,6);build['ordinary_shots_per_second']=round(1/period,6);build['ordinary_output_ratio_to_current_specialist_same_weapon']=round(reference/period,6)
    proposals={
      'eye_shot':{'damage_multiplier':.6,'blind_accuracy_penalty':25,'base_duration_seconds':6,'cooldown_seconds':18},
      'torso_shot':{'damage_multiplier':.8,'bleed_fraction_of_landed_direct_damage':.45,'maximum_gross_damage_in_units_of_one_ordinary_landed_hit':.8*(1+.45),'base_duration_seconds':12,'cooldown_seconds':16,'shared_bleed_channel':True},
      'confusion_shot':{'damage_multiplier':.6,'base_duration_seconds':3,'cooldown_seconds':20,'effect':'single native Stun, no Dizzy/Knockdown bundle'},
      'underhand_shot':{'damage_multiplier':.65,'base_duration_seconds':2,'cooldown_seconds':24,'effect':'single knockdown with existing immunity/recovery'},
      'fast_blast':{'damage_multiplier':3,'cooldown_seconds':120,'gross_damage_per_second_in_ordinary_hit_units':3/120,'extra_damage_per_second_if_replacing_one_ordinary_hit':(3-1)/120},
      'duelist_stance':{'single_opponent_direct_damage_reduction':.15,'duration_seconds':8,'cooldown_seconds':60,'ideal_uptime_fraction':8/60,'uniform_damage_mean_reduction':.15*8/60,'peak_effective_health_multiplier_against_bound_opponent':1/.85,'strongest_with_equivalent_reduction_not_multiplicative':True},
    }
    sources=[*templates.values(),native,'server/combat/CoreCuPolicy.h','server/combat/FencerPolicy.h','server/combat/SwgxrFencer.h','server/medic/CombatMedicPolicy.h','tools/server/audit_bounty_proposal.py']
    report={
      'scope':'NOT IMPLEMENTED Bounty Hunter combat proposal; bounded current-policy arithmetic only',
      'validation':{'proposal_implemented':False,'compiled_production_cadence_and_status_and_fencer_policies':True,'full_rotation_simulation':False,'encounter_measured':False,'services_or_client_launched':False},
      'source_skill_modifiers':{p:{k:v for k,v in m.items() if k.endswith('_speed') or k.endswith('_accuracy') or k=='ranged_defense'} for p,m in mods.items()},
      'cadence_cases':weapons,'production_status_curve':values['status'],'production_fencer_comparison':values['fencer'],'proposed_abilities':proposals,
      'assumptions':[
        'Scatter is the native pistol_scatter.lua default3.0-second weapon; DH17 is carbine_dh17.lua default3.5-second carbine, not the distinct DH17 pistol. Crafted speed varies.',
        'The production calculateWeaponAttackSpeed body is compiled with actual family skill totals from original skills.iff. skillSpeedRatio=1, armor output scaling=1, no Gunjack/combat haste/private speed bonuses.',
        'Proposed BH advanced speed is capped25. Existing Master Marksman contributes30 separately. A combined weapon specialist/BH selects the stronger advanced contribution, not their sum.',
        'The ratios compare ordinary cadence with identical weapon damage. Reloads, resources, special attacks, control, movement, enemy armor and actual hit probability are excluded. They do not establish whole-kit DPS or the proposed65–75% Rifleman target.',
        'Status probabilities use the compiled current resistance curve. Proposed BH base85 plus10 at mastery is compared with CombatMedic raw125. Both still cap at95% before no-resistance comparisons; CM advantage persists against resistance.',
        'Short effect durations use production integer ceiling. A2-second knockdown remains2seconds at rating100/125; resistance still lowers application probability. Shared control recovery and immunity are required separately.',
        'Torso maximum1.16 ordinary-hit units assumes its0.8 direct hit lands and its entire0.36-unit bleed budget successfully runs. Application failure, armor, absorption, shortening, cures, death and stronger shared bleeds reduce that ceiling.',
        'Duelist mean2% reduction assumes a constant stream of direct damage from one bound opponent and activation exactly on cooldown. It is not2% reduction of all incoming damage or a measured survival result.',
      ],
      'warnings':[
        'The proposed45%-of-landed-hit bleed is below Fencer50–80% ordinary progression; FlawlessAssault raises Fencer to100%. Do not describe50–80% as an unconditional Fencer ceiling.',
        'The65–75% whole-kit Rifleman output target and10–15% maximum specialist gain remain unvalidated design targets; this bounded audit supplies no whole-kit performance claim.',
        'Raw native BH carbine speed currently exceeds Carbineer: with MasterMarksman+BH80, the3.5s source carbine hits1s floor; MasterCarbineer65 yields1.225s. The proposed55 yields1.575s,77.7778% ordinary output of the same-weapon specialist.',
      ],
      'source_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources},
      'original_skill_table':{'asset_path':'datatables/skill/skills.iff','sha256':hashlib.sha256(data).hexdigest(),'source':'user-provided active TRE set via server.character_protocol.assets(); original bytes remain ignored'},
    }
    OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'report':str(OUT),'cadence':weapons,'status':values['status'],'duelist_mean_reduction':.15*8/60},indent=2))

if __name__=='__main__':main()
