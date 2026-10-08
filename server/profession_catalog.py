"""Read-only original profession graphs. Learned state comes from owner CREO1."""
from functools import lru_cache
import hashlib
from .character_protocol import assets
from character_formats import datatable
from stf import string_table
from .corecu_professions import contribution, trap_bonus_contribution


@lru_cache(maxsize=1)
def catalog():
    sources = {}
    def read(path):
        raw = assets().read(path)
        sources[path] = hashlib.sha256(raw).hexdigest()
        return raw
    rows = datatable(read('datatables/skill/skills.iff'))
    names = string_table(read('string/en/skl_n.stf'))
    descriptions = string_table(read('string/en/skl_d.stf'))
    professions = []
    warnings = []
    by_id = {row['NAME']:row for row in rows}
    def profession_parent(skill):
        parent = skill['PARENT']
        seen = set()
        while parent in by_id and parent not in seen:
            seen.add(parent)
            if by_id[parent]['IS_PROFESSION']: return parent
            parent = by_id[parent]['PARENT']
        return ''
    all_labels = {row['NAME']:names.get(row['NAME'], row['NAME']) for row in rows}
    for row in rows:
        if not row['IS_PROFESSION'] or row['IS_HIDDEN'] or row['GOD_ONLY']: continue
        nodes = []
        for skill in rows:
            if profession_parent(skill) != row['NAME'] or skill['IS_HIDDEN'] or skill['GOD_ONLY']: continue
            mods = {}
            for mod in filter(None, skill['SKILL_MODS'].split(',')):
                if mod.count('=') != 1:
                    warnings.append({'skill':skill['NAME'], 'field':'SKILL_MODS', 'raw':mod,
                                     'reason':'Malformed source modifier; not guessed'})
                    continue
                key, value = mod.split('=')
                mods[key] = int(value)
            resistance = contribution(row['NAME'], skill['NAME'])
            description = descriptions.get(skill['NAME'], '')
            if resistance:
                description += '\nCoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Strongest profession plus 25% of other contributions; existing resistance is retained when stronger.'
            trap_bonus = trap_bonus_contribution(skill['NAME'])
            if trap_bonus:
                description += f'\nCoreCU traps: +{trap_bonus} percentage point status application chance, capped at 95%; enemy duration resistance remains.'
            if skill['NAME'] == 'combat_brawler_novice':
                description += '\nTaunt: clench a free hand with grip and beat your chest twice while aiming the head reticle at an enemy. Keep trigger released; the first eligible enemy in the reticle is challenged.'
            nodes.append({'corecu_trap_success_bonus':trap_bonus, 'id':skill['NAME'], 'label':all_labels[skill['NAME']],
                          'description':description, 'corecu_resistance_contribution':resistance,
                          'requires':list(filter(None, skill['SKILLS_REQUIRED'].split(','))),
                          'requires_count':skill['SKILLS_REQUIRED_COUNT'],
                          'excludes':list(filter(None, skill['PRECLUSION_SKILLS'].split(','))),
                          'xp_type':skill['XP_TYPE'], 'xp_cost':skill['XP_COST'],
                          'credits':skill['MONEY_REQUIRED'], 'points':skill['POINTS_REQUIRED'],
                          'modifiers':mods,
                          'schematic_groups':list(filter(None,skill['SCHEMATICS_GRANTED'].split(','))),
                          'certificates':[c for c in skill['COMMANDS'].split(',') if c.startswith('cert_')]})
        professions.append({'id':row['NAME'], 'label':all_labels[row['NAME']],
                            'graph_type':row['GRAPH_TYPE'], 'nodes':nodes})
    return {'schema':1, 'backend_name':'CoreCU', 'advanced_professions':'provisional_core3_skeleton', 'professions':professions, 'labels':all_labels,
            'provenance':sources, 'warnings':warnings, 'read_only':True}
