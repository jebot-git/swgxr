#!/usr/bin/env python3
"""Read-only production-policy arithmetic; authored loadouts, not live encounters."""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

import audit_commando_balance as reference

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'runtime/evidence/bounty-combat/balance.json'
DT = .01
SOURCE = r'''
#include "server/combat/BountyHunterPolicy.h"
#include "server/combat/PistoleerPolicy.h"
#include "server/combat/CarbineerPolicy.h"
#include "server/combat/MarksmanPolicy.h"
#include "server/combat/ArmourModel.h"
#include <nlohmann/json.hpp>
#include <iostream>
using Json=nlohmann::json;
int main(){Json out;
 for(auto id:{"eye_shot","bleeding_shot","confusion_shot","underhand_shot","duelist_stance","fast_blast"}){auto a=corecu::bountyhunter::ability(id);out["bounty"][id]={{"damage",a.damage},{"action",a.action},{"mind",a.mind},{"cooldown",a.cooldown},{"duration",a.duration}};}
 for(auto id:{"double_tap","disarming_shot","fan_shot","run_and_gun","showdown"}){auto a=corecu::pistoleer::ability(id);out["pistol"][id]={{"damage",a.damage},{"action",a.action},{"mind",a.mind},{"cooldown",a.cooldown},{"blows",a.blows}};}
 for(auto id:{"controlled_burst","bleeding_shot"}){auto a=corecu::marksman::ability(id);out["marksman"][id]={{"damage",a.damage},{"action",a.action},{"mind",a.mind},{"cooldown",a.cooldown},{"blows",a.blows}};}
 for(auto id:{"charge_blast","tactical_brace"}){auto a=corecu::carbineer::ability(id);out["carbine"][id]={{"damage",a.damage},{"action",a.action},{"mind",a.mind},{"cooldown",a.cooldown}};}
 for(double q:{0.,.5,1.}){double low=276+134*q,high=592+138*q;out["lightning"].push_back({{"quality",q},{"damage",corecu::bountyhunter::lightningDamage(low,high,50)},{"quality_fraction",corecu::bountyhunter::lightningQuality(low,high)}});}
 out["lightning_stock_damage"]=corecu::bountyhunter::lightningDamage(420,750,50);
 out["bh_speed"]=corecu::bountyhunter::advancedSpeed(50);
 out["pistol_bleed_fraction"]=corecu::bountyhunter::bleedFraction(true,true,true);
 out["bh_bleed_fraction"]=corecu::bountyhunter::bleedFraction(false,true,true);
 for(auto family:{std::pair<const char*,int>{"lightning",swgxr::armour::Electricity},{"scatter",swgxr::armour::Acid},{"ordinary",swgxr::armour::Energy}}){
  for(auto defender:{std::pair<const char*,std::pair<double,double>>{"unarmoured",{0,0}},{"body50",{.5,0}},{"body50_element50",{.5,.5}}}){swgxr::armour::Damage p(1,swgxr::armour::weapon(family.second,std::string(family.first)=="ordinary"?0:1));p.mitigate(defender.second.first,defender.second.second);out["mitigation"][family.first][defender.first]=p.total();}}
 for(double rating:{0.,65.,100.,125.})out["bh_status"].push_back({{"rating",rating},{"chance_percent",corecu::bountyhunter::chance(rating,50)}});
 std::cout<<out.dump();}
'''


def compiled():
    with tempfile.TemporaryDirectory(prefix='swgxr-bounty-balance-') as temp:
        folder = Path(temp)
        (folder / 'audit.cpp').write_text(SOURCE)
        subprocess.run(['c++', '-std=c++17', '-O2', '-I'+str(ROOT), str(folder/'audit.cpp'), '-o', str(folder/'audit')], check=True)
        return json.loads(subprocess.check_output([str(folder/'audit')]))


def weapon(name, q, stock=False):
    folder = name.split('_')[0]
    path = ROOT / f'vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/{folder}/{name}.lua'
    source = path.read_text()
    def number(key):
        return float(re.search(r'\b'+key+r'\s*=\s*([\d.]+)', source)[1])
    if stock:
        values = [number(k) for k in ['minDamage', 'maxDamage', 'attackSpeed', 'healthAttackCost', 'actionAttackCost', 'mindAttackCost']]
    else:
        def array(key):
            return [x.strip().strip('"') for x in re.search(r'\b'+key+r'\s*=\s*\{([^}]+)', source)[1].split(',') if x.strip()]
        names = array('experimentalSubGroupTitles')
        low, high = array('experimentalMin'), array('experimentalMax')
        values = []
        for key in ['mindamage', 'maxdamage', 'attackspeed', 'attackhealthcost', 'attackactioncost', 'attackmindcost']:
            index = names.index(key)
            values.append(float(low[index])+(float(high[index])-float(low[index]))*q)
    profile = reference.BALANCE['weapons'][name]
    return dict(mean=(values[0]+values[1])/2, period=values[2], lethal_action=values[3]+values[4], lethal_mind=values[5]/2, **dict(reference.BALANCE['classes'][profile['class']], **profile))


