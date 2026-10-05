#!/usr/bin/env python3
"""Original delivery/crafting objectives on a dedicated local artisan; no grants.

Requires the rebuilt 0037 native server. Does not restart Core3, launch XR, use
admin commands, change skills, spawn items, or touch existing player accounts.
Every mission is accepted through an original terminal. On failure only this
fixture's newly accepted missions are cancelled and its original pose restored.
"""
import argparse
import json
import math
import secrets
import time
from pathlib import Path

import services_smoke as shared
from services_smoke import ROOT, redact, req


def key():
    return 'delivery_' + secrets.token_hex(12)


def pose(row):
    return {k: row[k] for k in ('position', 'building_id', 'cell_index', 'heading_radians') if k in row}


def item_ids(inventory):
    return {str(row['id']) for row in inventory.get('items', [])}


def allocations_for(state, allowed_ids):
    """Use only the actual mission-issued IDs, with native per-slot fit results."""
    remaining = {str(row['id']): int(row.get('quantity', 1)) for row in state.get('inventory', []) if str(row['id']) in allowed_ids}
    result = []
    for slot in state['schematic']['slots']:
        needed = int(slot['quantity'])
        chosen = []
        for row in state.get('inventory', []):
            oid = str(row['id'])
            if int(slot['index']) not in row.get('slots', []) or remaining.get(oid, 0) <= 0:
                continue
            if int(slot['kind']) == 0 and remaining[oid] < needed:
                continue
            used = min(remaining[oid], needed)
            chosen.append(oid)
            remaining[oid] -= used
            needed -= used
            if needed == 0:
                break
        if needed and not slot.get('optional', False):
            raise AssertionError('Original mission components do not fill native slot ' + str(slot['index']))
        result.append(chosen)
    return result


