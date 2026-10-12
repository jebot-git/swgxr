"""Original player hulls with native crafting or pilot certification paths.

Audited against Core3 player objects.lua and crafted chassis deeds. The uncertified
NPC/test corvette is excluded; the existing account Luxury Yacht is separate.
"""
SMALL_SHIPS = ('awing', 'basic_hutt_light', 'basic_tiefighter', 'basic_z95', 'blacksun_heavy_s01', 'blacksun_heavy_s02', 'blacksun_heavy_s03', 'blacksun_heavy_s04', 'blacksun_light_s01', 'blacksun_light_s02', 'blacksun_light_s03', 'blacksun_light_s04', 'blacksun_medium_s01', 'blacksun_medium_s02', 'blacksun_medium_s03', 'blacksun_medium_s04', 'bwing', 'firespray', 'hutt_heavy_s01', 'hutt_heavy_s02', 'hutt_light_s01', 'hutt_light_s02', 'hutt_medium_s01', 'hutt_medium_s02', 'hutt_turret_ship', 'prototype_hutt_light', 'prototype_tiefighter', 'prototype_z95', 'tie_in', 'tie_light_duty', 'tieadvanced', 'tieaggressor', 'tiebomber', 'tiefighter', 'tieinterceptor', 'tieoppressor', 'xwing', 'ywing', 'ywing_longprobe', 'z95')
POB_SHIPS = ('decimator', 'ykl37r', 'yt1300', 'yt1300_decorated_01')
SHIP_TEMPLATES = tuple("object/ship/player/player_"+name+".iff" for name in SMALL_SHIPS+POB_SHIPS)
