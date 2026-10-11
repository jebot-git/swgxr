#!/usr/bin/env python3
"""Compare a pinned, locally inspected SWG pilot source corpus with Core3/media.

Read-only; does not download source, grant skills, or claim playable progression.
Reference files and original dialogue remain in ignored runtime directories.
"""
import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from stf import string_table
from swg_formats import TreSet

COMMIT = 'e3aac29b55b46fec2ce2b1518db80a8f70d798a5'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=ROOT / 'runtime/reference/pilot-progression')
    parser.add_argument('--tre-dir', type=Path, default=ROOT / 'runtime/asset_sources/active_tre')
    parser.add_argument('--core3', type=Path, default=ROOT / 'vendor/Core3')
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/evidence/pilot-progression-audit.json')
    args = parser.parse_args()
    tre = TreSet(args.tre_dir)
    sources = json.loads((args.reference / 'sources.json').read_text())
    errors, conversations, tables = [], {}, {}
    for source in sources:
        path = source['path']
        if '/spacequest/' in path:
            local = args.reference / 'quest_tables' / path.split('/spacequest/')[1]
        else:
            local = args.reference / Path(path).name
        data = local.read_bytes()
        if hashlib.sha256(data).hexdigest() != source['sha256'] or COMMIT not in source['url']:
            errors.append('Source provenance mismatch: ' + path)
        if '/conversation/' in path:
            name = local.stem
            text = data.decode()
            resource = 'string/en/conversation/' + name + '.stf'
            raw = tre.read(resource)
            strings = string_table(raw)
            keys = set(re.findall(r'"(s_[0-9a-f]+)"', text))
            quests = sorted(set(re.findall(r'space_quest\.grantQuest\(player, "([^"]+)", "([^"]+)"\)', text)))
            conversations[name] = {
                'source': source, 'media_resource': resource,
                'media_sha256': hashlib.sha256(raw).hexdigest(),
                'media_archive': tre.entries[resource][0].name,
                'source_keys': len(keys), 'media_keys': len(strings),
                'missing_media_keys': sorted(keys - strings.keys()),
                'quest_grants': [kind + ':' + name for kind, name in quests],
                'uses_native_face_to_after_interaction': 'faceTo(npc, player)' in text,
            }
        elif '/spacequest/' in path:
            rows = list(csv.reader(data.decode().splitlines(), delimiter='\t'))
            tables[path.split('/spacequest/')[1]] = {
                'source': source, 'rows': [dict(zip(rows[0], row)) for row in rows[2:] if any(row)]
            }
    scripts = args.core3 / 'MMOCoreORB/bin/scripts'
    trainers = []
    for path in sorted((scripts / 'mobile/space').glob('*.lua')):
        text = path.read_text()
        if not re.search(r'planetMapSubCategory\s*=\s*"trainer_pilot_', text):
            continue
        match = re.search(r'conversationTemplate\s*=\s*"([^"]*)"', text)
        trainers.append({'mobile': path.stem, 'path': str(path.relative_to(ROOT)),
                         'conversation_template': match[1] if match else None})
    storm = scripts / 'screenplays/space/squadrons/StormSquadronScreenplay.lua'
    storm_text = storm.read_text()
    report = {
        'source_audit_passed': not errors, 'errors': errors, 'source_commit': COMMIT,
        'scope': 'Storm Squadron source conversations, Akal mission tables, Core3 map-marked pilot trainers',
        'conversations': conversations, 'mission_tables': tables,
        'native_trainers': trainers,
        'trainers_without_conversation': [row['mobile'] for row in trainers if not row['conversation_template']],
        'storm_screenplay_start_empty': bool(re.search(r'function StormSquadronScreenplay:start\(\)\s*end', storm_text)),
        'storm_screenplay_sha256': hashlib.sha256(storm.read_bytes()).hexdigest(),
        'playable_progression_validated': False,
        'compatibility_note': 'Later original source and supplied Total Experience dialogue differ; reconcile missing keys and later branches before porting. Server quest tables are not required client media.',
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'source_audit_passed': not errors, 'conversation_count': len(conversations),
                      'mission_tables': len(tables), 'trainers_without_conversation': report['trainers_without_conversation'],
                      'missing_dialogue_keys': {key: len(row['missing_media_keys']) for key, row in conversations.items()},
                      'errors': errors}))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
