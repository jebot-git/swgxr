"""Planning and per-request budgets; connected population has no fixed ceiling."""
import os
import re

TARGET_PLAYERS = 32
VISIBLE_PLAYERS = 32
NATIVE_CONNECTIONS = 64  # Initial Engine3 hash-table sizing, not an admission limit.

def configured_limit(name, default=0, *, allow_zero=True):
    value=os.environ.get(name,str(default))
    if not re.fullmatch(r'[0-9]+',value) or (not allow_zero and int(value)==0):
        raise ValueError(name+' must be a '+('non-negative' if allow_zero else 'positive')+' integer'+(' (0 means unlimited).' if allow_zero else '.'))
    return int(value)

HTTP_CONNECTIONS = configured_limit('SWGXR_HTTP_CONNECTIONS',128,allow_zero=False)
