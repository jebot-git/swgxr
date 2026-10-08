#!/usr/bin/env python3
"""Bounded TLS WebSocket Opus relay; does not decode, record or log voice content."""
import argparse,asyncio,base64,hashlib,json,secrets,ssl,struct,time
from collections import deque
from pathlib import Path
try:
 from .voice_protocol import *
except ImportError:
 from voice_protocol import *

try:
 from .capacity import configured_limit
except ImportError:
 from capacity import configured_limit

MAX_CLIENTS=configured_limit('SWGXR_MAX_VOICE_CLIENTS')

def frame(opcode,payload):
 n=len(payload)
 return bytes([128|opcode,n]) + payload if n<126 else bytes([128|opcode,126])+struct.pack('!H',n)+payload

async def read_frame(reader):
 a,b=await reader.readexactly(2)
 if a&0x70 or not a&128 or not b&128:raise VoiceError('Unsupported WebSocket frame')
 n=b&127
 if n==126:n=struct.unpack('!H',await reader.readexactly(2))[0]
 elif n==127:raise VoiceError('Oversized WebSocket frame')
 opcode=a&15
 if n>2048 or opcode not in(1,2,8,9,10)or(opcode>=8 and n>125):raise VoiceError('Unsupported WebSocket frame')
 mask=await reader.readexactly(4);body=await reader.readexactly(n)
 return opcode,bytes(value^mask[i%4]for i,value in enumerate(body))

