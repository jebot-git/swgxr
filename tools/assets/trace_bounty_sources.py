#!/usr/bin/env python3
"""Trace three dangling original NPC references through every supplied release.

This audits individual TRE indexes, including inactive archives and overridden
versions. It never activates archives, extracts replacements, or downloads media.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

from archive_policy import CORE3_TRE_PRIORITY
from character_formats import datatable
from swg_formats import cstring, parse_iff

ROOT = Path(__file__).resolve().parents[2]
TABLE = 'datatables/appearance/appearance_table.iff'
SOURCES = {
    'female_tusken_glove': {
        'missing': 'appearance/mesh/gloves_tusken_raider_f.lmg',
        'referrer': 'clientdata/npc/client_shared_npc_dressed_corsair_cutthroat_hum_f.cdf',
        'family_tokens': ['gloves_tusken_raider'],
    },
    'twilek_female_hair_10': {
        'missing': 'appearance/mesh/twk_f_hair_s10.lmg',
        'referrer': 'clientdata/npc/client_shared_npc_dressed_rebel_recruiter_twilek_female_01.cdf',
        'family_tokens': ['twk_f_hair_', 'hair_twilek_female_'],
    },
    'rebel_21b_client_data': {
        'missing': 'clientdata/npc/client_shared_dro_dressed_rebel_medic2_21b_01.cdf',
        'referrer': 'object/mobile/shared_dressed_rebel_medic2_21b_01.iff',
        'family_tokens': ['rebel_medic2', 'droid_21b', 'dro_21b'],
    },
}


def normalized(path):
    return path.lower().replace('\\', '/')


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def archive_index(path):
    """Return each authored entry, without cross-archive precedence or aliases."""
    with path.open('rb') as stream:
        if stream.read(8) != b'EERT5000':
            raise ValueError(f'Unsupported TRE header: {path}')
        count, offset, tc, ts, nc, ns, nlen = struct.unpack('<7I', stream.read(28))
        stream.seek(offset)
        toc = stream.read(ts if tc else count * 24)
        names = stream.read(ns if nc else nlen)
    if tc:
        toc = zlib.decompress(toc)
    if nc:
        names = zlib.decompress(names)
    if len(toc) != count * 24 or len(names) != nlen:
        raise ValueError(f'Invalid TRE index length: {path}')
    entries = []
    for index in range(count):
        _, size, offset, compression, compressed_size, name_offset = struct.unpack_from('<6I', toc, index * 24)
        source_name = names[name_offset:names.index(0, name_offset)].decode('ascii')
        entries.append({'name': normalized(source_name), 'source_name': source_name, 'bytes': size,
                        'offset': offset, 'compression': compression, 'compressed_bytes': compressed_size})
    return entries


def read_entry(path, entry):
    with path.open('rb') as stream:
        stream.seek(entry['offset'])
        raw = stream.read(entry['compressed_bytes'] if entry['compression'] else entry['bytes'])
    if entry['compression']:
        raw = zlib.decompress(raw)
    if len(raw) != entry['bytes']:
        raise ValueError(f'TRE entry length mismatch: {path}: {entry["name"]}')
    return raw


def reference_details(name, raw):
    if name == TABLE:
        rows = datatable(raw)
        row = next(row for row in rows if row['Object Template Name'] == 'shared_gloves_tusken_raider')
        return {'glove_appearance_row': {key: row[key] for key in ('Object Template Name', 'Female Human', 'Male Human')}}
    refs = sorted({normalized(value.decode('ascii')) for value in
                   re.findall(rb'[a-zA-Z0-9_./\\-]+\.(?:cdf|sat|lmg|mgn|iff)', raw)})
    result = {'resource_references': refs}
    if name.endswith('.cdf'):
        result['wearable_references'] = [normalized(cstring(node.data)[0]) for node in parse_iff(raw).walk('MESH')]
    return result


def trace(extracted, root=ROOT):
    referrers = {row['referrer'] for row in SOURCES.values()} | {TABLE}
    requested = {row['missing'] for row in SOURCES.values()}
    families = [token for row in SOURCES.values() for token in row['family_tokens']]
    versions = {}; releases = {}; failures = []
    for inventory_path in sorted(extracted.glob('*/media_inventory.json')):
        inventory = json.loads(inventory_path.read_text())
        release = inventory_path.parent.name
        release_row = {'inventory': str(inventory_path), 'inventory_sha256': sha256(inventory_path),
                       'media': inventory['media'], 'media_hash_status': 'Recorded extraction provenance; ISO images not rehashed by this trace.',
                       'archives': [], 'exact_sources_present': []}
        releases[release] = release_row
        for item in inventory['archives']:
            path = root / item['path']
            record = {'filename': item['filename'], 'path': item['path'], 'bytes': path.stat().st_size,
                      'sha256': sha256(path), 'inventory_sha256': item['sha256'],
                      'allowed_for_active_core3': item['filename'] in CORE3_TRE_PRIORITY}
            release_row['archives'].append(record)
            if record['sha256'] != item['sha256'] or record['bytes'] != item['bytes']:
                failures.append({'phase': 'archive_hash', 'path': str(path), 'error': 'Does not match extraction inventory'})
            try:
                index = archive_index(path)
                record['entries'] = len(index)
                record['normalized_index_sha256'] = hashlib.sha256('\n'.join(sorted(row['name'] for row in index)).encode()).hexdigest()
                for entry in index:
                    name = entry['name']
                    if name in requested:
                        release_row['exact_sources_present'].append(name)
                    if name not in referrers | requested and not any(token in name for token in families):
                        continue
                    raw = read_entry(path, entry)
                    digest = hashlib.sha256(raw).hexdigest()
                    version = versions.setdefault(name, {}).setdefault(digest, {'sha256': digest, 'bytes': len(raw), 'locations': []})
                    version['locations'].append({'release': release, 'archive': item['filename'],
                                                 'archive_sha256': record['sha256'], 'source_name': entry['source_name']})
                    if name in referrers and 'details' not in version:
                        version['details'] = reference_details(name, raw)
            except (OSError, ValueError, struct.error, zlib.error) as exc:
                failures.append({'phase': 'archive_index', 'path': str(path), 'error': str(exc)})
        release_row['exact_sources_present'] = sorted(set(release_row['exact_sources_present']))
    if not releases:
        failures.append({'phase': 'inventory', 'error': 'No supplied media inventories found'})
    findings = {}
    for key, spec in SOURCES.items():
        found = list(versions.get(spec['missing'], {}).values())
        ref_versions = list(versions.get(spec['referrer'], {}).values())
        findings[key] = {**spec, 'status': 'exact_original_present' if found else 'absent_from_supplied_archive_indexes',
                         'exact_source_versions': found, 'referrer_versions': ref_versions,
                         'referrer_versions_containing_missing_path': sum(spec['missing'] in row.get('details', {}).get('resource_references', []) for row in ref_versions),
                         'related_original_paths': sorted(name for name in versions if any(token in name for token in spec['family_tokens'])),
                         'repair_applied': False,
                         'release_containing_exact_source': None if not found else sorted({location['release'] for row in found for location in row['locations']})}
    return {'schema': 1, 'audit_passed': not failures, 'failures': failures,
            'archive_instances_scanned': sum(len(row['archives']) for row in releases.values()),
            'unique_archive_hashes': len({a['sha256'] for row in releases.values() for a in row['archives']}),
            'all_three_exact_sources_found': all(row['exact_source_versions'] for row in findings.values()),
            'releases': releases, 'findings': findings,
            'appearance_table_versions': list(versions.get(TABLE, {}).values()),
            'related_resource_versions': {name: list(rows.values()) for name, rows in sorted(versions.items()) if name not in referrers | requested},
            'scope': 'Every TRE listed in the supplied extraction inventories, including inactive post-cutoff archives and superseded versions. No archive activation or media replacement.',
            'interpretation': 'Absence is proven only for these supplied archives. Broken referrers do not establish that the missing files existed in another client release. Similar names are not replacements.',
            'next_source_check': 'If an independently owned later or fully patched original client is supplied, inspect its exact TRE/TRE index paths first. A release label alone does not prove that it contains any missing file.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extracted', type=Path, default=ROOT/'runtime/asset_sources/extracted')
    parser.add_argument('--output', type=Path, default=ROOT/'runtime/evidence/bounty-source-history.json')
    parser.add_argument('--web-evidence', type=Path, help='Optional reviewed public metadata JSON; no network access is performed')
    args = parser.parse_args()
    report = trace(args.extracted)
    if args.web_evidence:
        report['public_metadata'] = json.loads(args.web_evidence.read_text())
        report['public_metadata_sha256'] = sha256(args.web_evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'audit_passed': report['audit_passed'], 'archives': report['archive_instances_scanned'],
                      'unique_archive_hashes': report['unique_archive_hashes'],
                      'sources': {key: row['status'] for key, row in report['findings'].items()},
                      'output': str(args.output), 'failures': report['failures']}, indent=2))
    if not report['audit_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
