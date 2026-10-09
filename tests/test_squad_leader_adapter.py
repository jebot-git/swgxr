"""Real HTTP routing retains owned session admission for support casts."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class SquadLeaderAdapterTests(unittest.TestCase):
    def test_owned_cast_in_both_admission_lanes(self):
        hub = LiveCombatHub()
        active = dict(account='leader',character_id='42',id='session_leader',process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['leader'] = active
        reply = {'session_live':True,'mutation':{'success':True}}
        hub._exchange = Mock(return_value=reply)
        gate = RequestGate(.02,2)
        server = ThreadingHTTPServer(('127.0.0.1',0),adapter.Handler)
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        payload = dict(account='leader',character_id='42',session_id='session_leader',
                       shot_id='squadleader-001',item_id='55',target_id='77',
                       ability_id='steady_aim',origin=[0,1.5,0],direction=[0,0,-1],
                       group_id='999',damage_multiplier=100,native_concurrency='engine_cross_lock_v1')

        def post(value):
            connection = http.client.HTTPConnection(*server.server_address,timeout=2)
            try:
                connection.request('POST','/combat/session/squadleader',json.dumps(value),
                                   {'Content-Type':'application/json'})
                response = connection.getresponse()
                return response.status,json.loads(response.read())
            finally:
                connection.close()

        try:
            with patch.object(adapter,'LIVE_COMBAT',hub),patch.object(adapter,'LOCK',gate):
                with gate:
                    status,denied = post(payload)
                    self.assertEqual(status,503)
                    self.assertFalse(denied['mutation_started'])
                    hub._exchange.assert_not_called()
                self.assertEqual(post(payload),(200,reply))
                active['native_concurrency'] = 'engine_cross_lock_v1'
                with gate:
                    self.assertEqual(post(dict(payload,ability_id='volley_fire')),(200,reply))
                for call in hub._exchange.call_args_list:
                    command = call.args[1]
                    self.assertEqual(command['action'],'squadleader')
                    for key in ('group_id','damage_multiplier','native_concurrency'):
                        self.assertNotIn(key,command)
                admitted = hub._exchange.call_count
                for extra,status in (({'character_id':'99'},409),({'session_id':'foreign'},409),
                                     ({'target_id':'0'},400),({'target_id':'７７'},400),
                                     ({'ability_id':'reviveplayer'},400),
                                     ({'volley_mark_id':'volley_42_123456'},400)):
                    with self.subTest(extra=extra):
                        self.assertEqual(post(dict(payload,**extra))[0],status)
                self.assertEqual(hub._exchange.call_count,admitted)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
