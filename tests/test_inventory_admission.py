"""Readout refresh never waits behind an in-flight authoritative mutation."""
import json,threading,time,unittest,urllib.request,urllib.error
from http.server import ThreadingHTTPServer
from server.adapter import Handler,LOCK
class InventoryAdmission(unittest.TestCase):
 def test_inventory_read_fails_fast_while_mutation_pending(self):
  server=ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
  try:
   with LOCK:
    for path,payload in [('/inventory?account=test&character_id=1',None),('/inventory/status',{'account':'test','character_id':'1'})]:
     request=urllib.request.Request('http://127.0.0.1:'+str(server.server_address[1])+path,data=json.dumps(payload).encode()if payload else None,headers={'Content-Type':'application/json'})
     stamp=time.monotonic()
     with self.assertRaises(urllib.error.HTTPError)as caught:urllib.request.urlopen(request,timeout=1)
     self.assertLess(time.monotonic()-stamp,.5);self.assertEqual(caught.exception.code,503)
     body=json.load(caught.exception);caught.exception.close();self.assertEqual(body['error_code'],'backend_busy');self.assertIs(body['mutation_started'],False)
  finally:server.shutdown();server.server_close();thread.join()
