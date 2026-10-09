"""Real loopback HTTP admission for native BH gestures; no game process."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class BountyCombatAdapter(unittest.TestCase):
    def test_owned_gestures_in_both_admission_lanes(self):
        hub = LiveCombatHub()
        active = dict(account='hunter', character_id='42', id='owned', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['hunter'] = active
        self.addCleanup(hub.sessions.clear)
        reply = {'session_live': True, 'mutation': {'success': True}}
        hub._exchange = Mock(return_value=reply)
        gate = RequestGate(.02, 2)
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(payload):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/combat/session/bountyhunter', json.dumps(payload),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        base = dict(account='hunter', character_id='42', session_id='owned',
                    shot_id='bounty-001', item_id='55', origin=[0, 1.5, 0],
                    direction=[0, 0, -1], two_hands=True, ability_id='underhand_shot',
                    damage=9999, armed_until=9999, native_concurrency='engine_cross_lock_v1')
        cases = [base, dict(base, ability_id='duelist_stance', target_id='77', two_hands=False)]
        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), patch.object(adapter, 'LOCK', gate):
                with gate:
                    self.assertEqual(post(base)[0], 503)
                    hub._exchange.assert_not_called()
                for payload in cases:
                    self.assertEqual(post(payload), (200, reply))
                active['native_concurrency'] = 'engine_cross_lock_v1'
                with gate:
                    for payload in cases:
                        self.assertEqual(post(payload), (200, reply))
                self.assertEqual(hub._exchange.call_count, 4)
                for call in hub._exchange.call_args_list:
                    command = call.args[1]
                    self.assertEqual(command['action'], 'bountyhunter')
                    for key in ('damage', 'armed_until', 'native_concurrency'):
                        self.assertNotIn(key, command)
                for extra, status in (({'character_id': '99'}, 409),
                                      ({'session_id': 'other'}, 409),
                                      ({'two_hands': False}, 400),
                                      ({'target_id': '77'}, 400),
                                      ({'ability_id': 'spray_shot'}, 400)):
                    self.assertEqual(post(dict(base, **extra))[0], status)
                self.assertEqual(hub._exchange.call_count, 4)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
