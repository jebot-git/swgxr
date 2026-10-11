"""Prepared ground entity catalogs shared by conversion and private packaging."""
from pathlib import Path
GROUND_PLANETS=('tatooine','corellia','naboo','rori','talus','dantooine','dathomir','endor','lok','yavin4')
def ground_catalogs(root):
 base=Path(root)/'runtime/assets'
 paths=[base/p/'catalog.json' for p in ('combat_population/native_current','combat_population/mos_eisley_easy','combat_population/tatooine','combat_population/tatooine_entities','ambient_npcs')]
 paths += [base/'planets'/planet/component/'catalog.json' for planet in GROUND_PLANETS if planet!='tatooine' for component in ('entities','ambient')]
 return [p for p in paths if p.exists()]
