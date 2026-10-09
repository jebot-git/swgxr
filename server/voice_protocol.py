"""Bounded voice control plane and native-only routing metadata. No audio decoding."""
import base64, hashlib, hmac, json, math, os, secrets, sqlite3, struct, threading, time
from pathlib import Path
from contextlib import closing

CHANNELS=('proximity','group','planet','sector','faction')
CLIENT_HEADER=struct.Struct('<II')
SERVER_HEADER=struct.Struct('<IIQfff')
MAX_AUDIO=400

class VoiceError(ValueError): pass

def identifier(value,allow_zero=True):
    if type(value)not in(str,int):raise VoiceError('Native routing identity required')
    value=str(value)
    if not value.isascii()or not value.isdigit()or not (0 if allow_zero else 1)<=int(value)<2**64:raise VoiceError('Native routing identity required')
    return value

def routing_scope(state):
    # Old ground snapshots remain compatible; a space snapshot must explicitly
    # identify its sector and hull before it can grant any voice permission.
    space=str(state.get('zone','')).startswith('space_')
    scope=state.get('scope','sector' if space else 'planet')
    if scope not in('planet','sector')or (scope=='sector')!=space:raise VoiceError('Native voice scope mismatch')
    return scope

def validate_state(state):
    if not isinstance(state,dict):raise VoiceError('Native voice state required')
    if state.get('faction')not in('neutral','rebel','imperial'):raise VoiceError('Native faction required')
    if not isinstance(state.get('zone'),str)or not 0<len(state['zone'])<=96:raise VoiceError('Native zone required')
    for key in('character_id','group_id','zone_id'):
        if not isinstance(state.get(key),str):raise VoiceError('Canonical native voice identity required')
        identifier(state[key],key=='group_id')
    scope=routing_scope(state)
    if not isinstance(state.get('ship_id','0'),str)or not isinstance(state.get('building_id','0'),str):raise VoiceError('Canonical native location identity required')
    hull=identifier(state.get('ship_id','0'))
    if scope=='sector' and (state.get('scope')!='sector' or hull=='0'):raise VoiceError('Native space hull required')
    if scope=='planet' and hull!='0':raise VoiceError('Ground voice cannot use a space hull')
    identifier(state.get('building_id','0'))
    cell=state.get('cell_index',0)
    if type(cell)is not int or not 0<=cell<=256:raise VoiceError('Native voice cell required')
    if not isinstance(state.get('position'),list)or len(state['position'])!=3 or any(type(x)not in(int,float)or not math.isfinite(x)or abs(x)>100000 for x in state['position']):raise VoiceError('Native voice position required')
    return state

def opus_20ms_mono(payload):
    if not 1<=len(payload)<=MAX_AUDIO or payload[0]&4: return False
    config,code=payload[0]>>3,payload[0]&3
    duration=([100,200,400,600][config%4] if config<12 else [100,200][config%2] if config<16 else [25,50,100,200][config%4])
    frames=1 if code==0 else 2 if code<3 else (payload[1]&63 if len(payload)>1 else 0)
    return frames>0 and duration*frames==200

class NativeVoiceState:
    def __init__(self,path,clock=time.time): self.path=Path(path);self.lock=threading.Lock();self.states={};self.clock=clock
    def publish(self,account,character_id,player,*,session_id='',live=False):
        account=account.lower()
        try:
            voice=player.get('voice',{})
            if not isinstance(voice,dict)or not {'group_id','faction','zone_id'}<=voice.keys():raise VoiceError('Native membership required')
            state={'account':account,'character_id':identifier(character_id,False),'session_id':session_id,'live':live,
                   'name':str(player.get('name',character_id))[:96],'position':player.get('position'),'zone':player.get('zone'),
                   'zone_id':identifier(voice['zone_id'],False),'group_id':identifier(voice['group_id']),'faction':voice['faction'],
                   'scope':voice.get('scope','planet'),'ship_id':identifier(voice.get('ship_id','0')),
                   'building_id':identifier(player.get('building_id','0')),'cell_index':player.get('cell_index',0),
                   'updated_at':self.clock(),'ttl':4 if live else 15}
            validate_state(state)
            state['position']=list(state['position'])
        except (VoiceError,AttributeError,TypeError):
            self.remove(account)
            return
        with self.lock:
            self.states[account]=state;self._save()
    def remove(self,account):
        with self.lock:self.states.pop(account.lower(),None);self._save()
    def _save(self):
        now=self.clock();self.states={a:s for a,s in self.states.items()if 0<=now-s['updated_at']<=s['ttl']}
        self.path.parent.mkdir(parents=True,exist_ok=True)
        temporary=self.path.with_suffix('.tmp');temporary.write_text(json.dumps(self.states,separators=(',',':')));temporary.chmod(0o640);temporary.replace(self.path)
    def owned(self,account,character_id,session_id=None):
        with self.lock:
            state=self.states.get(account.lower())
            if not state or state['character_id']!=str(character_id)or not 0<=self.clock()-state['updated_at']<=state['ttl']:raise VoiceError('Fresh native voice state required')
            if session_id is not None and state['session_id']!=session_id:raise VoiceError('Native voice session mismatch')
            return dict(state,position=list(state['position']))

def granted(state):
    scope=routing_scope(state)
    channels=['proximity',scope];reasons={'planet' if scope=='sector' else 'sector':'Planet chat is available on the ground' if scope=='sector' else 'Sector chat is available in space'}
    if state['group_id']!='0':channels.append('group')
    else:reasons['group']='Join a native Core3 group first'
    if state['faction']in('rebel','imperial'):channels.append('faction')
    else:reasons['faction']='Rebel or Imperial enrollment required'
    return channels,reasons

def audible(a,b,channel):
    if a['character_id']==b['character_id']:return False
    same_zone=a['zone']==b['zone'] and a['zone_id']==b['zone_id']
    scope_a,scope_b=routing_scope(a),routing_scope(b)
    if channel=='proximity':
        same_hull=scope_a==scope_b and a.get('ship_id','0')==b.get('ship_id','0')
        if scope_a=='sector':same_hull=same_hull and a.get('ship_id','0')!='0'
        else:same_hull=same_hull and a.get('building_id','0')==b.get('building_id','0')
        return same_zone and same_hull and sum((x-y)**2 for x,y in zip(a['position'],b['position']))<=64**2
    if channel=='planet':return same_zone and scope_a==scope_b=='planet'
    if channel=='sector':return same_zone and scope_a==scope_b=='sector'
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
