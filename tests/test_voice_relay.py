import asyncio,base64,hashlib,json,secrets,ssl,struct,subprocess,tempfile,time,unittest
from pathlib import Path
from server.account_auth import AccountAuth
from server.voice_protocol import CLIENT_HEADER,SERVER_HEADER,TicketAuthority,opus_20ms_mono,audible
from server.voice_relay import Relay

class Tests(unittest.IsolatedAsyncioTestCase):
 async def asyncSetUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.cert=self.root/'cert.pem';self.key=self.root/'key.pem'
  subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=voice-test','-addext','subjectAltName=IP:127.0.0.1','-keyout',str(self.key),'-out',str(self.cert)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  (self.root/'secret').write_bytes(secrets.token_bytes(32));self.auth=AccountAuth(self.root/'auth.sqlite',registration_enabled=True);self.sessions={};self.states={};self.clients=[]
  for i,name in enumerate(('alice','bob','carol')):
   self.sessions[name]=self.auth.register(name,'only a test password','ip'+str(i))
   self.states[name]={'account':name,'character_id':str(101+i),'session_id':'','name':name,'position':[i*10 if i<2 else 80,0,0],'zone':'tatooine','zone_id':'55','group_id':'10'if i<2 else'20','faction':'rebel'if i<2 else'imperial','updated_at':time.time(),'ttl':15}
  self.write_states();config={'voice_secret':str(self.root/'secret'),'voice_state':str(self.root/'state.json'),'auth_database':str(self.root/'auth.sqlite'),'accounts':{}}
  self.relay=Relay(config);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(self.cert,self.key)
  self.server=await self.relay.start('127.0.0.1',0,context);self.port=self.server.sockets[0].getsockname()[1];self.context=ssl.create_default_context(cafile=str(self.cert))
 async def asyncTearDown(self):
  for c in self.clients:c['writer'].close()
  await self.relay.close();await asyncio.sleep(.02);self.temp.cleanup()
 def write_states(self):
  for state in self.states.values():state['updated_at']=time.time()
  (self.root/'state.json').write_text(json.dumps(self.states))
 def ticket(self,name):
  session=self.sessions[name];return self.relay.authority.issue(name,self.states[name]['character_id'],'',hashlib.sha256(session['token'].encode()).hexdigest(),False,session['expires_at'])
 async def send(self,c,opcode,payload):
  mask=secrets.token_bytes(4);n=len(payload);header=bytes([128|opcode,128|n])if n<126 else bytes([128|opcode,254])+struct.pack('!H',n)
  c['writer'].write(header+mask+bytes(b^mask[i%4]for i,b in enumerate(payload)));await c['writer'].drain()
 async def receive(self,c):
  a,b=await c['reader'].readexactly(2);n=b&127
  if n==126:n=struct.unpack('!H',await c['reader'].readexactly(2))[0]
  return a&15,await c['reader'].readexactly(n)
 async def next(self,c,opcode,timeout=.5,kind=None):
  async def loop():
   while True:
    op,payload=await self.receive(c)
    if op==opcode and(kind is None or json.loads(payload).get('type')==kind):return payload
  return await asyncio.wait_for(loop(),timeout)
 async def connect(self,name,ticket=None):
  reader,writer=await asyncio.open_connection('127.0.0.1',self.port,ssl=self.context,server_hostname='127.0.0.1');c={'reader':reader,'writer':writer};self.clients.append(c)
  writer.write(b'GET /voice HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: '+base64.b64encode(secrets.token_bytes(16))+b'\r\n\r\n');await writer.drain();self.assertIn(b'101',await reader.readuntil(b'\r\n\r\n'))
  await self.send(c,1,json.dumps({'type':'hello','ticket':ticket or self.ticket(name)}).encode());hello=json.loads(await self.next(c,1,kind='hello'));c.update(epoch=hello['epoch'],seq=0,hello=hello);return c
 async def tune(self,c,channel):
  await self.send(c,1,json.dumps({'type':'tune','channel':channel}).encode());result=json.loads(await self.next(c,1,kind='tuned'));c['epoch']=result['epoch'];c['seq']=0;return result
 async def audio(self,c):
  await self.send(c,2,CLIENT_HEADER.pack(c['epoch'],c['seq'])+b'\x98\x00');c['seq']+=1
 async def silent(self,c):
  with self.assertRaises(asyncio.TimeoutError):await self.next(c,2,timeout=.12)
 async def roster(self,c,ids):
  async def wait():
   while True:
    message=json.loads(await self.next(c,1,kind='roster'))
    if {p['id']for p in message['peers']}==set(ids):return
  await asyncio.wait_for(wait(),1)
 async def test_rosters_follow_tune_disconnect_and_reconnect(self):
  a=await self.connect('alice');b=await self.connect('bob')
  await self.roster(a,['102']);await self.roster(b,['101'])
  await self.tune(b,'planet');await self.roster(a,[]);await self.roster(b,[])
  await self.tune(a,'planet');await self.roster(a,['102']);await self.roster(b,['101'])
  b['writer'].close();await self.roster(a,[])
  b=await self.connect('bob');await self.roster(b,[])
  await self.tune(b,'planet');await self.roster(a,['102']);await self.roster(b,['101'])
  await self.send(b,8,b'');await self.roster(a,[])
  self.assertNotIn('bob',self.relay.peers)
 async def test_replacement_connection_survives_old_socket_cleanup(self):
  a=await self.connect('alice');b=await self.connect('bob')
  replacement=await self.connect('alice')
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(a,2)
  await self.audio(replacement);packet=SERVER_HEADER.unpack_from(await self.next(b,2))
  self.assertEqual(packet[2],101)
  self.assertEqual(set(self.relay.peers),{'alice','bob'})
 async def test_expired_source_closes_socket_and_removes_roster(self):
  a=await self.connect('alice');b=await self.connect('bob')
  await self.roster(a,['102']);await self.roster(b,['101'])
  self.states['bob']['ttl']=.2;self.write_states()
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(b,2,timeout=1)
  await self.roster(a,[])
  self.assertNotIn('bob',self.relay.peers)
 async def test_encrypted_three_client_channel_routing_and_membership(self):
  a,b,c=[await self.connect(n)for n in('alice','bob','carol')]
  self.assertIsNotNone(a['writer'].get_extra_info('ssl_object'))
  await self.audio(a);raw=await self.next(b,2);header=SERVER_HEADER.unpack_from(raw);self.assertEqual(header[:3],(b['epoch'],0,101));self.assertEqual(header[3:],(0,0,0));await self.silent(c)
  for peer in(a,b,c):await self.tune(peer,'planet')
  await self.audio(a);await self.next(b,2);await self.next(c,2)
  for peer in(a,b,c):await self.tune(peer,'group')
  await self.audio(a);await self.next(b,2);await self.silent(c)
  for peer in(a,b,c):await self.tune(peer,'faction')
  await self.audio(a);await self.next(b,2);await self.silent(c)
  self.states['bob']['faction']='neutral';self.write_states();change=json.loads(await self.next(b,1,kind='tuned'));self.assertEqual(change['channel'],'proximity');self.assertNotIn('faction',change['granted_channels'])
  await self.audio(a);await self.silent(b)
 async def test_admission_observes_source_publication_before_next_tick(self):
  # The first account is already connected. Native RPC then publishes a new
  # account, and its TLS hello arrives before the next100ms cache refresh.
  await self.connect('alice')
  self.relay.ticker.cancel()
  try:await self.relay.ticker
  except asyncio.CancelledError:pass
  self.relay.states={'alice':dict(self.states['alice'])}
  self.write_states()
  b=await self.connect('bob')
  self.assertEqual(b['hello']['type'],'hello')
  self.assertIn('bob',self.relay.peers)
 async def test_listener_delivery_sequence_survives_speaker_retune_and_reconnect(self):
  a=await self.connect('alice');b=await self.connect('bob')
  await self.audio(a);first=SERVER_HEADER.unpack_from(await self.next(b,2));self.assertEqual(first[1],0)
  await self.tune(a,'planet');await self.tune(a,'proximity')
  await self.audio(a);second=SERVER_HEADER.unpack_from(await self.next(b,2));self.assertEqual(second[1],1);self.assertEqual(second[0],first[0])
  a['writer'].close();await asyncio.sleep(.03);a=await self.connect('alice')
  await self.audio(a);third=SERVER_HEADER.unpack_from(await self.next(b,2));self.assertEqual(third[1],2);self.assertEqual(third[0],first[0])
  await self.tune(b,'planet');await self.tune(b,'proximity')
  await self.audio(a);reset=SERVER_HEADER.unpack_from(await self.next(b,2));self.assertEqual(reset[1],0);self.assertNotEqual(reset[0],first[0])
 async def test_spoof_replay_one_use_and_rate_fail_closed(self):
  ticket=self.ticket('alice');a=await self.connect('alice',ticket)
  with self.assertRaises(asyncio.IncompleteReadError):await self.connect('alice',ticket)
  await self.send(a,1,json.dumps({'type':'tune','channel':'group','group_id':'20'}).encode())
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(a,2)
  b=await self.connect('bob');await self.audio(b)
  await self.send(b,2,CLIENT_HEADER.pack(b['epoch'],0)+b'\x98\x00')
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(b,2)
  c=await self.connect('carol')
  for i in range(12):
   try:await self.audio(c)
   except (ConnectionError,ssl.SSLError):break
  with self.assertRaises((asyncio.IncompleteReadError,ConnectionError,ssl.SSLError)):await self.next(c,2)
 async def test_logout_and_stale_native_metadata_disconnect(self):
  a=await self.connect('alice');self.auth.logout(self.sessions['alice']['token'])
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(a,2)
  b=await self.connect('bob');self.states.pop('bob');self.write_states()
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(b,2)
 async def test_boundaries_invalid_codec_epoch_and_channel_grants(self):
  self.states['alice']['group_id']='0';self.states['alice']['faction']='neutral';self.write_states();await asyncio.sleep(.12)
  a=await self.connect('alice');self.assertEqual(set(a['hello']['granted_channels']),{'proximity','planet'})
  denied=await self.tune(a,'group');self.assertEqual(denied['channel'],'proximity')
  await self.send(a,2,CLIENT_HEADER.pack(a['epoch']-1,0)+b'\x98\x00')
  with self.assertRaises(asyncio.IncompleteReadError):await self.next(a,2)
  self.assertTrue(opus_20ms_mono(b'\x98\x00'));self.assertFalse(opus_20ms_mono(b'\x9c\x00'));self.assertFalse(opus_20ms_mono(b'\x98'*401));self.assertFalse(opus_20ms_mono(b'\x90\x00'))

if __name__=='__main__':unittest.main()
