#!/usr/bin/env python3
"""Export original language alphabets and safe NPC greetings from supplied media."""
import hashlib
import json
import re
from pathlib import Path

from character_formats import datatable
from stf import string_table
from swg_formats import TreSet

ROOT = Path(__file__).resolve().parents[2]
def build(root=ROOT):
    sources = TreSet(root / 'runtime/assets/active_tre')
    provenance = {}

    def read(path):
        raw = sources.read(path)
        provenance[path] = {'sha256': hashlib.sha256(raw).hexdigest(),
                            'bytes': len(raw), 'archive': sources.entries[path][0].name}
        return raw

    def source(path):
        raw = (root / path).read_bytes()
        provenance[path] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}
        return raw.decode()

    labels = string_table(read('string/en/game_language.stf'))
    rows = datatable(read('datatables/game_language/game_language.iff'))
    if len(rows) != 11:
        raise ValueError('Core3 supports the original eleven language IDs; audit this media revision.')
    languages = []
    for ident, row in enumerate(rows, 1):
        entry = {'id': ident, 'key': row['stringId'], 'name': labels[row['stringId']],
                 'audible': bool(row['audible']),
                 'syllables': {letter: row[letter] for letter in 'abcdefghijklmnopqrstuvwxyz'}}
        for kind in ('speak', 'comprehend'):
            mod = row[kind + 'SkillModName']
            skill = 'social_' + mod
            script = source('vendor/Core3/MMOCoreORB/bin/scripts/skills/language/' + skill + '.lua')
            if not re.search(r'skillName\s*=\s*"' + re.escape(skill) + r'"', script):
                raise ValueError('Native language skill mismatch: ' + skill)
            if not re.search(r'\{\s*"' + re.escape(mod) + r'"\s*,\s*100\s*\}', script):
                raise ValueError('Native language modifier mismatch: ' + mod)
            entry[kind + '_mod'] = mod
            entry[kind + '_skill'] = skill
            restrictions = re.search(r'speciesRequired\s*=\s*\{([^}]*)\}', script)
            entry[kind + '_species'] = re.findall(r'"([^"]+)"', restrictions[1]) if restrictions else []
        languages.append(entry)

    races = source('vendor/Core3/MMOCoreORB/src/server/zone/objects/player/Races.h')
    names = re.findall(r'"([^"]+)"', re.search(r'\bSpecies\[\]\s*=\s*\{([^}]+)\}', races)[1])
    integers = re.sub(r'//[^\n]*', '', re.search(r'\bTemplateSpecies\[\]\s*=\s*\{([^}]+)\}', races)[1])
    species_ids = [int(value.strip(), 0) for value in integers.split(',') if value.strip()]
    if len(names) != len(species_ids):
        raise ValueError('Native species arrays do not match.')
    mapping = {}
    for name, ident in dict(zip(names, species_ids)).items():
        template = source('vendor/Core3/MMOCoreORB/bin/scripts/object/creature/player/' + name + '_male.lua')
        starting = re.search(r'startingSkills\s*=\s*\{([^}]+)\}', template)
        skills = set(re.findall(r'"([^"]+)"', starting[1]))
        spoken = [language for language in languages if language['audible'] and language['speak_skill'] in skills]
        native = [language for language in spoken if language['key'] != 'basic'] or spoken
        if len(native) != 1:
            raise ValueError('Ambiguous original spoken species language: ' + name)
        mapping[str(ident)] = native[0]['id']

    greetings = {}
    for path in sorted(sources.entries):
        if path.startswith('string/en/npc_reaction/') and path.endswith('.stf'):
            table = string_table(read(path))
            keys = sorted(key for key, text in table.items() if re.fullmatch(r'hi_mid_\d+', key) and text.strip())
            if keys:
                greetings[path.removeprefix('string/en/').removesuffix('.stf')] = keys
    return {'schema': 1, 'languages': languages, 'species_languages': mapping,
            'ambient_reactions': greetings, 'strings': labels,
            'source_hashes': provenance, 'failures': [],
            'conversion': 'Original case-preserving letter-to-syllable substitution; use actual i column, correcting the NGE loader duplicate-h typo.'}


def main():
    catalog = build()
    target = ROOT / 'runtime/assets/chatter/catalog.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(catalog, indent=2) + '\n')
    temporary.replace(target)
    print(json.dumps({'languages': len(catalog['languages']),
                      'species': len(catalog['species_languages']),
                      'ambient_tables': len(catalog['ambient_reactions']), 'failures': catalog['failures']}))


if __name__ == '__main__':
    main()
