"""Bounded physical-contact intent; native BH policy owns weapon behavior."""
import math


def object_id(value):
    return (isinstance(value, str) and value.isascii() and value.isdigit()
            and 0 < int(value) < 2**64)


def contact_fields(data, action):
    result = {}
    if 'guided_target_id' in data:
        if action != 'fire' or not object_id(data['guided_target_id']):
            raise ValueError('Guidance requires a valid fire target intent.')
        result['guided_target_id'] = data['guided_target_id']
    if 'pellet_contacts' in data:
        contacts = data['pellet_contacts']
        if action != 'impact' or not isinstance(contacts, list) or not 1 <= len(contacts) <= 8:
            raise ValueError('Scatter impact requires one to eight pellet contacts.')
        copied, seen = [], set()
        for contact in contacts:
            if not isinstance(contact, dict) or set(contact) != {'pellet_index', 'hit_position', 'projectile_age_seconds'}:
                raise ValueError('Invalid pellet contact fields.')
            index = contact['pellet_index']
            if type(index) is not int or not 0 <= index < 8 or index in seen:
                raise ValueError('Invalid or repeated pellet index.')
            position = contact['hit_position']
            age = contact['projectile_age_seconds']
            if (not isinstance(position, list) or len(position) != 3
                    or any(type(v) not in (int, float) or not math.isfinite(v) for v in position)):
                raise ValueError('Invalid finite pellet contact position.')
            if type(age) not in (int, float) or not math.isfinite(age) or not 0 <= age <= 8:
                raise ValueError('Invalid pellet contact age.')
            seen.add(index)
            copied.append(dict(pellet_index=index, hit_position=list(position), projectile_age_seconds=age))
        result['pellet_contacts'] = copied
    return result
