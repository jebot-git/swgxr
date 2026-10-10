#!/usr/bin/env python3
"""Loopback-only prototype API. All characters are owned by actual Core3.

The adapter invokes upstream core3client inside the isolated server container.
It deliberately has no fallback character database. Godot locomotion is local;
entry validates the persistent identity through Core3, then chooses the stage.
"""
from __future__ import annotations
try:
 from .planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
except ImportError:
 from planets import SUPPORTED_PLANETS, context as planet_context, planet as validate_planet
import argparse
import hashlib
import hmac
import json
import math
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
try:
    from .character_protocol import summarize, appearance
    from .creation_catalog import creation_options, creation_action
    from .datapad_protocol import datapad
    from .weapon_protocol import weapon_snapshots
    from .combat_protocol import snapshot as combat_snapshot
    from .inventory_protocol import inventory_snapshot
    from .vehicles_protocol import command as vehicles_command, snapshot as vehicles_snapshot
    from .jtl_protocol import command as jtl_command, snapshot as jtl_snapshot
    from .jtl_presence import HUB as JTL_PRESENCE
    from .medic_protocol import command as medic_command, snapshot as medic_snapshot
    from .scout_protocol import command as scout_command, snapshot as scout_snapshot
    from .services_protocol import command as services_command, snapshot as services_snapshot
    from .services_presence import HUB as SERVICES_PRESENCE
    from .multiplayer_sync import HUB as WORLD_SYNC
    from .crafting_protocol import command as crafting_command, crafting_snapshot
    from .gathering_protocol import gathering_snapshot, corpse_snapshot
    from .entertainer_protocol import command as entertainer_command, snapshot as entertainer_snapshot
    from .image_design_protocol import normalize as image_design_normalize, normalize_appearance as image_appearance_normalize
    from .entertainment import HUB as PERFORMANCE_HUB
    from .live_combat import HUB as LIVE_COMBAT, LiveConflict
except ImportError:
    from character_protocol import summarize, appearance
    from creation_catalog import creation_options, creation_action
    from datapad_protocol import datapad
    from weapon_protocol import weapon_snapshots
    from combat_protocol import snapshot as combat_snapshot
    from inventory_protocol import inventory_snapshot
    from vehicles_protocol import command as vehicles_command, snapshot as vehicles_snapshot
    from jtl_protocol import command as jtl_command, snapshot as jtl_snapshot
    from jtl_presence import HUB as JTL_PRESENCE
    from medic_protocol import command as medic_command, snapshot as medic_snapshot
    from scout_protocol import command as scout_command, snapshot as scout_snapshot
    from services_protocol import command as services_command, snapshot as services_snapshot
    from services_presence import HUB as SERVICES_PRESENCE
    from multiplayer_sync import HUB as WORLD_SYNC
    from crafting_protocol import command as crafting_command, crafting_snapshot
    from gathering_protocol import gathering_snapshot, corpse_snapshot
    from entertainer_protocol import command as entertainer_command, snapshot as entertainer_snapshot
    from image_design_protocol import normalize as image_design_normalize, normalize_appearance as image_appearance_normalize
    from entertainment import HUB as PERFORMANCE_HUB
    from live_combat import HUB as LIVE_COMBAT, LiveConflict

try:
    from .session_protocol import logout_command, snapshot as session_snapshot
    from .request_gate import RequestGate, BackendBusy
    from .voice_protocol import NATIVE as VOICE_STATE, local_authority, granted as voice_granted
except ImportError:
    from session_protocol import logout_command, snapshot as session_snapshot
    from request_gate import RequestGate, BackendBusy
    from voice_protocol import NATIVE as VOICE_STATE, local_authority, granted as voice_granted

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime/server'
CONTAINER = os.environ.get('SWGXR_CONTAINER', 'swgxr-core3-build')
BIN = '/workspace/vendor/Core3/MMOCoreORB/bin'
LOCK = RequestGate()
HEALTH = {'time': 0.0, 'value': None}
MAX_BODY = 16384

class BackendError(Exception):
    pass

class NativeReplyTimeout(Exception):
    """The operation may have committed; preserve ownership, never replay it."""
    def response(self):
        return {'ok':False,'backend':'core3','error_code':'native_response_timeout',
                'request_timeout':True,'session_live':True,'mutation_started':True,
                'error':'Core3 reply timed out. The connection is retained; refresh before retrying the action.'}

class NativeJtlRejected(Exception):
    """Preserve a rejected ship action's owned snapshot for remote transitions."""
    def __init__(self, response):
        super().__init__(response['error'])
        self.result = response

class NativeMovementRejected(Exception):
    """An owned native rejection still carries the authoritative corrected pose."""
    def __init__(self, live):
        super().__init__(live['error_code'])
        self.live = live

    def response(self):
        return {'ok':False, 'backend':'core3', 'error':str(self),
                'error_code':str(self), 'live_response':self.live}

def check_live_error(live):
    code=live.get('error_code')
    if not code:return
    if code=='native_response_timeout':raise NativeReplyTimeout()
    if isinstance(code,str) and code.startswith('native_movement_'):
        raise NativeMovementRejected(live)
    raise ValueError(code)


