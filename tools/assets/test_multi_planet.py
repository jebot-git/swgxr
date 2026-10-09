#!/usr/bin/env python3
"""Contract regressions for real multi-planet source selection and cache safety."""
import hashlib, json, tempfile, unittest
from pathlib import Path
from planet_config import PLANETS, ROOT, origin_for, path_for
from prepare_services import travel_points
from prepare_planets import descriptor, sources_current
from swg_formats import TreSet
from prepare_environment import EnvironmentImporter,snapshot
from prepare_planet_entities import source_union

class MultiPlanetTests(unittest.TestCase):
    def test_media_and_travel_are_original(self):
        tre=TreSet(ROOT/'runtime/asset_sources/active_tre')
        for planet in PLANETS:
            with self.subTest(planet=planet):
                for name in (f'terrain/{planet}.trn',f'snapshot/{planet}.ws',f'datatables/environment/{planet}.iff',f'terrain/environment/{planet}.iff'):self.assertIn(name,tre.entries)
                d=descriptor(planet);self.assertEqual(d['origin'],origin_for(planet))
                self.assertTrue(d['travel_points']);self.assertTrue(all(p['zone']==planet for p in d['travel_points']))
                self.assertIn(d['default_entry'],[p['position'] for p in d['travel_points']])
                self.assertEqual(bool(d['stage']),planet=='tatooine')
    def test_dependency_validation_rejects_changed_source(self):
        class FakeTre:
            def read(self,name):return b'original'
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'manifest.json'
            p.write_text(json.dumps({'provenance':{'dependencies':{'source':{'sha256':hashlib.sha256(b'original').hexdigest()}}}}))
            self.assertTrue(sources_current(p,FakeTre()))
            p.write_text(json.dumps({'provenance':{'dependencies':{'source':{'sha256':hashlib.sha256(b'changed').hexdigest()}}}}))
            self.assertFalse(sources_current(p,FakeTre()))
    def test_planet_entity_graph_uses_requested_regions(self):
        for planet in ('corellia','naboo','endor','yavin4'):
            m=source_union(planet)
            self.assertTrue(m['regions_source'].endswith(planet+'_regions.lua'))
            self.assertTrue(m['mobiles']);self.assertTrue(m['lairs']);self.assertTrue(m['appearance_templates'])
            self.assertFalse(m['failures'],m['failures'])

if __name__=='__main__':unittest.main()
