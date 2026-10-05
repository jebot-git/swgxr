"""Pure deployment preparation checks; no Podman, native process or host changes."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('remote_runtime',Path(__file__).with_name('runtime.py'))
runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime)

class Tests(unittest.TestCase):
    def test_remote_profile(self):
        source=(runtime.BIN/'conf/config-local.lua').read_text()
        changed=runtime.render_config(source,'a'*64)
        for line in ('Core3.DBPass = "'+'a'*64+'"','Core3.ZoneProcessingThreads = 2','Core3.MaxNavMeshJobs = 1','Core3.ZonesEnabled = {"tatooine"}','Core3.SpaceZonesEnabled = {}'):
            self.assertIn(line,changed)
        self.assertNotIn('DBPass = "123456"',changed)
        self.assertEqual(source.split('Core3.TreFiles = {')[1].split('}')[0],changed.split('Core3.TreFiles = {')[1].split('}')[0])
        with self.assertRaises(ValueError):runtime.render_config(source,'bad credential')
    def test_resources(self):
        source=(runtime.BIN/'scripts/managers/resource_manager.lua').read_text()
        changed=runtime.render_resources(source)
        for value in ('buildInitialResourcesFromScript = 0','activeZones = "tatooine"','fixedpoolincludes = {{"iron",14}}'):self.assertIn(value,changed)
        for line in source.splitlines():
            if 'excludes =' in line:self.assertIn(line,changed)
    def test_refuse_incomplete_source(self):
        with self.assertRaises(ValueError):runtime.render_resources('activeZones = "tatooine"')
    def test_fresh_schema_only(self):
        source='USE `swgemu`;\nINSERT INTO galaxy VALUES(2);\nINSERT INTO db_metadata VALUES(1008);'
        runtime.validate_schema(source)
        for change in (source+'\nINSERT INTO accounts VALUES(1);',source.replace('db_metadata','account')):
            with self.assertRaises(ValueError):runtime.validate_schema(change)
    def test_bounded_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'console.log';path.write_bytes(b'0123456789'*10)
            runtime.rotate_path(path,16)
            self.assertEqual(path.stat().st_size,0)
            self.assertEqual(path.with_name('console.log.1').read_bytes(),b'4567890123456789')
    def test_bootstrap_refuses_existing_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);remote=root/'remote';remote.mkdir();(remote/'mysql').mkdir();(remote/'mysql'/'old.db').write_text('existing')
            (remote/'schema.sql').write_text('USE swgemu;\nINSERT INTO galaxy VALUES(2);\nINSERT INTO db_metadata VALUES(1008);')
            with patch.object(runtime,'REMOTE',remote):
                with self.assertRaisesRegex(RuntimeError,'existing database'):runtime.bootstrap(True)
            self.assertEqual((remote/'mysql'/'old.db').read_text(),'existing')
            self.assertFalse((remote/'db-password').exists())
    def test_bootstrap_idempotent_and_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);remote=root/'remote';remote.mkdir()
            (remote/'schema.sql').write_text('USE swgemu;\nINSERT INTO galaxy VALUES(2);\nINSERT INTO db_metadata VALUES(1008);')
            (remote/'config-local.lua').write_text('Packaged preliminary overlay')
            with patch.object(runtime,'REMOTE',remote),patch.object(runtime,'STATE',root/'state'):
                runtime.bootstrap(True)
                credential=(remote/'db-password').read_text()
                self.assertEqual(len(credential.strip()),64)
                self.assertEqual((remote/'db-password').stat().st_mode&0o777,0o600)
                self.assertIn(credential.strip(),(remote/'config-local.lua').read_text())
                (remote/'databases'/'saved.db').write_text('persistent')
                runtime.bootstrap(True)
                self.assertEqual((remote/'db-password').read_text(),credential)
                self.assertEqual((remote/'databases'/'saved.db').read_text(),'persistent')

    def test_apparmor_keeps_denials_and_exact_stacked_peer(self):
        profile=(Path(__file__).with_name('apparmor')/'swgxr-core3').read_text()
        self.assertIn('signal (send,receive) peer=swgxr-core3//&crun,',profile)
        self.assertIn('signal (send,receive) peer=crun//&swgxr-core3,',profile)
        self.assertNotIn('peer=swgxr-core3//&*',profile)
        self.assertNotIn('flags=(unconfined)',profile)
        for rule in ('deny mount,','deny @{PROC}/kcore rwklx,','deny /sys/kernel/security/** rwklx,'):
            self.assertIn(rule,profile)

    def test_units_expose_only_gateway(self):
        units=Path(__file__).with_name('systemd')
        gateway=(units/'swgxr-gateway.service.in').read_text()
        voice=(units/'swgxr-voice.service.in').read_text()
        self.assertIn('--port 18443',gateway)
        self.assertIn('ProtectSystem=strict',gateway)
        self.assertIn('ReadWritePaths=@ROOT@/runtime/auth',gateway)
        self.assertIn('--port 18444',voice)
        self.assertNotIn('--loopback-debug',voice)
        self.assertIn('MemoryMax=192M',voice)
        self.assertIn('LimitNOFILE=256',voice)
        self.assertIn('ProtectSystem=strict',voice)
        self.assertIn('--port 18080',(units/'swgxr-adapter.service.in').read_text())
        self.assertIn('stop-core',(units/'swgxr-core3.service.in').read_text())
        self.assertIn('After=swgxr-db.service',(units/'swgxr-core3.service.in').read_text())
        self.assertIn('Wants=swgxr-logs.timer',(units/'swgxr.target.in').read_text())
        # PartOf propagates explicit target shutdown downwards. Requiring a leaf
        # here would propagate its restart upwards and restart all native state.
        target=(units/'swgxr.target.in').read_text()
        self.assertNotIn('Requires=',target)
        for name in ('container','db','core3','adapter','gateway','voice'):
            self.assertIn('swgxr-'+name+'.service',target)
            self.assertIn('PartOf=swgxr.target',(units/('swgxr-'+name+'.service.in')).read_text())


class VehicleCatalogTests(unittest.TestCase):
    def test_real_catalog_covers_native_vehicle_templates(self):
        result=runtime.vehicle_catalog_status(runtime.ROOT)
        self.assertTrue(result['passed'],result)
        self.assertEqual(len(result['ready']),6)

    def test_missing_catalog_fails_readiness(self):
        with tempfile.TemporaryDirectory() as folder:
            result=runtime.vehicle_catalog_status(Path(folder))
        self.assertFalse(result['passed'])
        self.assertTrue(result['errors'])

    def test_incomplete_or_invalid_catalog_fails_readiness(self):
        source=json.loads((runtime.ROOT/'runtime/assets/vehicles/catalog.json').read_text())
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);path=root/'runtime/assets/vehicles/catalog.json';path.parent.mkdir(parents=True)
            missing=json.loads(json.dumps(source));del missing['items']['object/mobile/vehicle/landspeeder_x31.iff']
            path.write_text(json.dumps(missing));self.assertFalse(runtime.vehicle_catalog_status(root)['passed'])
            source['items']['object/mobile/vehicle/landspeeder_x31.iff']['bounds_min']=[float('nan'),0,0]
            path.write_text(json.dumps(source));self.assertFalse(runtime.vehicle_catalog_status(root)['passed'])
            path.write_text('{');self.assertFalse(runtime.vehicle_catalog_status(root)['passed'])

    def test_runtime_package_includes_native_vehicle_catalog(self):
        from tools.deploy.package_runtime import REQUIRED_ASSET_CATALOGS
        self.assertIn('runtime/assets/vehicles/catalog.json',REQUIRED_ASSET_CATALOGS)

if __name__=='__main__':unittest.main(verbosity=2)
