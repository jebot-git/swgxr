import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock,patch
from tools.character_export.launcher import Gateway
from tools.character_export.export_character import ExportError
from tools.client.package_test_client import included

class CharacterExport(unittest.TestCase):
    def gateway(self):
        gateway=Gateway.__new__(Gateway);gateway.token=None
        return gateway
    def test_roster_revokes_only_its_own_token(self):
        gateway=self.gateway();calls=[]
        def request(path,payload=None):
            calls.append((path,payload,gateway.token))
            return {'token':'own-token'} if path=='/auth/login' else {'backend':'core3','characters':[{'id':'12','name':'A'}]}
        gateway.request=request
        self.assertEqual(gateway.roster('account','secret')[0]['id'],'12')
        self.assertIsNone(gateway.token)
        self.assertEqual(calls[-1],('/auth/logout',{},'own-token'))
        self.assertEqual(calls[0][2],None)
    def test_failed_snapshot_still_revokes_session(self):
        gateway=self.gateway();gateway.request=Mock(side_effect=[{'token':'own-token'},ExportError('busy'),{}])
        with self.assertRaises(ExportError):gateway.snapshot('account','secret','12')
        self.assertIsNone(gateway.token)
        self.assertEqual(gateway.request.call_args.args,('/auth/logout',{}))
    def test_wrong_character_rejected(self):
        gateway=self.gateway();gateway.request=Mock(side_effect=[{'token':'own-token'},{'backend':'core3','character':{'id':'13','appearance':{'source':'core3_replication','race':'human_male'},'equipment':[]}},{}])
        with self.assertRaisesRegex(ExportError,'different character'):gateway.snapshot('account','secret','12')
    def test_export_helpers_in_both_packages(self):
        for target in ('linux-x86_64','windows-x86_64'):
            for name in ('portable_character_export','character_exporter','avatar_export_materials'):
                self.assertTrue(included(Path('tools')/(name+'.gd'),target))
            self.assertFalse(included(Path('tools/unrelated_diagnostic.gd'),target))
    def test_remote_plaintext_rejected_before_certificate_load(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'server.json').write_text(json.dumps({'base_url':'http://example.com'}))
            with self.assertRaisesRegex(ExportError,'HTTPS'):Gateway(root)
