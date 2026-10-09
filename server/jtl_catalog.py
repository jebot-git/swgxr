"""Original small craft with converted tester cockpit and exterior assets."""
SMALL_SHIPS = ('z95', 'basic_z95', 'prototype_z95', 'tiefighter', 'basic_tiefighter',
               'prototype_tiefighter', 'tie_light_duty', 'hutt_light_s01',
               'basic_hutt_light', 'prototype_hutt_light', 'ywing')
SHIP_TEMPLATES = tuple('object/ship/player/player_'+name+'.iff' for name in SMALL_SHIPS)