def simulate(policy, name, q, defender, duration, build, fraction=1., stock=False, normalization_scale=1.):
    """Damage-focused single-target loadout; utility stance pays its real resources."""
    w = weapon(name, q, stock)
    lightning, scatter = name=='rifle_lightning', name=='pistol_scatter'
    pistol = name.startswith('pistol_')
    specialist = build.startswith(('pistoleer', 'carbineer'))
    bounty = build.endswith('bounty')
    speed = policy['bh_speed'] if lightning else 30 + (49 if build.startswith('pistoleer') else 35 if build.startswith('carbineer') else policy['bh_speed'])
    period = max(1., w['period']*(1-speed/100.))
    mean = (policy['lightning_stock_damage'] if stock else next(r['damage'] for r in policy['lightning'] if r['quality']==q)) * normalization_scale if lightning else w['mean']
    packet = mean*1.5*policy['mitigation']['lightning' if lightning else 'scatter' if scatter else 'ordinary'][defender]*fraction
    abilities = {'lethal_shot': dict(damage=3.75, action=w['lethal_action'], mind=w['lethal_mind'], cooldown=30, blows=1)}
    if pistol:
        abilities['bleeding_shot'] = dict(policy['marksman']['bleeding_shot'])
        if specialist:
            abilities['bleeding_shot']['damage'] = 1.
            abilities['double_tap'] = dict(policy['pistol']['double_tap'])
            abilities['run_and_gun'] = dict(policy['pistol']['run_and_gun'])
        elif bounty:
            abilities['bleeding_shot'].update(policy['bounty']['bleeding_shot'])
    if name.startswith('carbine_'):
        abilities['controlled_burst'] = dict(policy['marksman']['controlled_burst'])
    if bounty:
        abilities['fast_blast'] = dict(policy['bounty']['fast_blast'])
        abilities['duelist_stance'] = dict(policy['bounty']['duelist_stance'])
    elif pistol and specialist:
        abilities['showdown'] = dict(policy['pistol']['showdown'], blows=3)
    # One equipped ultimate. Carbineer's area ultimate is deliberately omitted in
    # this damage-only single-target rotation: it deals less than ordinary fire.
    order = ['run_and_gun','duelist_stance','lethal_shot','fast_blast','showdown','double_tap','controlled_burst','bleeding_shot']
    ready = dict.fromkeys(abilities, 0.)
    ham = [1000., 1000.]
    nextfire, active_until, total, ammo, reloads = 0., -1., 0., w['capacity'], 0
    counts = {}
    nextbleed, bleeduntil, remaining, pulse = math.inf, -1., 0., 0.
    bleed_total = 0.
    for tick in range(round(duration/DT)):
        t = tick*DT
        ham[0], ham[1] = min(1000,ham[0]+10*DT), min(1000,ham[1]+8*DT)
        if t+1e-8>=nextbleed and t<bleeduntil and remaining>0:
            damage=min(remaining,pulse);total+=damage;bleed_total+=damage;remaining-=damage;nextbleed+=3
        if t+1e-8<nextfire:
            continue
        selected, costs = 'ordinary', [0.,0.]
        for candidate in order:
            if candidate not in abilities or t+1e-8<ready[candidate]:
                continue
            a = abilities[candidate]
            scale = .75 if t<active_until and candidate not in ['run_and_gun','duelist_stance','fast_blast','showdown'] else 1.
            candidate_costs = [math.ceil(a['action']*scale), math.ceil(a['mind']*scale)]
            if all(h>c for h,c in zip(ham,candidate_costs)):
                selected, costs = candidate, candidate_costs
                break
        a = abilities.get(selected, dict(damage=1,blows=1))
        gesture = selected in ['run_and_gun','duelist_stance']
        blows = 0 if gesture else a.get('blows',1)
        ammo_cost = 2 if selected=='double_tap' else 3 if selected=='showdown' else 0 if gesture else 1
        if ammo<ammo_cost:
            nextfire=t+w['reload_seconds'];ammo=w['capacity'];reloads+=1
            continue
        for index in [0,1]:ham[index]-=costs[index]
        recovery = period
        if selected!='ordinary':ready[selected]=t+a['cooldown']
        if gesture:
            recovery=.25
            if selected=='run_and_gun':active_until=t+8
        elif selected=='lethal_shot':
            recovery=period
        elif selected=='showdown':
            recovery=period+.5
        elif selected=='ordinary' and t<active_until:
            recovery=period/1.25
        damage=0 if gesture else packet*a['damage']*blows
        total+=damage
        if selected=='bleeding_shot':
            budget=math.floor(damage*policy['pistol_bleed_fraction' if specialist else 'bh_bleed_fraction'])
            if t>=bleeduntil:nextbleed=t+1.5
            remaining=max(remaining,budget);pulse=max(pulse,math.ceil(budget/4));bleeduntil=t+12
        counts[selected]=counts.get(selected,0)+1
        nextfire=t+recovery
        ammo-=ammo_cost
        if ammo==0:
            nextfire=max(nextfire,t+w['reload_seconds']);ammo=w['capacity'];reloads+=1
    return {'damage':round(total,3),'dps':round(total/duration,6),'remaining_action':round(ham[0],3),'remaining_mind':round(ham[1],3),'attacks':counts,'reloads':reloads,'native_period_seconds':round(period,4),'raw_mean_packet':round(mean,4),'bleed_upper_envelope_damage':round(bleed_total,3)}


