"""Exercise Rifleman's Focus through the real HTTP adapter and owned IPC gate."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class RiflemanAdapter(unittest.TestCase):
    def test_http_routing_preserves_owned_native_admission(self):
        hub = LiveCombatHub()
        active = dict(account='rifle', character_id='42', id='session_rifle', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['rifle'] = active
        reply = {'session_live': True, 'mutation': {'success': True}}
        hub._exchange = Mock(return_value=reply)
        gate = RequestGate(.02, 2)
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(payload):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/combat/session/rifleman', json.dumps(payload),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        payload = dict(account='rifle', character_id='42', session_id='session_rifle',
                       shot_id='rifleman-001', item_id='55', ability_id='rifleman_focus',
                       origin=[0, 1.5, 0], direction=[0, 0, -1], two_hands=True,
                       damage_multiplier=100, duration_seconds=999,
                       native_concurrency='engine_cross_lock_v1')
        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), patch.object(adapter, 'LOCK', gate):
                # Only the verified native session capability opens the parallel lane.
                with gate:
                    status, denied = post(payload)
                    self.assertEqual(status, 503)
                    self.assertFalse(denied['mutation_started'])
                    hub._exchange.assert_not_called()
                self.assertEqual(post(payload), (200, reply))
                active['native_concurrency'] = 'engine_cross_lock_v1'
                with gate:
                    self.assertEqual(post(payload), (200, reply))
                self.assertEqual(hub._exchange.call_count, 2)
                for call in hub._exchange.call_args_list:
                    command = call.args[1]
                    self.assertEqual(command['action'], 'rifleman')
                    self.assertEqual(command['ability_id'], 'rifleman_focus')
                    self.assertTrue(command['two_hands'])
                    for key in ('damage_multiplier', 'duration_seconds', 'native_concurrency'):
                        self.assertNotIn(key, command)
                for extra, status in (({'character_id': '99'}, 409),
                                      ({'session_id': 'foreign'}, 409),
                                      ({'two_hands': False}, 400),
                                      ({'two_hands': 1}, 400),
                                      ({'target_id': '77'}, 400),
                                      ({'volley_id': 'rifleman-001'}, 400),
                                      ({'ability_id': 'sniper_shot'}, 400),
                                      ({'ability_id': 'tactical_brace'}, 400)):
                    with self.subTest(extra=extra):
                        self.assertEqual(post(dict(payload, **extra))[0], status)
                self.assertEqual(hub._exchange.call_count, 2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
