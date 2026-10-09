"""Exercise the real HTTP adapter and owned Carbineer transport in both native lanes."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class CarbineerAdapter(unittest.TestCase):
    def test_http_routing_preserves_owned_native_admission(self):
        hub = LiveCombatHub()
        active = dict(account='carbine', character_id='42', id='session_carbine', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['carbine'] = active
        reply = {'session_live': True, 'mutation': {'success': True}}
        hub._exchange = Mock(return_value=reply)
        gate = RequestGate(.02, 2)
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(payload):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/combat/session/carbineer', json.dumps(payload),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        payload = dict(account='carbine', character_id='42', session_id='session_carbine',
                       shot_id='carbine-001', item_id='55', ability_id='full_auto_sweep',
                       origin=[0, 1.5, 0], direction=[0, 0, -1], two_hands=True,
                       target_ids=['77'], damage=9999, control_chance_bonus=100,
                       native_concurrency='engine_cross_lock_v1')
        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), patch.object(adapter, 'LOCK', gate):
                # A client capability claim cannot evade the legacy global gate.
                with gate:
                    status, denied = post(payload)
                    self.assertEqual(status, 503)
                    self.assertFalse(denied['mutation_started'])
                    hub._exchange.assert_not_called()
                for ability in ('full_auto_sweep', 'tactical_brace', 'charge_blast'):
                    self.assertEqual(post(dict(payload, ability_id=ability)), (200, reply))
                active['native_concurrency'] = 'engine_cross_lock_v1'
                with gate:
                    for ability in ('full_auto_sweep', 'tactical_brace', 'charge_blast'):
                        self.assertEqual(post(dict(payload, ability_id=ability)), (200, reply))
                self.assertEqual(hub._exchange.call_count, 6)
                for call in hub._exchange.call_args_list:
                    command = call.args[1]
                    self.assertEqual(command['action'], 'carbineer')
                    self.assertTrue(command['two_hands'])
                    for key in ('target_ids', 'damage', 'control_chance_bonus', 'native_concurrency'):
                        self.assertNotIn(key, command)
                for extra, status in (({'character_id': '99'}, 409),
                                      ({'two_hands': False}, 400),
                                      ({'target_id': '77'}, 400),
                                      ({'ability_id': 'forward_check'}, 400)):
                    self.assertEqual(post(dict(payload, **extra))[0], status)
                self.assertEqual(hub._exchange.call_count, 6)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
