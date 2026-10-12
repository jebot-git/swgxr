"""Validate supplied sector data and explicitly distinguish missing original media."""
import hashlib,json,math,unittest
from pathlib import Path
from server.jtl_protocol import SPACE_ZONES
ROOT=Path(__file__).resolve().parents[1]
class SectorAssets(unittest.TestCase):
 def test_hyperspace_map_positions_match_native_arrival_axis_order(self):
  import sys
  sys.path.insert(0,str(ROOT/'tools/assets'))
  from prepare_space_sectors import hyperspace_position
  from swg_formats import TreSet
  from character_formats import datatable
  root=ROOT/'runtime/assets/jtl';source=ROOT/'runtime/asset_sources/active_tre'
  if not (root/'catalog.json').is_file() or not source.is_dir():self.skipTest('Original converted assets unavailable')
  assets=TreSet(source)
  rows=datatable(assets.read('datatables/space/hyperspace/hyperspace_locations.iff'))
  native={r['HYPERSPACE_POINT_NAME']:[r['X'],r['Z'],r['Y']] for r in rows}
  catalog=json.loads((root/'catalog.json').read_text())
  for sector in catalog['sectors'].values():
   descriptor=json.loads((root/sector['descriptor']).read_text())
   self.assertEqual(sector['navigation'],descriptor['navigation'])
   for destination in sector['navigation']:
    self.assertEqual(destination['position'],native[destination['id']])
  self.assertEqual(hyperspace_position({'X':-944,'Y':4270,'Z':-4525}),[-944,-4525,4270])

 def test_all_original_sectors_have_source_planets_navigation_and_render_inputs(self):
  root=ROOT/'runtime/assets/jtl';catalog_path=root/'catalog.json'
  if not catalog_path.is_file():self.skipTest('Original converted assets unavailable')
  catalog=json.loads(catalog_path.read_text());self.assertEqual(set(catalog['sectors']),set(SPACE_ZONES))
  missing=set()
  for zone,entry in catalog['sectors'].items():
   with self.subTest(zone=zone):
    path=root/entry['descriptor'];self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),entry['sha256'])
    data=json.loads(path.read_text());self.assertEqual(data['source_zone'],zone)
    self.assertTrue(data['environment']['planets']);self.assertEqual(len(data['environment']['skybox']['faces']),6)
    for face in data['environment']['skybox']['faces'].values():self.assertTrue((root/face['path']).is_file())
    for planet in data['environment']['planets']:
     self.assertGreater(planet['surface']['radius'],0);self.assertTrue(all(math.isfinite(v) for v in planet['position']))
     for texture in planet['surface']['textures'].values():self.assertTrue((root/texture['path']).is_file())
    for row in data['navigation']:self.assertEqual(row['zone'],zone)
    for field in data['asteroidfield']:
     for row in field['instances']:
      self.assertIn(row['mesh'],data['meshes']);self.assertGreater(row['scale'],0)
      self.assertTrue(all(math.isfinite(v) for v in row['position']+row['quaternion']))
    missing.update(row['resource'] for row in data['conversion_failures'])
  self.assertEqual(missing,{'object/static/space/asteroid/shared_asteroid_molten_mammoth_01.iff','object/static/space/asteroid/shared_asteroid_molten_mammoth_02.iff'})
 def test_native_asteroid_extents_match_the_rendered_seeded_fields(self):
  root=ROOT/'runtime/assets/jtl';path=ROOT/'vendor/Core3/MMOCoreORB/bin/conf/swgxr-space-collision.json'
  if not path.exists():self.skipTest('Private native collision data unavailable')
  native=json.loads(path.read_text());catalog=json.loads((root/'catalog.json').read_text())
  self.assertEqual(set(native['sectors']),set(catalog['sectors']))
  for zone,entry in catalog['sectors'].items():
   data=json.loads((root/entry['descriptor']).read_text())
   self.assertEqual(native['source_sha256'][zone],entry['sha256'])
   self.assertEqual(native['sectors'][zone],[row for field in data['asteroidfield'] for row in field['collision_spheres']])
   for field in data['asteroidfield']:
    self.assertEqual({tuple(row['position']) for row in field['collision_spheres']},{(row['position'][0],row['position'][1],-row['position'][2]) for row in field['instances']})
    self.assertTrue(all(row['radius']>0 for row in field['collision_spheres']))

 def test_native_journal_labels_do_not_change_authoritative_ids_or_positions(self):
  from server.jtl_protocol import normalize_state
  from unittest.mock import patch
  state={'missions':[{'id':'spacequest:45:0','name':'@spacequest/patrol/example:title','description':'@spacequest/patrol/example:desc'}],'waypoints':[{'id':'123','name':'@spacequest/patrol/example:waypoint','position':[1,2,3]}]}
  with patch('server.datapad_protocol.display',side_effect=lambda t,k,f:'Resolved '+k):normalize_state(state)
  self.assertEqual(state['missions'][0]['name'],'Resolved title');self.assertEqual(state['missions'][0]['id'],'spacequest:45:0')
  self.assertEqual(state['waypoints'][0]['position'],[1,2,3])
if __name__=='__main__':unittest.main()
