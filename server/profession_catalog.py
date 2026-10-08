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
            if row['NAME'] in ('science_medic','science_doctor','science_combatmedic'):
                description=all_labels[skill['NAME']]+': CoreCU medical progression. Health is the damage and wound pool; Action and Mind are ability resources.'
                if row['NAME']=='science_combatmedic':
                    description+=' Poison treats Health as its damage pool; disease temporarily drains Action. Heal Mind restores a bounded amount of another patient’s Mind with resource cost and recovery, without self wounds.'
                if row['NAME']=='science_doctor':
                    description+=' Wound Medpacks treat Health wounds. Apply crafted enhancement, cure, state and resuscitation packs directly to patients. Enhancements are capped at 15% of base attributes.'
                if skill['NAME']=='science_medic_novice':
                    description='Medic training enables held stim treatment and medical crafting. Apply stims to injured patients and Health Wound Medpacks to wounds; Diagnose and separate Heal/Tend Wound abilities are retired.'
                if any(mods.get(key,0) for key in ('healing_injury_speed','healing_wound_speed','healing_range_speed')):
                    description+='\nCoreCU medical recovery: relevant speed rating reduces recovery by up to 25% at 100 rating. Injury/ranged speed uses the stronger rating for Heal Damage; wound speed improves Wound Medpack and enhancement recovery.'
                if mods.get('healing_wound_treatment',0):
                    description+='\nCoreCU Wound Medpacks: treatment proficiency increases base wound repair from 3% to 8%, modified by pack quality and capped at 10% per use before spice effects and battle fatigue.'
            if row['NAME'] in ('social_entertainer','social_dancer','social_musician'):
                description=description.replace('mind wounds','Health wounds').replace('Mind wounds','Health wounds').replace('mental wounds','Health wounds')
                description+='\nCoreCU performance treats Health wounds and battle fatigue; original mental-healing ratings continue to determine proficiency and inspiration.'
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
