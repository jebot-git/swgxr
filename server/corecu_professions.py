"""Presentation of provisional resistance contributions; combat stays native."""
from functools import lru_cache
import json
from pathlib import Path
import re

@lru_cache(maxsize=1)
def policy():
    return json.loads((Path(__file__).parent/'combat/corecu_professions.json').read_text())

def contribution(profession, skill):
    data = policy()
    values = data['professions'].get(profession)
    if values is None or not skill.startswith(profession+'_'):
        return {}
    suffix = skill[len(profession)+1:]
    weight = .1 if suffix in ('novice', 'master') else .05 if re.fullmatch(r'.+_0[1-4]', suffix) else 0
    return {name: round(value*weight, 6) for name, value in zip(data['statuses'], values) if value*weight}


def trap_bonus_contribution(skill):
    """Percentage points on the second trap application roll, capped at 95%."""
    return 1 if skill in ('outdoors_scout_novice', 'outdoors_ranger_master') or re.fullmatch(r'outdoors_(?:scout_tools|ranger_support)_0[1-4]', skill) else 0
