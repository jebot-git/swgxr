import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from server.gathering_protocol import gathering_snapshot

ROOT = Path(__file__).resolve().parents[1]


class SurveySamplingTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('g++'), 'C++ compiler unavailable')
    def test_native_offline_sampling_policy(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = str(Path(temporary) / 'survey_sampling')
            subprocess.run(['g++', '-std=c++17', '-O2', str(ROOT / 'tests/survey_sampling.cpp'),
                            '-o', binary], check=True, capture_output=True)
            subprocess.run([binary], check=True, capture_output=True)

    def test_full_storage_message_is_not_a_missing_original_localization(self):
        tool = dict(id='2', client_crc=0, template='object/tool.iff', customization_hex='')
        for status, phrase in [('full', 'Storage full'), ('duplicate_type', 'Sampling paused')]:
            state = dict(source_kind='core3_gathering', character_id='1', deployments=[
                dict(tool=tool.copy(), resource_name='Ore', sample_status=status, quantity=100000,
                     capacity=100000, tool_type=2)])
            native = dict(variables=dict(gathering=dict(character_id='1', state=state),
                                         weaponAttributes={'o2': {}}))
            with patch('server.gathering_protocol.template_names', return_value={}), \
                 patch('server.gathering_protocol.display', side_effect=lambda table, key, fallback: fallback):
                deployment = gathering_snapshot(native, '1')['state']['deployments'][0]
            self.assertIn(phrase, deployment['sample_message'])
            self.assertEqual(deployment['capacity'], 100000)
            self.assertEqual(deployment['tool_type'], 2)


if __name__ == '__main__':
    unittest.main()
