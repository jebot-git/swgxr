import io
import json
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch
from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import BackendBusy
from server.capacity import configured_limit
from tools.deploy import runtime
from tools.deploy.capacity import PROFILE, ALL_PLANETS_PROFILE, JTL_TEST_PROFILE, host_readiness, configuration_status
from tools.deploy.prepare_capacity_profile import prepare
from tools.server import native_build_receipt as build
from tools.server import population_smoke


class CapacityTests(unittest.TestCase):
    def test_jtl_test_profile_is_bounded_and_registration_explicit(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'old';source.mkdir();dest=Path(folder)/'jtl'
            (source/'config-local.lua').write_text(runtime.render_config((runtime.BIN/'conf/config-local.lua').read_text(),'b'*64))
            (source/'resource_manager.lua').write_text(runtime.render_resources((runtime.BIN/'scripts/managers/resource_manager.lua').read_text()))
            report=prepare(dest,source,JTL_TEST_PROFILE)
            self.assertTrue(configuration_status(dest)['passed'])
            self.assertEqual(report['space_zones'],['space_tatooine'])
            settings=json.loads((dest/'gateway-registration.json').read_text())
            self.assertEqual(settings,dict(registration_enabled=True,registration_invites_required=False,registration_grants_client_access=True))
            self.assertFalse(report['live_configuration_changed'])
            config=(dest/'config-local.lua').read_text()
            self.assertIn('Core3.SpaceZonesEnabled = {"space_tatooine"}',config)
            self.assertIn('Core3.SWGXR.RetailGroundOnly = false',config)
            (dest/'config-local.lua').write_text(config.replace('Core3.SWGXR.RetailGroundOnly = false','Core3.SWGXR.RetailGroundOnly = true'))
            self.assertFalse(configuration_status(dest)['passed'])
            (dest/'config-local.lua').write_text(config.replace('SwgxrDisableCombatSpawns = true','SwgxrDisableCombatSpawns = false'))
            self.assertFalse(configuration_status(dest)['passed'])

    def test_all_planets_profile_preserves_credentials_and_checks_selected_scope(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'remote';source.mkdir();dest=Path(folder)/'all'
            config=runtime.render_config((runtime.BIN/'conf/config-local.lua').read_text(),'b'*64)
            (source/'config-local.lua').write_text(config)
            (source/'resource_manager.lua').write_text(runtime.render_resources((runtime.BIN/'scripts/managers/resource_manager.lua').read_text()))
            result=prepare(dest,source,ALL_PLANETS_PROFILE)
            self.assertEqual(result['planets'],list(runtime.SUPPORTED_PLANETS))
            self.assertTrue(configuration_status(dest)['passed'])
            self.assertEqual((source/'config-local.lua').read_text(),config)
            target=(dest/'config-local.lua').read_text()
            self.assertIn('Core3.ZoneProcessingThreads = 6',target)
            self.assertIn('Core3.MaxNavMeshJobs = 2',target)
            self.assertIn('"'+'b'*64+'"',target)
            (dest/'config-local.lua').write_text(target.replace('"naboo",',''))
            self.assertFalse(configuration_status(dest)['passed'])
            with self.assertRaises(ValueError):runtime.render_config(config,'b'*64,capacity=ALL_PLANETS_PROFILE)

    def test_all_planets_target_checks_twelve_vcpus_and_twenty_four_gb_class(self):
        self.assertTrue(host_readiness(12,24_000_000_000//1024,ALL_PLANETS_PROFILE)['passed'])
        self.assertFalse(host_readiness(8,24*1024*1024,ALL_PLANETS_PROFILE)['passed'])
        self.assertFalse(host_readiness(12,16*1024*1024,ALL_PLANETS_PROFILE)['passed'])
        self.assertFalse(host_readiness(12,24*1024*1024,ALL_PLANETS_PROFILE)['load_validated'])

    def test_synthetic_harness_accepts_large_fixture_sets_and_enters_visible_scene(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'fixtures.json';report=Path(folder)/'report.json'
            source.write_text(json.dumps({'purpose':'corecu_population_test','players':[
                {'account':'loadtest'+str(n),'character_id':str(n+1)} for n in range(80)]}))
            self.assertEqual(len(population_smoke.fixtures(source,80)),80)
            updates=[];logouts=[];sequence=0
            location={'zone':'naboo','position':[0,0,0],'building_id':'0','cell_index':0,'heading_radians':0}
            def transport(request,**kwargs):
                nonlocal sequence
                body=json.loads(request.data);route=request.full_url.rsplit('/',1)[-1]
                if route=='enter':result={'source_location':location}
                elif route=='logout':logouts.append(body);result={'saved':True,'session_closed':True}
                elif route=='sync':result={'session_id':'owned','world_revision':1,'event_sequence':0,'world':{'players':[]}}
                else:
                    sequence+=1
                    if route=='update':updates.append(body)
                    result={'session_id':'owned','session_live':True,'sequence':sequence,'player':{'on_load_screen':not body.get('ready',False)}}
                response=MagicMock();response.__enter__.return_value=io.StringIO(json.dumps(result));return response
            arguments=['population_smoke','--fixtures',str(source),'--clients','1','--seconds','0.01','--report',str(report)]
            opener=Mock();opener.open.side_effect=transport
            with patch('sys.argv',arguments),patch.object(population_smoke.urllib.request,'build_opener',return_value=opener),patch('sys.stdout',io.StringIO()):population_smoke.main()
            result=json.loads(report.read_text())
            self.assertEqual(result['errors'],[])
            self.assertTrue(updates and all(row['ready'] for row in updates))
            self.assertEqual(len(logouts),1)
            self.assertEqual(logouts[0]['position'],location['position'])
            self.assertEqual(logouts[0]['zone'],'naboo')
            self.assertTrue(all(row['zone']=='naboo' for row in updates))
            self.assertEqual(result['planets'],['naboo'])
            self.assertEqual(result['cleanup'],[True])

    def test_unlimited_default_and_operator_override_have_no_fixed_upper_cap(self):
        with patch.dict('os.environ',{},clear=True):self.assertEqual(configured_limit('SWGXR_MAX_NATIVE_SESSIONS'),0)
        for value in ('0','32','128','100000'):
            with patch.dict('os.environ',{'SWGXR_MAX_NATIVE_SESSIONS':value}):
                self.assertEqual(configured_limit('SWGXR_MAX_NATIVE_SESSIONS'),int(value))

    def test_eighty_native_sessions_do_not_hit_an_old_population_ceiling(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict('os.environ',{'SWGXR_MAX_NATIVE_SESSIONS':'0'}), patch('server.live_combat.ROOT',Path(folder)), patch('server.live_combat.subprocess.Popen') as spawn, patch('server.live_combat.VOICE_STATE.remove'):
            def launch(*args,**kwargs):
                for path in (Path(folder)/'runtime/server/livecombat').iterdir(): (path/'ready.json').touch()
                child=Mock();child.poll.return_value=None;return child
            spawn.side_effect=launch
            hub=LiveCombatHub()
            hub._exchange=Mock(side_effect=lambda active,command,**kwargs:{'session_live':command['action']!='stop','character_id':active['character_id'],'session_id':active['id']})
            try:
                for n in range(80):hub.start('loadtest'+str(n),{'character_id':str(n+1),'position':[0,0,0]},b'fixture','fixture',lambda _: [{'id':str(n+1)}])
                self.assertEqual(len(hub.sessions),80)
                self.assertEqual(spawn.call_count,80)
                for active in hub.sessions.values():active['process'].terminate.assert_not_called()
            finally:hub.close()

    def test_thirty_two_owned_combat_waits_overlap_without_global_queue(self):
        hub=LiveCombatHub();barrier=threading.Barrier(32)
        for n in range(32):
            child=Mock();child.poll.return_value=None
            hub.sessions['p'+str(n)]={'account':'p'+str(n),'character_id':str(n+1),'id':'session_'+str(n),'process':child,'native_concurrency':'engine_cross_lock_v1'}
        def exchange(active,command,timeout=12,**kwargs):barrier.wait(timeout=3);return {'session_live':True,'session_id':active['id']}
        hub._exchange_owned=exchange
        forbidden=MagicMock();forbidden.__enter__.side_effect=BackendBusy('Global lane occupied')
        def request(n):
            body=dict(account='p'+str(n),character_id=str(n+1),session_id='session_'+str(n),shot_id='testshot_'+str(n),item_id='99',origin=[0,1,0],direction=[0,0,1])
            raw=json.dumps(body).encode();handler=object.__new__(adapter.Handler)
            handler.headers={'Content-Length':str(len(raw))};handler.rfile=io.BytesIO(raw);handler.path='/combat/session/melee';handler.respond=Mock()
            handler.do_POST();return handler.respond.call_args.args
        try:
            with patch.object(adapter,'LIVE_COMBAT',hub),patch.object(adapter,'LOCK',forbidden),ThreadPoolExecutor(max_workers=32) as pool:
                responses=list(pool.map(request,range(32)))
            self.assertTrue(all(status==200 for status,_ in responses),responses[:2])
            self.assertEqual(len({body['session_id'] for _,body in responses}),32)
            forbidden.__enter__.assert_not_called()
        finally:hub.sessions.clear()

    def test_profile_stages_tatooine_without_touching_credentials_or_data(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'remote';source.mkdir();destination=Path(folder)/'staged'
            config=runtime.render_config((runtime.BIN/'conf/config-local.lua').read_text(),'a'*64)
            resource=runtime.render_resources((runtime.BIN/'scripts/managers/resource_manager.lua').read_text())
            (source/'config-local.lua').write_text(config);(source/'resource_manager.lua').write_text(resource);(source/'data.db').write_bytes(b'persistent')
            result=prepare(destination,source)
            self.assertFalse(result['live_configuration_changed']);self.assertIsNone(result['session_limit'])
            self.assertEqual((source/'config-local.lua').read_text(),config);self.assertEqual((source/'data.db').read_bytes(),b'persistent')
            self.assertTrue(configuration_status(destination)['passed'])
            staged=(destination/'config-local.lua').read_text()
            for line in ('Core3.ZoneProcessingThreads = 4','Core3.MaxNavMeshJobs = 1','Core3.LoginAllowedConnections = 64','Core3.ZoneAllowedConnections = 64','Core3.ZonesEnabled = {"tatooine"}'):
                self.assertIn(line,staged)
            self.assertIn('"'+'a'*64+'"',staged);self.assertNotIn('a'*64,(destination/'preparation.json').read_text())
            self.assertEqual((destination/'config-local.lua').stat().st_mode&0o777,0o600)
            self.assertIn('SWGXR_MAX_NATIVE_SESSIONS=0',(destination/'capacity.env').read_text())
            with self.assertRaises(ValueError):prepare(destination,source)
            (source/'config-local.lua').write_text(config.replace('{"tatooine"}','{"tatooine","naboo"}'))
            with self.assertRaises(ValueError):prepare(Path(folder)/'other',source)

    def test_target_host_check_is_not_a_load_validation_claim(self):
        self.assertTrue(host_readiness(8,16*1024*1024)['passed'])
        self.assertFalse(host_readiness(8,16*1024*1024)['load_validated'])
        self.assertFalse(host_readiness(8,2*1024*1024)['passed'])
        self.assertFalse(host_readiness(4,32*1024*1024)['passed'])

    def test_runtime_package_requires_current_source_and_matching_binaries(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);binary=root/'vendor/Core3/MMOCoreORB/bin';binary.mkdir(parents=True)
            for name in build.BINARIES:(binary/name).write_bytes(b'fixture')
            with patch.object(build,'inputs',return_value={'source':'v1'}):
                build.record(root);self.assertTrue(build.verify(root)['linked_build'])
                (binary/'core3client').write_bytes(b'changed')
                with self.assertRaises(ValueError):build.verify(root)
                (binary/'core3client').write_bytes(b'fixture')
            with patch.object(build,'inputs',return_value={'source':'v2'}),self.assertRaises(ValueError):build.verify(root)

if __name__=='__main__':unittest.main()
