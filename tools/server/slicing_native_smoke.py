#!/usr/bin/env python3
"""Actual local native slicing and reward regression on disposable fixtures.

Administrative setup grants skills/items and reads the private native puzzle
witness only for deterministic integration testing. It does not test human
puzzle solving or tracked headset rendering. No global loot config is changed.
"""
import argparse
import json
import re
import secrets
import time
from services_smoke import ROOT, req, redact
from equipment_smoke import console


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutate-disposable-fixture', action='store_true', required=True)
    args = parser.parse_args()
    owners, sessions, checks, responses = [], {}, [], []
    report = dict(passed=False, native_execution=True, mocked=False, fixture_grants=True,
                  privileged_witness=True, headset_tested=False, fixtures=owners,
                  checks=checks, responses=responses)
    screenplay = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    added = ''
    active = {}
    solutions = {}

    def check(value, label):
        checks.append(dict(passed=bool(value), label=label))
        print(label, bool(value), flush=True)
        assert value, label

    def call(owner, path, **fields):
        result = req(path, dict(account=owner['account'], character_id=owner['id'], **fields))
        responses.append(dict(owner=owner['id'], path=path, response=redact(result)))
        return result

    def service(owner, action, **fields):
        if action not in ('status', 'open'):
            fields.setdefault('request_id', 'slicing_' + secrets.token_hex(12))
        return call(owner, '/services/' + action, session_id=sessions[owner['id']], zone='tatooine', **fields)

    def ent(owner, action, **fields):
        fields.setdefault('request_id', 'slicing_' + secrets.token_hex(12))
        return call(owner, '/entertainer/' + action, live_session_id=sessions[owner['id']], zone='tatooine', **fields)

    def pose(value):
        return {k: value[k] for k in ('position', 'building_id', 'cell_index')}

    def lua(name):
        log = ROOT / 'runtime/server/core3-console.log'
        offset = log.stat().st_size
        console('runLuaFunction Tests:' + name)
        for _ in range(100):
            with log.open() as stream:
                stream.seek(offset)
                found = re.search('runLuaFunction Tests:' + name.split(':', 1)[0] + r': result=([^\n]+)', stream.read())
            if found:
                return found.group(1).strip().strip('[]')
            time.sleep(.1)
        raise RuntimeError('Native fixture helper timed out: ' + name)

    def pending(owner):
        return lua('swgxrSlicingFixturePending:' + owner['id']) == '1'

    def inventory(owner):
        for _ in range(30):
            state = call(owner, '/inventory/status', live_session_id=sessions[owner['id']])
            if state.get('http_error') != 503:
                break
            time.sleep(.2)
        assert state.get('source_kind')=='core3_inventory', state
        return state['items']

    def balance(owner):
        return service(owner, 'status')['state']['wallet']['bank']

    def begin(owner, target_id, kind, location, **extra):
        p = location['position']
        return service(owner, 'slicing_begin', target_id=target_id, target_kind='terminal' if kind=='terminal' else 'item',
                       tool_id=tool['id'], tool_position=p, anchor_position=p, target_position=p,
                       heading_radians=0.0, **pose(location), **extra)

    def complete(owner, begun, location, valid=True, **extra):
        attempt = begun['state']['slicing']
        private = json.loads(lua('swgxrSlicingFixtureState:' + owner['id']))
        paths = private['_witness'] if valid else []
        solutions[attempt['attempt_id']] = paths
        return service(owner, 'slicing_complete', attempt_id=attempt['attempt_id'], paths=paths, **pose(location), **extra)

    try:
        for _ in range(2):
            owner = dict(account='invtestslicing' + secrets.token_hex(4), name='Ivtest' + ''.join(secrets.choice('aeilnorstu') for _ in range(8)))
            made = req('/characters', dict(owner, species='human', profession='combat_marksman'))
            assert 'character' in made, made
            owner['id'] = made['character']['id']
            owners.append(owner)
            location = call(owner, '/enter')['source_location']
            started = call(owner, '/session/start', **pose(location))
            check(started.get('session_live'), 'Disposable fixture starts actual native session')
            sessions[owner['id']] = started['session_id']
            call(owner, '/session/update', session_id=started['session_id'], ready=True, **pose(location))
            service(owner, 'status', position=[3501.7178,5,-4867.427], building_id='0', cell_index=0)
        smuggler, member = owners
        ids = ','.join(owner['id'] for owner in owners)
        added = f'''\n-- BEGIN SWGXR DISPOSABLE SLICING FIXTURE\nfunction Tests:swgxrSlicingFixtureGrant()
 local p=getSceneObject({smuggler['id']});if p==nil then return end
 awardSkill(p,"combat_smuggler_novice")
 for i=1,4 do awardSkill(p,"combat_smuggler_slicing_0"..i) end
 awardSkill(p,"combat_smuggler_master")
 local inv=SceneObject(p):getSlottedObject("inventory")
 local tool=giveItem(inv,"object/tangible/slicing/slicing_laser_knife.iff",-1);TangibleObject(tool):setUseCount(30)
 giveItem(inv,"object/weapon/ranged/pistol/pistol_fwg5.iff",-1)
 giveItem(inv,"object/weapon/ranged/pistol/pistol_fwg5.iff",-1)
 giveItem(inv,"object/weapon/melee/knife/knife_survival.iff",-1)
 giveItem(inv,"object/weapon/melee/knife/knife_survival.iff",-1)
 giveItem(inv,"object/tangible/wearables/armor/composite/armor_composite_chest_plate.iff",-1)
 giveItem(inv,"object/tangible/component/armor/shield_generator_personal.iff",-1)
 giveItem(inv,"object/tangible/container/loot/player_loot_crate.iff",-1)
 giveItem(inv,"object/tangible/wearables/shirt/shirt_s04.iff",-1)
 return "granted"
end
function Tests:swgxrSlicingFixturePromoteMember()
 local p=getSceneObject({member['id']});awardSkill(p,"combat_smuggler_novice");awardSkill(p,"combat_smuggler_slicing_01")
 local tool=giveItem(SceneObject(p):getSlottedObject("inventory"),"object/tangible/slicing/slicing_laser_knife.iff",-1);TangibleObject(tool):setUseCount(10);return "promoted"
end
function Tests:swgxrSlicingFixtureState(oid)
 if tonumber(oid)~={smuggler['id']} and tonumber(oid)~={member['id']} then return "invalid" end
 return readScreenPlayData(getSceneObject(tonumber(oid)),"swgxr_slicing","state")
end
function Tests:swgxrSlicingFixturePending(oid)
 if tonumber(oid)~={smuggler['id']} and tonumber(oid)~={member['id']} then return "invalid" end
 return readScreenPlayData(getSceneObject(tonumber(oid)),"swgxr_slicing_rewards","pending")
end
function Tests:swgxrSlicingFixtureExpire(oid)
 if tonumber(oid)~={smuggler['id']} and tonumber(oid)~={member['id']} then return "invalid" end
 local p=getSceneObject(tonumber(oid));local s=readScreenPlayData(p,"swgxr_slicing","state");s=string.gsub(s,'"deadline":%d+','"deadline":1');writeScreenPlayData(p,"swgxr_slicing","state",s);return "expired"
end
function Tests:swgxrSlicingFixtureProvenance(oid)
 local p=getSceneObject({smuggler['id']});local item=getSceneObject(tonumber(oid));if item==nil then return "missing" end
 local inv=SceneObject(p):getSlottedObject("inventory");if SceneObject(item):getParentID()~=SceneObject(inv):getObjectID() then return "unowned" end
 return tostring(TangibleObject(item):setCraftedProvenance({smuggler['id']},"{smuggler['name']}","SWGXR-FIXTURE-"..oid))
end
function Tests:swgxrSlicingFixtureSliced(oid)
 local p=getSceneObject(tonumber(oid));if p==nil then return "missing" end;return tostring(TangibleObject(p):isSliced())
end
function Tests:swgxrSlicingFixtureKill(oid)
 if tonumber(oid)~={smuggler['id']} and tonumber(oid)~={member['id']} then return "invalid" end
 local p=getSceneObject(tonumber(oid));local n=spawnMobile("tatooine","deliver_npc",0,3504,getTerrainHeight(p,3504,-4867),-4867,0,0)
 TangibleObject(n):setOptionsBitmask(0);CreatureObject(n):setPvpStatusBitmask(35)
 CreatureObject(n):inflictDamage(p,0,100000,1)
 local dead=CreatureObject(n):isDead();local inv=SceneObject(n):getSlottedObject("inventory");local crates=0
 for i=0,SceneObject(inv):getContainerObjectsSize()-1 do local item=SceneObject(inv):getContainerObject(i);if SceneObject(item):getTemplateObjectPath()=="object/tangible/container/loot/player_loot_crate.iff" then crates=crates+1 end end
 SceneObject(n):destroyObjectFromWorld();SceneObject(n):destroyObjectFromDatabase()
 CreatureObject(p):forcePeace()
 return tostring(dead)..":"..crates
end
-- END SWGXR DISPOSABLE SLICING FIXTURE\n'''
        screenplay.write_text(screenplay.read_text() + added)
        console('reloadscreenplays')
        time.sleep(.3)
        check(lua('swgxrSlicingFixtureGrant') == 'granted', 'Only isolated Smuggler receives original native skills and slicing fixtures')
        items = inventory(smuggler)
        tool = next(i for i in items if i['template'].endswith('/slicing_laser_knife.iff'))
        weapons = [i for i in items if i['template'].endswith('/pistol_fwg5.iff')]
        melee = [i for i in items if i['template'].endswith('/knife_survival.iff')]
        armor = next(i for i in items if i['template'].endswith('/armor_composite_chest_plate.iff'))
        psg = next(i for i in items if i['template'].endswith('/shield_generator_personal.iff'))
        crate = next(i for i in items if i['template'].endswith('/player_loot_crate.iff'))
        clothing = next(i for i in items if i['template'].endswith('/shirt_s04.iff'))
        check(ent(smuggler, 'group_invite', target_id=member['id']).get('ok'), 'Original native group invitation issued')
        check(ent(member, 'group_join').get('ok'), 'Original native group membership accepted')
        terminal = dict(id='1316125', position=[3501.7178,5,-4867.427], building_id='0', cell_index=0)
        started = begin(smuggler, terminal['id'], 'terminal', terminal)
        check(started.get('ok') and started['state']['slicing'].get('attempt_id'), 'Reach-validated original mission terminal starts native puzzle')
        check('_witness' not in json.dumps(started), 'Private puzzle solution never appears in client response')
        key = 'slicing_' + secrets.token_hex(12)
        finished = complete(smuggler, started, terminal, request_id=key)
        check(finished.get('ok') and finished['state']['slicing']['status']=='succeeded', 'Server validates exact puzzle paths and commits terminal success')
        check(pending(smuggler) and pending(member), 'Terminal success gives one persistent next-mission credit to each native party member')
        attempt_id = started['state']['slicing']['attempt_id']
        replay = service(smuggler, 'slicing_complete', attempt_id=attempt_id, paths=solutions[attempt_id], request_id=key, **pose(terminal))
        check(replay.get('mutation', {}).get('replayed') and pending(smuggler) and pending(member), 'Durable completion receipt replays without adding or consuming party credits')
        opened = service(smuggler, 'open', terminal_id=terminal['id'], **pose(terminal))
        check(opened.get('ok') and pending(smuggler), 'Generating native mission offers preserves pending slicing credit')
        offers = [m for m in opened['state']['terminal']['missions'] if m['type'] == 'deliver' and m.get('supported')]
        check(bool(offers), 'Original mission terminal supplies a native parcel route')
        offer = offers[0]
        accepted = service(smuggler, 'mission_accept', terminal_id=terminal['id'], mission_id=offer['id'], **pose(terminal))
        check(accepted.get('ok'), 'Boosted mission accepted through original MissionManager')
        mission = next(m for m in accepted['state']['missions'] if m['id'] == offer['id'])
        active[smuggler['id']] = mission['id']
        check(mission['reward'] == offer['reward'] * 3 // 2 and not pending(smuggler) and pending(member), 'Acceptance consumes only owner credit and stores exact native 1.5 reward')
        giver = next(c for c in accepted['state']['delivery_contacts'] if c['mission_id'] == mission['id'] and c['role'] == 'giver')
        pickup = service(smuggler, 'delivery_pickup', mission_id=mission['id'], npc_id=giver['id'], **pose(giver))
        check(pickup.get('ok'), 'Boosted native mission supplies real bound parcel')
        parcel = next(p for p in pickup['state']['parcels'] if p['mission_id'] == mission['id'])
        receiver = next(c for c in pickup['state']['delivery_contacts'] if c['mission_id'] == mission['id'] and c['role'] == 'receiver')
        service(member, 'status', **pose(receiver))
        before = [balance(owner) for owner in owners]
        done = service(smuggler, 'delivery_complete', mission_id=mission['id'], npc_id=receiver['id'], parcel_id=parcel['id'], **pose(receiver))
        check(done.get('ok'), 'Native receiver completes boosted original mission')
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            after = [balance(owner) for owner in owners]
            if after != before:
                break
            time.sleep(.2)
        check(all(after[i]-before[i] == mission['reward']//2 for i in range(2)), 'Original mission payout splits boosted credits exactly between nearby party members')
        active.pop(smuggler['id'], None)
        # Another job receives no bonus without another successful slice.
        time.sleep(1.5)
        opened = service(smuggler, 'open', terminal_id=terminal['id'], **pose(terminal))
        offer = next(m for m in opened['state']['terminal']['missions'] if m['type'] == 'deliver' and m.get('supported'))
        accepted = service(smuggler, 'mission_accept', terminal_id=terminal['id'], mission_id=offer['id'], **pose(terminal))
        active[smuggler['id']] = offer['id']
        check(next(m for m in accepted['state']['missions'] if m['id']==offer['id'])['reward'] == offer['reward'], 'Following accepted mission returns to original unboosted reward')
        service(smuggler, 'mission_abort', mission_id=offer['id'])
        active.pop(smuggler['id'], None)
        # Native crafted markers are privileged fixture setup, not earned crafting.
        rejected = begin(smuggler, weapons[0]['id'], 'weapon', terminal)
        check(rejected.get('http_error') == 400, 'Untouched original template gear cannot masquerade as crafted equipment')
        for item in weapons + [melee[0], armor, psg, clothing]:
            check(lua('swgxrSlicingFixtureProvenance:' + item['id']) == 'true', 'Explicit fixture writes original native crafter id and serial')
        gear = begin(smuggler, weapons[0]['id'], 'weapon', terminal)
        check(gear.get('ok'), 'Owned crafted-provenance weapon starts native spatial puzzle')
        check(lua('swgxrSlicingFixtureSliced:' + weapons[0]['id']) == 'true', 'Beginning equipment slice immediately burns original sliced flag')
        attempt_id = gear['state']['slicing']['attempt_id']
        invalid = service(smuggler, 'slicing_complete', attempt_id=attempt_id, paths=[], **pose(terminal))
        still = json.loads(lua('swgxrSlicingFixtureState:' + smuggler['id']))
        check(still.get('attempt_id') == attempt_id and still.get('active'), 'Invalid puzzle paths preserve active attempt until deadline')
        succeeded = complete(smuggler, gear, terminal)
        check(succeeded.get('ok') and succeeded['state']['slicing']['status']=='succeeded', 'Valid weapon paths commit native gear slice')
        check(begin(smuggler, weapons[0]['id'], 'weapon', terminal).get('http_error') == 400, 'Successfully sliced crafted weapon permanently rejects another attempt')
        gear = begin(smuggler, weapons[1]['id'], 'weapon', terminal)
        check(gear.get('ok'), 'Second original crafted fixture opens independent attempt')
        check(lua('swgxrSlicingFixtureExpire:' + smuggler['id']) == 'expired', 'Only isolated attempt deadline is administratively expired')
        service(smuggler, 'status')
        check(begin(smuggler, weapons[1]['id'], 'weapon', terminal).get('http_error') == 400, 'Timed-out crafted weapon permanently rejects retry')
        for item, kind in [(melee[0], 'weapon'), (armor, 'armor'), (psg, 'shield'), (clothing, 'clothing'), (crate, 'container')]:
            sliced = begin(smuggler, item['id'], kind, terminal)
            check(sliced.get('ok'), 'Original ' + kind + ' target opens native puzzle')
            done = complete(smuggler, sliced, terminal)
            check(done.get('ok') and done['state']['slicing']['status']=='succeeded', 'Server validates original ' + kind + ' puzzle completion')
        report['gear_after'] = inventory(smuggler)
        weapon_after = next(i for i in report['gear_after'] if i['id']==weapons[0]['id'])
        wb = weapon_after['slice_bonuses']
        check(len({'capacity_pct','rof_pct'} & set(wb))==1 and 'range_pct' in wb and bool({'min_damage_pct','max_damage_pct'} & set(wb)) and all(20<=v<=35 for v in wb.values()), 'Master ranged slice records independent native primary, range and damage bonuses in approved bounds')
        armor_after = next(i for i in report['gear_after'] if i['id']==armor['id'])
        ab = armor_after['slice_bonuses']
        check(len(armor_after['slice_skill_mods'])==2 and all(20<=m['value']<=25 for m in armor_after['slice_skill_mods']) and 11<=ab['protection_pct']<=35 and len({'sac_health_pct','sac_action_pct','sac_mind_pct'} & set(ab))==1, 'Master armor slice records two native modifiers, protection and one cost reduction in approved bounds')
        clothing_after = next(i for i in report['gear_after'] if i['id']==clothing['id'])
        check(len(clothing_after['slice_skill_mods'])==6 and len({m['id'] for m in clothing_after['slice_skill_mods']})==6 and all(20<=m['value']<=25 for m in clothing_after['slice_skill_mods']), 'Master clothing receives six distinct native modifiers in approved bounds')
        check(not any(i['id']==crate['id'] for i in report['gear_after']) and any(i['template'].endswith('/loot_crate.iff') for i in report['gear_after']), 'Original locked loot container is consumed and replaced by native unlocked crate')
        # Empty original deliver_npc loot tables isolate the additional crate roll.
        for _ in range(5):
            result = lua('swgxrSlicingFixtureKill:' + member['id'])
            check(result == 'true:0', 'Actual non-Smuggler final blow creates no bonus crate on original empty-loot NPC')
        found = False
        trials = []
        for _ in range(80):
            result = lua('swgxrSlicingFixtureKill:' + smuggler['id'])
            trials.append(result)
            assert result.startswith('true:'), result
            if int(result.split(':')[1]) > 0:
                found = True
                break
        report['native_bonus_kills'] = trials
        check(found, 'Actual Smuggler killing blow yields original locked container through independent native bonus roll')
        member_offers = service(member, 'open', terminal_id=terminal['id'], **pose(terminal))
        member_offer = next(m for m in member_offers['state']['terminal']['missions'] if m['type']=='deliver' and m.get('supported'))
        member_accept = service(member, 'mission_accept', terminal_id=terminal['id'], mission_id=member_offer['id'], **pose(terminal))
        active[member['id']] = member_offer['id']
        check(next(m for m in member_accept['state']['missions'] if m['id']==member_offer['id'])['reward']==member_offer['reward']*3//2 and not pending(member), 'Party member independently consumes only their own next-mission slicing credit')
        service(member, 'mission_abort', mission_id=member_offer['id'])
        active.pop(member['id'], None)
        # Upgrade the already-tested non-Smuggler control only after its loot checks.
        check(lua('swgxrSlicingFixturePromoteMember')=='promoted', 'Previously verified non-Smuggler control is explicitly promoted for separate terminal failure test')
        tool = next(i for i in inventory(member) if i['template'].endswith('/slicing_laser_knife.iff'))
        failed_terminal = begin(member, terminal['id'], 'terminal', terminal)
        check(failed_terminal.get('ok'), 'Another character starts independent terminal attempt')
        check(lua('swgxrSlicingFixtureExpire:' + member['id'])=='expired', 'Only second fixture terminal deadline is expired')
        service(member, 'status')
        rejected = begin(member, terminal['id'], 'terminal', terminal)
        check(rejected.get('http_error')==400 and 'terminal_slice_permanently_failed' in str(rejected), 'Terminal timeout permanently blocks that exact character-terminal pair')
        check(not pending(member), 'Failed terminal slice grants no new next-mission credit')
        report['passed'] = True
    finally:
        for owner in owners:
            if owner['id'] in active:
                service(owner, 'mission_abort', mission_id=active[owner['id']])
            if owner['id'] in sessions:
                location=service(owner,'status')['state']['player']
                call(owner, '/session/logout', live_session_id=sessions[owner['id']], **pose(location))
        if added:
            screenplay.write_text(screenplay.read_text().replace(added, ''))
            console('reloadscreenplays')
        path = ROOT / 'runtime/evidence/slicing-native-smoke.json'
        path.write_text(json.dumps(redact(report), indent=2) + '\n')
        print(json.dumps(dict(passed=report['passed'], checks=len(checks), evidence=str(path))), flush=True)


if __name__ == '__main__':
    main()
