"""Validate the actual supplied POB data, not a placeholder room fixture."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]


class JtlAssets(unittest.TestCase):
    def test_small_ship_cockpits_exteriors_and_server_capabilities_match(self):
        from server.jtl_catalog import SHIP_TEMPLATES
        directory=ROOT/'runtime/assets/jtl'
        if not (directory/'catalog.json').is_file():self.skipTest('Original JtL assets have not been converted')
        catalog=json.loads((directory/'catalog.json').read_text())
        actual={key for key,row in catalog['templates'].items() if row.get('kind')=='fighter'}
        self.assertEqual(actual,set(SHIP_TEMPLATES))
        for template in SHIP_TEMPLATES:
            row=catalog['templates'][template]
            self.assertTrue(row['cockpit_source'].startswith('cockpit/'))
            self.assertIn(row['cockpit_source'],catalog['provenance'])
            self.assertIn(row['frame_source'],catalog['provenance'])
            for key,digest in [('descriptor','sha256'),('exterior_descriptor','exterior_sha256')]:
                path=directory/row[key]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),row[digest])
                stage=json.loads(path.read_text())
                self.assertTrue(stage['meshes'] and stage['instances'])
                self.assertFalse(stage['conversion_failures'])
                for mesh in stage['meshes'].values():
                    for surface in mesh['surfaces']:
                        self.assertTrue(surface['indices'])
                        self.assertTrue((directory/surface['texture']).is_file())
            self.assertEqual(json.loads((directory/row['descriptor']).read_text())['spawn'],row['cockpit_position'])

    def test_original_rooms_fixtures_materials_and_navigation_landmark(self):
        directory=ROOT/'runtime/assets/jtl'
        if not (directory/'catalog.json').is_file():self.skipTest('Original JtL assets have not been converted')
        catalog=json.loads((directory/'catalog.json').read_text())
        stage=json.loads((directory/catalog['stage']).read_text())
        self.assertEqual(catalog['conversion_failures'],[])
        self.assertEqual(len(catalog['original_fixtures']),8)
        interior=[row for row in stage['cells'].values() if not row['is_exterior']]
        self.assertEqual(len(interior),11)
        self.assertTrue(all(row['floor_indices'] for row in interior))
        invisible=0
        for instance in stage['instances']:
            for surface in stage['meshes'][instance['mesh']]['surfaces']:
                if surface.get('source_invisible'):
                    invisible+=len(surface['indices'])//3
                    self.assertEqual(surface['source_effect'],'effect/e_invisible_collidable.eft')
                else:self.assertTrue((directory/surface['texture']).is_file())
        self.assertEqual(invisible,73)
        space=json.loads((directory/catalog['space_stage']).read_text())
        self.assertEqual(space['source_zone'],'space_tatooine')
        self.assertTrue(space['instances'] and space['meshes'])
        source=catalog['station_source']
        self.assertEqual(hashlib.sha256((ROOT/source['path']).read_bytes()).hexdigest(),source['sha256'])
        descriptor=next(iter(catalog['templates'].values()))
        self.assertEqual(hashlib.sha256((directory/descriptor['descriptor']).read_bytes()).hexdigest(),descriptor['sha256'])

    def test_all_planet_service_catalogs_include_original_starship_anchors(self):
        from tools.assets.planet_config import PLANETS,path_for
        for planet in PLANETS:
            path=path_for(planet,'services')/'catalog.json'
            if not path.exists():self.skipTest('Original planet catalog missing: '+planet)
            data=json.loads(path.read_text())
            rows=[row for row in data['static_terminals'] if row['kind']=='starship']
            self.assertTrue(rows,planet)
            self.assertTrue(all(row['template']=='object/tangible/terminal/terminal_space.iff' for row in rows),planet)


if __name__=='__main__':unittest.main()