class Relay:
 def __init__(self,config):
  self.authority=TicketAuthority(Path(config['voice_secret']).read_bytes());self.credentials=Credentials(config)
  self.state_path=Path(config['voice_state']);self.states={};self.peers={};self.connections=0;self.server=None;self.ticker=None
 def state(self,claims):
  try:
   s=self.states.get(claims['a'])
   if not isinstance(s,dict)or s.get('character_id')!=claims['c'] or s.get('session_id')!=claims['s']:return None
   if not 0<=time.time()-s['updated_at']<=s['ttl'] or not 0<s['ttl']<=15:return None
   if s['faction']not in('neutral','rebel','imperial')or not isinstance(s['zone'],str)or not s['zone']:return None
   if not all(isinstance(s[key],str)and s[key].isdigit()for key in('character_id','group_id','zone_id')):return None
   if not 0<int(s['character_id'])<2**64:return None
   if not isinstance(s['position'],list)or len(s['position'])!=3 or any(type(x)not in(int,float)or not math.isfinite(x)or abs(x)>100000 for x in s['position']):return None
   return s
  except (KeyError,TypeError,ValueError):return None
 def control(self,p,kind,**extra):
  data={'type':kind,**extra};self.enqueue(p,(None,0,0,frame(1,json.dumps(data,separators=(',',':')).encode())))
 def enqueue(self,p,entry):
  if len(p['queue'])>=16:p['queue'].popleft()
  p['queue'].append((time.monotonic(),entry));p['wake'].set()
 def tune(self,p,channel,kind='tuned'):
  allowed,reasons=granted(p['state']);p['channel']=channel if channel in allowed else 'proximity'
  p['epoch']=(p['epoch']+1)&0xffffffff or 1;p['seq']=-1;p['queue'].clear();p['speakers'].clear();p['delivery_seq']={}
  self.control(p,kind,epoch=p['epoch'],channel=p['channel'],granted_channels=allowed,reasons=reasons)
 def signature(self,state):return(state['zone'],state['zone_id'],state['group_id'],state['faction'])
 def refresh_states(self):
  # Ticket issuance follows the source's atomic publication. Admission cannot
  # wait for the periodic cache refresh or it races the new character's entry.
  try:
   with self.state_path.open('rb')as stream:raw=stream.read(65537)
   self.states=json.loads(raw)if len(raw)<=65536 else {}
   if not isinstance(self.states,dict):self.states={}
  except (OSError,ValueError):self.states={}
 async def tick(self):
  while True:
   self.refresh_states()
   for key,p in list(self.peers.items()):
    state=self.state(p['claims'])
    if not state or not self.credentials.valid(p['claims']):p['writer'].close();continue
    changed=self.signature(state)!=self.signature(p['state']);p['state']=state
    if changed:self.tune(p,p['channel'])
    roster=[{'id':q['state']['character_id'],'name':str(q['state'].get('name',''))[:64]}for q in self.peers.values()if q is not p and q['channel']==p['channel']and audible(state,q['state'],p['channel'])]
    if roster!=p.get('roster'):p['roster']=roster;self.control(p,'roster',peers=roster)
   await asyncio.sleep(.1)
 async def send(self,p):
  while True:
   await p['wake'].wait()
   while p['queue']:
    queued_at,(sender,se,epoch,packet)=p['queue'].popleft()
    if sender is not None:
     if time.monotonic()-queued_at>.25:continue
     source=self.peers.get(sender)
     if not source or source['epoch']!=se or p['epoch']!=epoch or source['channel']!=p['channel']:continue
     if not audible(source['state'],p['state'],p['channel']):continue
    p['writer'].write(packet)
    await asyncio.wait_for(p['writer'].drain(),.25)
   p['wake'].clear()
 def audio(self,p,raw):
  if not 9<=len(raw)<=408:raise VoiceError('Invalid audio size')
  epoch,seq=CLIENT_HEADER.unpack_from(raw);payload=raw[8:]
  if epoch!=p['epoch'] or seq<=p['seq'] or seq>p['seq']+10000:raise VoiceError('Stale audio sequence')
  if not opus_20ms_mono(payload):raise VoiceError('Expected20ms mono Opus')
  now=time.monotonic();p['tokens']=min(6.,p['tokens']+(now-p['token_time'])*50);p['token_time']=now
  if p['tokens']<1:raise VoiceError('Audio rate exceeded')
  p['tokens']-=1;p['seq']=seq
  # Metadata is source-owned and shared by recipients; encoded payload remains opaque.
  for key,q in self.peers.items():
   if q['channel']!=p['channel'] or not audible(p['state'],q['state'],p['channel']):continue
   q['speakers']={speaker:at for speaker,at in q['speakers'].items()if now-at<1}
   speaker=p['state']['character_id']
   if speaker not in q['speakers'] and len(q['speakers'])>=8:continue
   q['speakers'][speaker]=now
   # Sender sequence restarts on its tune/reconnect. A listener's decoder
   # retains this speaker, so its delivery sequence resets only with its own epoch.
   delivery=q.setdefault('delivery_seq',{}).get(speaker,0)
   q['delivery_seq'][speaker]=delivery+1
   packet=SERVER_HEADER.pack(q['epoch'],delivery,int(speaker),*p['state']['position'])+payload
   self.enqueue(q,(p['key'],p['epoch'],q['epoch'],frame(2,packet)))
 async def accept(self,reader,writer):
  self.connections+=1;p=None;send_task=None
  try:
   if MAX_CLIENTS and self.connections>MAX_CLIENTS:raise VoiceError('Relay capacity reached')
   header=await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'),5)
   if len(header)>8192:raise VoiceError('Headers too large')
   lines=header.decode('ascii').split('\r\n')
   if lines[0]!='GET /voice HTTP/1.1':raise VoiceError('Invalid voice target')
   headers={}
   for line in lines[1:]:
    if not line:continue
    name,value=line.split(':',1);name=name.lower()
    if name in headers:raise VoiceError('Duplicate header')
    headers[name]=value.strip()
   if headers.get('origin')or headers.get('transfer-encoding')or headers.get('content-length'):raise VoiceError('Unsupported framing')
   if headers.get('upgrade','').lower()!='websocket'or 'upgrade'not in [part.strip()for part in headers.get('connection','').lower().split(',')]or headers.get('sec-websocket-version')!='13':raise VoiceError('Invalid upgrade')
   key=headers.get('sec-websocket-key','')
   if len(base64.b64decode(key,validate=True))!=16:raise VoiceError('Invalid WebSocket key')
   digest=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
   writer.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+digest+b'\r\n\r\n');await writer.drain()
   opcode,body=await asyncio.wait_for(read_frame(reader),5)
   hello=json.loads(body)
   if opcode!=1 or set(hello)!={'type','ticket'}or hello['type']!='hello':raise VoiceError('Voice hello required')
   claims=self.authority.consume(hello['ticket'])
   self.refresh_states()
   state=self.state(claims)
   if not state or not self.credentials.valid(claims):raise VoiceError('Voice authentication unavailable')
   if claims['a']in self.peers:self.peers[claims['a']]['writer'].close()
   p={'key':claims['a'],'claims':claims,'state':state,'channel':'proximity','epoch':secrets.randbits(31),'seq':-1,'queue':deque(),'wake':asyncio.Event(),'writer':writer,'speakers':{},'tokens':6.,'token_time':time.monotonic(),'controls':deque()}
   self.peers[p['key']]=p;self.tune(p,'proximity','hello');send_task=asyncio.create_task(self.send(p))
   def sender_done(task):
    if not task.cancelled():task.exception()
    writer.close()
   send_task.add_done_callback(sender_done)
   while True:
    opcode,body=await read_frame(reader)
    if not self.state(claims):raise VoiceError('Native voice state stale')
    if opcode==8:break
    if opcode==2:self.audio(p,body);continue
    now=time.monotonic();p['controls']=deque(t for t in p['controls']if now-t<1)
    if len(p['controls'])>=10:raise VoiceError('Control rate exceeded')
    p['controls'].append(now)
    if opcode==9:self.enqueue(p,(None,0,0,frame(10,body)));continue
    if opcode==10:continue
    request=json.loads(body)
    if set(request)!={'type','channel'}or request['type']!='tune'or request['channel']not in CHANNELS:raise VoiceError('Invalid voice control')
    self.tune(p,request['channel'])
  except (Exception,asyncio.CancelledError):pass # Never log tickets, request text or voice content.
  finally:
   if p and self.peers.get(p['key'])is p:self.peers.pop(p['key'],None)
   if send_task:send_task.cancel()
   writer.close()
   try:await writer.wait_closed()
   except Exception:pass
   self.connections-=1
 async def start(self,host,port,context):
  self.server=await asyncio.start_server(self.accept,host,port,ssl=context,limit=8193,backlog=32,**({'ssl_handshake_timeout':5,'ssl_shutdown_timeout':2}if context else {}))
  self.ticker=asyncio.create_task(self.tick());await asyncio.sleep(.01);return self.server
 async def close(self):
  if self.ticker:self.ticker.cancel()
  for p in list(self.peers.values()):p['writer'].close()
  if self.server:self.server.close();await self.server.wait_closed()

async def run(args):
 config=json.loads(args.config.read_text());context=None
 if args.loopback_debug:
  if args.bind not in('127.0.0.1','::1'):raise ValueError('Plaintext debug relay must bind loopback')
  config['_loopback_debug']=True
 else:
  context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_2;context.load_cert_chain(config['certificate'],config['private_key'])
 relay=Relay(config);await relay.start(args.bind,args.port,context)
 try:await relay.server.serve_forever()
 finally:await relay.close()
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',type=Path,required=True);parser.add_argument('--loopback-debug',action='store_true');parser.add_argument('--bind',default='127.0.0.1');parser.add_argument('--port',type=int,default=18444);asyncio.run(run(parser.parse_args()))
