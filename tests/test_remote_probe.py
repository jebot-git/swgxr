import io
import json
import unittest
import urllib.error
from unittest.mock import Mock

from tools.client.remote_connection import safe_http_diagnostic
from tools.client.remote_two_client_smoke import Simulation


class RemoteProbe(unittest.TestCase):
    def test_static_error_diagnostics_never_echo_private_fields(self):
        known = 'A fresh owned native session is required for multiplayer sync'
        for body, expected in [({'error': known, 'token': 'secret'}, known),
                               ({'error': 'account secret-token'}, 'Unrecognized server message omitted'),
                               ({'error': ['secret']}, 'Unreadable server message omitted')]:
            error = urllib.error.HTTPError('https://secret.invalid/private', 400, 'private', {},
                                           io.BytesIO(json.dumps(body).encode()))
            result = safe_http_diagnostic(error)
            error.close()
            self.assertEqual(result, {'http_status': 400, 'server_error': expected})
            self.assertNotIn('secret', json.dumps(result))

    def test_simulation_enters_scene_and_records_actual_native_visibility(self):
        profiles = [Mock(account=name, base_url='https://test.invalid') for name in ('nettest_one', 'nettest_two')]
        simulation = Simulation(profiles, gameplay=True)
        a, b = simulation.clients
        a.update(id='1', session='session1', sequence=1)
        b.update(id='2', session='session2', sequence=1)
        response = {'session_live': True, 'session_id': 'session1', 'character_id': '1', 'sequence': 2,
                    'snapshot': {'player': {'on_load_screen': False}, 'world': {'players': [{'id': '2'}]}}}
        simulation.call = Mock(return_value=response)
        simulation.snapshot(a)
        self.assertTrue(simulation.call.call_args.args[2]['ready'])
        self.assertEqual(a['visible_players'], {'2'})
        response['sequence'] = 3
        response['snapshot']['player']['on_load_screen'] = True
        with self.assertRaisesRegex(AssertionError, 'scene-ready'):
            simulation.snapshot(a)


if __name__ == '__main__':
    unittest.main()
