#!/usr/bin/env python3
"""Verify applied native slicing stats on the disposable slicing suite's items."""
import argparse
import json
import math
import re
import secrets
import time
from services_smoke import ROOT, req, redact
from equipment_smoke import console


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--mutate-disposable-fixture',action='store_true',required=True)
    parser.parse_args()
    source=json.loads((ROOT/'runtime/evidence/slicing-native-smoke.json').read_text())
    owner=source['fixtures'][0]
    assert owner['account'].startswith('invtestslicing')
    base=dict(account=owner['account'],character_id=owner['id'])
    report=dict(passed=False,native_execution=True,fixture=owner,privileged_fixture=True,headset_tested=False,checks=[],responses=[])
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    added='';session='';cleanup_items=[]
    def check(ok,label):
        report['checks'].append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
    def call(path,**fields):
        result=req(path,dict(base,**fields));report['responses'].append(dict(path=path,response=redact(result)));return result
    def service(action='slicing_status',**fields):
        return call('/services/'+action,session_id=session,zone='tatooine',request_id='slice_stats_'+secrets.token_hex(12),**fields)
    def pose(row):return {k:row[k] for k in ('position','building_id','cell_index')}
    def lua(name):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset);match=re.search('runLuaFunction Tests:'+name.split(':')[0]+r': result=([^\n]+)',stream.read())
            if match:return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise RuntimeError('Native helper timeout '+name)
    def equip(item):
        result=call('/inventory/equip',item_id=item['id'],arrangement=0,live_session_id=session)
        check(result.get('mutation',{}).get('success'),'Original native equip accepts '+item['id'])
    def remove(item):check(lua('swgxrSliceStatsRemove:'+item['id'])=='true','Original inventory transfer removes fixture equipment')
    def attributes(snapshot,item):return snapshot['live_response']['service_attributes']['o'+item['id']]
    try:
        loc=call('/enter')['source_location'];started=call('/session/start',**pose(loc));session=started['session_id']
        call('/session/update',session_id=session,ready=True,**pose(loc))
        added=f'''\n-- BEGIN SWGXR SLICING DERIVED STATS FIXTURE\nfunction Tests:swgxrSliceStatsPrepare()
 local p=getSceneObject({owner['id']});awardSkill(p,"combat_marksman_master");CreatureObject(p):forcePeace();CreatureObject(p):addCooldown("swgxr_smuggler_lethal_shot",0)
 for i=0,8 do CreatureObject(p):setWounds(i,0);CreatureObject(p):setHAM(i,CreatureObject(p):getMaxHAM(i)) end
 return "ready"
end
function Tests:swgxrSliceStatsRemove(oid)
 local p=getSceneObject({owner['id']});local item=getSceneObject(tonumber(oid));if item==nil or SceneObject(item):getParentID()~={owner['id']} then return "unowned" end
 return tostring(SceneObject(SceneObject(p):getSlottedObject("inventory")):transferObject(item,-1,true))
end
function Tests:swgxrSliceStatsMod(name)
 return tostring(CreatureObject(getSceneObject({owner['id']})):getSkillMod(name))
end
-- END SWGXR SLICING DERIVED STATS FIXTURE\n'''
        script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.2);lua('swgxrSliceStatsPrepare')
        state=service();items=state['state']['inventory']['items']
        ranged=next(i for i in items if i['template'].endswith('/pistol_fwg5.iff') and i['slice_bonuses'])
        plain=next(i for i in items if i['template'].endswith('/pistol_fwg5.iff') and not i['slice_bonuses'])
        armor=next(i for i in items if i['template'].endswith('/armor_composite_chest_plate.iff'))
        psg=next(i for i in items if i['template'].endswith('/shield_generator_personal.iff'))
        cloth=next(i for i in items if i['template'].endswith('/shirt_s04.iff') and i['slice_skill_mods'])
        cleanup_items=[i for i in items if i['slice_bonuses'] or i['slice_skill_mods']]
        for item in cleanup_items:
            if item.get('equipped'):remove(item)
        for suffix in ['/pistol_fwg5.iff','/knife_survival.iff']:
            sliced=next(i for i in items if i['template'].endswith(suffix) and i['slice_bonuses'])
            raw=next(i for i in items if i['template'].endswith(suffix) and not i['slice_bonuses'])
            a,b=attributes(state,sliced),attributes(state,raw);mods=sliced['slice_bonuses']
            expected_max=float(b['swgxr.max_damage'])*(1+mods.get('max_damage_pct',0)/100)
            expected_min=min(float(b['swgxr.min_damage'])*(1+mods.get('min_damage_pct',0)/100),expected_max)
            check(math.isclose(float(a['swgxr.min_damage']),expected_min,abs_tol=.02) and math.isclose(float(a['swgxr.max_damage']),expected_max,abs_tol=.02),'Actual swgxr damage attributes derive once from native original '+suffix)
            check(all(float(a['swgxr.'+key])-float(b['swgxr.'+key])==mods['range_pct'] for key in ('near_accuracy','ideal_accuracy','max_accuracy')),'Native accuracy attributes apply exact range points')
            if suffix.startswith('/pistol'):
                check(int(a['Capacity (shots)'])==math.floor(float(b['Capacity (shots)'])*(1+mods.get('capacity_pct',0)/100)+.5) and math.isclose(float(a['Rate of fire (RPM)']),float(b['Rate of fire (RPM)'])*(1+mods.get('rof_pct',0)/100),abs_tol=.02),'Native ranged profile applies Capacity or RoF exactly')
            else:
                check(all(math.isclose(float(a[label]),float(b[label])*(1+mods.get(key,0)/100),abs_tol=.02) for label,key in [('Power','power_pct'),('Stance recovery','stance_recovery_pct')]),'Native melee profile applies Power or Stance Recovery exactly')
            equip(sliced);observed=service()['live_response']['snapshot']['weapon']
            check(math.isclose(observed['min_damage'],expected_min,abs_tol=.02) and math.isclose(observed['max_damage'],expected_max,abs_tol=.02),'Actual equipped WeaponObject getters match derived slice attributes')
            remove(sliced)
        for item,base_energy in [(armor,75),(psg,24)]:
            at=attributes(state,item);energy=[v for k,v in at.items() if k.endswith('armor_eff_energy')]
            expected=min(90,math.floor(base_energy*(1+item['slice_bonuses']['protection_pct']/100)+.5))
            check(bool(energy) and float(energy[0].rstrip('%'))==expected,'Native '+item['slice_kind']+' energy protection getter and examine apply rolled bonus')
        mods=cloth['slice_skill_mods'];before={m['id']:int(float(lua('swgxrSliceStatsMod:'+m['id']))) for m in mods}
        equip(cloth)
        worn={m['id']:int(float(lua('swgxrSliceStatsMod:'+m['id']))) for m in mods}
        check(all(worn[m['id']]-before[m['id']]==m['value'] for m in mods),'All six clothing modifiers reach actual CreatureObject skill modifiers')
        remove(cloth)
        check(all(int(float(lua('swgxrSliceStatsMod:'+m['id'])))==before[m['id']] for m in mods),'Unequipping clothing removes exactly its native modifiers')
        equip(cloth)
        check(all(int(float(lua('swgxrSliceStatsMod:'+m['id'])))==worn[m['id']] for m in mods),'Re-equipping clothing restores modifiers without stacking')
        remove(cloth)
        equip(ranged)
        for item in [armor,psg]:
            equip(item);lua('swgxrSliceStatsPrepare')
            # A real launch executes original Special Attack Cost, with no fabricated hit.
            before=call('/combat/session/update',session_id=session,ready=True,**pose(loc))
            before_ham=before['snapshot']['player']['raw_ham'];weapon=before['snapshot']['weapon']
            origin=before['snapshot']['player']['position'].copy();origin[1]+=1
            time.sleep(max(0.05,weapon['fire_interval_seconds']+.05))
            lua('swgxrSliceStatsPrepare')
            before=service();before_ham=before['state']['inventory']['equipment_stats']['ham']
            shot=call('/combat/session/fire',session_id=session,shot_id='slice_cost_'+secrets.token_hex(10),item_id=ranged['id'],origin=origin,direction=[1,0,0],ability_id='lethal_shot')
            check(shot.get('mutation',{}).get('ham_cost_committed'),'Actual native Lethal Shot launch commits HAM costs wearing '+item['slice_kind'])
            after=shot['snapshot']['player']['raw_ham'];attr=attributes(state,ranged);bonus=item['slice_bonuses'];expected=[]
            for pool,secondary,label in [(0,1,'health'),(3,4,'action'),(6,7,'mind')]:
                cost=float(attr['swgxr.'+label+'_cost'])*(1-bonus.get('sac_'+label+'_pct',0)/100)*max(0,1-(before_ham[secondary]-300)/1200)
                expected.append(int(cost+1e-5))
            observed=[before_ham[p]-after[i] for i,p in enumerate((0,3,6))]
            report.setdefault('launch_costs',[]).append(dict(kind=item['slice_kind'],observed=observed,expected=expected,bonuses=bonus))
            check(observed==expected,'Worn '+item['slice_kind']+' SAC reduction changes actual native HAM charge by exact formula')
            remove(item)
        report['passed']=True
    finally:
        if session:
            for item in cleanup_items:
                lua('swgxrSliceStatsRemove:'+item['id'])
            location=service('status')['state']['player'];call('/session/logout',live_session_id=session,**pose(location))
        if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
        out=ROOT/'runtime/evidence/slicing-stats-native-smoke.json';out.write_text(json.dumps(redact(report),indent=2)+'\n')
        print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']),evidence=str(out))),flush=True)


if __name__=='__main__':main()
