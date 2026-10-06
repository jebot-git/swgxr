"""Select original crafting profession recipe previews; native CraftingSession grants recipes."""
import hashlib
import re
from .profession_scope import CRAFTING_PROFESSIONS


def recipe_previews(core3, professions):
    modifiers = {
        p['id']: {key for node in p['nodes'] for key in node['modifiers']}
        for p in professions['professions'] if p['id'] in CRAFTING_PROFESSIONS
    }
    result = {'professions': {key: [] for key in CRAFTING_PROFESSIONS},
              'templates': [], 'sources_sha256': {}}
    templates = set()
    for source in sorted((core3/'MMOCoreORB/bin/scripts/object/draft_schematic').rglob('*.lua')):
        raw = source.read_bytes()
        text = raw.decode()
        assembly = re.search(r'assemblySkill\s*=\s*"([^"]+)"', text)
        target = re.search(r'targetTemplate\s*=\s*"([^"]+)"', text)
        if not assembly or not target:
            continue
        owners = [key for key, mods in modifiers.items() if assembly[1] in mods]
        if not owners:
            continue
        relative = str(source.relative_to(core3))
        result['sources_sha256'][relative] = hashlib.sha256(raw).hexdigest()
        templates.add(target[1])
        for owner in owners:
            result['professions'][owner].append({'source': relative, 'template': target[1],
                                                  'assembly_skill': assembly[1]})
    result['templates'] = sorted(templates)
    result['policy'] = 'Preview coverage only. Core3 learned schematic grants and tool/station checks remain authoritative.'
    return result
