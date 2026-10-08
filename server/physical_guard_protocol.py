"""Bounded tracking evidence; native CoreCU resolves guard eligibility and damage."""
import math


def pose(value):
    if not isinstance(value, dict):
        raise ValueError('Invalid physical guard pose')
    mode = value.get('mode')
    if mode == 'none' and set(value) == {'mode'}:
        return {'mode': 'none'}
    keys = {'mode', 'item_id', 'main', 'head', 'forward', 'left', 'right', 'axis'}
    if mode not in ('boxing', 'parry') or set(value) != keys:
        raise ValueError('Invalid physical guard fields')
    if value['main'] not in ('left', 'right') or not isinstance(value['item_id'], str) or not value['item_id'].isdigit() or not 0 < int(value['item_id']) < 2**64:
        raise ValueError('Invalid physical guard weapon')
    result = dict(value)
    for key in ('head', 'forward', 'left', 'right', 'axis'):
        p = value[key]
        limit = 20000 if key == 'head' else 2
        if not isinstance(p, list) or len(p) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > limit for v in p):
            raise ValueError('Invalid physical guard vector')
        result[key] = list(p)
    return result
