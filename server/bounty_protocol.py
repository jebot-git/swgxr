"""Input boundary for original Core3 PvE bounty mission interactions.

Only interaction intent crosses this boundary. The owned mission, signature,
droid charges, search result and reward are resolved by native Core3.
"""
try:
    from .planets import planet
except ImportError:
    from planets import planet

import math

FIELDS = {
    'bounty_informant': 'target_id',
    'bounty_probe': 'item_id',
    'bounty_seek': 'item_id',
    'bounty_track': 'item_id',
}
ACTIONS = tuple(FIELDS)


def fields(action, data):
    field = FIELDS[action]
    value = data.get(field)
    if (not isinstance(value, str) or not value.isascii()
            or not value.isdigit() or not 0 < int(value) < 2**64):
        raise ValueError('Valid native bounty ' + field + ' required.')
    out = {field: value}
    if action == 'bounty_probe':
        out['search_planet'] = planet(data.get('search_planet'))
    return out


def normalize_snapshot(bounty, label):
    """Bound the owned native projection and resolve original message labels."""
    if not isinstance(bounty, dict) or bounty.get('pve_only') is not True:
        raise ValueError('Native PvE-only bounty state required.')
    for key, maximum in (('droids', 256), ('informants', 128), ('planets', 10)):
        rows = bounty.get(key, [])
        if not isinstance(rows, list) or len(rows) > maximum:
            raise ValueError('Native bounty ' + key + ' exceeds bounds.')
        if key == 'planets':
            for value in rows:
                planet(value)
            if len(set(rows)) != len(rows):
                raise ValueError('Duplicate native bounty search planet.')
        else:
            for row in rows:
                if not isinstance(row, dict):
                    raise ValueError('Native bounty object required.')
                value = row.get('id')
                if (not isinstance(value, str) or not value.isascii()
                        or not value.isdigit() or not 0 < int(value) < 2**64):
                    raise ValueError('Native bounty object identity required.')
                if 'name' in row:
                    row['name'] = label(row['name'])
    for key in ('message',):
        if key in bounty:
            bounty[key] = label(bounty[key])
    waypoint = bounty.get('waypoint', {})
    if not isinstance(waypoint, dict):
        raise ValueError('Native bounty waypoint required.')
    if waypoint.get('active'):
        planet(waypoint.get('planet'))
        position = waypoint.get('position')
        if (not isinstance(position, list) or len(position) != 3
                or any(type(v) not in (int, float) or not math.isfinite(v)
                       or abs(v) > (2048 if i == 1 else 8192)
                       for i, v in enumerate(position))):
            raise ValueError('Native bounty waypoint position required.')
    return bounty
