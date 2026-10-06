"""Canonical original ground zones; enabled instances remain server configuration."""
SUPPORTED_PLANETS = ('tatooine', 'naboo', 'corellia', 'rori', 'talus', 'dantooine',
                     'dathomir', 'endor', 'lok', 'yavin4')


def planet(value):
    if not isinstance(value, str) or value not in SUPPORTED_PLANETS:
        raise ValueError('Unsupported original ground planet.')
    return value


def context(data):
    """Optional source-zone fence; omission supports legacy same-zone callers."""
    out = {}
    for key in ('planet', 'zone'):
        if key in data:
            out[key] = planet(data[key])
    if len(out) == 2 and out['planet'] != out['zone']:
        raise ValueError('Conflicting source planet and zone.')
    return out
