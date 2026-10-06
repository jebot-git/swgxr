"""Ground planets available to the pre-CU runtime; no expansion placeholders."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
PLANETS = ('corellia','dantooine','dathomir','endor','lok','naboo','rori','talus','tatooine','yavin4')

def origin_for(planet):
    return [3618.98388671875, 5, -4801.0859375] if planet == 'tatooine' else [0,0,0]

def path_for(planet, component):
    if planet == 'tatooine':
        return ROOT/'runtime/assets'/dict(terrain='terrain',world='tatooine_world',environment='tatooine_environment',services='services',ambient='ambient_npcs')[component]
    return ROOT/'runtime/assets/planets'/planet/component
