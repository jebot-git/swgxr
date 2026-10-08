"""Professions exposed through the existing trainer and artisan interfaces."""
BASIC_TRAINERS = ('artisan', 'brawler', 'entertainer', 'marksman', 'medic', 'scout')
ARTISAN_TRAINERS = ('armorsmith', 'weaponsmith', 'chef', 'tailor', 'architect',
                    'droidengineer', 'merchant', 'shipwright')
ENTERTAINER_TRAINERS = ('dancer', 'musician', 'imagedesigner')
CREATURE_HANDLER_TRAINERS = ('creaturehandler',)
BIOENGINEER_TRAINERS = ('bioengineer',)
RANGER_TRAINERS = ('ranger',)
SMUGGLER_TRAINERS = ('smuggler',)
TRAINERS = BASIC_TRAINERS + ARTISAN_TRAINERS + ENTERTAINER_TRAINERS + CREATURE_HANDLER_TRAINERS + BIOENGINEER_TRAINERS + RANGER_TRAINERS + SMUGGLER_TRAINERS
ARTISAN_PROFESSIONS = tuple('crafting_' + name for name in ('artisan',) + ARTISAN_TRAINERS)

CRAFTING_PROFESSIONS = ARTISAN_PROFESSIONS + ('outdoors_bio_engineer', 'combat_smuggler')
