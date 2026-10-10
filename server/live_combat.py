"""Bounded authenticated persistent Core3 zone session; private file IPC only."""
from __future__ import annotations
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
import atexit,hashlib,hmac,json,math,os,re,secrets,subprocess,time,threading
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
 from .jtl_protocol import SPACE_ZONES, normalize_state as normalize_jtl
 from .jtl_presence import HUB as JTL_PRESENCE
except ImportError:
 from multiplayer_sync import HUB as WORLD_SYNC
 from jtl_protocol import SPACE_ZONES, normalize_state as normalize_jtl
 from jtl_presence import HUB as JTL_PRESENCE
try:
 from .character_protocol import template_names,decode_customization
except ImportError:
 from character_protocol import template_names,decode_customization
try:
 from .capacity import configured_limit
except ImportError:
 from capacity import configured_limit
ROOT=Path(__file__).resolve().parents[1]
class LiveConflict(ValueError):pass

def native_session_capacity():
 return configured_limit('SWGXR_MAX_NATIVE_SESSIONS')

class LiveCombatHub:
 def __init__(self):
  self.max_sessions=native_session_capacity()
  self.sessions={};self.admission_lock=threading.RLock();atexit.register(self.close)
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
  JTL_PRESENCE.remove(account.lower())
  try:
   if active['process'].poll() is None:
    self._exchange(active,{'action':'stop','session_id':active['id']},timeout=2)
    try:active['process'].wait(timeout=2)
    except subprocess.TimeoutExpired:active['process'].terminate()
  except Exception:
   if active['process'].poll() is None:active['process'].terminate()
  # The final native stop reply can publish once more; clear it after IPC too.
  WORLD_SYNC.remove(account.lower())
  JTL_PRESENCE.remove(account.lower())
  try:VOICE_STATE.remove(account.lower())
  except OSError:pass
  active['options'].unlink(missing_ok=True)
  (active['folder']/'final.json').unlink(missing_ok=True)
 def _record(self,active,command,result,elapsed=0):
  # Bounded local diagnostics; never retain credentials or entire actor snapshots.
  action=command.get('action','unknown');counts=active.setdefault('action_counts',{})
  counts[action]=counts.get(action,0)+1
  timings=active.setdefault('timings',deque(maxlen=128))
  timings.append({'time_unix':time.time(),'action':action,'detail':command.get('jtl',command.get('service',{})).get('action',''),'elapsed_ms':round(elapsed*1000,2),'error_code':result.get('error_code',result.get('mutation',{}).get('error_code'))})
  if action not in ('start','fire','melee','taunt','warcry','swordsman','pikeman','fencer','pistoleer','carbineer','rifleman','commando','bountyhunter','squadleader','tka','brawler_buff','impact','stop','life') and not result.get('error_code'):
   self._write_audit(active,counts);return
  mutation=result.get('mutation',{});snap=result.get('snapshot',{});player=snap.get('player',{})
  entry={'time_unix':time.time(),'action':action,'sequence':result.get('sequence'),
   'life_action':command.get('life_action'),'shot_id':command.get('shot_id'),'item_id':command.get('item_id'),'target_id':mutation.get('target_id',command.get('target_id')),'taunted':mutation.get('taunted'),
   'error_code':result.get('error_code',mutation.get('error_code')),'success':mutation.get('success'),
   'native_result':mutation.get('native_result'),'damage':mutation.get('damage'),
   'ham_cost_committed':mutation.get('ham_cost_committed'),'ready':snap.get('ready'),
   'player_ham':player.get('ham'),'player_posture':player.get('posture')}
  events=active.setdefault('events',deque(maxlen=128));events.append(entry)
  self._write_audit(active,counts)
 def _write_audit(self,active,counts):
  tmp=active['folder']/'audit.tmp';tmp.write_text(json.dumps({'capacity':128,'counts':counts,'events':list(active.get('events',[])),'timings':list(active.get('timings',[]))},separators=(',',':')));tmp.chmod(0o600);tmp.replace(active['folder']/'audit.json')
 def _exchange(self,active,command,timeout=12):
  # Each native child has one file mailbox and one rate budget. Unrelated
  # capable children may overlap their network wait, never their own mailbox.
  with active.setdefault('ipc_gate',RequestGate()):
   return self._exchange_owned(active,command,timeout)
 def _exchange_owned(self,active,command,timeout=12):
  started=time.monotonic()
  # The native XR envelope allows 20 Hz; stay below it with a shared
  # 12.5 Hz account budget, including shots, contacts and service requests.
  delay=active.get("next_command_at",0)-time.monotonic()
  if delay>0:time.sleep(delay)
  active["next_command_at"]=time.monotonic()+.08
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
     try:self._record(active,command,result,time.monotonic()-started)
     except OSError:pass # Diagnostic storage cannot invalidate an already committed action.
     resolved=self._resolve(result)
     # An uncertain receipt has no new authoritative state. Preserve the last
     # world/voice snapshot and keep the owned child available for a heartbeat.
     if resolved.get('error_code')=='native_response_timeout':return resolved
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
  if snapshot.get('player',{}).get('player_summary') is not None:
   try:from .datapad_protocol import normalize_summary
   except ImportError:from datapad_protocol import normalize_summary
   snapshot['player']['player_summary']=normalize_summary(snapshot['player']['player_summary'],result['character_id'])
  if 'npc_speech' in snapshot.get('player',{}):
   try:from .chatter_protocol import normalize as normalize_speech
   except ImportError:from chatter_protocol import normalize as normalize_speech
   snapshot['player']['npc_speech']=normalize_speech(snapshot['player']['npc_speech'],snapshot['player'],world)
  actors=snapshot.get('actors',[])+world.get('actors',[])+world.get('players',[])+world.get('deployments',[])+world.get('spice_outlines',[])
  # JtL publishes the same native public appearance in its ship-local roster.
  # Normalize each wire copy used by mutation, session and scene consumers.
  for ship_state in (snapshot.get('jtl'),snapshot.get('player',{}).get('jtl'),result.get('mutation',{}).get('jtl')):
   if isinstance(ship_state,dict) and isinstance(ship_state.get('ship'),dict):
    normalize_jtl(ship_state)
    actors+=ship_state['ship'].get('crew',[])
  for actor in actors:
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
  with self.admission_lock:return self._start(account,data,secret,container,characters)
 def _start(self,account,data,secret,container,characters):
  source_zone=planet_context(data)
  account=account.lower()
  active=self.active_for(account)
  if active:
   if active['process'].poll() is None:raise LiveConflict('A live session already owns this account; stop it explicitly first.')
   self.close(account)
  for key,other in list(self.sessions.items()):
   if other['process'].poll() is not None:self.close(key)
  if self.max_sessions and len(self.sessions)>=self.max_sessions:raise LiveConflict(f'Native session capacity reached ({self.max_sessions} concurrent sessions); existing players remain connected.')
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
  active=self.active_for(account)
  if not active:raise LiveConflict('Live session identity does not match this owned character.')
  with active.setdefault('ipc_gate',RequestGate()):
   if self.active_for(account) is not active:raise LiveConflict('Live session changed before request admission.')
   return self._request_owned(account,action,data)
 def _request_owned(self,account,action,data):
  account=account.lower()
  active=self.active_for(account)
  if not active or active['account']!=account or active['character_id']!=str(data.get('character_id','')) or active['id']!=data.get('session_id'):raise LiveConflict('Live session identity does not match this owned character.')
  if action not in ('snapshot','loadout','update','fire','melee','taunt','warcry','swordsman','pikeman','fencer','pistoleer','carbineer','rifleman','commando','bountyhunter','squadleader','tka','brawler_buff','impact','stop','inventory','replication','corpse','session','gathering','scout','medic','life','services','crafting','vehicles','entertainer','jtl'):raise ValueError('Unsupported live combat action.')
  fields={'jtl':('jtl',),'loadout':('item_id','loadout'),'entertainer':('entertainer',),'corpse':('corpse',),'session':('session',),'gathering':('gathering',),'vehicles':('vehicles',),'medic':('medic',),'services':('service',),'crafting':('crafting',),'life':('action',),'scout':('scout',),'update':('position','heading_radians'),'fire':('shot_id','item_id','origin','direction'),'melee':('shot_id','item_id','origin','direction'),'taunt':('shot_id','origin','direction'),'warcry':('shot_id','item_id','origin','direction'),'pistoleer':('shot_id','item_id','ability_id','origin','direction'),'pikeman':('shot_id','item_id','ability_id','origin','direction'),'fencer':('shot_id','item_id','ability_id','origin','direction'),'swordsman':('shot_id','item_id','ability_id','origin','direction'),'tka':('shot_id','item_id','ability_id','origin','direction'),'brawler_buff':('shot_id','item_id','ability_id'),'impact':('shot_id','target_id','hit_position','projectile_age_seconds')}.get(action,())
  if action in ('carbineer','rifleman','commando','bountyhunter'):fields=('shot_id','item_id','ability_id','origin','direction','two_hands')
  if action=='squadleader':fields=('shot_id','item_id','ability_id','target_id','origin','direction')
  if action=='jtl':
   try:from .jtl_protocol import command as jtl_command, context as jtl_context
   except ImportError:from jtl_protocol import command as jtl_command, context as jtl_context
   intent=data.get('jtl')
   if not isinstance(intent,dict):raise ValueError('JtL intent required.')
   data=dict(data,jtl=jtl_command(intent.get('action'),intent))
   if data['jtl']['action']=='crew_join':
    try:from .services_presence import HUB as presence
    except ImportError:from services_presence import HUB as presence
    crew=data['jtl']
    proof=presence.authorize_crew_handshake(account,active['character_id'],crew['pilot_id'],crew['launch_id'],crew['request_id'],crew['crew_handshake_id'])
    crew['handshake_authorized']=True
    crew['handshake_receipt_only']=proof['receipt_only']
   source_context=jtl_context(data)
  elif action=='session' and isinstance(data.get('session'),dict) and data['session'].get('action')=='logout' and data['session'].get('zone',data['session'].get('planet')) in SPACE_ZONES:
   # The native session helper restores the owned ship's actual ground return
   # and checks its persistent receipt before applying movement. Omit the outer
   # ground-zone fence so a lost logout reply can be replayed after landing.
   source_context={}
  else:source_context=planet_context(data)
  command={'action':action,'session_id':active['id'],**source_context}
  for key in fields:
   if key not in data and key!='heading_radians':raise ValueError('Missing '+key)
   command['life_action' if action=='life' and key=='action' else key]=data.get(key,0)
  if 'movement_revision' in data:
   revision=data['movement_revision']
   if type(revision) is not int or not 0<=revision<=2**53-1:raise ValueError('Invalid movement_revision.')
   command['movement_revision']=revision
  if action=='inventory' and 'inventory_command'in data:command['inventory_command']=data['inventory_command']
  if action=='replication' and 'command'in data:command['command']=data['command']
  if action=='loadout':
   try:from .combat_loadout_protocol import validate
   except ImportError:from combat_loadout_protocol import validate
   command['loadout']=validate(data.get('loadout'))
  if action=='life' and command.get('life_action') not in ('recover','force_of_will','medical_transport'):raise ValueError('Unsupported life action.')
  if any(key in data for key in ('volley_id','volley_index')) and not (action=='fire' and data.get('ability_id') in ('showdown','flurry_shot')):raise ValueError('Volley metadata is only valid for Showdown or Flurry Shot fire.')
  if action=='squadleader':
   try:from .squad_leader_protocol import validate_cast
   except ImportError:from squad_leader_protocol import validate_cast
   validate_cast(data)
  if action=='bountyhunter':
   ability=data.get('ability_id')
   if ability not in ('underhand_shot','duelist_stance'):raise ValueError('Unsupported Bounty Hunter gesture.')
   if type(data.get('two_hands')) is not bool:raise ValueError('two_hands must be boolean.')
   if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Bounty Hunter shot_id.')
   if ability=='underhand_shot':
    if data['two_hands'] is not True:raise ValueError('Underhand Shot requires two_hands true.')
    if 'target_id' in data:raise ValueError('Underhand arming is not target-bound.')
   else:
    value=data.get('target_id')
    if not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Duelist Stance requires target_id.')
    command['target_id']=value
  if action=='pistoleer':
   if data.get('ability_id') not in ('fan_shot','run_and_gun'):raise ValueError('Unsupported Pistoleer gesture.')
   if 'target_id' in data:raise ValueError('Pistoleer gesture targets are selected by the server.')
   if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Pistoleer gesture shot_id.')
  if action=='carbineer':
   if data.get('ability_id') not in ('full_auto_sweep','tactical_brace','charge_blast'):raise ValueError('Unsupported Carbineer ability.')
   if 'target_id' in data:raise ValueError('Carbineer area targets are selected by the server.')
   if data.get('two_hands') is not True:raise ValueError('Carbineer ability requires two_hands true.')
   if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Carbineer shot_id.')
  if action=='rifleman':
   if data.get('ability_id')!='rifleman_focus':raise ValueError('Unsupported Rifleman gesture.')
   if 'target_id' in data:raise ValueError('Rifleman Focus is self-only.')
   if data.get('two_hands') is not True:raise ValueError('Rifleman Focus requires two_hands true.')
   if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Rifleman shot_id.')
  if action=='commando':
   ability=data.get('ability_id')
   if ability not in ('','focused_discharge','acid_spray','overdrive'):raise ValueError('Unsupported Commando discharge.')
   if type(data.get('two_hands')) is not bool:raise ValueError('two_hands must be boolean.')
   if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Commando shot_id.')
   if ability in ('focused_discharge','acid_spray'):
    value=data.get('target_id')
    if not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64:raise ValueError('Commando discharge requires target_id.')
    command['target_id']=value
   elif 'target_id' in data:raise ValueError('Commando area and self targets are selected by the server.')
  if action=='pikeman':
   ability=data.get('ability_id')
   if ability not in ('knockdown_strike','polearm_stun','pinning_strike','disrupting_jab','overhead_whirl','sweeping_trip','driving_jabs','whirlwind'):raise ValueError('Unsupported Pikeman ability.')
   if ability in ('overhead_whirl','sweeping_trip','driving_jabs','whirlwind'):
    if 'target_id' in data:raise ValueError('Gesture targets are selected by the server.')
   else:
    if not data.get('target_id'):raise ValueError('Pikeman ability requires target_id.')
    command['target_id']=data['target_id']
  if action=='fencer':
   ability=data.get('ability_id')
   if ability not in ('arterial_cut','nerve_strike','disorienting_thrust','exposing_thrust','probing_jabs','raking_slash','guard_bash','flawless_assault'):raise ValueError('Unsupported Fencer ability.')
   if ability in ('probing_jabs','raking_slash','guard_bash','flawless_assault'):
    if 'target_id' in data:raise ValueError('Gesture targets are selected by the server.')
   else:
    if not data.get('target_id'):raise ValueError('Fencer ability requires target_id.')
    command['target_id']=data['target_id']
  if action=='swordsman':
   ability=data.get('ability_id')
   if ability not in ('rending_cut','disrupting_blow','hamstring','decisive_strike','overhead_cleave','ground_slam','armour_break'):raise ValueError('Unsupported Swordsman ability.')
   if ability in ('overhead_cleave','ground_slam'):
    if 'target_id' in data:raise ValueError('Gesture targets are selected by the server.')
   else:
    if not data.get('target_id'):raise ValueError('Swordsman ability requires target_id.')
    command['target_id']=data['target_id']
  if action=='tka' and data.get('ability_id') not in ('tka_sweep','tka_half_spin','tka_volley','indomitable_focus'):raise ValueError('Unsupported Teras Kasi ability.')
  if action=='brawler_buff' and data.get('ability_id') not in ('center_of_being','berserk'):raise ValueError('Unsupported Brawler buff.')
  if action=='melee' and 'ability_id' in data:
   if data['ability_id'] not in ('knockdown_strike','unarmed_stun','unarmed_blind','polearm_stun','challenging_strike'):raise ValueError('Unsupported native melee ability.')
   if not data.get('target_id'):raise ValueError('Melee ability requires target_id.')
   command['ability_id']=data['ability_id'];command['target_id']=data['target_id']
  if action=='fire':
   if 'two_hands' in data:
    if type(data['two_hands']) is not bool:raise ValueError('two_hands must be boolean.')
    command['two_hands']=data['two_hands']
   if 'firing_posture' in data:
    if data['firing_posture'] not in ('standing','crouched','prone'):raise ValueError('Invalid firing_posture.')
    command['firing_posture']=data['firing_posture']
  if action=='fire' and 'ability_id' in data:
   if data['ability_id'] not in ('lethal_shot','last_ditch','low_blow','restraining_shot','concussion_shot_improved','suppression_fire','warning_shot','controlled_burst','bleeding_shot','double_tap','disarming_shot','showdown','crippling_shot','wild_shot','charge_shot','piercing_shot','flurry_shot','surprise_shot','sniper_shot','focused_discharge','eye_shot','confusion_shot','underhand_shot','fast_blast'):raise ValueError('Unsupported native ranged ability.')
   if data['ability_id'] in ('eye_shot','confusion_shot','underhand_shot','fast_blast'):
    value=data.get('target_id')
    if (data['ability_id']!='underhand_shot' or 'target_id' in data) and (not isinstance(value,str) or not value.isascii() or not value.isdigit() or not 0<int(value)<2**64):raise ValueError('Bounty Hunter attack requires a valid target_id.')
    if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid Bounty Hunter shot_id.')
    if data['ability_id'] in ('confusion_shot','underhand_shot') and data.get('two_hands') is not True:raise ValueError('Bounty Hunter carbine attack requires two_hands true.')
   if data['ability_id'] in ('suppression_fire','warning_shot','controlled_burst','bleeding_shot') and not data.get('target_id'):raise ValueError('Marksman ability requires target_id.')
   if data['ability_id'] in ('double_tap','disarming_shot','showdown') and not data.get('target_id'):raise ValueError('Pistoleer ability requires target_id.')
   if data['ability_id'] in ('crippling_shot','wild_shot','charge_shot') and not data.get('target_id'):raise ValueError('Carbineer ability requires target_id.')
   if data['ability_id'] in ('piercing_shot','flurry_shot','surprise_shot','sniper_shot') and not data.get('target_id'):raise ValueError('Rifleman ability requires target_id.')
   if data['ability_id']=='focused_discharge' and not data.get('target_id'):raise ValueError('Focused Discharge requires target_id.')
   if data['ability_id']=='sniper_shot' and data.get('two_hands') is not True:raise ValueError('Sniper Shot requires two_hands true.')
   if data['ability_id'] in ('showdown','flurry_shot'):
    volley_name='Showdown' if data['ability_id']=='showdown' else 'Flurry Shot'
    volley_id=data.get('volley_id');volley_index=data.get('volley_index')
    if not isinstance(volley_id,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',volley_id):raise ValueError('Invalid '+volley_name+' volley_id.')
    if type(volley_index) is not int or not 0<=volley_index<=2:raise ValueError('Invalid '+volley_name+' volley_index.')
    if volley_index==0 and volley_id!=data['shot_id']:raise ValueError(volley_name+' first shot must identify its volley.')
    if not isinstance(data.get('shot_id'),str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,80}',data['shot_id']):raise ValueError('Invalid '+volley_name+' shot_id.')
    command['volley_id']=volley_id;command['volley_index']=volley_index
   command['ability_id']=data['ability_id']
   if 'target_id' in data:command['target_id']=data['target_id']
  try:from .squad_leader_protocol import mark_intent
  except ImportError:from squad_leader_protocol import mark_intent
  command.update(mark_intent(data,action,command.get('ability_id',''),data.get('target_id')))
  try:from .bounty_combat_protocol import contact_fields
  except ImportError:from bounty_combat_protocol import contact_fields
  command.update(contact_fields(data,action))
  if action=='update':
   if 'guard_pose' in data:
    try:from .physical_guard_protocol import pose as guard_pose
    except ImportError:from physical_guard_protocol import pose as guard_pose
    command['guard_pose']=guard_pose(data['guard_pose'])
   if 'smuggler_pose' in data:
    pose=data['smuggler_pose']
    if not isinstance(pose,dict) or set(pose)!={'tracked','feign','upright'} or any(type(v) is not bool for v in pose.values()) or (pose['feign'] and pose['upright']):raise ValueError('Invalid Smuggler posture.')
    command['smuggler_pose']=pose
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
   JTL_PRESENCE.remove(account)
   (active['folder']/'final.json').unlink(missing_ok=True)
  elif not result.get('session_live'):
   self.close(account);raise LiveConflict(result.get('error_code','Native session lost.'))
  return result
HUB=LiveCombatHub()