def prepare_secret():
    RUNTIME.mkdir(parents=True, exist_ok=True)
    secret_path = RUNTIME / 'adapter.secret'
    try:
        fd = os.open(secret_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return secret_path.read_bytes()
    with os.fdopen(fd, 'wb') as stream:
        stream.write(secrets.token_bytes(32))
    return secret_path.read_bytes()

SECRET = prepare_secret()

def account_name(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9_]{1,24}', value):
        raise ValueError('Account must contain 1–24 letters, digits or underscores.')
    return 'swgxr_' + value.lower()

def invoke(account, actions, timeout=60):
    """JSON files, not command interpolation; private outputs can contain tokens."""
    active=LIVE_COMBAT.active_for(account)
    if active:
        selects=[a for a in actions if a.get('action')=='selectContext'];zones=[a for a in actions if a.get('action')=='zoneInCharacter']
        if len(selects)==1 and len(zones)==1 and str(selects[0].get('characterOid'))==active['character_id'] and not zones[0].get('inventoryRequest'):
            data=dict(character_id=active['character_id'],session_id=active['id'])
            if zones[0].get('datapadCommand'):data['command']=zones[0]['datapadCommand']
            reply=LIVE_COMBAT.request(account,'replication',data)
            if reply.get('error_code'):raise ValueError(reply['error_code'])
            variables=reply['native_variables'];loc=variables['session']['location'];variables.setdefault('scene',{})['characterOid']=active['character_id']
            variables['spice']=reply.get('snapshot',{}).get('player',{}).get('spice',{})
            variables['player_summary']=reply.get('snapshot',{}).get('player',{}).get('player_summary')
            return {'variables':variables,'zoneConnected':True,'zoneStats':{'sceneReady':True},'overallSuccess':True}
        LIVE_COMBAT.guard(account)
    username = account_name(account)
    password = hmac.new(SECRET, username.encode(), hashlib.sha256).hexdigest()[:24]
    request_id = secrets.token_hex(8)
    request_path = RUNTIME / f'{request_id}.options.json'
    result_path = RUNTIME / f'{request_id}.result.json'
    options = {'username': username, 'password': password, 'loginHost': '127.0.0.1',
               'loginPort': 44453, 'loginTimeout': 5, 'zoneTimeout': 15,
               'saveState': f'/workspace/runtime/server/{result_path.name}',
               'actions': actions, 'logLevel': 2}
    request_path.write_text(json.dumps(options))
    request_path.chmod(0o600)
    try:
        proc = subprocess.run(['podman', 'exec', '-w', BIN, CONTAINER,
                               './core3client', '--options-json',
                               f'/workspace/runtime/server/{request_path.name}'],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=timeout, text=True)
        # Preserve bounded diagnostics, without raw options or tokens.
        if not result_path.exists():
            detail = proc.stdout[-1800:].replace(password, '[redacted]')
            raise BackendError('core3client did not produce a result: ' + detail)
        result = json.loads(result_path.read_text())
        failures = [a for a in result.get('actions', []) if a.get('status') == 'failed']
        if proc.returncode or not result.get('overallSuccess'):
            if any(a.get('action')=='selectContext' and a.get('error')=='Character OID not found' for a in failures):
                raise ValueError('Character is not owned by this account.')
            raise BackendError('; '.join(a.get('error', a.get('action', 'failed')) for a in failures)
                               or f'Core3 request failed (exit {proc.returncode}).')
        return result
    except subprocess.TimeoutExpired as exc:
        raise BackendError('Core3 request timed out; server may still be loading.') from exc
    finally:
        request_path.unlink(missing_ok=True)
        result_path.unlink(missing_ok=True)

def health(force=False):
    if not force and HEALTH['value'] is not None and time.monotonic()-HEALTH['time']<8:return HEALTH['value']
    with LOCK:
        if not force and HEALTH['value'] is not None and time.monotonic() - HEALTH['time'] < 8:
            return HEALTH['value']
        ready = False
        detail = 'Core3 binary has not been built.'
        if (ROOT / 'vendor/Core3/MMOCoreORB/bin/core3client').exists():
            try:
                result = invoke('health', [{'action': 'loginAccount'}, {'action': 'selectContext'},
                                          {'action': 'connectToZone'}], timeout=20)
                ready = result.get('loginSuccess', False) and result.get('zoneConnected', False)
                detail = 'Actual Core3 login and zone connection verified.' if ready else 'Core3 zone unavailable.'
            except (BackendError, OSError) as exc:
                detail = str(exc)
        value = {'status': 'ready' if ready else 'blocked', 'backend': 'core3',
                 'backend_name': 'CoreCU', 'combat_policy_version': 1, 'upstream': 'SWGEmu Core3',
                 'core3': {'ready': ready, 'detail': detail},
                 'population': {'limit': LIVE_COMBAT.max_sessions or None, 'target':32, 'scope':'server_wide', 'capacity_load_validated':False},
                 'movement': 'local_godot_prototype', 'stage': 'mos_eisley_starport'}
        HEALTH.update(time=time.monotonic(), value=value)
        return value

def characters(account, timeout=60):
    result = invoke(account, [{'action': 'loginAccount'}], timeout=timeout)
    return [summarize(c) for c in result.get('characters', [])]

def select_character(account, oid, timeout=60):
    deadline = time.monotonic() + timeout
    if not oid.isdigit(): raise ValueError('character_id must be an unsigned integer.')
    result = invoke(account, [{'action': 'selectContext', 'characterOid': int(oid)},
                              {'action': 'zoneInCharacter'}], timeout=max(0.1, deadline-time.monotonic()))
    scene = result.get('variables', {}).get('scene', {})
    ground_scene = scene.get('terrain') in {'terrain/'+p+'.trn' for p in SUPPORTED_PLANETS}
    # Native reconnect recovery can finish before the queued scene-header update
    # reaches core3client. Accept only an owned, native ground status receipt.
    if scene.get('terrain') == 'terrain/space_tatooine.trn':
        try:
            receipt=session_snapshot(result.get('variables',{}).get('session',{}),oid)
            ground_scene=receipt.get('source_kind')=='core3_session_status'
        except ValueError:
            ground_scene=False
    if (not ground_scene
            or str(scene.get('characterOid', '')) != oid
            or not result.get('zoneStats', {}).get('sceneReady')):
        raise BackendError('Core3 did not confirm this character in a ready original ground scene.')
    scene['characterOid'] = str(scene['characterOid'])
    try: character = appearance(result, oid)
    except ValueError as exc: raise BackendError(str(exc)) from exc
    return result, character

def read_inventory(account, oid, split=None, operation=None):
    if not isinstance(oid, str) or not oid.isdigit():
        raise ValueError('character_id must be an unsigned integer.')
    command = 'swgxr_inventory_v1'
    if split is not None:
        item_id, quantity = split
        if not isinstance(item_id, str) or not item_id.isdigit() or int(item_id) > 2**64-1:
            raise ValueError('item_id must be an unsigned object identifier.')
        if type(quantity) is not int or not 1 <= quantity <= 2**31-1:
            raise ValueError('quantity must be a positive integer.')
        command += f' split {item_id} {quantity}'
    if operation is not None:
        verb, item_id, arrangement = operation
        if verb not in ('equip', 'unequip', 'consume') or not isinstance(item_id, str) or not item_id.isdigit() or int(item_id)>2**64-1:
            raise ValueError('Invalid inventory operation or item identifier.')
        if type(arrangement) is not int or not 0 <= arrangement < 32:
            raise ValueError('arrangement must be an integer from 0 to 31.')
        command += f' {verb} {item_id}' + (f' {arrangement}' if verb == 'equip' else '')
    active=LIVE_COMBAT.active_for(account)
    if active:
        live=LIVE_COMBAT.request(account,'inventory',dict(character_id=oid,session_id=active['id'],inventory_command=command))
        check_live_error(live)
        result={'variables':{'inventory':live.get('mutation',{}).get('inventory',{}),'weaponAttributes':live.get('service_attributes',{})}}
    else:
        result = invoke(account, [{'action':'selectContext','characterOid':int(oid)},
                                  {'action':'zoneInCharacter','inventoryRequest':command}])
    try:
        snapshot = inventory_snapshot(result, oid)
    except ValueError as exc:
        raise BackendError(str(exc)) from exc
    if operation is not None:
        mutation = snapshot.pop('mutation', {})
        if mutation.get('success') is not True:
            raise ValueError(mutation.get('error', 'Core3 rejected the operation.'))
        after = read_inventory(account, oid)
        by_id = {item['id']: item for item in after['items']}
        verb, item_id, arrangement = operation
        if verb == 'equip':
            selected = by_id.get(item_id, {})
            if not selected.get('equipped') or selected.get('arrangement') != arrangement:
                raise BackendError('Equipment acknowledgement did not match fresh Core3 state; refresh before retrying.')
            for displaced in mutation.get('displaced_item_ids', []):
                if by_id.get(displaced, {}).get('container_id') != after['inventory']['id']:
                    raise BackendError('Displaced equipment is not in the inventory; refresh before retrying.')
        elif verb == 'unequip':
            selected = by_id.get(item_id, {})
            if selected.get('equipped') or selected.get('container_id') != after['inventory']['id']:
                raise BackendError('Unequip acknowledgement did not match fresh Core3 inventory.')
        elif mutation.get('removed'):
            if item_id in by_id: raise BackendError('Consumed item still exists in fresh Core3 inventory.')
        elif by_id.get(item_id, {}).get('use_count') != mutation.get('remaining_use_count'):
            raise BackendError('Consumed charge did not match fresh Core3 inventory.')
        return {'backend':'core3','source_kind':'core3_inventory_'+verb,'mutation':mutation,
                'inventory':after,'verified_by':'fresh_owned_native_snapshot'}
    if split is not None:
        mutation = snapshot.pop('mutation', {})
        if mutation.get('success') is not True:
            raise ValueError(mutation.get('error', 'Core3 rejected the split.'))
        # No automatic retry: an ambiguous network failure must never duplicate a mutation.
        after = read_inventory(account, oid)
        by_id = {item['id']: item for item in after['items']}
        if (by_id.get(mutation['item_id'], {}).get('quantity') != mutation['remaining_quantity']
                or by_id.get(mutation['new_item_id'], {}).get('quantity') != mutation['quantity']):
            raise BackendError('Split acknowledgement did not match the fresh Core3 snapshot; refresh before retrying.')
        return {'backend':'core3','source_kind':'core3_inventory_split','mutation':mutation,
                'inventory':after,'verified_by':'fresh_owned_native_snapshot'}
    PERFORMANCE_HUB.refresh_inventory(account, oid, snapshot.get('items', []))
    return snapshot

def gameplay_session(account,data,start=False,life=False):
    if start:
        active=LIVE_COMBAT.active_for(account)
        if active:
            if active.get('purpose')!='gameplay':raise LiveConflict('A combat session already owns this account')
            reply=LIVE_COMBAT.request(account,'snapshot',dict(character_id=str(data.get('character_id','')),session_id=active['id']))
        else:
            reply=LIVE_COMBAT.start(account,data,SECRET,CONTAINER,characters)
            LIVE_COMBAT.active_for(account)['purpose']='gameplay'
    else:
        active=LIVE_COMBAT.active_for(account)
        if not active:raise LiveConflict('Native gameplay session is not active')
        reply=LIVE_COMBAT.request(account,'life'if life else 'update',dict(data,session_id=data.get('session_id',data.get('live_session_id',active['id']))))
    check_live_error(reply)
    player=reply.get('snapshot',{}).get('player',{})
    return {'backend':'core3','source_kind':'core3_gameplay_session','native_concurrency':reply.get('native_concurrency',''),'sequence':reply.get('sequence',0),'character_id':reply['character_id'],'session_id':reply['session_id'],'session_live':reply['session_live'],'location':{k:player.get(k)for k in('position','building_id','cell_id','cell_index','zone','heading_radians')},'snapshot':{'player':player,'vehicles':player.get('vehicles',{}),'transport':reply.get('snapshot',{}).get('transport',{}),'world':reply.get('snapshot',{}).get('world',{}),'weapon':reply.get('snapshot',{}).get('weapon')},'player':player,'vehicles':player.get('vehicles',{}),'transport':reply.get('snapshot',{}).get('transport',{}),'mutation':reply.get('mutation',{})}

def logout_session(account,oid,data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required')
    command=logout_command(data);active=LIVE_COMBAT.active_for(account)
    if 'request_id'not in command:
        identity=data.get('live_session_id',active['id']if active else '')
        command['request_id']='logout_'+hashlib.sha256((str(identity)+json.dumps(command,sort_keys=True)).encode()).hexdigest()[:40]
    if active:
        live=LIVE_COMBAT.request(account,'session',dict(data,session=command,character_id=oid,session_id=data.get('live_session_id',active['id'])))
        check_live_error(live)
        out=session_snapshot(live.get('mutation',{}),oid)
        if not out.get('saved'):raise BackendError('Native position save was not acknowledged')
        LIVE_COMBAT.request(account,'stop',dict(character_id=oid,session_id=active['id']))
    else:
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},{'action':'zoneInCharacter','inventoryRequest':'swgxr_session_v1 '+json.dumps(command,separators=(',',':'))}])
        out=session_snapshot(raw.get('variables',{}).get('session',{}),oid)
        if not out.get('saved'):raise BackendError('Native position save was not acknowledged')
    VOICE_STATE.remove(account)
    return dict(out,session_closed=True)