class Probe:
    def __init__(self, mode, output):
        self.mode = mode
        self.output = output
        self.session = ''
        self.draft = ''
        self.accepted = set()
        self.initial_pose = None
        self.fixture = None
        self.state = {}
        self.report = dict(passed=False, native_execution=True, mocked=False, headset_tested=False,
                           grants_used=False, server_restart_tested=False,
                           session_logout_restart_tested=False, checks=[], responses=[])

    def check(self, value, label):
        self.report['checks'].append(dict(passed=bool(value), label=label))
        print(label, bool(value), flush=True)
        if not value:
            raise AssertionError(label)

    def call(self, path, **fields):
        data = dict(account=self.fixture['account'], character_id=self.fixture['id'], **fields)
        if self.session:
            data.setdefault('live_session_id' if path.startswith(('/crafting/', '/inventory/', '/session/logout')) else 'session_id', self.session)
        start = time.monotonic()
        result = req(path, data)
        self.report['responses'].append(dict(path=path, request=redact(data), seconds=time.monotonic()-start, response=redact(result)))
        if result.get('source_kind') == 'core3_services' and result.get('ok'):
            self.state = result['state']
        return result

    def service(self, action, **fields):
        if action not in ('status', 'open', 'delivery_open'):
            fields.setdefault('request_id', key())
        return self.call('/services/' + action, **fields)

    def inventory(self):
        result = self.call('/inventory/status')
        self.check(result.get('source_kind') == 'core3_inventory', 'Read actual owned native inventory')
        return result

    def start(self, location):
        result = self.call('/session/start', **pose(location))
        self.check(result.get('source_kind') == 'core3_gameplay_session' and result.get('session_live'), 'Owned normal gameplay session starts')
        self.session = result['session_id']
        ready = self.call('/session/update', **pose(location), ready=True)
        self.check(ready.get('session_live'), 'Normal native session is ready')

    def setup(self):
        if shared.BASE != 'http://127.0.0.1:18080':
            raise RuntimeError('This destructive-fixture probe permits the fixed loopback server only')
        path = ROOT / 'runtime/server/delivery-mission-fixture.json'
        if path.exists():
            self.fixture = json.loads(path.read_text())
        else:
            self.fixture = dict(account='invtestdelivery'+secrets.token_hex(4), name='Parcel'+''.join(secrets.choice('aeilnorstu') for _ in range(9)))
            result = req('/characters', dict(self.fixture, species='human', profession='crafting_artisan'))
            self.check('character' in result, 'Create dedicated original novice artisan without grants')
            self.fixture['id'] = result['character']['id']
            path.write_text(json.dumps(self.fixture, indent=2)+'\n')
        if not self.fixture['account'].startswith('invtestdelivery'):
            raise RuntimeError('Refusing a non-delivery-fixture account')
        self.report['fixture'] = self.fixture
        entered = self.call('/enter')
        self.initial_pose = entered['source_location']
        self.start(self.initial_pose)
        initial = self.service('status')
        self.check(initial.get('ok') and 'delivery_contacts' in initial.get('state', {}), 'Rebuilt native delivery snapshot is installed')
        self.check(not initial['state']['missions'], 'Dedicated fixture has no pre-existing missions to disturb')
        self.report['initial'] = initial['state']
        self.baseline = item_ids(self.inventory())
        catalog = json.loads((ROOT / 'runtime/assets/services/catalog.json').read_text())
        candidates = [t for t in catalog['static_terminals'] if t['kind']=='mission' and int(t['id'])>0]
        self.terminals = {}
        for kind, suffix in [('deliver', '/terminal_mission.iff'), ('crafting', '/terminal_mission_artisan.iff')]:
            self.terminals[kind] = min((t for t in candidates if t['template'].endswith(suffix)), key=lambda t: math.dist(t['position'], [3500, 5, -4860]))

    def accept(self, kind):
        terminal = self.terminals[kind]
        for _ in range(4):
            opened = self.service('open', terminal_id=terminal['id'], **pose(terminal))
            self.check(opened.get('ok'), 'Open original '+kind+' terminal')
            offers = [m for m in opened['state']['terminal'].get('missions', []) if m['type']==kind and m.get('supported') and not m.get('active')]
            if offers:
                break
        self.check(bool(offers), 'Original terminal generates supported '+kind+' offers')
        offer = min(offers, key=lambda m: (m['difficulty'], m['reward']))
        result = self.service('mission_accept', terminal_id=terminal['id'], mission_id=offer['id'], **pose(terminal))
        if result.get('ok'):
            self.accepted.add(offer['id'])
        self.check(result.get('ok') and any(m['id']==offer['id'] for m in result['state']['missions']), 'Original '+kind+' mission accepted')
        self.check(len([c for c in result['state']['delivery_contacts'] if c['mission_id']==offer['id']])==2, 'Original giver and receiver spawned for owned mission')
        return offer

    def contact(self, mission_id, role):
        result = self.service('status')
        return next(c for c in result['state']['delivery_contacts'] if c['mission_id']==mission_id and c['role']==role)

    def open_contact(self, contact):
        return self.service('delivery_open', npc_id=contact['id'], mission_id=contact['mission_id'], **pose(contact))

    def pickup(self, mission_id):
        giver = self.contact(mission_id, 'giver')
        before = item_ids(self.inventory())
        opened = self.open_contact(giver)
        self.check(opened.get('ok') and opened['state']['terminal'].get('dialogue') and opened['state']['terminal'].get('confirm_action')=='delivery_pickup', 'Original NPC text opens separate pickup confirmation')
        self.check(not any(p['mission_id']==mission_id for p in opened['state']['parcels']) and item_ids(self.inventory())==before, 'Read-only dialogue neither grants nor advances mission')
        response = self.service('delivery_pickup', npc_id=giver['id'], mission_id=mission_id, **pose(giver))
        self.check(response.get('ok') and response.get('mutation', {}).get('success'), 'Explicit confirm invokes original pickup objective')
        return response, item_ids(self.inventory())-before

    def complete(self, offer, parcel):
        receiver = self.contact(offer['id'], 'receiver')
        opened = self.open_contact(receiver)
        self.check(opened.get('ok') and opened['state']['terminal'].get('confirm_action')=='delivery_complete', 'Receiver recognises exact owned finished mission item')
        before = opened['state']['wallet'].copy()
        fields = dict(npc_id=receiver['id'], mission_id=offer['id'], parcel_id=parcel['id'], request_id=key(), **pose(receiver))
        wrong = dict(fields, parcel_id=next(iter(sorted(self.baseline))), request_id=key())
        self.check(self.service('delivery_complete', **wrong).get('http_error')==400, 'Unrelated actually owned item cannot replace mission parcel')
        response = self.service('delivery_complete', **fields)
        self.check(response.get('ok') and response.get('mutation',{}).get('stage')=='complete', 'Original objective accepts exact parcel handoff')
        # Original CompleteMissionObjectiveTask awards/removes on the task queue.
        deadline=time.monotonic()+12
        while any(m['id']==offer['id'] for m in self.state.get('missions',[])) and time.monotonic()<deadline:
            time.sleep(.25)
            response=self.service('status')
        self.check(response.get('ok') and not any(m['id']==offer['id'] for m in response['state']['missions']), 'Original completion task removes mission')
        after = response['state']['wallet']
        self.check(after['cash']==before['cash'] and after['bank']-before['bank']==offer['reward'], 'Exact original mission reward deposited once')
        self.check(not any(p['mission_id']==offer['id'] for p in response['state']['parcels']) and parcel['id'] not in item_ids(self.inventory()), 'Delivered actual item and datapad projection removed')
        retry = dict(fields, position=[fields['position'][0]+0.25, fields['position'][1], fields['position'][2]])
        replay = self.service('delivery_complete', **retry)
        self.check(replay.get('ok') and replay.get('mutation', {}).get('replayed') and replay['state']['wallet']==after, 'Same semantic receipt with fresh handoff pose cannot duplicate reward')
        self.accepted.discard(offer['id'])

    def cancel(self, mission_id, removed_ids=(), preserved_ids=()):
        fields = dict(mission_id=mission_id, request_id=key())
        before_state = self.service('status')['state']
        before = before_state['wallet'].copy()
        receiver = next((c for c in before_state['delivery_contacts'] if c['mission_id']==mission_id and c['role']=='receiver'), None)
        result = self.service('mission_abort', **fields)
        self.check(result.get('ok') and not any(m['id']==mission_id for m in result['state']['missions']), 'Cancel removes owned original objective')
        inv = item_ids(self.inventory())
        self.check(not set(removed_ids)&inv and set(preserved_ids)<=inv and self.baseline<=inv, 'Cancellation removes only mission-tagged objects and preserves unrelated possessions')
        self.check(not any(p['mission_id']==mission_id for p in result['state']['parcels']) and result['state']['wallet']==before, 'Cancellation clears datapad parcel without awarding credits')
        replay = self.service('mission_abort', **fields)
        self.check(replay.get('ok') and replay['state']['wallet']==before and not any(p['mission_id']==mission_id for p in replay['state']['parcels']), 'Cancellation replay returns current empty parcel projection')
        if receiver and removed_ids:
            stale = self.service('delivery_complete', npc_id=receiver['id'], mission_id=mission_id, parcel_id=next(iter(sorted(removed_ids))), **pose(receiver))
            self.check(stale.get('http_error')==400, 'Stale held parcel cannot complete an aborted mission')
        self.accepted.discard(mission_id)

    def delivery(self):
        offer = self.accept('deliver')
        giver = self.contact(offer['id'], 'giver')
        receiver = self.contact(offer['id'], 'receiver')
        wrong = self.service('delivery_pickup', npc_id=receiver['id'], mission_id=offer['id'], **pose(receiver))
        self.check(wrong.get('http_error')==400, 'Receiver cannot impersonate mission giver')
        far = pose(giver);far['position']=[giver['position'][0]+10,giver['position'][1],giver['position'][2]]
        self.check(self.service('delivery_pickup', npc_id=giver['id'], mission_id=offer['id'], **far).get('http_error')==400, 'Pickup beyond original NPC distance is rejected')
        response, added = self.pickup(offer['id'])
        parcel = next(p for p in response['state']['parcels'] if p['mission_id']==offer['id'])
        self.check(parcel['id'] in added and parcel['template'].endswith('/mission_datadisk.iff'), 'Original mission datadisk is one actual inventory object projected in datapad')
        saved = self.call('/session/logout', **pose(giver), request_id=key())
        self.check(saved.get('saved') and saved.get('session_closed'), 'Parcel-bearing character saves and logs out')
        self.session=''
        entry = self.call('/enter')
        self.start(entry['source_location'])
        persisted = self.service('status')
        self.check(any(p['id']==parcel['id'] and p['mission_id']==offer['id'] for p in persisted['state']['parcels']), 'Exact parcel persists through logout and fresh session startup')
        self.report['session_logout_restart_tested']=True
        self.complete(offer, parcel)  # Resolve fresh NPC IDs after reactivation.
        cancelled = self.accept('deliver')
        received, added = self.pickup(cancelled['id'])
        self.cancel(cancelled['id'], added)

    def craft(self, offer, component_ids, finish=True):
        giver = self.contact(offer['id'], 'giver')
        inv = self.inventory()
        tool = next(i for i in inv['items'] if i['template'].endswith('/generic_tool.iff'))
        base = dict(tool_id=tool['id'], **pose(giver))
        self.draft=key()
        opened = self.call('/crafting/open', request_id=self.draft, **base)
        self.check(opened.get('source_kind')=='core3_crafting' and opened.get('mutation',{}).get('success'), 'Original starter artisan tool opens learned recipes')
        recipes = opened['state']['schematics']
        expected = giver['expected_template'].replace('/shared_', '/')
        recipe = next((r for r in recipes if r['template'].replace('/shared_', '/')==expected), None)
        self.check(recipe is not None, 'Original rewarded mission schematic is usable with starter tool')
        selected = self.call('/crafting/select', session_id=self.draft, request_id=key(), index=recipe['index'], **base)
        self.check(selected.get('source_kind')=='core3_crafting' and selected['state'].get('stage')==2, 'Actual mission output recipe selects native ingredient slots')
        allocations = allocations_for(selected['state'], component_ids)
        assembled = self.call('/crafting/assemble', session_id=self.draft, request_id=key(), allocations=allocations, **base)
        self.check(assembled.get('source_kind')=='core3_crafting' and assembled.get('mutation',{}).get('success'), 'Original issued components pass native assembly')
        current = assembled
        if finish and current['state'].get('stage') in (3,4):
            current = self.call('/crafting/finish', session_id=self.draft, request_id=key(), points=[], colors=[], **base)
            self.check(current.get('source_kind')=='core3_crafting' and current.get('mutation',{}).get('success'), 'Native crafting finishes without invented statistics')
        if current['state'].get('jobs'):
            self.draft=''
        if not finish:
            return current
        jobs = current['state'].get('jobs', [])
        self.check(bool(jobs), 'Original timed crafting job owns real prototype')
        deadline=time.monotonic()+min(180,max(20,max(j['due'] for j in jobs)-int(time.time())+15))
        while time.monotonic()<deadline:
            status=self.call('/crafting/status')
            if not status.get('state',{}).get('jobs'):
                break
            time.sleep(1)
        self.check(not status.get('state',{}).get('jobs'), 'Original timed crafting production completes')
        result=self.service('status')
        parcel=next((p for p in result['state']['parcels'] if p['mission_id']==offer['id']),None)
        self.check(parcel is not None and parcel['template'].replace('/shared_','/')==expected and parcel['id'] in item_ids(self.inventory()), 'Only original finished mission-tagged output becomes draggable parcel')
        return parcel

    def crafting(self):
        offer=self.accept('crafting')
        response, components=self.pickup(offer['id'])
        self.check(bool(components) and not any(p['mission_id']==offer['id'] for p in response['state']['parcels']), 'Craft giver issues components and recipe, not a fictitious completed parcel')
        parcel=self.craft(offer,components)
        self.complete(offer,parcel)
        # A second original mission supplies unrelated mission items which must
        # survive the first mission's escrow/job cancellation.
        cancelled=self.accept('crafting');_,components=self.pickup(cancelled['id'])
        survivor=self.accept('crafting');_,other_components=self.pickup(survivor['id'])
        staged=self.craft(cancelled,components,finish=False)
        jobs=staged['state'].get('jobs',[])
        self.report['craft_cancel_phase']='timed_job' if jobs else 'assembled_escrow'
        prototype_ids={j['prototype_id'] for j in jobs}
        due=max((j['due'] for j in jobs),default=int(time.time()))
        self.cancel(cancelled['id'],components|prototype_ids,other_components)
        self.draft=''
        status=self.call('/crafting/status')
        self.check(not any(j['prototype_id'] in prototype_ids for j in status['state'].get('jobs',[])) and not status['state'].get('session_id'), 'Cancelled mission clears matching native craft escrow or timed job')
        deadline=time.monotonic()+min(180,max(1,due-int(time.time())+2))
        while time.monotonic()<deadline:
            time.sleep(min(1,deadline-time.monotonic()))
        settled=self.call('/crafting/status')
        inv=item_ids(self.inventory())
        self.check(not prototype_ids&inv and other_components<=inv, 'Old native completion timer cannot recreate cancelled output or consume other mission items')
        self.cancel(survivor['id'],other_components)

    def cleanup(self):
        errors=[]
        if not self.fixture or not self.initial_pose:
            return
        for mission_id in list(self.accepted):
            try:
                current=self.service('status')
                if current.get('ok') and not any(m['id']==mission_id for m in current['state']['missions']):
                    continue
                result=self.service('mission_abort',mission_id=mission_id)
                if not result.get('ok'):
                    raise RuntimeError(result.get('error',str(result)))
            except Exception as error:
                errors.append('mission '+mission_id+': '+str(error))
        if self.draft:
            try:
                self.call('/crafting/cancel',session_id=self.draft,request_id=key())
            except Exception as error:
                errors.append('draft: '+str(error))
        try:
            result=self.call('/session/logout',**pose(self.initial_pose),request_id=key())
            if not result.get('saved') or not result.get('session_closed'):
                raise RuntimeError(str(result))
            self.session=''
        except Exception as error:
            errors.append('restore: '+str(error))
        self.report['cleanup_errors']=errors
        self.report['original_pose_restored']=not errors

    def run(self):
        try:
            self.setup()
            if self.mode in ('all','delivery'):
                self.delivery()
            if self.mode in ('all','crafting'):
                self.crafting()
            self.report['passed']=True
        except Exception as error:
            self.report['error']=str(error)
        finally:
            self.cleanup()
            self.report['passed']=self.report['passed'] and not self.report.get('cleanup_errors')
            self.output.parent.mkdir(parents=True,exist_ok=True)
            self.output.write_text(json.dumps(redact(self.report),indent=2)+'\n')
            print(json.dumps({k:self.report.get(k) for k in ('passed','error','cleanup_errors','craft_cancel_phase')}),flush=True)
        return 0 if self.report['passed'] else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-native',action='store_true',required=True,help='Explicitly mutate only the dedicated local test fixture')
    parser.add_argument('--mode',choices=('all','delivery','crafting'),default='all')
    parser.add_argument('--output',type=Path,default=ROOT/'runtime/evidence/delivery-mission-native.json')
    args=parser.parse_args()
    return Probe(args.mode,args.output).run()


if __name__=='__main__':
    raise SystemExit(main())
