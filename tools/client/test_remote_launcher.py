#!/usr/bin/env python3
"""Launcher remote/local branching and private-profile activation regressions."""
import contextlib
import io
import json
from pathlib import Path
import ssl
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import run_prototype as launcher
from client import install_remote_profile as installer

EVIDENCE=Path(__file__).resolve().parents[2]/'runtime/evidence/remote-client'
EVIDENCE.mkdir(parents=True,exist_ok=True)


class RemoteLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='launcher-',dir=EVIDENCE)
        self.root=Path(self.temporary.name)
        for relative in ['client/addons/godot-xr-tools/plugin.cfg','client/native/bin/libswg_native.so',
                         'runtime/assets/mos_eisley/scene.json','runtime/assets/characters/catalog.json',
                         *['runtime/assets/'+name for name in ('terrain/tatooine.json','terrain/context.json','tatooine_world/world.json',
                           'tatooine_environment/environment.json','ambient_npcs/placements.json','ambient_npcs/catalog.json')]]:
            path=self.root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('{}')
        self.stack=contextlib.ExitStack()
        self.stack.enter_context(patch.object(launcher,'ROOT',self.root))
        self.stack.enter_context(patch.object(launcher,'RUNTIME',self.root/'runtime/server'))
        for name in ('inventory_assets','corpse_assets','combat_assets','live_entity_assets','mission_assets','cached_world_assets'):
            self.stack.enter_context(patch.object(launcher,name))
        self.inventory=self.stack.enter_context(patch.object(launcher,'selected_inventory_assets'))
        self.voice=self.stack.enter_context(patch.object(launcher,'ensure_local_voice'))
        self.run=self.stack.enter_context(patch.object(launcher.subprocess,'run'))
        self.spawn=self.stack.enter_context(patch.object(launcher.subprocess,'Popen'))
        self.client=self.stack.enter_context(patch.object(launcher.subprocess,'call',return_value=0))
        self.stack.enter_context(patch.object(sys,'argv',['run_prototype.py','--desktop']))
        self.remote=Mock();self.remote.base_url='https://45.147.228.101:18443';self.remote.account='fixture'
        self.remote.authenticated=True
        self.remote.request_json.return_value={'backend':'core3','core3':{'ready':True}}
    def tearDown(self):
        self.stack.close();self.temporary.cleanup()
    def test_planet_readiness_requires_actual_manifests(self):
        path=self.root/'runtime/assets/planets/catalog.json';path.parent.mkdir(parents=True)
        component=self.root/'component.json';component.write_text('{}')
        row={key:str(component) for key in ('terrain','terrain_context','world','environment','services','ambient_npcs','ambient_placements','entities')}
        row.update(planet='naboo',ready=True)
        path.write_text(json.dumps({'schema_version':1,'planets':{'naboo':row}}))
        self.assertEqual(launcher.planet_assets(['--planet=naboo']),['naboo'])
        component.unlink()
        with self.assertRaisesRegex(ValueError,'manifests are missing'):launcher.planet_assets(['--planet=naboo'])
        row['ready']=False
        path.write_text(json.dumps({'schema_version':1,'planets':{'naboo':row}}))
        with self.assertRaisesRegex(ValueError,'not prepared'):launcher.planet_assets(['--planet=naboo'])

    def test_remote_launch_starts_no_local_server_or_container(self):
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop','--connection-profile=/private/profile.json'],self.remote)):
            self.assertEqual(launcher.run(),0)
        self.run.assert_not_called();self.spawn.assert_not_called()
        self.voice.assert_not_called()
        self.remote.request_json.assert_not_called()
        self.inventory.assert_called_once_with(['--desktop','--connection-profile=/private/profile.json'],connection=self.remote)
        command=self.client.call_args.args[0]
        self.assertIn('--connection-profile=/private/profile.json',command)
        self.assertEqual(command[command.index('--xr-mode')+1],'off')
        self.assertFalse((self.root/'vendor/Core3/MMOCoreORB/bin/core3').exists())
    def test_remote_tls_failure_never_falls_back_to_local(self):
        self.remote.request_json.side_effect=ssl.SSLCertVerificationError('IP SAN mismatch')
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop','--enter-character=Fixture'],self.remote)),self.assertRaisesRegex(SystemExit,'HTTPS health check failed'):
            launcher.run()
        self.run.assert_not_called();self.spawn.assert_not_called();self.client.assert_not_called()
    def test_endpoint_only_launch_reaches_sign_in_without_any_account_request(self):
        self.remote.authenticated=False
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop'],self.remote)):
            self.assertEqual(launcher.run(),0)
        self.remote.request_json.assert_not_called();self.inventory.assert_not_called()
        self.run.assert_not_called();self.spawn.assert_not_called();self.client.assert_called_once()
    def test_endpoint_only_cannot_automatically_enter_character(self):
        self.remote.authenticated=False
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop','--enter-character=Fixture'],self.remote)),self.assertRaisesRegex(SystemExit,'Launch without --enter-character'):
            launcher.run()
        self.remote.request_json.assert_not_called();self.inventory.assert_not_called();self.client.assert_not_called()
    def test_remote_profile_invalid_fails_before_service_or_asset_work(self):
        with patch.object(launcher,'connection_arguments',side_effect=ValueError('Private profile invalid')),self.assertRaisesRegex(SystemExit,'Private profile invalid'):
            launcher.run()
        self.run.assert_not_called();self.spawn.assert_not_called();self.inventory.assert_not_called()
    def test_explicit_local_retains_local_server_start(self):
        binary=self.root/'vendor/Core3/MMOCoreORB/bin/core3';binary.parent.mkdir(parents=True);binary.write_text('fixture')
        health=io.BytesIO(json.dumps({'backend':'core3','core3':{'ready':True}}).encode())
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop','--local'],None)),patch.object(launcher.urllib.request,'urlopen',return_value=health):
            launcher.run()
        self.assertEqual(self.run.call_count,2)
        self.voice.assert_called_once_with(self.root)
        self.assertEqual(self.run.call_args_list[0].args[0][:2],['podman','start'])
        self.assertTrue(str(self.run.call_args_list[1].args[0][0]).endswith('start-core3.sh'))
        self.inventory.assert_called_once_with(['--desktop','--local'],connection=None)
    def test_offline_launch_starts_no_server(self):
        with patch.object(launcher,'connection_arguments',return_value=(['--desktop','--offline'],None)):
            launcher.run()
        self.run.assert_not_called();self.spawn.assert_not_called();self.inventory.assert_not_called()
    def test_remote_inventory_endpoint_cannot_redirect_auth_to_other_base(self):
        with self.assertRaisesRegex(ValueError,'differs from the authenticated profile'):
            launcher.backend_json('https://other.example','/inventory',connection=self.remote)
        self.remote.request_json.assert_not_called()
    def test_installer_refuses_activation_before_native_readiness(self):
        self.remote.request_json.return_value={'backend':'core3','core3':{'ready':False}}
        with patch.object(installer,'ROOT',self.root),patch.object(installer.RemoteConnection,'load',return_value=self.remote),self.assertRaisesRegex(ValueError,'not ready'):
            installer.install('/ignored/private-input.json')
        self.assertFalse((self.root/'runtime/client/connection.json').exists())
    def test_installer_copies_trust_and_keeps_profile_private(self):
        ca=self.root/'source-ca.pem';ca.write_text('Public CA fixture')
        self.remote.ca_certificate=ca;self.remote.token='synthetic-secret-not-for-production'
        with patch.object(installer,'ROOT',self.root),patch.object(installer.RemoteConnection,'load',return_value=self.remote):
            destination=installer.install('/ignored/private-input.json')
        value=json.loads(destination.read_text())
        self.assertEqual(value['base_url'],self.remote.base_url)
        self.assertEqual(Path(value['ca_certificate']).read_text(),'Public CA fixture')
        self.assertEqual(destination.stat().st_mode & 0o777,0o600)
        self.assertEqual(Path(value['ca_certificate']).stat().st_mode & 0o777,0o600)
    def test_installer_cannot_write_secret_into_source_tree(self):
        with patch.object(installer,'ROOT',self.root),patch.object(installer.RemoteConnection,'load',return_value=self.remote),self.assertRaisesRegex(ValueError,'ignored runtime'):
            installer.install('/ignored/private-input.json',self.root/'client/connection.json')
        self.remote.request_json.assert_not_called()
    def test_endpoint_only_installer_does_not_require_account_or_write_credentials(self):
        self.remote.authenticated=False
        ca=self.root/'source-ca.pem';ca.write_text('Public CA fixture')
        self.remote.ca_certificate=ca
        with patch.object(installer,'ROOT',self.root),patch.object(installer.RemoteConnection,'load',return_value=self.remote):
            destination=installer.install('/ignored/endpoint.json')
        self.remote.request_json.assert_not_called()
        self.assertEqual(set(json.loads(destination.read_text())),{'base_url','ca_certificate'})


if __name__=='__main__':unittest.main(verbosity=2)