def vehicles_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required')
    command=vehicles_command(action,data)
    active=LIVE_COMBAT.active_for(account)
    if action.startswith("ch_") and not active:
        raise LiveConflict("Creature Handler interactions need an owned native gameplay session")
    if active:
        live=LIVE_COMBAT.request(account,'vehicles',dict(data,vehicles=command,character_id=oid,session_id=data.get('live_session_id',data.get('session_id',active['id']))))
        check_live_error(live)
        out=vehicles_snapshot(live['mutation'],oid);attributes=live.get('service_attributes',{})
        out['live_response']=live
    else:
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
            {'action':'zoneInCharacter','inventoryRequest':'swgxr_vehicles_v1 '+json.dumps(command,separators=(',',':'))}])
        out=vehicles_snapshot(raw.get('variables',{}).get('vehicles',{}),oid);attributes=raw.get('variables',{}).get('weaponAttributes',{})
    if out.get('inventory'):out['inventory']=inventory_snapshot({'variables':{'inventory':out['inventory'],'weaponAttributes':attributes}},oid)
    return out

def entertainer_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required')
    command=entertainer_command(action,data)
    active=LIVE_COMBAT.active_for(account)
    if not active:raise LiveConflict('Entertainer interactions need an owned native gameplay session')
    if action=='group_bump':
        proof=SERVICES_PRESENCE.authorize_group_bump(account,oid,command['target_id'],command['request_id'],command['group_bump_id'])
        command['group_bump_authorized']=True
        command['group_bump_receipt_only']=proof['receipt_only']
    live=LIVE_COMBAT.request(account,'entertainer',dict(data,entertainer=command,character_id=oid,
        session_id=data.get('live_session_id',active['id'])))
    check_live_error(live)
    out=entertainer_snapshot(live.get('mutation',{}),oid)
    state=out['state']
    if isinstance(state.get('appearance'),dict):state['appearance']=image_appearance_normalize(state['appearance'])
    if isinstance(state.get('image_design'),dict):state['image_design']=image_design_normalize(state['image_design'])
    out.update(sequence=live.get('sequence',0),live_response=live)
    PERFORMANCE_HUB.observe_native(account,oid,out)
    return out


