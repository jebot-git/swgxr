"""Bounded loadout proposals; Core3 owns grants, weapon family and persistence."""
import re
FAMILIES={'unarmed','pistols','carbines','rifles','heavy','1h_melee','2h_melee','polearms','1h_lightsaber','2h_lightsaber','polearm_lightsaber','other'}
def validate(value):
    if not isinstance(value,dict) or set(value)!={'family','slots','ultimate','revision'}:raise ValueError('Invalid combat loadout fields')
    if not isinstance(value['family'],str) or value['family'] not in FAMILIES:raise ValueError('Invalid weapon family')
    slots=value['slots']
    if not isinstance(slots,list) or len(slots)!=4:raise ValueError('Exactly four combat slots required')
    for key in slots+[value['ultimate']]:
        if not isinstance(key,str) or (key and not re.fullmatch('[a-z][a-z0-9_]{0,63}',key)):raise ValueError('Invalid ability ID')
    equipped=[key for key in slots+[value['ultimate']] if key]
    if len(set(equipped))!=len(equipped):raise ValueError('Duplicate equipped ability')
    if type(value['revision']) is not int or not 0<=value['revision']<2**53-1:raise ValueError('Invalid loadout revision')
    return dict(value,slots=list(slots))