def main():
    policy, rifle_policy = compiled(), reference.compiled()
    solo, hybrids = [], []
    for duration in [120,300]:
        for q in [0.,.5,1.]:
            for defender in ['unarmoured','body50','body50_element50']:
                rifle=reference.rifle(rifle_policy,1.,q,defender,duration)
                for name, fraction in [('rifle_lightning',1.),('pistol_scatter',1.),('pistol_scatter',.5),('pistol_scatter',.125)]:
                    result=simulate(policy,name,q,defender,duration,'bounty',fraction)
                    solo.append(dict(weapon=name,quality=q,pellet_fraction=fraction,defender=defender,duration_seconds=duration,bounty=result,rifleman=rifle,ratio=round(result['dps']/rifle['dps'],6)))
                for name,build in [('pistol_dl44','pistoleer'),('carbine_dh17','carbineer')]:
                    base=simulate(policy,name,q,defender,duration,build)
                    hybrid=simulate(policy,name,q,defender,duration,build+'_bounty')
                    hybrids.append(dict(weapon=name,quality=q,defender=defender,duration_seconds=duration,specialist=base,hybrid=hybrid,ratio=round(hybrid['dps']/base['dps'],6)))
    stock=[]
    for duration in [120,300]:
        stock_rifle=reference.rifle(rifle_policy,1.,1.,'unarmoured',duration)
        # Master rifle speed95 floors both stock and maximum-quality T21 at1s;
        # fixed Rifleman ability costs are independent of weapon quality.
        stock_rifle_mean=weapon('rifle_t21',1.,True)['mean']
        stock_rifle['damage']=round(stock_rifle['damage']*stock_rifle_mean/245,3)
        stock_rifle['dps']=round(stock_rifle['dps']*stock_rifle_mean/245,6)
        for name in ['rifle_lightning','pistol_scatter']:
            for fraction in ([1,.5,.125] if name=='pistol_scatter' else [1]):
                result=simulate(policy,name,.5,'unarmoured',duration,'bounty',fraction,True)
                stock.append(dict(weapon=name,pellet_fraction=fraction,duration_seconds=duration,bounty=result,rifleman=stock_rifle,ratio=round(result['dps']/stock_rifle['dps'],6)))
    lightning=[r['ratio'] for r in solo if r['weapon']=='rifle_lightning' and r['defender']=='unarmoured']
    summary={'lightning_unarmoured_ratio_range':[min(lightning),max(lightning)],'hybrid_ratio_range':[min(r['ratio'] for r in hybrids),max(r['ratio'] for r in hybrids)],'intended_lightning_ratio':[.65,.75],'intended_max_hybrid_ratio':1.15,
        'lightning_armor_ratios':{defender:[min(r['ratio'] for r in solo if r['weapon']=='rifle_lightning' and r['defender']==defender),max(r['ratio'] for r in solo if r['weapon']=='rifle_lightning' and r['defender']==defender)] for defender in ['unarmoured','body50','body50_element50']},
        'lightning_stock_unarmoured_ratio_range':[min(r['ratio'] for r in stock if r['weapon']=='rifle_lightning'),max(r['ratio'] for r in stock if r['weapon']=='rifle_lightning')],
        'generic_lethal_recovery_discrepancy':'Source overChargeShot2 speedMultiplier=2 is not applied in the current non-Rifleman launch recovery. Model preserves actual1x behavior; changing this affects all Marksman-derived professions.'}
    catalog=json.loads((ROOT/'runtime/assets/professions/catalog.json').read_text())
    nodes={n['id']:n for profession in catalog['professions'] for n in profession['nodes']}
    def skill_points(roots):
        trained=set()
        def visit(skill):
            if skill in trained:return
            trained.add(skill)
            for requirement in nodes[skill]['requires']:
                if requirement in nodes:visit(requirement)
        for skill in roots:visit(skill)
        return sum(nodes[skill]['points'] for skill in trained)
    skill_budgets={build:skill_points(roots) for build,roots in {
        'bounty':['combat_bountyhunter_master'],
        'pistoleer':['combat_pistol_master','combat_marksman_master'],
        'carbineer':['combat_carbine_master','combat_marksman_master'],
        'rifleman':['combat_rifleman_master','combat_marksman_master'],
        'pistoleer_bounty':['combat_pistol_master','combat_bountyhunter_master'],
        'carbineer_bounty':['combat_carbine_master','combat_bountyhunter_master'],
    }.items()}
    assert all(points<=250 for points in skill_budgets.values()), skill_budgets
    sources=['server/combat/BountyHunterPolicy.h','server/combat/SwgxrBountyHunterModifiers.h','server/combat/PistoleerPolicy.h','server/combat/CarbineerPolicy.h','server/combat/MarksmanPolicy.h','server/combat/RiflemanPolicy.h','server/combat/ArmourModel.h','client/combat/balance.json','runtime/assets/professions/catalog.json','tools/server/audit_commando_balance.py','tools/server/audit_bounty_combat_balance.py']
    sources += ['vendor/Core3/MMOCoreORB/bin/scripts/commands/'+name+'.lua' for name in ['attack','overChargeShot2']]
    sources += ['vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/damageovertime/DamageOverTime.cpp']
    sources += [f'vendor/Core3/MMOCoreORB/bin/scripts/object/weapon/ranged/{name.split("_")[0]}/{name}.lua' for name in ['rifle_lightning','pistol_scatter','pistol_dl44','carbine_dh17','rifle_t21']]
    report=dict(scope='Compiled production arithmetic; deterministic authored damage-focused loadouts, not live encounters.',summary=summary,skill_point_budgets=skill_budgets,policy=policy,solo=solo,hybrids=hybrids,stock_defaults=stock,source_sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources},assumptions=[
        'Master Marksman prerequisite plus Master BH or the named specialist. BH lightning uses its dedicated speed25; ordinary BH pistol/carbine uses Marksman30 plus BH25. Hybrids use the strongest advanced contribution, never sum BH with the specialist.',
        'Both builds start with1000 Action/Mind, recover10/8 per second, and receive no incoming damage. Costs use stock/crafted native values with no secondary-stat discount; original Health cost goes to Action and Mind cost halves. Ordinary attack has zero multipliers and costs nothing.',
        'Current generic Lethal Shot is3.75x,30-second cooldown and ordinary recovery: the live physical launch path does not apply its source speedMultiplier2. Rifleman reference reuses the existing Commando audit, including upgraded4.25x Head Shot with twice ordinary recovery, Focus, Piercing, Flurry, Surprise without opening bonus, and Sniper.',
        'All direct physical contacts land, except the explicit scatter fraction. One aggregate scatter shot is fractions1,4/8,1/8 of the original packet, never eight full packets. Homing changes contact assistance only.',
        'Both builds use neutral1.0 range/posture scaling and actual compiled elemental/AP armor conversion. This does not assert identical firing positions: original weapon range curves differ.',
        'Client magazine capacity and reload values come from balance.json. Reload overlaps native recovery using max, and only starts when a magazine is empty or cannot cover an ability. Controlled Burst resolves three hits for one launch/ammo unit, matching the native/client receipt model.',
        'Damage-focused loadouts omit damage-losing CC on a stationary target. BH pays Duelist resources/recovery on cooldown; Pistoleer pays Run and Gun. Added control and survival utility are not assigned an invented DPS value.',
        'One equipped ultimate: pure Pistoleer uses Showdown, BH hybrids use Fast Blast. A pure Carbineer single-target damage rotation omits its weaker-than-ordinary area ultimate; its crowd control and AoE value are outside this comparison.',
        'Bleed is an optimistic successful, unabsorbed upper envelope, based on landed damage; native first tick1.5s then3-second spacing. Refresh preserves only the stronger remaining budget. No stacking from BH plus Pistoleer. Resistance, immunities, cures and finite target health reduce actual output.',
        'Quality0/.5/1 interpolates original experimental minima/maxima, separately for damage, speed and costs. Stock defaults are compared separately against stockT21 mean267.5 at the same1-second MasterRifleman cadence because original defaults can exceed the crafted recipe envelope.',
        'These are authoring benchmarks, not official SOE formulas, optimal rotations, bounty completion rates, PvP, network, renderer or headset validation.'
    ])
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(summary=summary,records=len(solo)+len(hybrids)+len(stock),evidence=str(OUT))))


if __name__=='__main__':main()
