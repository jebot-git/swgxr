"""Compare the prepared language catalogue with the user's actual original media."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from character_formats import datatable
from stf import string_table
from swg_formats import TreSet


class ChatterAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'runtime/assets/chatter/catalog.json').read_text())
        cls.media = TreSet(ROOT / 'runtime/asset_sources/active_tre')

    def test_original_ids_alphabets_and_display_names(self):
        original = datatable(self.media.read('datatables/game_language/game_language.iff'))
        labels = string_table(self.media.read('string/en/game_language.stf'))
        self.assertEqual(len(self.catalog['languages']), 11)
        for index, (actual, source) in enumerate(zip(self.catalog['languages'], original), 1):
            self.assertEqual(actual['id'], index)
            self.assertEqual(actual['name'], labels[source['stringId']])
            self.assertEqual(actual['syllables'], {letter: source[letter] for letter in 'abcdefghijklmnopqrstuvwxyz'})
            self.assertEqual(actual['comprehend_mod'], source['comprehendSkillModName'])
            self.assertEqual(actual['speak_mod'], source['speakSkillModName'])

    def test_body_language_cannot_be_learned_by_hearing_and_species_rules_remain(self):
        lekku = next(row for row in self.catalog['languages'] if row['key'] == 'lekku')
        self.assertFalse(lekku['audible'])
        self.assertEqual(lekku['comprehend_species'], ['twilek'])
        self.assertNotIn(lekku['id'], self.catalog['species_languages'].values())
        by_id = {row['id']: row for row in self.catalog['languages']}
        self.assertEqual(by_id[self.catalog['species_languages']['4']]['key'], 'shyriiwook')
        self.assertEqual(by_id[self.catalog['species_languages']['33']]['name'], 'Ithorese')

    def test_ambient_greetings_are_nonempty_original_neutral_reactions(self):
        self.assertGreater(len(self.catalog['ambient_reactions']), 0)
        for table, keys in self.catalog['ambient_reactions'].items():
            original = string_table(self.media.read('string/en/' + table + '.stf'))
            for key in keys:
                self.assertRegex(key, r'^hi_mid_\d+$')
                self.assertTrue(original[key].strip())

    def test_source_hashes_match_media_and_native_skill_definitions(self):
        for path, entry in self.catalog['source_hashes'].items():
            raw = (ROOT / path).read_bytes() if path.startswith('vendor/') else self.media.read(path)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['sha256'], path)
        self.assertEqual(self.catalog['failures'], [])


if __name__ == '__main__':
    unittest.main()
