"""Read combat state from Core3 replication; never calculate damage or life state.

Wire layouts: pinned TangibleObjectMessage3/6 and CreatureObjectMessage3/6.
This is a baseline decoder for the persistent-zone bridge, not a live session.
Posture is authoritative: zero HAM alone must not invent an incap/death event.
"""
from __future__ import annotations

try:
    from .character_protocol import Reader
except ImportError:
    from character_protocol import Reader

CREO = 0x4352454F
TANO = 0x54414E4F
POSTURES = {0: 'upright', 1: 'crouched', 2: 'prone', 3: 'sneaking',
            4: 'blocking', 5: 'climbing', 6: 'flying', 7: 'lying_down',
            8: 'sitting', 9: 'skill_animating', 10: 'driving', 11: 'riding',
            12: 'knocked_down', 13: 'incapacitated', 14: 'dead'}
ATTRIBUTES = ('health', 'strength', 'constitution', 'action', 'quickness',
              'stamina', 'mind', 'focus', 'willpower')


def vector(reader, fmt, expected=None, limit=4096):
    count, counter = reader.u32(), reader.u32()
    if count > limit or (expected is not None and count != expected):
        raise ValueError('Invalid Core3 combat vector length.')
    values = [reader.number(fmt) for _ in range(count)]
    return {'counter': counter, 'values': values}


def baseline(record):
    """Decode one original creature or tangible baseline pair.

    All IDs/64-bit flags are strings for Godot JSON precision. Missing baseline
    6 is an incomplete observation, never fabricated full-health state.
    Tangibles include lairs; their durability is not creature HAM.
    """
    kind = record.get('type')
    if kind not in (CREO, TANO):
        raise ValueError('Unsupported combat object type.')
    if not record.get('baseline3'):
        raise ValueError('Core3 combat baseline 3 is missing.')
    r = Reader(bytes.fromhex(record['baseline3']))
    r.number('f')  # complexity
    table = r.ascii().decode('ascii'); r.u32(); key = r.ascii().decode('ascii')
    name = r.unicode(); r.u32(); r.ascii()  # volume, customization
    vector(r, 'I')  # visible components
    options = r.u32(); use_count = r.u32()
    condition_damage, max_condition = r.number('i'), r.number('i')
    visible = bool(r.number('B'))
    out = {'kind': 'creature' if kind == CREO else 'tangible', 'name': name,
           'name_string_id': {'table': table, 'key': key}, 'options': options,
           'condition_damage': condition_damage, 'max_condition': max_condition,
           'visible': visible, 'source': 'core3_replication', 'complete': False}
    if kind == CREO:
        posture = r.number('B'); r.number('B'); r.u64(); height = r.number('f')
        shock = r.number('i'); states = r.u64(); wounds = vector(r, 'i', 9)
        if posture not in POSTURES:
            raise ValueError('Unsupported Core3 creature posture.')
        out.update(posture=posture, posture_name=POSTURES[posture],
                   incapacitated=posture == 13, dead=posture == 14,
                   knocked_down=posture == 12, height=height, shock_wounds=shock,
                   states=str(states), wounds=wounds,
                   incapacitation_recovery_seconds=use_count)
    if r.pos != len(r.data):
        raise ValueError('Unexpected trailing combat baseline 3 data.')
    if not record.get('baseline6'):
        return out
    r = Reader(bytes.fromhex(record['baseline6']))
    r.u32(); defenders = vector(r, 'Q')
    out['defenders'] = [str(oid) for oid in defenders['values']]
    if kind == CREO:
        level = r.number('H'); r.ascii(); r.ascii()
        weapon = r.u64(); r.u64(); r.u64(); r.u64(); r.u32()
        target = r.u64(); r.number('B'); r.u32(); r.u32()
        ham = vector(r, 'i', 9); maximum = vector(r, 'i', 9)
        # Equipment/alternate appearance/frozen follow; their variable-length
        # layout is owned by the appearance decoder, not guessed here.
        out.update(level=level, weapon_id=str(weapon), target_id=str(target),
                   ham=ham, max_ham=maximum)
        out['pools'] = {name: {'current': ham['values'][index],
                               'maximum': maximum['values'][index],
                               'wounds': wounds['values'][index]}
                        for index, name in enumerate(ATTRIBUTES)}
    out['complete'] = True
    return out


def snapshot(result, character_id):
    """Bounded read-only entry snapshot, explicitly not ongoing zone authority."""
    character_id = str(character_id)
    variables = result.get('variables', {})
    if str(variables.get('scene', {}).get('characterOid', '')) != character_id:
        raise ValueError('Combat snapshot does not match the selected character.')
    objects = variables.get('replication', {}).get('objects', {})
    player = objects.get('o' + character_id)
    if not player or player.get('type') != CREO:
        raise ValueError('Selected Core3 creature combat state missing.')
    return {'backend': 'core3', 'source': 'authenticated_core3_baselines',
            'character_id': character_id, 'player': baseline(player),
            'live': False, 'session': 'validated_then_disconnected'}


def apply_attribute_delta(current, payload):
    """Apply the fixed nine-slot HAM/wounds list format transactionally.

    Ordered reliable Core3 delivery is required. Missing/reordered counters
    demand a fresh baseline; never silently guess across a dropped update.
    Returns a new value and leaves the previous baseline untouched on failure.
    """
    r = Reader(payload)
    count, counter = r.u32(), r.u32()
    if count > 9 or len(current['values']) != 9:
        raise ValueError('Invalid attribute delta length.')
    previous = current['counter']
    if counter != ((previous + count) & 0xffffffff):
        raise ValueError('Core3 attribute delta gap; fresh baseline required.')
    values = list(current['values'])
    for _ in range(count):
        operation, index = r.number('B'), r.number('H')
        if operation != 2 or index >= 9:
            raise ValueError('Unexpected attribute list operation; refresh baseline.')
        values[index] = r.number('i')
    if r.pos != len(r.data):
        raise ValueError('Trailing attribute delta bytes.')
    return {'counter': counter, 'values': values}
