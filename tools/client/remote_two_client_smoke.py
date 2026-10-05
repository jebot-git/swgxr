#!/usr/bin/env python3
"""Two to ten authenticated native clients over verified HTTPS; no game or XR launch.

Uses only dedicated nettest_one/nettest_two/nettest_p03–p10 accounts. Creates one persistent
character on an empty account, reuses it on later runs, stops its own sessions,
and leaves Core3 running. Evidence contains summaries, never credentials/poses.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import secrets
import statistics
import string
import threading
import time
import urllib.error

if __package__:
    from .remote_connection import RemoteConnection
else:
    from remote_connection import RemoteConnection

ROOT = Path(__file__).resolve().parents[2]


class Simulation:
    def __init__(self, connections, rounds=4, require_existing=False, gameplay=False, duration=0, sync_rate=0, checkpoint=None, native_schedule="fair"):
        allowed = {'nettest_one', 'nettest_two'} | {'nettest_p%02d' % n for n in range(3, 11)}
        if not 2 <= len(connections) <= 10 or len({c.account for c in connections}) != len(connections) or any(c.account not in allowed for c in connections):
            raise ValueError('Use two to ten distinct dedicated network-test profiles.')
        if len({c.base_url for c in connections}) != 1:
            raise ValueError('Both simulated clients must use the same verified HTTPS origin.')
        self.clients = [{'connection': c, 'id': '', 'session': '', 'position': [3511 + .25*i, 5, -4927]}
                        for i, c in enumerate(connections)]
        self.native_schedule=native_schedule
        self.native_errors=[]
        self.optional_deferrals=[]
        self.checkpoint = checkpoint
        self.started_at = time.monotonic()
        self.sync_rate = sync_rate
        self.sync_errors = []
        self.sync_counts = {}
        self.gameplay = gameplay
        self.duration = duration
        self.rounds = rounds
        self.require_existing = require_existing
        self.lock = threading.Lock()
        self.report = {'passed': False, 'endpoint': connections[0].base_url,
                       'native_execution': True, 'client_count': len(connections),
                       'require_existing': require_existing, 'gameplay_sessions': gameplay, 'requested_soak_seconds': duration, 'requested_sync_hz_per_client': sync_rate,
                       'rendering': 'none; protocol simulation only', 'xr': 'not launched',
                       'checks': [], 'requests': [], 'cleanup': []}

    def check(self, condition, label):
        with self.lock:
            self.report['checks'].append({'passed': bool(condition), 'label': label})
        if not condition:
            raise AssertionError(label)

    def call(self, client, path, body=None):
        start = time.monotonic()
        record = {'client': self.clients.index(client) + 1, 'path': path.split('?')[0],
                  'method': 'GET' if body is None else 'POST', 'success': False,
                  'started_seconds': round(start-self.started_at, 3)}
        try:
            result = client['connection'].request_json(path, method=record['method'], body=body, timeout=90)
            record['success'] = True
            if path in ('/session/update','/inventory/status','/services/status'):
                now=time.monotonic()
                if 'native_at' in client:
                    client.setdefault('native_gaps',[]).append(now-client['native_at'])
                client['native_at']=now
            if path == '/health':
                record['backend'] = result.get('backend')
                record['native_ready'] = result.get('core3', {}).get('ready')
            return result
        except urllib.error.HTTPError as exc:
            record['http_status'] = exc.code
            record.update(getattr(exc, 'safe_diagnostic', {}))
            raise
        finally:
            record['milliseconds'] = round((time.monotonic() - start) * 1000, 2)
            with self.lock:
                self.report['requests'].append(record)

    def save_checkpoint(self):
        # Separate ignored recovery file, never public evidence or credentials.
        if self.checkpoint is None:return
        self.checkpoint.parent.mkdir(parents=True,exist_ok=True)
        rows=[{key:c.get(key) for key in ('id','session','saved_location','logout_request_id','restored')}
              | {'account':c['connection'].account} for c in self.clients]
        temp=self.checkpoint.with_suffix('.tmp')
        with open(os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as stream:
            json.dump({'version':1,'endpoint':self.report['endpoint'],'clients':rows},stream)
        temp.chmod(0o600);temp.replace(self.checkpoint)

    def inventory_status(self, client):
        inventory=self.call(client,'/inventory/status',dict(self.identity(client),live_session_id=client['session']))
        self.check(inventory.get('source_kind')=='core3_inventory' and str(inventory.get('character_id'))==client['id'],
                   client['connection'].account+': owned inventory stays usable without session replacement')

    def fair_native_step(self, client):
        # One bounded operation per player per turn. Optional reads replace a
        # stationary heartbeat because they publish the same native world state.
        # Never stall every player's heartbeat behind one all-account UI batch.
        tick=client.get('maintenance_tick',0)
        if tick % 8 == 1:self.inventory_status(client)
        elif tick % 8 == 3:self.register_presence(client)
        else:self.snapshot(client)
        client['maintenance_tick']=tick+1

    def identity(self, client):
        return {'account': client['connection'].account, 'character_id': client['id']}

    def prepare(self, client):
        account = client['connection'].account
        health = self.call(client, '/health')
        self.check(health.get('backend') == 'core3' and health.get('core3', {}).get('ready') is True,
                   account + ': authenticated native readiness')
        listing = self.call(client, '/characters?account=' + account)
        self.check(listing.get('backend') == 'core3' and isinstance(listing.get('characters'), list),
                   account + ': original native character list')
        characters = listing['characters']
        if self.require_existing:
            self.check(bool(characters), account + ': existing character survived backend restart')
        if not characters:
            options = self.call(client, '/creation-options')
            self.check('combat_marksman' in {row['id'] for row in options.get('professions', [])},
                       account + ': original Marksman creation option available')
            suffix = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(8))
            name = 'Net' + suffix
            try:
                created = self.call(client, '/characters', {'account': account, 'name': name,
                                    'species': 'human', 'sex': 'male', 'profession': 'combat_marksman'})
            except urllib.error.HTTPError as exc:
                if exc.code < 500:raise
                # Creation may have committed before a follow-up read failed.
                # Reconcile once from Core3; never submit another creation.
                listing = self.call(client, '/characters?account=' + account)
                matching = [c for c in listing.get('characters', []) if c.get('name', '').lower() == name.lower()]
                if len(matching) != 1:raise
                created = {'backend':'core3','character':matching[0]}
                self.report.setdefault('reconciled_creation_receipts',[]).append(self.clients.index(client)+1)
            self.check(created.get('backend') == 'core3' and bool(created.get('character', {}).get('id')),
                       account + ': persistent native character created')
            client['id'] = str(created['character']['id'])
        else:
            client['id'] = str(characters[0]['id'])
        listing = self.call(client, '/characters?account=' + account)
        self.check(client['id'] in {str(c['id']) for c in listing.get('characters', [])},
                   account + ': character persisted across fresh login')
        selected = self.call(client, '/characters/' + client['id'] + '?account=' + account)
        self.check(selected.get('backend') == 'core3' and str(selected.get('character', {}).get('id')) == client['id'],
                   account + ': original owned character selection')
        entry = self.call(client, '/enter', self.identity(client))
        client['saved_location'] = entry.get('source_location', {})
        client['logout_request_id'] = secrets.token_hex(16)
        self.save_checkpoint()
        self.check(entry.get('backend') == 'core3' and entry.get('core3_zone_verified') is True
                   and str(entry.get('character_id')) == client['id'], account + ': native zone entry confirmed')

    def start(self, client):
        response = self.call(client, '/session/start' if self.gameplay else '/combat/session/start', dict(self.identity(client),
                             position=client['position'], heading_radians=0, spawn_test_lair=False))
        # Keep cleanup identity even when a later assertion fails.
        client['session'] = str(response.get('session_id', ''))
        self.save_checkpoint()
        self.check(response.get('source_kind') == ('core3_gameplay_session' if self.gameplay else 'core3_live_combat') and response.get('session_live') is True
                   and str(response.get('character_id')) == client['id'] and bool(client['session']),
                   client['connection'].account + ': persistent native session established')
        client['sequence'] = int(response.get('sequence', 0))
        if self.native_schedule=='concurrent':
            self.check(response.get('native_concurrency')=='engine_cross_lock_v1',
                       client['connection'].account+': actual owned native start advertises safe cross-lock concurrency')

    def snapshot(self, client):
        response = self.call(client, '/session/update' if self.gameplay else '/combat/session/update', dict(self.identity(client),
                             session_id=client['session'], position=client['position'],
                             heading_radians=0, building_id='0', cell_index=0, ready=True))
        self.check(response.get('session_live') is True and response.get('session_id') == client['session']
                   and str(response.get('character_id')) == client['id']
                   and int(response.get('sequence', 0)) > client['sequence'],
                   client['connection'].account + ': simultaneous session identity and sequence retained')
        client['sequence'] = int(response['sequence'])
        snapshot = response.get('snapshot', {})
        self.check(snapshot.get('player', {}).get('on_load_screen') is False,
                   client['connection'].account + ': original native scene-ready transition completed')
        client['visible_players'] = {str(row['id']) for row in snapshot.get('world', {}).get('players', [])}

    def register_presence(self, client):
        response = self.call(client, '/services/status', dict(self.identity(client),
                             session_id=client['session'], position=client['position'], building_id='0', cell_index=0))
        self.check(response.get('source_kind') == 'core3_services'
                   and response.get('live_response', {}).get('session_live') is True
                   and bool(response.get('presence', {}).get('token')),
                   client['connection'].account + ': hand presence backed by owned live Core3 state')
        client['presence'] = response['presence']
        client['native_player'] = response['state']['player']
        client['sequence'] = int(response['live_response']['sequence'])

    def pose(self, client):
        registration = client['presence']
        registration['sequence_floor'] = int(registration.get('sequence_floor', -1)) + 1
        player = client['native_player']
        position = player['position']
        body = dict(self.identity(client), token=registration['token'], sequence=registration['sequence_floor'],
                    position=position, building_id=str(player.get('building_id', '0')), cell_index=player.get('cell_index', 0),
                    hand={'position': [position[0], position[1]+1.2, position[2]], 'tracked': True, 'grip': False}, wallet_held=False)
        response = self.call(client, '/services/presence', body)
        self.check(response.get('source_kind') == 'authenticated_hand_presence', 'Synthetic hand pose authenticated')
        return response.get('peers', [])

    def presentation_loop(self, client, stop):
        sequence = 0
        revision = -1
        events = -1
        seen = set()
        count = 0
        started = time.monotonic()
        while not stop.is_set():
            stamp = time.monotonic()
            sequence += 1
            p = client['position']
            tracking = {name: {'tracked': True, 'position': [p[0]+x,p[1]+y,p[2]], 'rotation':[0,0,0,1]}
                        for name,x,y in [('head',0,1.7),('left_hand',-.3,1.2),('right_hand',.3,1.2)]}
            try:
                response = self.call(client, '/session/sync', dict(self.identity(client), session_id=client['session'],
                                     sequence=sequence, world_revision=revision, event_sequence=events, position=p,
                                     heading_radians=0, building_id='0', cell_index=0, tracking=tracking))
                if not (response.get('source_kind') == 'core3_multiplayer_sync' and response.get('session_id') == client['session']
                        and str(response.get('character_id')) == client['id'] and response.get('sequence') == sequence):
                    raise AssertionError('Multiplayer presentation owner/sequence mismatch')
                revision = response['world_revision'];events=response['event_sequence']
                if response.get('world') is not None:
                    world = response['world']
                    if not (world.get('source_kind') == 'core3_world' and world.get('full') is True
                            and len(world.get('players', [])) <= 16 and len(world.get('actors', [])) <= 96):
                        raise AssertionError('Native public world contract mismatch')
                for peer in response.get('poses', []):
                    if str(peer.get('id')) != client['id'] and peer.get('tracking', {}).get('head', {}).get('tracked'):
                        seen.add(str(peer['id']))
                count += 1
            except Exception as exc:
                error = {'client': self.clients.index(client)+1, 'failure_type': type(exc).__name__,
                         'elapsed_seconds': round(time.monotonic()-started, 3)}
                error.update(getattr(exc, 'safe_diagnostic', {}))
                with self.lock:self.sync_errors.append(error)
                stop.set()
                break
            stop.wait(max(0,1/self.sync_rate-(time.monotonic()-stamp)))
        elapsed = time.monotonic()-started
        with self.lock:self.sync_counts[client['connection'].account]={'responses':count,'elapsed_seconds':round(elapsed, 3),
            'achieved_hz':round(count/max(elapsed, .001), 3), 'seen_other_players':len(seen),
            'all_test_peers_seen':{c['id']for c in self.clients if c is not client} <= seen}

    def concurrent_native_loop(self, client, stop, until):
        index=self.clients.index(client)
        due=time.monotonic()+index*3/len(self.clients)
        reads=0
        optional_due=due+3+index
        while not stop.is_set() and time.monotonic()<until:
            if stop.wait(max(0,min(due,until)-time.monotonic())):break
            if time.monotonic()>=until:break
            try:
                self.snapshot(client)
                client['soak_heartbeats']=client.get('soak_heartbeats',0)+1
                due=max(due+3,time.monotonic())
                if time.monotonic()>=optional_due:
                    try:
                        if reads % 2==0:self.inventory_status(client)
                        else:self.register_presence(client)
                        reads+=1
                        client['soak_optional_reads']=reads
                        optional_due=time.monotonic()+12
                    except urllib.error.HTTPError as exc:
                        diagnostic=getattr(exc,'safe_diagnostic',{})
                        if exc.code!=503 or diagnostic.get('server_error') not in (
                            'Inventory refresh waits for an authoritative transaction; retain last confirmed readout',
                            'Core3 is processing another request; retry shortly',
                            'Core3 request queue is full; retry shortly'):raise
                        with self.lock:self.optional_deferrals.append({'client':index+1,**diagnostic})
                        optional_due=time.monotonic()+3
            except Exception as exc:
                with self.lock:self.native_errors.append({'client':index+1,'failure_type':type(exc).__name__,**getattr(exc,'safe_diagnostic',{})})
                stop.set();return

    def run(self):
        started = time.monotonic()
        sync_stop=threading.Event()
        sync_pool=None
        try:
            # Original legacy selection is completed before persistent sessions own these accounts.
            for client in self.clients:
                self.prepare(client)
            for client in self.clients:
                self.start(client)
            self.check(len({c['id'] for c in self.clients}) == len(self.clients)
                       and len({c['session'] for c in self.clients}) == len(self.clients), 'Accounts own distinct native characters and sessions')
            with ThreadPoolExecutor(max_workers=min(4,len(self.clients))) as pool:
                for _ in range(self.rounds):
                    list(pool.map(self.snapshot, self.clients))
                if self.gameplay:
                    # The first ready sweep can observe later clients still loading.
                    list(pool.map(self.snapshot, self.clients))
            if self.gameplay:
                for client in self.clients:
                    self.check({other['id'] for other in self.clients if other is not client} <= client['visible_players'],
                               client['connection'].account + ': all test peers visible through original native world after scene readiness')
            for client in self.clients:
                self.register_presence(client)
            seen = [False] * len(self.clients)
            for _ in range(3):
                for index, client in enumerate(self.clients):
                    peers = self.pose(client)
                    seen[index] |= any(str(peer.get('id')) in {other['id'] for other in self.clients if other is not client} and peer.get('fresh') for peer in peers)
            self.check(all(seen), 'All authenticated clients observe another fresh native-owned player')
            if self.sync_rate:
                sync_pool=ThreadPoolExecutor(max_workers=len(self.clients))
                for client in self.clients:sync_pool.submit(self.presentation_loop,client,sync_stop)
            soak_start = time.monotonic()
            if self.native_schedule=='concurrent':
                with ThreadPoolExecutor(max_workers=len(self.clients)) as native_pool:
                    futures=[native_pool.submit(self.concurrent_native_loop,c,sync_stop,soak_start+self.duration) for c in self.clients]
                    for future in futures:future.result()
                self.check(not self.native_errors,'Independent 3s owned native heartbeats remained available')
                self.check(all(c.get('soak_heartbeats',0)>10 and c.get('soak_optional_reads',0)>=2 for c in self.clients),
                           'Every player retained heartbeat plus inventory and service access during concurrent load')
            else:
                cursor=0
                while time.monotonic()-soak_start < self.duration:
                    if sync_pool and sync_stop.is_set():
                        raise AssertionError('Presentation worker failed; bounded soak stopped before further load')
                    client=self.clients[cursor % len(self.clients)]
                    # Request 3s stationary refresh, with bounded one-operation
                    # admission. Report achieved cadence; do not claim active combat.
                    due=client.get('native_at',0)+3
                    if due>time.monotonic():sync_stop.wait(min(due-time.monotonic(),max(0,self.duration-(time.monotonic()-soak_start))))
                    if time.monotonic()-soak_start>=self.duration:break
                    self.fair_native_step(client)
                    cursor+=1
            self.report['soak_seconds'] = round(time.monotonic() - soak_start, 2)
            if sync_pool:
                sync_stop.set();sync_pool.shutdown(wait=True);sync_pool=None
                self.check(not self.sync_errors, 'High-rate presentation path remained available during native transactions')
                self.check(all(v['all_test_peers_seen'] and v['responses']>10 for v in self.sync_counts.values()), 'Every client received every other test player tracked pose from native visibility')
            for client in self.clients:
                self.snapshot(client)
            self.report['passed'] = True
        except Exception as exc:
            # Never serialize exception text: a remote body or URL could contain private data.
            self.report['failure_type'] = type(exc).__name__
        finally:
            sync_stop.set()
            if sync_pool:sync_pool.shutdown(wait=True)
            self.report['presentation']=self.sync_counts
            self.report['presentation_errors']=self.sync_errors
            self.report['native_schedule']=self.native_schedule
            self.report['native_errors']=self.native_errors
            self.report['optional_read_deferrals']=self.optional_deferrals
            for client in self.clients:
                if client['session']:
                    try:
                        if self.gameplay:
                            saved = client['saved_location']
                            pose = {key: saved[key] for key in ('position', 'building_id', 'cell_index', 'heading_radians')}
                            response = self.call(client, '/session/logout', dict(self.identity(client), **pose, live_session_id=client['session'], request_id=client['logout_request_id']))
                            stopped = response.get('saved') is True and response.get('session_closed') is True
                        else:
                            response = self.call(client, '/combat/session/stop', dict(self.identity(client), session_id=client['session']))
                            stopped = response.get('session_live') is False
                    except Exception:
                        stopped = False
                    client['restored']=stopped
                    self.save_checkpoint()
                    self.report['cleanup'].append({'client': self.clients.index(client)+1, 'session_stopped': stopped})
                    self.report['passed'] &= stopped
            if self.report['passed']:
                try:
                    for client in self.clients:
                        rows = self.call(client, '/characters?account=' + client['connection'].account)
                        self.check(client['id'] in {str(c['id']) for c in rows.get('characters', [])},
                                   client['connection'].account + ': persistence after simultaneous sessions close')
                        if self.gameplay:
                            entry = self.call(client, '/enter', self.identity(client))
                            location = entry.get('source_location', {})
                            original = client['saved_location']
                            self.check(location.get('building_id') == original['building_id'] and location.get('cell_index') == original['cell_index']
                                       and math.dist(location.get('position', []), original['position']) < .02,
                                       client['connection'].account + ': original saved location restored after simultaneous gameplay logout')
                except Exception as exc:
                    self.report['passed'] = False
                    self.report['failure_type'] = type(exc).__name__
            self.report['native_refresh']={str(i+1):{'count':len(c.get('native_gaps',[])),'soak_heartbeats':c.get('soak_heartbeats',0),'soak_optional_reads':c.get('soak_optional_reads',0),
                'max_gap_seconds':round(max(c.get('native_gaps',[0])),3),
                'median_gap_seconds':round(statistics.median(c.get('native_gaps',[0])),3)} for i,c in enumerate(self.clients)}
            self.report['native_load_note']=('Independent 3s stationary heartbeat per account with staggered optional reads and explicitly counted admission deferrals.' if self.native_schedule=='concurrent' else 'Stationary fair round-robin with 3s desired refresh and periodic inventory/services replacing heartbeat.')+' Actual cadence reported. Ten-player active combat is not proven.'
            durations = [r['milliseconds'] for r in self.report['requests']]
            self.report['timing'] = {'wall_seconds': round(time.monotonic()-started, 3), 'request_count': len(durations),
                'request_median_ms': round(statistics.median(durations), 2) if durations else 0,
                'request_max_ms': max(durations, default=0),
                'note': 'Native commands are serialized server-side; these are transport+native-operation timings, not FPS.'}
        return self.report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profiles', nargs='+', type=Path, default=[ROOT/'runtime/deploy/credentials'/name for name in ('nettest_one.json', 'nettest_two.json')])
    parser.add_argument('--evidence', type=Path, default=ROOT/'runtime/evidence/remote-client/two-client-native.json')
    parser.add_argument('--rounds', type=int, choices=range(1, 21), default=4)
    parser.add_argument('--require-existing', action='store_true', help='Fail on an empty account; never create replacement characters.')
    parser.add_argument('--gameplay', action='store_true', help='Use normal persistent gameplay sessions and save/restore original test character locations.')
    parser.add_argument('--duration', type=int, choices=range(0, 601), default=0, help='Keep all sessions active with mixed reads for this many seconds (max600).')
    parser.add_argument('--sync-rate', type=int, choices=(0,2,5,10), default=0, help='Authenticated presentation polling per client during soak.')
    parser.add_argument('--native-schedule',choices=('fair','concurrent'),default='fair')
    args = parser.parse_args()
    try:
        simulation = Simulation([RemoteConnection.load(path) for path in args.profiles], args.rounds, args.require_existing, args.gameplay, args.duration, args.sync_rate, ROOT/'runtime/deploy/recovery'/('nettest-'+str(time.time_ns())+'.json'), args.native_schedule)
        report = simulation.run()
    except Exception as exc:
        report = {'passed': False, 'failure_type': type(exc).__name__}
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'passed': report['passed'], 'checks': len(report.get('checks', [])),
                      'timing': report.get('timing', {}), 'evidence': str(args.evidence)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
