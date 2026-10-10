"""Bounded ship intents; Core3 alone owns ships, flight and POB contents."""
from copy import deepcopy
import math
import re

try:
    from .planets import SUPPORTED_PLANETS
    from .housing_protocol import fields as housing_fields
except ImportError:
    from planets import SUPPORTED_PLANETS
    from housing_protocol import fields as housing_fields

ACTIONS = ('status', 'launch', 'land', 'station', 'leave', 'control', 'walk',
           'decorate', 'recover', 'command', 'crew_prepare', 'crew_cancel',
           'crew_remove', 'crew_join', 'boarding_request', 'boarding_accept',
           'boarding_decline', 'return_ship', 'hyperspace', 'abort_hyperspace',
           'terminal', 'terminal_recover')
SPACE_ZONES = tuple('space_'+name for name in ('corellia', 'dantooine', 'dathomir',
    'endor', 'lok', 'naboo', 'tatooine', 'yavin4', 'light1', 'heavy1'))
COMMANDS = ('shield_front', 'shield_rear', 'shield_balance', 'power_engines', 'power_balanced',
            'elevator_up', 'elevator_down')


def context(data):
    result = {}
    for key in ('zone', 'planet'):
        if key in data:
            if data[key] not in SUPPORTED_PLANETS + SPACE_ZONES:
                raise ValueError('Unsupported JtL source zone.')
            result[key] = data[key]
    if len(result) == 2 and result['zone'] != result['planet']:
        raise ValueError('Conflicting JtL source zones.')
    return result


def number(value, minimum, maximum, label):
    if type(value) not in (int, float) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError('Invalid bounded ' + label + '.')
    return value


def local_vector(value):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError('Ship-local position required.')
    return [number(v, -64, 64, 'ship-local coordinate') for v in value]


def identifier(value):
    if not isinstance(value, str) or not value.isascii() or not value.isdigit() or not 0 < int(value) < 2**64:
        raise ValueError('Native object identity required.')
    return value


def command(action, data):
    if action not in ACTIONS:
        raise ValueError('Unsupported JtL action.')
    out = dict(action=action, **context(data))
    if action not in ('status', 'control', 'walk'):
        value = data.get('request_id')
        if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', value):
            raise ValueError('Stable JtL request_id required.')
        out['request_id'] = value
    if action in ('control', 'walk'):
        value = data.get('sequence')
        if type(value) is not int or not 0 < value <= 2**53 - 1:
            raise ValueError('Monotonic JtL sequence required.')
        out['sequence'] = value
    if action in ('launch', 'crew_prepare', 'terminal', 'terminal_recover'):
        out['terminal_id'] = identifier(data.get('terminal_id'))
    if action == 'terminal_recover':
        out['item_id'] = identifier(data.get('item_id'))
    if action == 'crew_prepare' and 'ship_id' in data:
        out['ship_id'] = identifier(data['ship_id'])
    if action in ('launch', 'crew_join'):
        value = data.get('launch_id')
        if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', value):
            raise ValueError('Native launch preparation required.')
        out['launch_id'] = value
    for name, field in (('crew_remove', 'member_id'), ('crew_join', 'pilot_id'),
                        ('boarding_request', 'target_ship_id'),
                        ('boarding_accept', 'requester_id'), ('boarding_decline', 'requester_id')):
        if action == name:
            out[field] = identifier(data.get(field))
    if action == 'crew_join':
        value = data.get('crew_handshake_id')
        if not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{24}', value):
            raise ValueError('Observed crew handshake required.')
        out['crew_handshake_id'] = value
    if action == 'station':
        if data.get('station_id') not in ('pilot', 'passenger'):
            raise ValueError('Original yacht station required.')
        out['station_id'] = data['station_id']
    if action == 'hyperspace':
        value = data.get('destination')
        if not isinstance(value, str) or not re.fullmatch(r'[a-z0-9_]{1,64}', value):
            raise ValueError('Original hyperspace destination required.')
        out['destination'] = value
    if action == 'control':
        fire = data.get('primary_fire', False)
        if type(fire) is not bool: raise ValueError('Boolean primary fire intent required.')
        out['primary_fire'] = fire
        for axis in ('pitch', 'yaw', 'roll', 'throttle'):
            out[axis] = number(data.get(axis), 0 if axis == 'throttle' else -1, 1, axis)
    if action in ('walk', 'decorate'):
        value = data.get('cell_index')
        if type(value) is not int or not 1 <= value <= 11:
            raise ValueError('Original interior yacht cell required.')
        out['cell_index'] = value
    if action == 'walk':
        out['position'] = local_vector(data.get('position'))
    if action in ('decorate', 'recover'):
        # Keep the same item pose/suspension/two-hand contract as ground houses.
        out.update(housing_fields('house_drop' if action == 'decorate' else 'house_recover', data))
        for key in ('placement_position', 'left_hand', 'right_hand'):
            if key in out:
                out[key] = local_vector(out[key])
    if action == 'command':
        value = data.get('command_id')
        if value not in COMMANDS and not (isinstance(value, str) and re.fullmatch(r'droidcommand_[a-z0-9_]{1,51}', value)):
            raise ValueError('Supported native ship command required.')
        out['command_id'] = value
        if value in ('elevator_up', 'elevator_down'):
            out['interaction_id'] = identifier(data.get('interaction_id'))
    return out


def normalize_state(state):
    try:from .datapad_protocol import display
    except ImportError:from datapad_protocol import display
    for row in state.get("missions",[])+state.get("waypoints",[]):
        for field in ("name","description"):
            value=row.get(field,"")
            if value.startswith("@") and ":" in value:
                table,key=value[1:].split(":",1);row[field]=display(table,key,key.replace("_"," ").title())
    return state

def snapshot(raw, oid):
    if not isinstance(raw, dict) or raw.get('source_kind') != 'core3_jtl' or raw.get('character_id') != str(oid):
        raise ValueError('Owned native JtL response required.')
    state = raw.get('jtl')
    if not isinstance(state, dict):
        raise ValueError('Native JtL snapshot required.')
    out = dict(ok=raw.get('success') is True, backend='core3', source_kind='core3_jtl',
                character_id=str(oid), state=normalize_state(deepcopy(state)),
                mutation=deepcopy({key: value for key, value in raw.items() if key != 'jtl'}))
    if not out['ok']:
        out['error_code'] = str(raw.get('error_code', 'jtl_rejected'))
        out['error'] = str(raw.get('error', out['error_code']))
    return out
