#!/usr/bin/env python3
"""Prepare/apply bounded tester stock through existing native inventory/bazaar APIs.

Run `plan` offline, then `apply` on the authorized test host. Apply requires its
running loopback adapter and trusted console; it never launches/restarts services.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from server.planets import SUPPORTED_PLANETS

TAG = 'swgxr_bazaar_onboarding_v1'
# SKU, original template, number of separate stock items, fixed tester price.
STOCK = (
    ('pistol', 'weapon/ranged/pistol/pistol_cdef', 2, 60),
    ('carbine', 'weapon/ranged/carbine/carbine_cdef', 1, 65),
    ('rifle', 'weapon/ranged/rifle/rifle_cdef', 1, 70),
    ('knife', 'weapon/melee/knife/knife_survival', 2, 25),
    ('maul', 'weapon/melee/2h_sword/2h_sword_maul', 1, 60),
    ('staff', 'weapon/melee/polearm/lance_staff_wood_s1', 1, 40),
    ('bone_chest', 'tangible/wearables/armor/bone/armor_bone_s01_chest_plate', 1, 75),
    ('bone_boots', 'tangible/wearables/armor/bone/armor_bone_s01_boots', 1, 30),
    ('bone_helmet', 'tangible/wearables/armor/bone/armor_bone_s01_helmet', 1, 35),
    ('medical_tool', 'tangible/medicine/medikit_tool_basic', 1, 20),
    ('stim', 'tangible/medicine/stimpack_sm_s1', 3, 20),
    ('crafting_tool', 'tangible/crafting/station/generic_tool', 2, 20),
    ('mineral_tool', 'tangible/survey_tool/survey_tool_mineral', 2, 20),
    ('gas_tool', 'tangible/survey_tool/survey_tool_gas', 1, 20),
    ('instrument', 'tangible/instrument/slitherhorn', 1, 40),
    ('backpack', 'tangible/wearables/backpack/backpack_s01', 1, 25),
    ('trap', 'tangible/scout/trap/trap_noise_maker', 2, 10),
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stock_name(planet):
    # Planet names themselves match original reserved-name filters (Tatooine
    # even matches inside a longer name). Use stable ordinary test-owner names.
    alphabet = 'aeilor'
    suffix = ''.join(alphabet[b % len(alphabet)] for b in hashlib.sha256((TAG+planet).encode()).digest()[:8])
    return 'Ivstock'+suffix


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(data, output, indent=2)
        output.write('\n')
    temporary.replace(path)


def plan(root=ROOT):
    items = []
    for sku, relative, count, price in STOCK:
        source = root/'vendor/Core3/MMOCoreORB/bin/scripts/object'/f'{relative}.lua'
        text = source.read_text()
        template = f'object/{relative}.iff'
        if f'"{template}"' not in text:
            raise ValueError('Original template registration missing: '+template)
        items.append(dict(sku=sku, template=template, quantity=count, price=price,
                          source=str(source.relative_to(root)), source_sha256=digest(source)))
    if sum(item['quantity'] for item in items) > 25:
        raise ValueError('Native bazaar seller limit exceeded')
    planets = []
    world = json.loads((root/'runtime/assets/planets/catalog.json').read_text())['planets']
    for planet in SUPPORTED_PLANETS:
        path = (root/'runtime/assets/services/catalog.json' if planet == 'tatooine'
                else root/'runtime/assets/planets'/planet/'services/catalog.json')
        rows = json.loads(path.read_text())['static_terminals']
        eligible = [r for r in rows if r['kind'] == 'bazaar' and int(r['id']) > 0
                    and r['building_id'] == '0' and r['cell_index'] == 0]
        if not eligible:
            raise ValueError('No original outdoor bazaar for '+planet)
        entry = world[planet]['default_entry']
        terminal = min(eligible, key=lambda r: (math.dist(r['position'], entry), int(r['id'])))
        planets.append(dict(planet=planet, account='invtestbazaar'+planet,
                            name=stock_name(planet), terminal_id=terminal['id'],
                            position=terminal['position'], building_id='0', cell_index=0,
                            source=str(path.relative_to(root)), source_sha256=digest(path)))
    return dict(schema=1, tag=TAG, target='current authorized test VPS',
                planets=planets, items=items, items_per_planet=sum(i['quantity'] for i in items),
                stats='Unmodified original giveItem defaults; no crafting rolls, slices, powerups, stat or charge setters.',
                policy='One initial stock batch per planet. Repeated execution resumes the same item IDs, including sold items; no automatic replenishment or changes to player listings.')


def units(manifest):
    return [dict(item, key=item['sku']+'_'+str(index)) for item in manifest['items']
            for index in range(item['quantity'])]


def lua_prepare(manifest, planet, owner):
    ident = str(owner['id'])
    if not ident.isascii() or not ident.isdigit() or not 0 < int(ident) < 2**64:
        raise ValueError('Invalid dedicated stock owner ID')
    if owner['name'] != planet['name'] or owner['account'] != planet['account']:
        raise ValueError('Dedicated stock owner mismatch')
    literal = json.dumps
    function = 'swgxrBazaarSeed'+planet['planet'].capitalize()
    rows = ','.join('{'+literal(u['key'])+','+literal(u['template'])+'}' for u in units(manifest))
    return function, f'''\n-- BEGIN {TAG} {planet['planet']}
function Tests:{function}()
 local p=getSceneObject({ident});if p==nil or CreatureObject(p):getFirstName()~={literal(owner['name'])} then return "wrong_owner" end
 local terminal=getSceneObject({planet['terminal_id']})
 if terminal==nil or SceneObject(terminal):getZoneName()~={literal(planet['planet'])} or SceneObject(terminal):getTemplateObjectPath()~="object/tangible/terminal/terminal_bazaar.iff" then return "wrong_terminal" end
 -- Lua scene wrappers share their bound object. Resolve coordinates first;
 -- nested SceneObject(terminal) calls would retarget the outer player wrapper.
 local x=SceneObject(terminal):getPositionX()+1
 local z=SceneObject(terminal):getPositionZ()
 local y=SceneObject(terminal):getPositionY()
 SceneObject(p):switchZone({literal(planet['planet'])},x,z,y,0)
 SceneObject(p):teleport(x,z,y,0)
 local inv=SceneObject(p):getSlottedObject("inventory");if inv==nil then return "missing_inventory" end
 local namespace={literal(TAG)};local rows={{{rows}}};local ids={{}}
 for _,row in ipairs(rows) do
  local id=readScreenPlayData(p,namespace,row[1])
  if id=="" then
   local item=giveItem(inv,row[2],-1);if item==nil then return "create_failed:"..row[1] end
   id=tostring(SceneObject(item):getObjectID());writeScreenPlayData(p,namespace,row[1],id)
  end
  table.insert(ids,id)
 end
 if readScreenPlayData(p,namespace,"fees")=="" then
  CreatureObject(p):addBankCredits({len(units(manifest))*20},false)
  writeScreenPlayData(p,namespace,"fees","paid")
 end
 return "ready:"..table.concat(ids,",")
end
-- END {TAG} {planet['planet']}
'''


def listing_decision(item, record, inventory):
    """Only list the exact provisioned object; never replace sold/missing stock."""
    if record is not None:
        if record['owner_id'] != item['owner_id']:
            raise ValueError('Stock listing owner changed')
        return 'existing'
    held = inventory.get(item['id'])
    if held is None:
        return 'unresolved'
    if held['template'] != item['template']:
        raise ValueError('Stock item template mismatch')
    return 'sell'


class Native:
    def __init__(self, container):
        self.container = container

    def request(self, path, data=None):
        request = urllib.request.Request('http://127.0.0.1:18080'+path,
                  data=json.dumps(data).encode() if data is not None else None,
                  headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.load(response)

    def console(self, command):
        subprocess.run(['podman', 'exec', self.container, 'bash', '-lc',
                        'printf "%s\\n" "$1" >/workspace/runtime/server/core3-console',
                        'bazaar_seed', command], check=True)

    @contextmanager
    def screenplay(self, function, source):
        path = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
        original = path.read_text()
        if 'function Tests:'+function+'(' in original:
            raise RuntimeError('Seed function already installed; inspect previous interrupted run')
        path.write_text(original+source)
        try:
            self.console('reloadscreenplays')
            time.sleep(.5)
            yield
        finally:
            current = path.read_text()
            if current.count(source) != 1:
                raise RuntimeError('Seed screenplay changed concurrently; refusing to overwrite it')
            path.write_text(current.replace(source, '', 1))
            self.console('reloadscreenplays')

    def call(self, function):
        log = ROOT/'runtime/server/core3-console.log'
        offset = log.stat().st_size
        command = 'runLuaFunction Tests:'+function
        self.console(command)
        deadline = time.monotonic()+60
        while time.monotonic() < deadline:
            with log.open() as handle:
                handle.seek(offset)
                text = handle.read()
            match = re.search(re.escape(command)+r': result=([^\n]+)', text)
            if match:
                return match[1].strip().strip('[]')
            if 'Failed to runLuaFunction' in text or 'Exception in runLuaFunction' in text:
                raise RuntimeError('Native seed function failed; see private Core3 console log')
            time.sleep(.1)
        raise TimeoutError('Native seed function response timed out')


def apply(manifest, native, ledger_path):
    if manifest != plan():
        raise ValueError('Prepared manifest no longer matches the current sources/stock plan')
    ledger = json.loads(ledger_path.read_text()) if ledger_path.exists() else dict(tag=TAG, owners={}, planets={})
    if ledger.get('tag') != TAG:
        raise ValueError('Unrelated seed ledger')
    for planet in manifest['planets']:
        zone = planet['planet']
        owner = ledger['owners'].get(zone)
        if owner is None:
            listing = native.request('/characters?account='+planet['account'])
            if listing.get('characters'):
                raise RuntimeError('Dedicated account already contains characters without this seed ledger: '+zone)
            created = native.request('/characters', dict(account=planet['account'], name=planet['name'],
                                     species='human', sex='male', profession='crafting_artisan'))['character']
            owner = dict(account=planet['account'], name=created['name'], id=created['id'])
            ledger['owners'][zone] = owner
            save(ledger_path, ledger)
        base = dict(account=owner['account'], character_id=owner['id'])
        entry = native.request('/enter', base)['source_location']
        context = {k: entry[k] for k in ('position', 'zone', 'building_id', 'cell_index')}
        session = native.request('/session/start', dict(base, **context))['session_id']
        try:
            native.request('/session/update', dict(base, session_id=session, ready=True, **context))
            # Finish the old movement session before the trusted console warp;
            # the new session must start from the resulting native destination.
            native.request('/combat/session/stop', dict(base, session_id=session))
            session = ''
            function, source = lua_prepare(manifest, planet, owner)
            with native.screenplay(function, source):
                result = native.call(function)
            if not result.startswith('ready:'):
                raise RuntimeError('Native bazaar preparation: '+result)
            ids = result[6:].split(',')
            if len(ids) != len(units(manifest)) or len(set(ids)) != len(ids) or not all(i.isdigit() for i in ids):
                raise ValueError('Native stock identity response invalid')
            # The trusted console moved this dedicated owner. Re-enter at the
            # saved native location so movement budgets/readiness use that zone.
            entry = native.request('/enter', base)['source_location']
            if entry['zone'] != zone or entry['building_id'] != '0' or math.dist(entry['position'], planet['position']) > 8:
                raise RuntimeError('Native stock owner did not arrive at its original bazaar: '+zone+' '+str(entry))
            context = {k: entry[k] for k in ('position', 'zone', 'building_id', 'cell_index')}
            session = native.request('/session/start', dict(base, **context))['session_id']
            native.request('/session/update', dict(base, session_id=session, ready=True, **context))
            # Services check actual native range. Do not move the owner with a
            # catalog height or attempt to bypass the player movement budget.
            at = dict(base, live_session_id=session, terminal_id=planet['terminal_id'], zone=zone)
            inventory = native.request('/inventory/status', dict(base, live_session_id=session))
            inventory = {row['id']: row for row in inventory['items']}
            listings = {}
            for page in range(100):
                state = native.request('/services/open', dict(at, page=page, category_id=0))['state']['terminal']
                listings.update({row['id']: row for row in state['listings']})
                if not state['has_more']:
                    break
            else:
                raise RuntimeError('Bazaar scan exceeded bounded 100 pages')
            recorded = []
            previous = {row['id']: row for row in ledger['planets'].get(zone, [])}
            for unit, ident in zip(units(manifest), ids):
                item = dict(unit, id=ident, owner_id=owner['id'])
                decision = listing_decision(item, listings.get(ident), inventory)
                if decision == 'unresolved':
                    if ident not in previous:
                        raise RuntimeError('Unconfirmed stock item missing from both bazaar and owned inventory: '+ident)
                    decision = 'previously_confirmed_no_longer_listed'
                if decision == 'sell':
                    request = dict(at, item_id=ident, price=unit['price'], auction=False,
                                   galactic_search=True, description='Tester starter stock; original unmodified item stats.',
                                   request_id='bazaar_v1_'+zone+'_'+unit['key'])
                    response = native.request('/services/bazaar_sell', request)
                    if response.get('mutation', {}).get('listing_id') != ident:
                        raise RuntimeError('Native bazaar listing did not confirm stock identity')
                recorded.append(dict(id=ident, sku=unit['sku'], slot=unit['key'], price=unit['price'], result=decision))
                previous[ident] = recorded[-1]
                ledger['planets'][zone] = list(previous.values())
                save(ledger_path, ledger)
        finally:
            if session:
                native.request('/combat/session/stop', dict(base, session_id=session))
    ledger['applied'] = True
    save(ledger_path, ledger)
    return ledger


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'apply'))
    parser.add_argument('--manifest', type=Path, default=ROOT/'runtime/evidence/bazaar-onboarding/manifest.json')
    parser.add_argument('--ledger', type=Path, default=ROOT/'runtime/server/bazaar-onboarding/ledger.json')
    parser.add_argument('--container', default='swgxr-core3-build')
    args = parser.parse_args()
    if args.action == 'plan':
        data = plan()
        save(args.manifest, data)
        print(json.dumps(dict(prepared=True, applied=False, planets=len(data['planets']),
                              item_types=len(data['items']), items_per_planet=data['items_per_planet'], manifest=str(args.manifest))))
    else:
        data = apply(json.loads(args.manifest.read_text()), Native(args.container), args.ledger)
        print(json.dumps(dict(applied=data['applied'], planets=len(data['planets']), ledger=str(args.ledger))))


if __name__ == '__main__':
    main()