def medic_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required')
    command=medic_command(action,data)
    if LIVE_COMBAT.active_for(account):
        live=LIVE_COMBAT.request(account,'medic',dict(data,medic=command,character_id=oid,session_id=data.get('live_session_id',data.get('session_id',LIVE_COMBAT.active_for(account)['id']))))
        check_live_error(live)
        return medic_snapshot(live['mutation'],oid)
    raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
        {'action':'zoneInCharacter','inventoryRequest':'swgxr_medic_v1 '+json.dumps(command,separators=(',',':'))}])
    return medic_snapshot(raw.get('variables',{}).get('medic',{}),oid)

def scout_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required')
    command=scout_command(action,data)
    active=LIVE_COMBAT.active_for(account)
    if action in ('ranger_status','conceal','rescue','area_track') and not active:
        raise LiveConflict('Ranger interactions need an owned native gameplay session')
    if active:
        live=LIVE_COMBAT.request(account,'scout',dict(data,scout=command,character_id=oid,session_id=data.get('live_session_id',data.get('session_id',active['id']))))
        check_live_error(live)
        out=scout_snapshot(live['mutation'],oid,live.get('scout_attributes',{}))
    else:
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
            {'action':'zoneInCharacter','inventoryRequest':'swgxr_scout_v1 '+json.dumps(command,separators=(',',':'))}])
        out=scout_snapshot(raw.get('variables',{}).get('scout',{}),oid,raw.get('variables',{}).get('weaponAttributes',{}))
    return out

def jtl_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isascii() or not oid.isdigit():raise ValueError('Owned character_id required.')
    intent=jtl_command(action,data)
    active=LIVE_COMBAT.active_for(account)
    if not active:raise LiveConflict('JtL requires an owned native gameplay session.')
    live=LIVE_COMBAT.request(account,'jtl',dict(data,jtl=intent,character_id=oid,
        session_id=data.get('live_session_id',data.get('session_id',active['id']))))
    check_live_error(live)
    out=jtl_snapshot(live['mutation'],oid)
    SERVICES_PRESENCE.observe_launch_stage(account,oid,out['state'].get('launch_stage'))
    out['live_response']=live
    if 'sequence' in live:out['sequence']=live['sequence']
    # Presentation is never part of the native mutation or its durable receipt.
    # A rejected tracking sample cannot turn a committed boarding/flight action
    # into an apparent transaction failure.
    try:
        out.update(JTL_PRESENCE.exchange(account,oid,active['id'],out['state'],
            data.get('presentation') if action in ('status','control','walk') else None))
    except ValueError as error:
        JTL_PRESENCE.invalidate(account)
        out.update(crew_poses=[],crew_pose_ttl_ms=750,presentation_error=str(error))
    if action in ('decorate','recover') and out['ok']:
        out['inventory']=read_inventory(account,oid)
    if not out['ok']:raise NativeJtlRejected(out)
    return out

def services_request(account, oid, action, data):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required.')
    command=services_command(action,data)
    if action in ('recruiter_join','recruiter_promote','recruiter_status_toggle','recruiter_purchase','contraband_answer') and not LIVE_COMBAT.active_for(account):
        raise LiveConflict('Faction interactions need an owned native gameplay session')
    temporary_recipient=None
    try:
        if action in ('pay','house_permission'):
            proof=(SERVICES_PRESENCE.authorize_payment(account,oid,command['target_id'],command['request_id'],(command['amount'],command.get('faction_points',{}))) if action=='pay' else SERVICES_PRESENCE.authorize_house_permission(account,oid,command['target_id'],command['request_id'],command['arm_id']))
            recipient_account=proof.get('target_account')
            if recipient_account and not LIVE_COMBAT.active_for(recipient_account):
                native={'position':proof['target_position'],'zone':proof['target_zone'],'building_id':proof['target_building_id'],'cell_index':proof['target_cell_index']}
                LIVE_COMBAT.start(recipient_account,dict(native,character_id=command['target_id']),SECRET,CONTAINER,characters)
                temporary_recipient=recipient_account
                current=LIVE_COMBAT.active_for(recipient_account)
                LIVE_COMBAT.request(recipient_account,'update',dict(native,character_id=command['target_id'],session_id=current['id']))
        active=LIVE_COMBAT.active_for(account)
        if active:
            live=LIVE_COMBAT.request(account,'services',dict(data,service=command,character_id=oid,session_id=data.get('live_session_id',data.get('session_id',active['id']))))
            check_live_error(live)
            out=services_snapshot(live['mutation'],oid,live.get('service_attributes',{}))
            out['live_response']=live
        else:
            raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
                {'action':'zoneInCharacter','inventoryRequest':'swgxr_services_v1 '+json.dumps(command,separators=(',',':'))}])
            out=services_snapshot(raw.get('variables',{}).get('services',{}),oid,raw.get('variables',{}).get('weaponAttributes',{}))
        out['presence']=SERVICES_PRESENCE.register(account,oid,out['state']['player'])
        if action=='house_permission_arm' and out.get('mutation',{}).get('success') and out['mutation'].get('arm'):
            SERVICES_PRESENCE.arm_house_permission(account,oid,out['mutation']['arm'])
        try:VOICE_STATE.publish(account,oid,out['state']['player'],session_id=active['id'] if active else '',live=bool(active))
        except (OSError,ValueError):pass
        return out
    finally:
        if temporary_recipient:LIVE_COMBAT.close(temporary_recipient)

