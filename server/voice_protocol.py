"""Bounded voice control plane and native-only routing metadata. No audio decoding."""
import base64, hashlib, hmac, json, math, os, secrets, sqlite3, struct, threading, time
from pathlib import Path
from contextlib import closing

CHANNELS=('proximity','group','planet','faction')
CLIENT_HEADER=struct.Struct('<II')
SERVER_HEADER=struct.Struct('<IIQfff')
MAX_AUDIO=400

class VoiceError(ValueError): pass

def opus_20ms_mono(payload):
    if not 1<=len(payload)<=MAX_AUDIO or payload[0]&4: return False
    config,code=payload[0]>>3,payload[0]&3
    duration=([100,200,400,600][config%4] if config<12 else [100,200][config%2] if config<16 else [25,50,100,200][config%4])
    frames=1 if code==0 else 2 if code<3 else (payload[1]&63 if len(payload)>1 else 0)
    return frames>0 and duration*frames==200

class NativeVoiceState:
    def __init__(self,path): self.path=Path(path);self.lock=threading.Lock();self.states={}
    def publish(self,account,character_id,player,*,session_id='',live=False):
        voice=player.get('voice',{})
        # Require a full source-owned membership envelope. Never infer neutral or solo.
        if not {'group_id','faction','zone_id'}<=voice.keys(): return
        position=player.get('position');zone=player.get('zone')
        if not isinstance(position,list)or len(position)!=3 or any(type(x)not in(int,float)or not math.isfinite(x)for x in position):return
        if not isinstance(zone,str)or not zone:return
        state={'account':account,'character_id':str(character_id),'session_id':session_id,'live':live,
               'name':player.get('name',str(character_id)),'position':position,'zone':zone,'zone_id':str(voice['zone_id']),
               'group_id':str(voice['group_id']),'faction':voice['faction'],'updated_at':time.time(),'ttl':4 if live else 15}
        with self.lock:
            self.states[account]=state;self._save()
    def remove(self,account):
        with self.lock:self.states.pop(account,None);self._save()
    def _save(self):
        now=time.time();self.states={a:s for a,s in self.states.items()if now-s['updated_at']<=s['ttl']}
        if len(self.states)>64:raise VoiceError('Voice participant capacity reached')
        self.path.parent.mkdir(parents=True,exist_ok=True)
        temporary=self.path.with_suffix('.tmp');temporary.write_text(json.dumps(self.states,separators=(',',':')));temporary.chmod(0o640);temporary.replace(self.path)
    def owned(self,account,character_id,session_id=None):
        with self.lock:
            state=self.states.get(account)
            if not state or state['character_id']!=str(character_id)or time.time()-state['updated_at']>state['ttl']:raise VoiceError('Fresh native voice state required')
            if session_id is not None and state['session_id']!=session_id:raise VoiceError('Native voice session mismatch')
            return dict(state)

def granted(state):
    channels=['proximity','planet'];reasons={}
    if state['group_id']!='0':channels.append('group')
    else:reasons['group']='Join a native Core3 group first'
    if state['faction']in('rebel','imperial'):channels.append('faction')
    else:reasons['faction']='Rebel or Imperial enrollment required'
    return channels,reasons

def audible(a,b,channel):
    if a['character_id']==b['character_id']:return False
    same_zone=a['zone']==b['zone'] and a['zone_id']==b['zone_id']
    if channel=='proximity':return same_zone and sum((x-y)**2 for x,y in zip(a['position'],b['position']))<=64**2
    if channel=='planet':return same_zone
    if channel=='group':return a['group_id']!='0' and a['group_id']==b['group_id']
    if channel=='faction':return a['faction']in('rebel','imperial') and a['faction']==b['faction']
    return False

class TicketAuthority:
    def __init__(self,secret):
        if len(secret)<32:raise ValueError('Voice secret requires at least32 random bytes')
        self.secret=secret;self.used={};self.lock=threading.Lock()
    def issue(self,account,character_id,session_id,credential_digest,legacy,auth_expiry):
        now=time.time();claims={'a':account,'c':str(character_id),'s':session_id,'h':credential_digest,'l':bool(legacy),'x':auth_expiry,'e':now+30,'n':secrets.token_hex(16)}
        body=base64.urlsafe_b64encode(json.dumps(claims,separators=(',',':')).encode()).rstrip(b'=')
        signature=hmac.new(self.secret,body,hashlib.sha256).hexdigest().encode()
        return (body+b'.'+signature).decode()
    def consume(self,ticket):
        if not isinstance(ticket,str)or len(ticket)>2048:raise VoiceError('Invalid voice ticket')
        try:
            body,signature=ticket.encode('ascii').split(b'.')
            if not hmac.compare_digest(hmac.new(self.secret,body,hashlib.sha256).hexdigest().encode(),signature):raise VoiceError('Invalid voice ticket')
            claims=json.loads(base64.urlsafe_b64decode(body+b'='*((-len(body))%4)))
            now=time.time()
            if claims['e']<=now or claims['e']>now+31 or claims['x']<=now:raise VoiceError('Expired voice ticket')
            with self.lock:
                self.used={n:e for n,e in self.used.items()if e>now}
                if claims['n']in self.used:raise VoiceError('Voice ticket already used')
                if len(self.used)>=4096:raise VoiceError('Voice ticket capacity reached')
                self.used[claims['n']]=claims['e']
            return claims
        except (KeyError,TypeError,UnicodeError,ValueError):raise VoiceError('Invalid or expired voice ticket')from None

class Credentials:
    def __init__(self,config):self.database=config.get('auth_database');self.accounts=config.get('accounts',{});self.local_debug=config.get('_loopback_debug',False)
    def valid(self,claims):
        if claims.get('x',0)<=time.time():return False
        try:
            if self.local_debug and claims['l'] and claims['h']=='local-debug':return True
            if claims['l']:
                digest=self.accounts.get(claims['a'],'')
                if not hmac.compare_digest(digest,claims['h']):return False
                if not self.database:return True
                with closing(sqlite3.connect('file:'+self.database+'?mode=ro',uri=True,timeout=.1))as db:
                    row=db.execute('SELECT legacy_disabled FROM credentials WHERE account=?',(claims['a'],)).fetchone()
                    return not row or not row[0]
            if not self.database:return False
            with closing(sqlite3.connect('file:'+self.database+'?mode=ro',uri=True,timeout=.1))as db:
                row=db.execute('SELECT account,expires_at FROM sessions WHERE token_hash=?',(claims['h'],)).fetchone()
                return bool(row and row[0]==claims['a'] and row[1]>time.time())
        except (sqlite3.Error,KeyError,OSError):return False

ROOT=Path(__file__).resolve().parents[1]
NATIVE=NativeVoiceState(os.environ.get('SWGXR_VOICE_STATE',str(ROOT/'runtime/server/voice-state.json')))

LOCAL_AUTHORITY=None
def local_authority():
    global LOCAL_AUTHORITY
    if LOCAL_AUTHORITY is None:
        explicit=os.environ.get('SWGXR_VOICE_SECRET')
        path=Path(explicit or ROOT/'runtime/server/voice.secret')
        if not explicit and not path.exists():
            path.parent.mkdir(parents=True,exist_ok=True)
            try:
                fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                with os.fdopen(fd,'wb')as stream:stream.write(secrets.token_bytes(32))
            except FileExistsError:pass
        LOCAL_AUTHORITY=TicketAuthority(path.read_bytes())
    return LOCAL_AUTHORITY
