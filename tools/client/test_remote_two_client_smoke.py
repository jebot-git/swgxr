"""Orchestration tests only; actual Core3 execution is a separate explicit run."""
import json
import unittest
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch
import urllib.error
from tools.client.remote_two_client_smoke import Simulation


class FakeConnection:
    base_url = 'https://127.0.0.1:18443'
    def __init__(self, index, world, fail_start=False):
        self.index=index;self.account=['nettest_one','nettest_two'][index];self.world=world
        self.oid=str(100+index);self.created=False;self.sequence=0;self.stopped=False;self.fail_start=fail_start
        self.paths=[];self.ready=False;self.ready_requests=[]
        self.location={'position':[3511+self.index,5,-4927],'building_id':'0','cell_index':0,'heading_radians':0}
    def request_json(self,path,method='GET',body=None,timeout=90):
        self.paths.append(path)
        if path=='/health':return {'backend':'core3','core3':{'ready':True}}
        if path=='/creation-options':return {'professions':[{'id':'combat_marksman'}]}
        if path.startswith('/characters?'):return {'backend':'core3','characters':[{'id':self.oid}] if self.created else []}
        if path=='/characters':self.created=True;return {'backend':'core3','character':{'id':self.oid}}
        if path.startswith('/characters/'):return {'backend':'core3','character':{'id':self.oid}}
        if path=='/enter':return {'backend':'core3','core3_zone_verified':True,'character_id':self.oid,'source_location':dict(self.location)}
        if path=='/session/logout':
            self.stopped=True;self.world.discard(self.oid)
            self.location={key:body[key] for key in self.location}
            return {'saved':True,'session_closed':True}
        if path=='/combat/session/start' and self.fail_start:raise ValueError('PrivateSecretMustNeverAppear')
        if path.startswith('/combat/session/') or path in ('/session/start','/session/update'):
            self.sequence+=1
            if path.endswith('/stop'):self.stopped=True
            if path.endswith('/update'):
                self.ready_requests.append(body.get('ready'))
                if body.get('ready') is True:self.ready=True;self.world.add(self.oid)
            return {'source_kind':'core3_gameplay_session' if path.startswith('/session/') else 'core3_live_combat','character_id':self.oid,'session_id':'session'+self.oid,
                    'session_live':not self.stopped,'sequence':self.sequence,
                    'snapshot':{'player':{'on_load_screen':not self.ready},'world':{'players':[{'id':oid} for oid in self.world if oid!=self.oid]}}}
        if path=='/services/status':
            self.sequence+=1
            return {'source_kind':'core3_services','live_response':{'session_live':True,'sequence':self.sequence},
                    'presence':{'token':'PrivatePresenceMustNeverAppear','sequence_floor':-1},
                    'state':{'player':{'position':[3511+self.index,5,-4927],'building_id':'0','cell_index':0}}}
        if path=='/services/presence':
            self.world.add(self.oid)
            return {'source_kind':'authenticated_hand_presence','peers':[{'id':oid,'fresh':True} for oid in self.world if oid!=self.oid]}
        raise AssertionError('Unexpected protocol path')