def crafting_request(account, oid, action='status', data=None):
    if not isinstance(oid,str) or not oid.isdigit():raise ValueError('Owned character_id required.')
    data=data or {}
    command=crafting_command(action,data)
    active=LIVE_COMBAT.active_for(account)
    if active:
        live_data=dict(data,crafting=command,character_id=oid,session_id=data.get('live_session_id',active['id']))
        live=LIVE_COMBAT.request(account,'crafting',live_data)
        check_live_error(live)
        out=crafting_snapshot({'variables':{'crafting':live['mutation']}},oid)
        if live['mutation'].get('inventory'):
            out['inventory']=inventory_snapshot({'variables':{'inventory':live['mutation']['inventory'],'weaponAttributes':live.get('service_attributes',{})}},oid)
        out['live_response']=live
    else:
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
            {'action':'zoneInCharacter','inventoryRequest':'swgxr_crafting_v1 '+json.dumps(command,separators=(',',':'))}])
        out=crafting_snapshot(raw,oid)
        if action in ('assemble','finish','cancel'):out['inventory']=read_inventory(account,oid)
    return out

def gathering_request(account, oid, action='status', data=None):
    if not isinstance(oid,str) or not oid.isdigit() or int(oid)>2**64-1:
        raise ValueError('character_id must be an unsigned integer.')
    data=data or {};command={'action':action,**planet_context(data)}
    if action not in ('status','survey','deploy','collect','holster','return_tool'):
        raise ValueError('Unsupported gathering action.')
    if action!='status':
        key=data.get('request_id')
        if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):
            raise ValueError('request_id must be a stable 8–64 character idempotency key.')
        command['request_id']=key
    for field in ('tool_id','resource_id'):
        if field not in data:continue
        value=data[field]
        if not isinstance(value,str) or not value.isdigit() or int(value)>2**64-1:
            raise ValueError(field+' must be a Core3 object identifier.')
        command[field]=value
    if action in ('survey','deploy','collect'):
        position=data.get('position')
        if not isinstance(position,list) or len(position)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) for v in position):
            raise ValueError('position must be finite SWG world [x,y,z], y up.')
        if abs(position[0])>8192 or abs(position[2])>8192 or abs(position[1])>2048:
            raise ValueError('Position is outside ground planet bounds.')
        if action in ('survey','deploy') and (not command.get('tool_id') or not command.get('resource_id')):raise ValueError('tool_id and resource_id are required.')
        command.update(position=position)
    if action=='collect':
        deployment=data.get('deployment_id')
        if not isinstance(deployment,str) or not re.fullmatch(r'[0-9]{1,20}:[0-9]{1,20}',deployment):raise ValueError('Invalid deployment_id.')
        command['deployment_id']=deployment
    elif action in ('holster','return_tool') and not command.get('tool_id'):raise ValueError('tool_id is required.')
    active=LIVE_COMBAT.active_for(account)
    if active:
        live=LIVE_COMBAT.request(account,'gathering',dict(data,gathering=command,character_id=oid,session_id=data.get('live_session_id',active['id'])))
        check_live_error(live)
        raw={'variables':{'gathering':live['mutation'],'weaponAttributes':live.get('service_attributes',{})}}
    else:
        live=None
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
                            {'action':'zoneInCharacter','inventoryRequest':'swgxr_gathering_v1 '+json.dumps(command,separators=(',',':'))}])
    result=gathering_snapshot(raw,oid)
    if live:result['live_response']=live
    if action=='status':
        state=result['state']
        if live:state['live_response']=live
        return state
    if result.get('mutation',{}).get('success') is not True:raise BackendError('Core3 gathering mutation did not complete.')
    result['inventory']=inventory_snapshot({'variables':{'inventory':raw['variables']['gathering']['inventory'],'weaponAttributes':raw['variables'].get('weaponAttributes',{})}},oid)
    result['verified_by']='native_core3_receipt_and_committed_inventory_snapshot'
    return result

def corpse_request(account, oid, action='corpses', data=None):
    if not isinstance(oid,str) or not oid.isdigit() or int(oid)>2**64-1:raise ValueError('Invalid character_id.')
    data=data or {};position=data.get('position')
    if not isinstance(position,list) or len(position)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) for v in position):raise ValueError('position must be finite source world [x,y,z].')
    if abs(position[0])>8192 or abs(position[2])>8192 or abs(position[1])>2048:raise ValueError('Position outside ground planet bounds.')
    if action not in ('corpses','corpse_inspect','corpse_harvest','corpse_loot'):raise ValueError('Unsupported corpse action.')
    command={'action':action,'position':position,**planet_context(data)}
    if action!='corpses':
        corpse=data.get('corpse_id');key=data.get('request_id')
        if not isinstance(corpse,str) or not corpse.isdigit() or int(corpse)>2**64-1:raise ValueError('Invalid corpse_id.')
        if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}',key):raise ValueError('Stable request_id required.')
        command.update(corpse_id=corpse,request_id=key)
        if action=='corpse_harvest':
            if data.get('kind') not in ('meat','hide','bone'):raise ValueError('Invalid organic resource kind.')
            command['kind']=data['kind']
    active=LIVE_COMBAT.active_for(account)
    if active:
        live=LIVE_COMBAT.request(account,'corpse',dict(data,character_id=oid,session_id=active['id'],corpse=command))
        check_live_error(live)
        raw={'variables':{'gathering':live['mutation']}}
    else:
        raw=invoke(account,[{'action':'selectContext','characterOid':int(oid)},
            {'action':'zoneInCharacter','inventoryRequest':'swgxr_corpse_v1 '+json.dumps(command,separators=(',',':'))}])
    result=corpse_snapshot(raw,oid)
    if action in ('corpse_harvest','corpse_loot'):
        if result.get('mutation',{}).get('success') is not True:raise BackendError('Native corpse mutation incomplete.')
        result['inventory']=read_inventory(account,oid)
        result['verified_by']='native_core3_receipt_and_fresh_inventory_login'
    return result


