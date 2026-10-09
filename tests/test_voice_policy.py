import asyncio,json,tempfile,time,unittest
from collections import deque
from pathlib import Path
from server.voice_protocol import *
from server.voice_relay import Relay

class Tests(unittest.TestCase):
 def state(self,oid,**changes):return dict({'account':str(oid),'character_id':str(oid),'session_id':'','position':[0,0,0],'zone':'tatooine','zone_id':'12','group_id':'1','faction':'rebel','updated_at':time.time(),'ttl':15},**changes)
 def test_source_partition_and_radius(self):
  a=self.state(1);b=self.state(2,position=[64,0,0]);self.assertTrue(audible(a,b,'proximity'));b['position'][0]=64.01;self.assertFalse(audible(a,b,'proximity'))
  b['zone_id']='13';self.assertFalse(audible(a,b,'planet'));self.assertTrue(audible(a,b,'group'))
  a['group_id']=b['group_id']='0';self.assertFalse(audible(a,b,'group'))
  a['faction']=b['faction']='neutral';self.assertFalse(audible(a,b,'faction'))
 def test_ticket_signature_expiry_replay(self):
  t=TicketAuthority(b'a'*32);token=t.issue('alice','1','','hash',False,time.time()+86400)
  self.assertEqual(t.consume(token)['a'],'alice')
  with self.assertRaises(VoiceError):t.consume(token)
  with self.assertRaises(VoiceError):t.consume(token[:-1]+'z')
  expired=t.issue('alice','1','','hash',False,time.time()-1)
  with self.assertRaises(VoiceError):t.consume(expired)
 def test_source_cache_requires_native_membership(self):
  with tempfile.TemporaryDirectory()as tmp:
   n=NativeVoiceState(Path(tmp)/'state.json');n.publish('alice','1',{'position':[0,0,0],'zone':'tatooine'})
   with self.assertRaises(VoiceError):n.owned('alice','1')
   n.publish('alice','1',{'position':[0,0,0],'zone':'tatooine','voice':{'group_id':'0','zone_id':'12','faction':'neutral'}})
   self.assertEqual(n.owned('alice','1')['group_id'],'0')
   with self.assertRaises(VoiceError):n.owned('alice','2')
   n.remove('alice')
   with self.assertRaises(VoiceError):n.owned('alice','1')
 def test_native_voice_participants_can_exceed_old_sixty_four_cap(self):
  with tempfile.TemporaryDirectory()as tmp:
   n=NativeVoiceState(Path(tmp)/'state.json')
   for i in range(80):n.publish('loadtest'+str(i),str(i+1),{'position':[0,0,0],'zone':'tatooine','voice':{'group_id':'0','zone_id':'12','faction':'neutral'}})
   self.assertEqual(len(n.states),80)
   self.assertEqual(n.owned('loadtest79','80')['character_id'],'80')
 def test_queue_and_eight_active_speaker_limits(self):
  relay=object.__new__(Relay);relay.peers={};relay.states={}
  for oid in range(1,11):
   p={'key':str(oid),'claims':{'a':str(oid),'c':str(oid),'s':''},'state':self.state(oid),'channel':'proximity','epoch':1,'seq':-1,'queue':deque(),'wake':asyncio.Event(),'speakers':{},'tokens':6.,'token_time':time.monotonic()};relay.peers[str(oid)]=p;relay.states[str(oid)]=p['state']
  listener=relay.peers['10']
  for oid in range(1,10):relay.audio(relay.peers[str(oid)],CLIENT_HEADER.pack(1,0)+b'\x98\x00')
  self.assertEqual(len(listener['speakers']),8);self.assertEqual(len(listener['queue']),8)
  for _ in range(100):relay.enqueue(listener,('source',1,1,b'test'))
  self.assertEqual(len(listener['queue']),16)

if __name__=='__main__':unittest.main()
