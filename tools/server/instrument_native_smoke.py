#!/usr/bin/env python3
"""Bounded local native instrument slot/placement regression; no VR or remote work."""
import json
import re
import secrets
import time
from services_smoke import ROOT, req, redact
from equipment_smoke import console


def main():
    owner = {'account': 'invtestinstrument' + secrets.token_hex(3),
             'name': 'Ivtest' + ''.join(secrets.choice('aeilnorstu') for _ in range(8))}
    report = {'passed': False, 'native_execution': True, 'headset_tested': False,
              'remote_server_changed': False, 'fixture': owner, 'checks': [], 'responses': [],
              'fixture_setup': 'Original novice entertainer starter slitherhorn. Privileged disposable fixture grants original musician master prerequisites, survival knife, and spawns an original nalargon world object; no earned progression claimed.'}
    script = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    added = ''; session = ''; original = {}; outside = {'position': [3527, 5, -4810], 'building_id': '0', 'cell_index': 0, 'zone': 'tatooine'}

    def check(value, label):
        report['checks'].append({'passed': bool(value), 'label': label})
        print(label, bool(value), flush=True)
        (ROOT / 'runtime/evidence/instrument-native.json').write_text(json.dumps(redact(report), indent=2) + '\n')
        assert value, label

    def call(path, **fields):
        for attempt in range(6):
            out = req(path, dict(account=owner['account'], character_id=owner['id'], **fields))
            report['responses'].append({'path': path, 'response': redact(out)})
            (ROOT / 'runtime/evidence/instrument-native.json').write_text(json.dumps(redact(report), indent=2) + '\n')
            if not (out.get('error_code') == 'backend_busy' and out.get('mutation_started') is False):
                return out
            time.sleep(.5)
        return out

    def ent(action, **fields):
        return call('/entertainer/' + action, live_session_id=session,
                    request_id='instrument_' + secrets.token_hex(8), zone='tatooine', **fields)

    def inventory():
        return call('/inventory/status', live_session_id=session)

    def lua(name):
        log = ROOT / 'runtime/server/core3-console.log'; offset = log.stat().st_size
        console('runLuaFunction Tests:' + name)
        for _ in range(80):
            with log.open() as stream:
                stream.seek(offset)
                match = re.search('runLuaFunction Tests:' + name.split(':')[0] + r': result=([^\n]+)', stream.read())
            if match:
                return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise AssertionError('Fixture helper timeout: ' + name)

    def equipped(result, item_id):
        inv = result['inventory'] if 'items' in result.get('inventory', {}) else result
        return next((i for i in inv.get('equipment', []) if i['id'] == item_id), {})

    def stored(result, item_id):
        inv = result['inventory'] if 'items' in result.get('inventory', {}) else result
        return next((i for i in inv.get('items', []) if i['id'] == item_id
                     and i.get('container_id') == inv.get('inventory', {}).get('id')), {})

    try:
        made = req('/characters', dict(owner, species='human', profession='social_entertainer'))
        check('character' in made, 'Create dedicated original entertainer fixture')
        owner['id'] = made['character']['id']
        entry = call('/enter'); original = entry['source_location']; performance_token = entry['entertainment']['token']
        opened = call('/session/start', **{k: original[k] for k in ('position', 'building_id', 'cell_index', 'zone')})
        session = opened['session_id']
        ready = call('/session/update', session_id=session, ready=True,
                     **{k: original[k] for k in ('position', 'building_id', 'cell_index', 'zone')})
        check(ready.get('player', {}).get('on_load_screen') is False, 'Dedicated fixture enters actual native scene')
        added = f'''
-- BEGIN SWGXR INSTRUMENT SLOT FIXTURE
function Tests:swgxrInstrumentSetup()
 local p=getSceneObject({owner['id']});if p==nil then return "missing" end
 awardSkill(p,"social_musician_master")
 giveItem(SceneObject(p):getSlottedObject("inventory"),"object/weapon/melee/knife/knife_survival.iff",-1)
 SceneObject(p):teleport(3527,5,-4810,0)
 local n=spawnSceneObject("tatooine","object/tangible/instrument/nalargon.iff",3528,5,-4810,0,0)
 if n==nil then return "missing_instrument" end
 writeData("swgxrInstrument:{owner['id']}",SceneObject(n):getObjectID())
 return tostring(SceneObject(n):getObjectID())
end
function Tests:swgxrInstrumentMoveFar()
 SceneObject(getSceneObject({owner['id']})):teleport(3538,5,-4810,0);return "far"
end
function Tests:swgxrInstrumentCleanup()
 local n=getSceneObject(readData("swgxrInstrument:{owner['id']}"))
 if n~=nil then SceneObject(n):destroyObjectFromWorld();SceneObject(n):destroyObjectFromDatabase() end
 deleteData("swgxrInstrument:{owner['id']}");return "clean"
end
-- END SWGXR INSTRUMENT SLOT FIXTURE
'''
        script.write_text(script.read_text() + added); console('reloadscreenplays')
        placed_id = lua('swgxrInstrumentSetup')
        check(placed_id.isdigit(), 'Spawn original stationary nalargon on isolated fixture path')
        call('/session/update', session_id=session, ready=True, **outside)
        inv = inventory(); horn = next(i for i in inv['items'] if i['template'].endswith('/slitherhorn.iff'))
        knife = next(i for i in inv['items'] if i['template'].endswith('/knife_survival.iff'))
        denied = ent('perform', kind='music', name='starwars1', item_id=horn['id'])
        check(denied.get('http_error') == 400 and 'instrument_requires_weapon_slot' in str(denied.get('error', '')),
              'Inventory-only instrument cannot start music or silently equip')
        check(bool(stored(inventory(), horn['id'])), 'Denied performance leaves exact instrument in inventory')
        held = call('/inventory/equip', live_session_id=session, item_id=horn['id'], arrangement=0)
        check(held.get('mutation', {}).get('success') and 'hold_r' in equipped(held, horn['id']).get('equipped_slots', []),
              'Explicit inventory equip puts exact instrument in native hold_r')
        played = ent('perform', kind='music', name='starwars1', item_id=horn['id'])
        check(played.get('ok') and played['state']['performing'] and played['state']['instrument_mode'] == 'equipped'
              and played['state']['item_id'] == horn['id'], 'Held instrument starts original native music')
        returned = call('/inventory/unequip', live_session_id=session, item_id=horn['id'])
        check(returned.get('mutation', {}).get('success') and bool(stored(returned, horn['id'])) and not equipped(returned, horn['id']),
              'Explicit unequip returns exact item to inventory in fresh response')
        check(not ent('status')['state']['performing'], 'Explicit instrument unequip immediately stops native music')
        held = call('/inventory/equip', live_session_id=session, item_id=horn['id'], arrangement=0)
        check(bool(equipped(held, horn['id'])), 'Same returned instrument can be equipped again')
        check(ent('perform', kind='music', name='starwars1', item_id=horn['id']).get('ok'), 'Re-equipped instrument can perform again')
        displaced = call('/inventory/equip', live_session_id=session, item_id=knife['id'], arrangement=0)
        check(displaced.get('mutation', {}).get('success') and bool(stored(displaced, horn['id'])),
              'Equipping another held item returns displaced instrument to inventory')
        check(not ent('status')['state']['performing'], 'Displacing held instrument immediately stops native music')
        state = ent('status')['state']; placed = next((i for i in state['placed_instruments'] if i['id'] == placed_id), {})
        check(placed.get('playable') is True, 'Nearby original placed instrument is discovered as playable')
        played = ent('perform', kind='music', name='starwars1', item_id=placed_id)
        check(played.get('ok') and played['state']['performing'] and played['state']['instrument_mode'] == 'placed'
              and played['state']['instrument_id'] == placed_id, 'Nearby placed instrument starts original native music without inventory equip')
        presentation = call('/performance', token=performance_token, seq=1, position=outside['position'], area='tatooine',
                            item_id=placed_id, enabled=True)
        check(presentation.get('native_authority') and presentation.get('performance_id')
              and any(b.get('performance', {}).get('performance_index') == played['state']['performance_index'] for b in presentation.get('bands', [])),
              'Presentation bus accepts native placed item and projects matching original music performance')
        check(any(b.get('performance', {}).get('instrument') == 'nalargon' and b['performance'].get('sounds', {}).get('mainloop')
                  for b in presentation.get('bands', [])), 'Placed performance projects original nalargon audio references')
        check(placed_id not in {i['id'] for i in inventory()['items']}, 'Playing placed instrument does not move world object into inventory')
        presentation = call('/performance', token=performance_token, seq=2, position=outside['position'], area='tatooine',
                            item_id=placed_id, enabled=True)
        check(presentation.get('native_authority') and presentation.get('performance_id'),
              'Placed music remains projected after an inventory refresh')
        check(lua('swgxrInstrumentMoveFar') == 'far', 'Move only disposable fixture beyond native three-metre instrument range')
        far = dict(outside, position=[3538, 5, -4810])
        outside = far
        call('/session/update', session_id=session, ready=True, **far)
        denied = ent('perform', kind='music', name='starwars1', item_id=placed_id)
        check(denied.get('http_error') == 400 and 'nearby_placed_instrument_required' in str(denied.get('error', '')),
              'Placed instrument performance rejected outside original source range')
        report['passed'] = True
    finally:
        if added:
            try:
                check(lua('swgxrInstrumentCleanup') == 'clean', 'Disposable placed instrument removed from world and database')
            finally:
                script.write_text(script.read_text().replace(added, '')); console('reloadscreenplays')
                report['helper_removed'] = added not in script.read_text()
        if session:
            ent('stop')
            result = call('/session/logout', live_session_id=session, request_id='instrument_logout_' + secrets.token_hex(8),
                          **outside)
            report['logout'] = redact(result)
            check(result.get('saved') and result.get('session_closed'), 'Dedicated fixture saves current native position and closes native session')
        (ROOT / 'runtime/evidence/instrument-native.json').write_text(json.dumps(redact(report), indent=2) + '\n')
        print(json.dumps({'passed': report['passed'], 'checks': len(report['checks'])}), flush=True)


if __name__ == '__main__':
    main()
