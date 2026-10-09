"""Source history must retain overridden records without guessing replacements."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/assets'))
from trace_bounty_sources import SOURCES, archive_index, read_entry, trace


def archive(path, files, compressed=False):
    payload = bytearray(); names = bytearray(); toc = bytearray()
    for name, raw in files.items():
        stored = zlib.compress(raw) if compressed else raw
        toc.extend(struct.pack('<6I', 0, len(raw), 36+len(payload), int(compressed), len(stored), len(names)))
        payload.extend(stored); names.extend(name.encode()+b'\0')
    toc_bytes = zlib.compress(toc) if compressed else bytes(toc)
    name_bytes = zlib.compress(names) if compressed else bytes(names)
    header = b'EERT5000'+struct.pack('<7I', len(files), 36+len(payload), int(compressed), len(toc_bytes), int(compressed), len(name_bytes), len(names))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header+payload+toc_bytes+name_bytes)


def inventory(root, release, filename, files, compressed=False):
    directory = root/'extracted'/release
    path = directory/filename
    archive(path, files, compressed)
    row = {'filename': filename, 'path': str(path.relative_to(root)), 'bytes': path.stat().st_size,
           'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (directory/'media_inventory.json').write_text(json.dumps({'media': [], 'archives': [row]}))


class BountySourceHistory(unittest.TestCase):
    def test_individual_index_preserves_authored_name_and_compressed_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'fixture.tre'
            archive(path, {'Appearance\\Mesh\\Example.lmg': b'original compressed bytes'}, True)
            row = archive_index(path)[0]
            self.assertEqual(row['name'], 'appearance/mesh/example.lmg')
            self.assertEqual(row['source_name'], 'Appearance\\Mesh\\Example.lmg')
            self.assertEqual(read_entry(path, row), b'original compressed bytes')

    def test_overridden_referrers_and_inactive_archives_are_retained_without_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); spec = SOURCES['rebel_21b_client_data']
            alternative = spec['missing'].replace('client_shared_dro_', 'client_shared_npc_')
            inventory(root, 'base', 'patch_00.tre', {spec['referrer']: b'first\0'+spec['missing'].encode()+b'\0'})
            inventory(root, 'later', 'patch_15_00.tre', {spec['referrer']: b'second\0'+spec['missing'].encode()+b'\0', alternative: b'alternative'}, True)
            report = trace(root/'extracted', root)
            self.assertTrue(report['audit_passed'])
            finding = report['findings']['rebel_21b_client_data']
            self.assertEqual(len(finding['referrer_versions']), 2)
            self.assertEqual(finding['referrer_versions_containing_missing_path'], 2)
            self.assertEqual(finding['status'], 'absent_from_supplied_archive_indexes')
            self.assertIn(alternative, finding['related_original_paths'])
            self.assertFalse(report['releases']['later']['archives'][0]['allowed_for_active_core3'])

    def test_exact_inactive_original_is_reported_without_being_activated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); spec = SOURCES['female_tusken_glove']
            inventory(root, 'later', 'patch_15_00.tre', {spec['missing']: b'exact original fixture'})
            report = trace(root/'extracted', root)
            finding = report['findings']['female_tusken_glove']
            self.assertEqual(finding['status'], 'exact_original_present')
            self.assertEqual(finding['release_containing_exact_source'], ['later'])
            self.assertFalse(finding['repair_applied'])

    def test_changed_archive_cannot_receive_clean_source_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inventory(root, 'base', 'patch_00.tre', {'appearance/example.apt': b'original'})
            path = root/'extracted/base/patch_00.tre'
            path.write_bytes(path.read_bytes()+b'unexpected change')
            report = trace(root/'extracted', root)
            self.assertFalse(report['audit_passed'])
            self.assertEqual(report['failures'][0]['phase'], 'archive_hash')


if __name__ == '__main__':
    unittest.main()