def read_datapad(account, oid, timeout=30):
    deadline = time.monotonic()+timeout
    result, _ = select_character(account, oid, timeout=timeout)
    try:
        initial = datapad(result, oid)
        ids = [int(entry['id']) for entry in initial['waypoints']+initial['physical_entries']]
        if len(ids)>128: raise ValueError('Datapad attribute limit exceeded.')
        if ids and not LIVE_COMBAT.active_for(account):
            result = invoke(account,[{'action':'selectContext','characterOid':int(oid)},
                                     {'action':'zoneInCharacter','attributeTargets':ids}],
                            timeout=max(0.1,deadline-time.monotonic()))
        return datapad(result, oid)
    except ValueError as exc: raise BackendError(str(exc)) from exc

def delete_datapad_entry(account, data):
    oid = str(data.get('character_id',''))
    entry_id = str(data.get('entry_id',''))
    if not entry_id.isdigit(): raise ValueError('entry_id must identify a removable Core3 object.')
    before = read_datapad(account,oid)
    entry = next((entry for entry in before['entries'] if entry['id']==entry_id),None)
    if entry is None or not entry.get('deletable',False):
        raise ValueError('Entry is not owned, removable, or is managed by Core3.')
    invoke(account,[{'action':'selectContext','characterOid':int(oid)},
                    {'action':'zoneInCharacter','datapadCommand':{'name':'serverdestroyobject','target':int(entry_id),'arguments':'swgxr_datapad'}}],timeout=25)
    after = read_datapad(account,oid)
    if any(entry['id']==entry_id for entry in after['entries']):
        raise BackendError('Core3 did not confirm deletion on fresh login; the item may be in use or protected.')
    return {'backend':'core3','deleted_id':entry_id,'datapad':after,'verified_by':'fresh_owned_native_snapshot'}

def create_waypoint(account, data):
    deadline = time.monotonic() + 45
    oid = str(data.get('character_id', ''))
    name = data.get('name', '')
    # The command bridge currently uses Engine3 String -> UnicodeString.
    # Keep its supported ASCII transport explicit rather than corrupt names.
    if not isinstance(name, str) or not re.fullmatch(r'[ -~]{1,64}', name) or not name.strip():
        raise ValueError('Waypoint name must contain 1–64 printable ASCII characters.')
    name = name.strip()
    waypoint_planet=validate_planet(data.get('planet','tatooine'))
    position = data.get('position', {})
    if not isinstance(position, dict): raise ValueError('position must contain x, y, z.')
    values = []
    for axis, bound in [('x',8192),('y',4096),('z',8192)]:
        value = position.get(axis)
        if isinstance(value, bool) or not isinstance(value, (int,float)) or not math.isfinite(value) or abs(value)>bound:
            raise ValueError('Waypoint position is outside the supported ground planet bounds.')
        values.append(float(value))
    before = read_datapad(account, oid)
    old_ids = {w['id'] for w in before['waypoints']}
    arguments = waypoint_planet+' ' + ' '.join(format(v,'.9g') for v in values) + ' ' + name
    invoke(account,[{'action':'selectContext','characterOid':int(oid)},
                    {'action':'zoneInCharacter','datapadCommand':{'name':'requestwaypointatposition','arguments':arguments}}],timeout=25)
    # A sent command is not an acknowledgement. A separate authenticated
    # session must receive the persisted PlayerObject waypoint before success.
    after = read_datapad(account, oid, timeout=max(0.1,deadline-time.monotonic()))
    match = next((w for w in after['waypoints'] if w['id'] not in old_ids and w['name']==name and w['planet']==waypoint_planet and all(abs(a-b)<0.002 for a,b in zip(w['position'],values))), None)
    if match is None:
        raise BackendError('Core3 did not confirm waypoint creation on fresh login. Refresh before retrying to avoid duplicates.')
    return {'backend':'core3','waypoint':match,'datapad':after,'verified_by':'fresh_owned_native_snapshot'}

def stage_local(position):
    manifest=json.loads((ROOT/'runtime/assets/mos_eisley/scene.json').read_text())
    origin=manifest['origin']
    return [position[0]-origin[0],position[1]-origin[1],origin[2]-position[2]]

def stage_spawn():
    path = ROOT / 'runtime/assets/mos_eisley/scene.json'
    if not path.exists():
        raise BackendError('Mos Eisley scene manifest is not prepared.')
    manifest = json.loads(path.read_text())
    spawn = manifest.get('spawn')
    if isinstance(spawn, list) and len(spawn) == 3:
        return dict(zip(('x', 'y', 'z'), spawn))
    if isinstance(spawn, dict) and all(k in spawn for k in ('x', 'y', 'z')):
        return spawn
    raise BackendError('Mos Eisley scene manifest has no valid spawn.')

VOICE_ATTEMPTS={}
def voice_request(account,data,issue=False):
    oid=str(data.get('character_id',''))
    if not oid.isdigit():raise ValueError('Owned character_id required')
    active=LIVE_COMBAT.active_for(account)
    if active:
        if active['character_id']!=oid or data.get('session_id',active['id'])!=active['id']:raise ValueError('Owned live voice session required')
        state=VOICE_STATE.owned(account,oid,active['id'])
    else:
        # A disconnected ship voice request must not turn into a legacy ground
        # login/status action. Native session recovery belongs to gameplay.
        if data.get('session_id') or data.get('live_session_id') or any(str(data.get(key,'')).startswith('space_') for key in ('zone','planet')):
            raise ValueError('An active owned native session is required for space or live voice')
        now=time.monotonic()
        try:state=VOICE_STATE.owned(account,oid,'')
        except ValueError:state=None
        if now-VOICE_ATTEMPTS.get(account,0)<5:
            if state is None:raise ValueError('Voice native refresh pending; retry after5seconds')
        elif state is None or time.time()-state['updated_at']>=5:
            for key,at in list(VOICE_ATTEMPTS.items()):
                if now-at>60:VOICE_ATTEMPTS.pop(key,None)
            VOICE_ATTEMPTS[account]=now
            services_request(account,oid,'status',data)
            state=VOICE_STATE.owned(account,oid,'')
    allowed,reasons=voice_granted(state)
    out={'backend':'core3','character_id':oid,'native_session_id':state['session_id'],'needs_presence':not bool(active),'presence_interval':5,'channels':allowed,'reasons':reasons,'channel':'proximity','protocol':'swgxr-voice-v1','relay_port':18084,
         'scope':state.get('scope','planet'),'zone':state['zone'],'ship_id':state.get('ship_id','0')}
    if issue:
        out['ticket']=local_authority().issue(account,oid,state['session_id'],'local-debug',True,time.time()+86400)
        out['expires_in']=30
    return out

