#!/usr/bin/env python3
"""Launcher entity gate tests with temporary catalogs and mocked subprocesses.

No asset conversion, native service startup or real RPC occurs in this test.
"""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_prototype as launcher


class EntityPreparationTest(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.root=Path(self.folder.name)
        self.root_patch=patch.object(launcher,'ROOT',self.root);self.root_patch.start()
        self.calls=patch.object(launcher.subprocess,'run');self.run=self.calls.start()
        self.entity=self.root/'runtime/assets/combat_population/tatooine_entities'
        self.entity.mkdir(parents=True)
        self.inventory=self.root/'runtime/assets/inventory';self.inventory.mkdir(parents=True)
        self.template='object/mobile/source_fixture.iff'
        self.lair='object/tangible/lair/base/source_fixture.iff'
        self.write(self.entity/'sources.json',{'appearance_templates':[self.template],'lairs':{'source':{'building_templates':[self.lair]}}})
        self.write(self.entity/'coverage.json',{'templates':{self.template:{'status':'partial'}},'counts':{'ready':0,'partial':1,'missing':0},'source_resolution_failures':[]})
        self.write(self.inventory/'catalog.json',{'items':{self.lair:{'status':'ready','model':'model.json'}}})
        self.write(self.inventory/'model.json',{'fixture':True})
    def tearDown(self):
        self.calls.stop();self.root_patch.stop();self.folder.cleanup()
    def write(self,path,value):path.write_text(json.dumps(value))
    def test_non_live_does_nothing(self):
        self.assertIsNone(launcher.live_entity_assets(['--desktop']))
        self.run.assert_not_called()
    def test_repeat_launch_indexes_without_reconverting_ready_lairs(self):
        for _ in range(2):
            result=launcher.live_entity_assets(['--live-combat'])
            self.assertFalse(result['lairs_prepared'])
            self.assertEqual(result['counts']['partial'],1)
        self.assertEqual(self.run.call_count,2)
        for call in self.run.call_args_list:
            self.assertTrue(call.args[0][1].endswith('prepare_planet_entities.py'))
            self.assertNotIn('--retry-missing',call.args[0])
    def test_missing_lair_model_prepares_population_dependency_index(self):
        (self.inventory/'model.json').unlink()
        result=launcher.live_entity_assets(['--live-combat'])
        self.assertTrue(result['lairs_prepared'])
        self.assertEqual(self.run.call_count,2)
        self.assertEqual(self.run.call_args.args[0][-2:],['--population-lairs',str(self.entity/'sources.json')])
    def test_unresolved_source_gate_precedes_any_lair_conversion(self):
        self.write(self.entity/'coverage.json',{'templates':{self.template:{}},'source_resolution_failures':[{'error':'unknown source'}]})
        with self.assertRaisesRegex(ValueError,'source references are unresolved'):
            launcher.live_entity_assets(['--live-combat'])
        self.assertEqual(self.run.call_count,1)
    def test_missing_coverage_fails_explicitly(self):
        (self.entity/'coverage.json').unlink()
        with self.assertRaisesRegex(ValueError,'did not publish source coverage'):
            launcher.live_entity_assets(['--live-combat'])


if __name__=='__main__':unittest.main()
