#!/usr/bin/env python3
"""Audit original basic trainers; placement metadata never grants native services."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from prepare_datapad import string_table
from swg_formats import TreSet

ROOT = Path(__file__).resolve().parents[2]
BASIC = ('artisan', 'brawler', 'entertainer', 'marksman', 'medic', 'scout')


def audit(tre_dir, core3, ambient):
    files, dependencies = {}, {}
    def read(path):
        raw = path.read_bytes()
        files[str(path.resolve())] = hashlib.sha256(raw).hexdigest()
        return raw
    tre = TreSet(tre_dir)
    def table(name):
        path = 'string/en/' + name + '.stf'
        raw = tre.read(path)
        dependencies[path] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'archive': tre.entries[path][0].name}
        return string_table(raw)
    teacher, names = table('skill_teacher'), table('mob/creature_names')
    scripts = core3 / 'MMOCoreORB/bin/scripts'
    skills_text = read(scripts / 'screenplays/trainers/trainerData.lua').decode()
    manifest = json.loads(read(ambient / 'placements.json'))
    catalog = json.loads(read(ambient / 'catalog.json'))
    trainers, failures, placements = {}, [], []
    for name in BASIC:
        mobile = 'trainer_' + name
        source = scripts / 'mobile/trainer' / (mobile + '.lua')
        definition = read(source).decode()
        templates = re.findall(r'"(object/mobile/[^"]+)"', re.search(r'templates\s*=\s*\{([^}]+)\}', definition).group(1))
        skills = re.findall(r'"([^"]+)"', re.search(r'\b' + mobile + r'\s*=\s*\{([^}]+)\}', skills_text).group(1))
        if len(templates) != 3 or len(skills) != 18:
            raise ValueError('Unexpected original basic trainer structure: ' + mobile)
        trainers[mobile] = {'profession': skills[0].removesuffix('_novice'), 'templates': templates,
                            'skill_ids': skills, 'name': names[mobile], 'greeting': teacher[mobile],
                            'source_file': str(source.relative_to(core3)), 'placement_ids': []}
    for original in manifest['instances']:
        mobile = original.get('mobile', '')
        if mobile not in trainers:
            continue
        row = {key: original[key] for key in ('id', 'mobile', 'template', 'appearance_id', 'source_world_xyz', 'source_xyz',
               'source_heading_degrees', 'source_cell_id', 'cell_id', 'building_object_id', 'source_file', 'source_line')}
        row['appearance_available'] = row['appearance_id'] in catalog['races']
        if not row['appearance_available']:
            failures.append({'placement': row['id'], 'error': 'Prepared original appearance missing'})
        if row['template'] not in trainers[mobile]['templates']:
            failures.append({'placement': row['id'], 'error': 'Appearance is outside source trainer variant set'})
        source = ROOT / row['source_file']
        if source.exists() and str(source.resolve()) not in files:
            read(source)
        placements.append(row)
        trainers[mobile]['placement_ids'].append(row['id'])
    return {'schema_version': 1, 'zone': 'tatooine', 'trainers': trainers, 'placements': placements,
            'provenance': {'files_sha256': files, 'dependencies': dependencies}, 'failures': failures,
            'policy': 'Original placement/variant audit only. Reuse authored ambient NPCs. Native Core3 trainer IDs, proximity, eligibility, costs and skill awards remain authoritative.'}


def export(tre_dir, core3, ambient, out):
    data = audit(tre_dir, core3, ambient)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, separators=(',', ':')))
    tmp.replace(out)
    if data['failures']:
        raise ValueError(data['failures'])
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/assets/active_tre')
    parser.add_argument('--core3', type=Path, default=ROOT/'vendor/Core3')
    parser.add_argument('--ambient', type=Path, default=ROOT/'runtime/assets/ambient_npcs')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/services/trainers.json')
    args = parser.parse_args()
    data = export(args.tre_dir, args.core3, args.ambient, args.out)
    print(json.dumps({'trainers': len(data['trainers']), 'placements': len(data['placements']), 'failures': data['failures']}))

if __name__ == '__main__':
    main()