class RemoteSimulationTest(unittest.TestCase):
    def test_two_native_protocol_flows_and_persistence(self):
        world=set();clients=[FakeConnection(i,world) for i in range(2)]
        report=Simulation(clients,rounds=2).run()
        self.assertTrue(report['passed']);self.assertTrue(all(c.stopped for c in clients))
        self.assertGreater(len(report['checks']),20)
        for client in clients:
            self.assertEqual(client.paths.count('/characters'),1)
            self.assertEqual(client.paths[-1],'/characters?account='+client.account)
        self.assertNotIn('PrivatePresence',json.dumps(report))
    def test_failure_stops_already_started_session_and_does_not_echo_secrets(self):
        world=set();clients=[FakeConnection(0,world),FakeConnection(1,world,fail_start=True)]
        report=Simulation(clients).run()
        self.assertFalse(report['passed']);self.assertTrue(clients[0].stopped)
        self.assertNotIn('PrivateSecret',json.dumps(report))
        self.assertEqual(report['failure_type'],'ValueError')
    def test_concurrent_probe_requires_native_capability_before_ready_sweep(self):
        simulation=Simulation([FakeConnection(i,set()) for i in range(2)],gameplay=True,native_schedule='concurrent')
        client=simulation.clients[0];client['id']='100'
        with self.assertRaisesRegex(AssertionError,'actual owned native start'):
            simulation.start(client)
        self.assertEqual(client['session'],'session100') # Identity retained for cleanup.
        self.assertNotIn('/session/update',client['connection'].paths)
    def test_fair_native_turn_never_batches_all_optional_reads(self):
        simulation=Simulation([FakeConnection(i,set()) for i in range(2)])
        simulation.snapshot=Mock();simulation.inventory_status=Mock();simulation.register_presence=Mock()
        clients=simulation.clients
        for turn in range(8):
            for client in clients:simulation.fair_native_step(client)
        self.assertEqual(simulation.snapshot.call_count,12)
        self.assertEqual(simulation.inventory_status.call_count,2)
        self.assertEqual(simulation.register_presence.call_count,2)
        self.assertTrue(all(c['maintenance_tick']==8 for c in clients))
    def test_concurrent_worker_keeps_three_second_heartbeat_and_records_optional_admission(self):
        simulation=Simulation([FakeConnection(i,set()) for i in range(2)],native_schedule='concurrent')
        now=[0.0];heartbeats=[]
        class Stop:
            stopped=False
            def is_set(self):return self.stopped
            def set(self):self.stopped=True
            def wait(self,seconds):now[0]+=max(0,seconds);return self.stopped
        stop=Stop()
        def heartbeat(client):heartbeats.append(now[0]);now[0]+=.2
        busy=urllib.error.HTTPError('https://example.invalid',503,'Busy',{},None)
        busy.safe_diagnostic={'http_status':503,'server_error':'Inventory refresh waits for an authoritative transaction; retain last confirmed readout'}
        simulation.snapshot=heartbeat
        simulation.inventory_status=Mock(side_effect=[busy,None])
        simulation.register_presence=Mock()
        with patch('tools.client.remote_two_client_smoke.time.monotonic',side_effect=lambda:now[0]):
            simulation.concurrent_native_loop(simulation.clients[0],stop,24)
        self.assertEqual(heartbeats,[0,3,6,9,12,15,18,21])
        self.assertEqual(len(simulation.optional_deferrals),1)
        self.assertFalse(simulation.native_errors)
        self.assertEqual(simulation.clients[0]['soak_optional_reads'],2)
        busy.close()
    def test_private_checkpoint_retains_exact_restore_receipt_without_credentials(self):
        world=set();clients=[FakeConnection(i,world) for i in range(2)]
        for client in clients:client.created=True
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'recovery.json'
            report=Simulation(clients,rounds=1,require_existing=True,gameplay=True,checkpoint=path).run()
            self.assertTrue(report['passed'])
            self.assertEqual(path.stat().st_mode & 0o777,0o600)
            saved=json.loads(path.read_text())
            self.assertTrue(all(c['restored'] and len(c['logout_request_id'])==32 for c in saved['clients']))
            self.assertEqual(saved['clients'][0]['saved_location'],clients[0].location)
            self.assertNotIn('password',path.read_text())
            self.assertNotIn(saved['clients'][0]['logout_request_id'],json.dumps(report))
    def test_refuses_non_fixture_accounts(self):
        clients=[FakeConnection(i,set()) for i in range(2)];clients[0].account='blux'
        with self.assertRaises(ValueError):Simulation(clients)
        self.assertFalse(any(c.paths for c in clients))
    def test_restart_mode_cannot_recreate_missing_character(self):
        clients=[FakeConnection(i,set()) for i in range(2)]
        report=Simulation(clients,require_existing=True).run()
        self.assertFalse(report['passed'])
        self.assertFalse(any('/characters' in c.paths for c in clients))
        self.assertFalse(any(c.created for c in clients))
        self.assertIn('survived backend restart',report['checks'][-1]['label'])
    def test_restart_mode_reuses_existing_native_characters(self):
        world=set();clients=[FakeConnection(i,world) for i in range(2)]
        for client in clients:client.created=True
        report=Simulation(clients,rounds=1,require_existing=True).run()
        self.assertTrue(report['passed'])
        self.assertTrue(report['require_existing'])
        self.assertFalse(any('/characters' in c.paths for c in clients))
    def test_gameplay_probe_enters_original_scene_before_visibility_checks(self):
        world=set();clients=[FakeConnection(i,world) for i in range(2)]
        for client in clients:client.created=True
        report=Simulation(clients,rounds=1,require_existing=True,gameplay=True).run()
        self.assertTrue(report['passed'])
        self.assertTrue(all(client.ready_requests and all(client.ready_requests) for client in clients))
        self.assertTrue(all(client.stopped for client in clients))
        visible=[check for check in report['checks'] if 'all test peers visible' in check['label']]
        self.assertEqual(len(visible),2)
        self.assertTrue(all(check['passed'] for check in visible))


if __name__=='__main__':unittest.main()
