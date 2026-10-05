"""Transport/ownership regression checks; native cross-lock has a separate real proof."""
import json
from http.server import ThreadingHTTPServer
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.request
import urllib.error
from unittest.mock import Mock, patch
from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate, BackendBusy


class NativeConcurrency(unittest.TestCase):
    def setUp(self):
        self.hub=LiveCombatHub()
        for account,oid in [('one','1'),('two','2')]:
            self.hub.sessions[account]={'id':'session_'+account,'account':account,'character_id':oid,'process':Mock()}
            self.hub.sessions[account]['process'].poll.return_value=None
    def tearDown(self):self.hub.sessions.clear()
    def test_same_account_mailbox_is_serialized(self):
        active=self.hub.sessions['one'];inside=0;maximum=0;guard=threading.Lock();results=[]
        def exchange(*args):
            nonlocal inside,maximum
            with guard:inside+=1;maximum=max(maximum,inside)
            time.sleep(.04)
            with guard:inside-=1
            return {'session_live':True}
        self.hub._exchange_owned=exchange
        threads=[threading.Thread(target=lambda:results.append(self.hub._exchange(active,{'action':'snapshot'})))for _ in range(4)]
        for thread in threads:thread.start()
        for thread in threads:thread.join(1)
        self.assertEqual(len(results),4);self.assertEqual(maximum,1)
    def test_unrelated_account_native_waits_overlap(self):
        barrier=threading.Barrier(2);results=[]
        def exchange(*args):barrier.wait(timeout=.5);return True
        self.hub._exchange_owned=exchange
        threads=[threading.Thread(target=lambda active=active:results.append(self.hub._exchange(active,{})))for active in self.hub.sessions.values()]
        for thread in threads:thread.start()
        for thread in threads:thread.join(1)
        self.assertEqual(results,[True,True])
    def test_busy_mailbox_does_not_close_healthy_session(self):
        active=self.hub.sessions['one'];active['ipc_gate']=RequestGate(.02,1)
        entered=threading.Event();release=threading.Event()
        def hold():
            with active['ipc_gate']:entered.set();release.wait(1)
        thread=threading.Thread(target=hold);thread.start();entered.wait(1)
        self.hub.close=Mock()
        try:
            with self.assertRaises(BackendBusy):self.hub.request('one','snapshot',{'character_id':'1','session_id':'session_one'})
            self.hub.close.assert_not_called();self.assertIs(self.hub.active_for('one'),active)
        finally:release.set();thread.join()
    def test_capability_requires_verified_owner_and_live_child(self):
        active=self.hub.sessions['one'];body={'character_id':'1','session_id':'session_one','native_concurrency':'engine_cross_lock_v1'}
        self.assertFalse(self.hub.parallel_update_allowed('one',body))
        active['native_concurrency']='unknown_future_version';self.assertFalse(self.hub.parallel_update_allowed('one',body))
        active['native_concurrency']='engine_cross_lock_v1';self.assertTrue(self.hub.parallel_update_allowed('one',body))
        self.assertFalse(self.hub.parallel_update_allowed('one',dict(body,character_id='2')))
        self.assertFalse(self.hub.parallel_update_allowed('two',body))
        active['process'].poll.return_value=0;self.assertFalse(self.hub.parallel_update_allowed('one',body))
    def test_real_http_bypasses_global_gate_only_for_capable_owned_session(self):
        gate=RequestGate(.03,2);active=self.hub.sessions['one']
        server=ThreadingHTTPServer(('127.0.0.1',0),adapter.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        body={'account':'one','character_id':'1','session_id':'session_one','native_concurrency':'engine_cross_lock_v1'}
        def post(path):
            request=urllib.request.Request('http://127.0.0.1:%s%s'%(server.server_port,path),data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(request,timeout=1) as result:return result.status,json.load(result)
            except urllib.error.HTTPError as error:
                with error:return error.code,json.load(error)
        try:
            with patch.object(adapter,'LOCK',gate),patch.object(adapter,'LIVE_COMBAT',self.hub),patch.object(adapter,'gameplay_session',return_value={'native':True}) as gameplay:
                with gate:
                    self.assertEqual(post('/session/update')[0],503) # Forged body marker cannot bypass.
                    gameplay.assert_not_called()
                    active['native_concurrency']='engine_cross_lock_v1'
                    self.assertEqual(post('/session/update'),(200,{'native':True}))
                    self.assertEqual(post('/session/life')[0],503) # Other mutation routes retain their lane.
                    body['character_id']='2';self.assertEqual(post('/session/update')[0],503)
                self.assertEqual(gameplay.call_count,1)
        finally:server.shutdown();server.server_close();thread.join()
    def test_gameplay_envelope_copies_only_native_capability(self):
        reply={'session_id':'session_one','character_id':'1','session_live':True,'native_concurrency':'engine_cross_lock_v1'}
        with patch.object(adapter,'LIVE_COMBAT',self.hub),patch.object(self.hub,'request',return_value=reply):
            result=adapter.gameplay_session('one',{'character_id':'1','session_id':'session_one','native_concurrency':'forged'})
            self.assertEqual(result['native_concurrency'],'engine_cross_lock_v1')
            reply.pop('native_concurrency')
            self.assertEqual(adapter.gameplay_session('one',{'character_id':'1','session_id':'session_one','native_concurrency':'engine_cross_lock_v1'})['native_concurrency'],'')
    def test_start_records_only_matching_native_reply_capability(self):
        self.hub.sessions.clear()
        with tempfile.TemporaryDirectory() as directory,patch('server.live_combat.ROOT',Path(directory)),patch('server.live_combat.subprocess.Popen') as spawn:
            def launch(*args,**kwargs):
                for folder in (Path(directory)/'runtime/server/livecombat').iterdir():(folder/'ready.json').write_text('{}')
                process=Mock();process.poll.return_value=None;return process
            spawn.side_effect=launch
            for native_marker,wrong_owner,expected in [('',False,''),('engine_cross_lock_v1',False,'engine_cross_lock_v1'),('engine_cross_lock_v1',True,'')]:
                def exchange(active,command,**kwargs):return {'session_live':True,'session_id':active['id'],'character_id':'999'if wrong_owner else'1','native_concurrency':native_marker}
                self.hub._exchange=Mock(side_effect=exchange)
                self.hub.start('one',{'character_id':'1','position':[0,0,0],'native_concurrency':'engine_cross_lock_v1'},b'secret','local',lambda account:[{'id':'1'}])
                self.assertEqual(self.hub.sessions['one']['native_concurrency'],expected)
                self.hub.sessions.clear()

if __name__=='__main__':unittest.main()
