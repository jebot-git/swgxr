"""Validate supplied sector data and explicitly distinguish missing original media."""
import hashlib,json,math,unittest
from pathlib import Path
from server.jtl_protocol import SPACE_ZONES
ROOT=Path(__file__).resolve().parents[1]
class SectorAssets(unittest.TestCase):
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
 def test_native_journal_labels_do_not_change_authoritative_ids_or_positions(self):
  from server.jtl_protocol import normalize_state
  from unittest.mock import patch
  state={'missions':[{'id':'spacequest:45:0','name':'@spacequest/patrol/example:title','description':'@spacequest/patrol/example:desc'}],'waypoints':[{'id':'123','name':'@spacequest/patrol/example:waypoint','position':[1,2,3]}]}
  with patch('server.datapad_protocol.display',side_effect=lambda t,k,f:'Resolved '+k):normalize_state(state)
  self.assertEqual(state['missions'][0]['name'],'Resolved title');self.assertEqual(state['missions'][0]['id'],'spacequest:45:0')
  self.assertEqual(state['waypoints'][0]['position'],[1,2,3])
if __name__=='__main__':unittest.main()
