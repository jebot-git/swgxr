"""Squad Leader intent validation; membership, marks and combat remain native."""
import re

BUFF_ABILITIES = ('steady_aim', 'rally', 'form_up', 'boost_morale', 'retreat')
ABILITIES = BUFF_ABILITIES + ('volley_fire',)
ATTACK_ACTIONS = frozenset(('fire', 'melee', 'commando', 'tka', 'swordsman',
                            'fencer', 'pikeman', 'pistoleer', 'carbineer', 'grenade', 'trap'))
SELF_BUFFS = frozenset(('overdrive', 'indomitable_focus', 'flawless_assault',
                        'run_and_gun', 'tactical_brace'))


def object_id(value):
    return (isinstance(value, str) and value.isascii() and value.isdigit()
            and 0 < int(value) < 2**64)


def token(value):
    return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{8,80}', value) is not None


def validate_cast(data):
    if data.get('ability_id') not in ABILITIES:
        raise ValueError('Unsupported Squad Leader ability.')
    if not token(data.get('shot_id')):
        raise ValueError('Invalid Squad Leader shot_id.')
    for key in ('item_id', 'target_id'):
        if not object_id(data.get(key)):
            raise ValueError('Invalid Squad Leader '+key+'.')


def mark_intent(data, action, ability_id='', target_id=None):
    """Forward an explicit mark reference, never a client hit/damage claim."""
    fields = ('volley_mark_id', 'volley_target_id')
    if not any(key in data for key in fields):
        return {}
    if action not in ATTACK_ACTIONS or ability_id in SELF_BUFFS:
        raise ValueError('Volley Fire marks require a damaging attack.')
    if not token(data.get('volley_mark_id')) or not object_id(data.get('volley_target_id')):
        raise ValueError('A valid Volley Fire mark and target pair is required.')
    if target_id is not None and target_id != data['volley_target_id']:
        raise ValueError('Volley Fire target must match the attack target.')
    return {key: data[key] for key in fields}