class Handler(BaseHTTPRequestHandler):
    server_version = 'SWGXRPrototype/0.1'

    def log_message(self, format, *args):
        # Base logging includes request targets and native session query tokens.
        # Keep credentials, request bodies and attacker-controlled text out of logs.
        pass

    def respond(self, status, data):
        # Every caller has finished its native transaction before responding.
        # A slow client's TCP reader must not hold the global native lane.
        LOCK.release_completed()
        encoded = json.dumps(data).encode()
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(encoded)))
            self.send_header('Cache-Control', 'no-store')
            if 'retry_after' in data:self.send_header('Retry-After',str(int(data['retry_after'])))
            self.end_headers()
            self.wfile.write(encoded)
        except (BrokenPipeError,ConnectionResetError,TimeoutError):
            self.close_connection=True

    def allowed(self):
        # Native Godot has no Origin. No browser cross-origin API access.
        if self.headers.get('Origin'):
            self.respond(403, {'error': 'Browser origins are not accepted by this local prototype API.'})
            return False
        return True

    def do_GET(self):
        if not self.allowed(): return
        path = urlparse(self.path)
        try:
            if path.path == '/health':
                self.respond(200, health())
            elif path.path == '/combat/session':
                query=parse_qs(path.query);data={key:value[0] for key,value in query.items()}
                with LOCK:self.respond(200,LIVE_COMBAT.request(data.get('account','prototype'),'snapshot',data))
            elif path.path == '/gathering/corpses':
                query=parse_qs(path.query)
                try:position=[float(v) for v in query.get('position',[''])[0].split(',')]
                except ValueError:raise ValueError('position query must be x,y,z.')
                with LOCK:
                    self.respond(200,corpse_request(query.get('account',['prototype'])[0],query.get('character_id',[''])[0],data={'position':position}))
            elif path.path == '/crafting':
                query=parse_qs(path.query)
                with LOCK:self.respond(200,crafting_request(query.get('account',['prototype'])[0],query.get('character_id',[''])[0],data={key:value[0] for key,value in query.items()}))
            elif path.path == '/gathering':
                query=parse_qs(path.query)
                data={'tool_id':query['tool_id'][0]} if query.get('tool_id') else {}
                with LOCK:
                    self.respond(200,gathering_request(query.get('account',['prototype'])[0],query.get('character_id',[''])[0],data=data))
            elif path.path == '/inventory':
                if LOCK.occupied.is_set():raise BackendBusy('Inventory refresh waits for an authoritative transaction; retain last confirmed readout')
                query = parse_qs(path.query)
                with LOCK:
                    self.respond(200, read_inventory(query.get('account',['prototype'])[0], query.get('character_id',[''])[0]))
            elif path.path == '/weapons':
                query = parse_qs(path.query)
                oid = query.get('character_id',[''])[0]
                with LOCK:
                    result, _ = select_character(query.get('account',['prototype'])[0], oid)
                    self.respond(200, weapon_snapshots(result, oid))
            elif path.path == '/datapad':
                query = parse_qs(path.query)
                with LOCK:
                    self.respond(200, read_datapad(query.get('account',['prototype'])[0], query.get('character_id',[''])[0]))
            elif path.path == '/creation-options':
                self.respond(200, creation_options())
            elif re.fullmatch(r'/characters/[0-9]+', path.path):
                account = parse_qs(path.query).get('account', ['prototype'])[0]
                with LOCK:
                    _, character = select_character(account, path.path.rsplit('/', 1)[1])
                    self.respond(200, {'backend': 'core3', 'character': character})
            elif path.path == '/characters':
                account = parse_qs(path.query).get('account', ['prototype'])[0]
                with LOCK:
                    self.respond(200, {'backend': 'core3', 'characters': characters(account)})
            else:
                self.respond(404, {'error': 'Unknown endpoint.'})
        except BackendBusy as exc:self.respond(503,{'backend':'core3','error_code':'backend_busy','retry_after':1,'mutation_started':False,'error':str(exc)})
        except NativeReplyTimeout as exc:self.respond(504,exc.response())
        except LiveConflict as exc: self.respond(409,{'backend':'core3','session_live':False,'error_code':'live_session_conflict','error':str(exc)})
        except NativeMovementRejected as exc:self.respond(400,exc.response())
        except ValueError as exc: self.respond(400, {'error': str(exc)})
        except (BackendError, OSError) as exc: self.respond(503, {'backend': 'core3', 'error': str(exc)})

    def do_POST(self):
        if not self.allowed(): return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_BODY:
                raise ValueError('Invalid request size.')
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict): raise ValueError('Expected a JSON object.')
            account = data.get('account', 'prototype')
            account_name(account)
            if self.path == '/session/sync':
                self.respond(200,WORLD_SYNC.sync(account,data))
                return
            if self.path == '/session/update' and LIVE_COMBAT.parallel_update_allowed(account,data):
                # Verified new native binaries use Engine cross-locking. Keep
                # old binaries behind the global lane to avoid player deadlock.
                self.respond(200,gameplay_session(account,data))
                return
            if self.path in ('/combat/session/loadout','/combat/session/update','/combat/session/fire','/combat/session/melee','/combat/session/taunt','/combat/session/warcry','/combat/session/pikeman','/combat/session/fencer','/combat/session/pistoleer','/combat/session/carbineer','/combat/session/rifleman','/combat/session/commando','/combat/session/bountyhunter','/combat/session/squadleader','/combat/session/swordsman','/combat/session/tka','/combat/session/brawler_buff','/combat/session/impact') and LIVE_COMBAT.parallel_update_allowed(account,data):
                # Cross-account native waits may overlap; the owned IPC gate
                # still serializes every mutation for one player.
                self.respond(200,LIVE_COMBAT.request(account,self.path.rsplit('/',1)[-1],data))
                return
            if self.path == '/services/presence':
                self.respond(200,SERVICES_PRESENCE.update(account,str(data.get('character_id','')),data.get('token',''),data))
                return
            if self.path == '/performance':
                self.respond(200, PERFORMANCE_HUB.update(account, data))
                return
            if self.path=='/inventory/status' and LOCK.occupied.is_set():raise BackendBusy('Inventory refresh waits for an authoritative transaction; retain last confirmed readout')
            with LOCK:
                if self.path in ('/voice/session','/voice/presence'):
                    self.respond(200,voice_request(account,data,self.path=='/voice/session'))
                elif self.path == '/inventory/status':
                    active=LIVE_COMBAT.active_for(account)
                    if active and data.get('live_session_id',active['id'])!=active['id']:raise LiveConflict('Live session identity mismatch')
                    self.respond(200,read_inventory(account,str(data.get('character_id',''))))
                elif self.path in ('/session/start','/session/update','/session/life'):
                    self.respond(200,gameplay_session(account,data,self.path.endswith('/start'),self.path.endswith('/life')))
                elif self.path == '/session/logout':
                    self.respond(200,logout_session(account,str(data.get('character_id','')),data))
                elif self.path == '/combat/session/start':
                    self.respond(200,LIVE_COMBAT.start(account,data,SECRET,CONTAINER,characters))
                elif self.path in ('/combat/session/loadout','/combat/session/update','/combat/session/fire','/combat/session/melee','/combat/session/taunt','/combat/session/warcry','/combat/session/pikeman','/combat/session/fencer','/combat/session/pistoleer','/combat/session/carbineer','/combat/session/rifleman','/combat/session/commando','/combat/session/bountyhunter','/combat/session/squadleader','/combat/session/swordsman','/combat/session/tka','/combat/session/brawler_buff','/combat/session/impact','/combat/session/stop','/combat/session/life'):
                    self.respond(200,LIVE_COMBAT.request(account,self.path.rsplit('/',1)[-1],data))
                elif self.path in ('/gathering/corpse/inspect','/gathering/corpse/harvest','/gathering/corpse/loot'):
                    self.respond(200,corpse_request(account,str(data.get('character_id','')),'corpse_'+self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/services/'):
                    self.respond(200,services_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/jtl/'):
                    self.respond(200,jtl_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/vehicles/'):
                    self.respond(200,vehicles_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/entertainer/'):
                    self.respond(200,entertainer_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/medic/'):
                    self.respond(200,medic_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/scout/'):
                    self.respond(200,scout_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path.startswith('/crafting/'):
                    self.respond(200,crafting_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path in ('/gathering/status','/gathering/survey','/gathering/deploy','/gathering/collect','/gathering/holster','/gathering/return_tool'):
                    self.respond(200,gathering_request(account,str(data.get('character_id','')),self.path.rsplit('/',1)[-1],data))
                elif self.path in ('/inventory/equip', '/inventory/unequip', '/inventory/consume'):
                    self.respond(200, read_inventory(account, str(data.get('character_id','')),
                                                     operation=(self.path.rsplit('/',1)[-1],data.get('item_id'),data.get('arrangement',0))))
                elif self.path == '/inventory/split':
                    self.respond(200, read_inventory(account, str(data.get('character_id','')),
                                                     (data.get('item_id'), data.get('quantity'))))
                elif self.path == '/datapad/delete':
                    self.respond(200, delete_datapad_entry(account, data))
                elif self.path == '/waypoints':
                    self.respond(201, create_waypoint(account, data))
                elif self.path == '/characters':
                    action = creation_action(data)
                    try: result = invoke(account, [action])
                    except BackendError as exc:
                        if 'Character creation failed:' in str(exc): raise ValueError(str(exc)) from exc
                        raise
                    created = next(a for a in result['actions'] if a['action'] == 'createCharacter')
                    oid = str(created['createdOid'])
                    _, character = select_character(account, oid)
                    self.respond(201, {'backend': 'core3', 'character': character})
                elif self.path == '/enter':
                    oid = str(data.get('character_id', ''))
                    if not oid.isdigit(): raise ValueError('character_id must be an unsigned integer.')
                    result, character = select_character(account, oid)
                    server_scene = result['variables']['scene']
                    location=session_snapshot(result.get('variables',{}).get('session',{}),oid)['location']
                    self.respond(200, {'backend': 'core3', 'character_id': oid, 'name': character['name'], 'character': character,
                                       'scene': location['zone'], 'stage': 'mos_eisley_starport' if location['zone']=='tatooine' else location['zone'],
                                       'position':dict(zip(('x','y','z'),location['position'])), 'position_space': 'swg_world', 'source_location':location,
                                       'core3_zone_verified': result.get('zoneConnected', False),
                                       'core3_scene': server_scene,
                                       'datapad': datapad(result, oid),
                                       'weapon_snapshot': weapon_snapshots(result, oid),
                                       'combat_snapshot': combat_snapshot(result, oid),
                                       'entertainment': PERFORMANCE_HUB.register(account, oid, result, stage_local(location['position'])),
                                       'core3_session': 'validated_then_disconnected',
                                       'movement': 'local_godot_prototype'})
                else: self.respond(404, {'error': 'Unknown endpoint.'})
        except BackendBusy as exc:
            self.respond(503,{'backend':'core3','error_code':'backend_busy','retry_after':1,'mutation_started':False,'error':str(exc)})
        except NativeReplyTimeout as exc:
            self.respond(504,exc.response())
        except LiveConflict as exc:
            self.respond(409, {'backend':'core3','session_live':False,'error_code':'live_session_conflict','error':str(exc)})
        except NativeMovementRejected as exc:
            self.respond(400,exc.response())
        except NativeJtlRejected as exc:
            self.respond(400,exc.result)
        except (ValueError, TypeError, KeyError, StopIteration) as exc:
            self.respond(400, dict({'error': str(exc) or 'Invalid Core3 result.'}, **({'mutation_started':False,'confirmed_rejection':True} if getattr(exc,'confirmed_rejection',False) else {})))
        except (BackendError, OSError) as exc:
            self.respond(503, {'backend': 'core3', 'error': str(exc)})

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18080)
    args = parser.parse_args()
    print(f'SWGXR actual-Core3 adapter on http://127.0.0.1:{args.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
