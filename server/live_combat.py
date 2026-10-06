"""Bounded authenticated persistent Core3 zone session; private file IPC only."""
from __future__ import annotations
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
import atexit,hashlib,hmac,json,math,os,re,secrets,subprocess,time
try:
 from .voice_protocol import NATIVE as VOICE_STATE
except ImportError:
 from voice_protocol import NATIVE as VOICE_STATE
try:
 from .request_gate import RequestGate, BackendBusy
except ImportError:
 from request_gate import RequestGate, BackendBusy
from collections import deque
from pathlib import Path
try:
 from .multiplayer_sync import HUB as WORLD_SYNC
except ImportError:
 from multiplayer_sync import HUB as WORLD_SYNC
try:
 from .character_protocol import template_names,decode_customization
except ImportError:
 from character_protocol import template_names,decode_customization
ROOT=Path(__file__).resolve().parents[1]
class LiveConflict(ValueError):pass

def native_session_capacity():
 value=os.environ.get('SWGXR_MAX_NATIVE_SESSIONS','10')
 if not re.fullmatch(r'[0-9]+',value) or not 1<=int(value)<=16:
  raise ValueError('SWGXR_MAX_NATIVE_SESSIONS must be an integer from 1 to 16.')
 return int(value)

class LiveCombatHub:
 def __init__(self):
  self.max_sessions=native_session_capacity()
  self.sessions={};atexit.register(self.close)
 @property
 def active(self):
  # Compatibility diagnostics only; account routing uses active_for.
  return next(iter(self.sessions.values()),None)
 def active_for(self,account):
  return self.sessions.get(account.lower())
 def parallel_update_allowed(self,account,data):
  active=self.active_for(account)
  return bool(active and active.get('native_concurrency')=='engine_cross_lock_v1'
   and active['process'].poll() is None and active['character_id']==str(data.get('character_id',''))
   and active['id']==data.get('session_id',data.get('live_session_id','')))
 def guard(self,account):
  account=account.lower()
  active=self.active_for(account)
  if active:
   if active['process'].poll() is not None:self.close(account);return
   raise LiveConflict('A live Core3 combat session owns this account; stop it before legacy roster or character creation RPCs.')
 def close(self,account=None):
  if account is None:
   for key in list(self.sessions):self.close(key)
   return
  active=self.sessions.pop(account.lower(),None)
  if not active:return
  try:VOICE_STATE.remove(account.lower())
  except OSError:pass
  WORLD_SYNC.remove(account.lower())
  try:
   if active['process'].poll() is None:
    self._exchange(active,{'action':'stop','session_id':active['id']},timeout=2)
    try:active['process'].wait(timeout=2)
    except subprocess.TimeoutExpired:active['process'].terminate()
  except Exception:
   if active['process'].poll() is None:active['process'].terminate()
  # The final native stop reply can publish once more; clear it after IPC too.
  WORLD_SYNC.remove(account.lower())
  try:VOICE_STATE.remove(account.lower())
  except OSError:pass
  active['options'].unlink(missing_ok=True)
  (active['folder']/'final.json').unlink(missing_ok=True)
 def _record(self,active,command,result):
  # Bounded local diagnostics; never retain credentials or entire actor snapshots.
  action=command.get('action','unknown');counts=active.setdefault('action_counts',{})
  counts[action]=counts.get(action,0)+1
  if action not in ('start','fire','impact','stop','life') and not result.get('error_code'):return
  mutation=result.get('mutation',{});snap=result.get('snapshot',{});player=snap.get('player',{})
  entry={'time_unix':time.time(),'action':action,'sequence':result.get('sequence'),
   'life_action':command.get('life_action'),'shot_id':command.get('shot_id'),'item_id':command.get('item_id'),'target_id':command.get('target_id'),
   'error_code':result.get('error_code',mutation.get('error_code')),'success':mutation.get('success'),
   'native_result':mutation.get('native_result'),'damage':mutation.get('damage'),
   'ham_cost_committed':mutation.get('ham_cost_committed'),'ready':snap.get('ready'),
   'player_ham':player.get('ham'),'player_posture':player.get('posture')}
  events=active.setdefault('events',deque(maxlen=128));events.append(entry)
  tmp=active['folder']/'audit.tmp';tmp.write_text(json.dumps({'capacity':128,'counts':counts,'events':list(events)},separators=(',',':')));tmp.chmod(0o600);tmp.replace(active['folder']/'audit.json')
 def _exchange(self,active,command,timeout=12):
  # Each native child has one file mailbox and one rate budget. Unrelated
  # capable children may overlap their network wait, never their own mailbox.
  with active.setdefault('ipc_gate',RequestGate()):
   return self._exchange_owned(active,command,timeout)
 def _exchange_owned(self,active,command,timeout=12):
  # Core3 rejects >5 source commands/second without an attribute response.
  # All requests for this account share the budget, including shots/contacts.
  delay=active.get("next_command_at",0)-time.monotonic()
  if delay>0:time.sleep(delay)
  active["next_command_at"]=time.monotonic()+.275
  request_id=secrets.token_hex(12);command=dict(command,request_id=request_id)
  folder=active['folder'];(folder/'response.json').unlink(missing_ok=True)
  temp=folder/'request.tmp';temp.write_text(json.dumps(command,separators=(',',':')));temp.chmod(0o600);temp.replace(folder/'request.json')
  deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   response=folder/'response.json'
   if response.exists():
    result=json.loads(response.read_text())
    if result.get('request_id')==request_id:
     response.unlink()
     try:self._record(active,command,result)
     except OSError:pass # Diagnostic storage cannot invalidate an already committed action.
     resolved=self._resolve(result)
     WORLD_SYNC.publish(active['account'],active['character_id'],active['id'],resolved.get('snapshot',{}),resolved.get('sequence',0),command=command,mutation=resolved.get('mutation',{}))
     try:VOICE_STATE.publish(active['account'],active['character_id'],resolved.get('snapshot',{}).get('player',{}),session_id=active['id'],live=True)
     except (OSError,ValueError):pass
     return resolved
   if active['process'].poll() is not None:raise LiveConflict('Persistent Core3 zone session exited.')
   time.sleep(.01)
  raise LiveConflict('Persistent Core3 command timed out; session must be restarted.')
 def _resolve(self,result):
  names=template_names()
  def visual(row):
   row['shared_template']=names.get(row.get('client_crc'),'')
   row['customization']=decode_customization(bytes.fromhex(row.get('customization_hex','')))
  snapshot=result.get('snapshot',{})
  world=snapshot.get('world',{})
  if 'npc_speech' in snapshot.get('player',{}):
   try:from .chatter_protocol import normalize as normalize_speech
   except ImportError:from chatter_protocol import normalize as normalize_speech
   snapshot['player']['npc_speech']=normalize_speech(snapshot['player']['npc_speech'],snapshot['player'],world)
  for actor in snapshot.get('actors',[])+world.get('actors',[])+world.get('players',[])+world.get('deployments',[]):
   visual(actor)
   appearance=actor.get('appearance')
   if isinstance(appearance,dict):
    visual(appearance)
    appearance['hair_customization']=decode_customization(bytes.fromhex(appearance.get('hair_customization_hex','')))
    for item in appearance.get('equipment',[]):visual(item)
  # Reuse the existing native vehicle view without exposing private control devices.
  if world:world['vehicles']=snapshot.get('player',{}).get('vehicles',{}).get('vehicles',[])
  result.setdefault('backend','core3');result.setdefault('source_kind','core3_live_combat')
  return result
 def start(self,account,data,secret,container,characters):
  source_zone=planet_context(data)
  account=account.lower()
  active=self.active_for(account)
  if active:
   if active['process'].poll() is None:raise LiveConflict('A live session already owns this account; stop it explicitly first.')
   self.close(account)
  for key,other in list(self.sessions.items()):
   if other['process'].poll() is not None:self.close(key)
  if len(self.sessions)>=self.max_sessions:raise LiveConflict(f'Native session capacity reached ({self.max_sessions} concurrent sessions); existing players remain connected.')
  value=data.get('position');heading=data.get('heading_radians',0)
  if not isinstance(value,list) or len(value)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) for v in value) or type(heading) not in (int,float) or not math.isfinite(heading):raise ValueError('Finite source position and heading required.')
  oid=str(data.get('character_id',''))
  if not oid.isdigit() or not any(c['id']==oid for c in characters(account)):raise ValueError('Owned character_id required.')
  token=secrets.token_hex(16);folder=ROOT/'runtime/server/livecombat'/token;folder.mkdir(parents=True,mode=0o700)
  options=folder/'options.json';username='swgxr_'+account.lower()
  config={'username':username,'password':hmac.new(secret,username.encode(),hashlib.sha256).hexdigest()[:24],
   'loginHost':'127.0.0.1','loginPort':44453,'loginTimeout':5,'zoneTimeout':15,
   'saveState':'/workspace/runtime/server/livecombat/'+token+'/final.json',
   'actions':[{'action':'selectContext','characterOid':int(oid)},{'action':'zoneInCharacter','liveDirectory':'/workspace/runtime/server/livecombat/'+token}], 'logLevel':1}
  options.write_text(json.dumps(config));options.chmod(0o600)
  log=open(folder/'client.log','w');os.chmod(folder/'client.log',0o600)
  process=subprocess.Popen(['podman','exec','-w','/workspace/vendor/Core3/MMOCoreORB/bin',container,'./core3client','--options-json','/workspace/runtime/server/livecombat/'+token+'/options.json'],stdout=log,stderr=subprocess.STDOUT);log.close()
  active={'id':token,'account':account,'character_id':oid,'folder':folder,'options':options,'process':process};self.sessions[account]=active
  try:
   deadline=time.monotonic()+25
   while not (folder/'ready.json').exists():
    if process.poll() is not None:raise LiveConflict('Core3 live zone login failed; inspect private session log.')
    if time.monotonic()>deadline:raise LiveConflict('Core3 live zone login timed out.')
    time.sleep(.02)
   # Credential-bearing options are no longer needed after successful login.
   options.unlink(missing_ok=True)
   active['next_command_at']=time.monotonic()+1.05 # Separate initial source attribute commands from the live window.
   result=self._exchange(active,{'action':'start',**source_zone,'session_id':token,'position':data.get('position'),'heading_radians':data.get('heading_radians',0),'spawn_test_lair':bool(data.get('spawn_test_lair',False)),**{k:data[k]for k in ('building_id','cell_index')if k in data}})
   if not result.get('session_live'):raise LiveConflict(result.get('error_code','Native session start rejected.'))
   # Capability is learned only from the owned native start reply, never a
   # client-provided field. Older binaries retain global HTTP serialization.
   active['native_concurrency']='engine_cross_lock_v1' if (result.get('session_id')==token and str(result.get('character_id',''))==oid and result.get('native_concurrency')=='engine_cross_lock_v1') else ''
   return result
  except Exception:self.close(account);raise
 def request(self,account,action,data):
  account=account.lower()
  active=self.active_for(account)
  if not active or active['account']!=account or active['character_id']!=str(data.get('character_id','')) or active['id']!=data.get('session_id'):raise LiveConflict('Live session identity does not match this owned character.')
  if action not in ('snapshot','update','fire','impact','stop','inventory','replication','corpse','session','gathering','scout','medic','life','services','crafting','vehicles','entertainer'):raise ValueError('Unsupported live combat action.')
  fields={'entertainer':('entertainer',),'corpse':('corpse',),'session':('session',),'gathering':('gathering',),'vehicles':('vehicles',),'medic':('medic',),'services':('service',),'crafting':('crafting',),'life':('action',),'scout':('scout',),'update':('position','heading_radians'),'fire':('shot_id','item_id','origin','direction'),'impact':('shot_id','target_id','hit_position','projectile_age_seconds')}.get(action,())
  command={'action':action,'session_id':active['id'],**planet_context(data)}
  for key in fields:
   if key not in data and key!='heading_radians':raise ValueError('Missing '+key)
   command['life_action' if action=='life' and key=='action' else key]=data.get(key,0)
  if action=='inventory' and 'inventory_command'in data:command['inventory_command']=data['inventory_command']
  if action=='replication' and 'command'in data:command['command']=data['command']
  if action=='life' and command.get('life_action') not in ('recover','medical_transport'):raise ValueError('Unsupported life action.')
  if action=='update':
   if 'vehicle_controls' in data:
    try:from .vehicles_protocol import controls
    except ImportError:from vehicles_protocol import controls
    command['vehicle_controls']=controls(data['vehicle_controls'])
   if 'medic_pose' in data:
    try:from .medic_protocol import pose
    except ImportError:from medic_protocol import pose
    command['medic_pose']=pose(data['medic_pose'])
   if 'building_id' in data:
    if not isinstance(data['building_id'],str) or not data['building_id'].isdigit() or int(data['building_id'])>2**64-1:raise ValueError('Invalid building_id.')
    if type(data.get('cell_index')) is not int or not 0<=data['cell_index']<=256:raise ValueError('Invalid cell_index.')
    command.update(building_id=data['building_id'],cell_index=data['cell_index'])
   if 'transport_ack' in data:
    if not isinstance(data['transport_ack'],str) or len(data['transport_ack'])>100:raise ValueError('Invalid transport_ack.')
    command['transport_ack']=data['transport_ack']
  if action=='update' and 'ready' in data:
   if type(data['ready']) is not bool:raise ValueError('ready must be boolean.')
   command['ready']=data['ready']
  for key in ('position','origin','direction','hit_position'):
   if key in command:
    value=command[key]
    if not isinstance(value,list) or len(value)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) for v in value):raise ValueError('Invalid finite '+key)
  for key in ('heading_radians','projectile_age_seconds'):
   if key in command and (type(command[key]) not in (int,float) or not math.isfinite(command[key])):raise ValueError('Invalid '+key)
  for key in ('item_id','target_id'):
   if key in command and (not isinstance(command[key],str) or not command[key].isdigit() or int(command[key])>2**64-1):raise ValueError('Invalid source object '+key)
  for key in ('shot_id','item_id','target_id'):
   if key in command and (not isinstance(command[key],str) or len(command[key])>80):raise ValueError('Invalid '+key)
  try:result=self._exchange(active,command)
  except BackendBusy:raise # Admission refusal did not mutate or lose the native session.
  except Exception:self.close(account);raise
  if action=='stop':
   try:active['process'].wait(timeout=3)
   except subprocess.TimeoutExpired:active['process'].terminate()
   self.sessions.pop(account,None);active['options'].unlink(missing_ok=True)
   try:VOICE_STATE.remove(account)
   except OSError:pass
   WORLD_SYNC.remove(account)
   (active['folder']/'final.json').unlink(missing_ok=True)
  elif not result.get('session_live'):
   self.close(account);raise LiveConflict(result.get('error_code','Native session lost.'))
  return result
HUB=LiveCombatHub()
