"""Commando presentation remains traceable to the supplied local media."""
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools/assets'), str(ROOT/'tools/combat')]
from swg_formats import TreSet, parse_iff, cstring


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(), 'Supplied TREs required')
class CommandoAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.media = TreSet(ROOT/'runtime/asset_sources/active_tre')
        cls.assets = json.loads((ROOT/'runtime/assets/combat/assets.json').read_text())
        cls.grenades = json.loads((ROOT/'runtime/assets/grenades/assets.json').read_text())

    def test_original_heavy_muzzle2_preserves_source_transform(self):
        for key in ('heavy_particle_beam', 'heavy_acid_beam', 'heavy_lightning_beam', 'heavy_rocket_launcher'):
            row = self.assets['weapons'][key]
            self.assertEqual(row['muzzle_hardpoint'], 'muzzle2')
            source = parse_iff(self.media.read(row['muzzle_source']))
            hp = next(h for h in source.walk('HPNT') if cstring(h.data, 48)[0] == 'muzzle2')
            matrix = list(struct.unpack_from('<12f', hp.data))
            self.assertEqual(row['muzzle_source_matrix'], matrix)
            self.assertEqual(row['muzzle'], [matrix[3], matrix[7], -matrix[11]])

    def test_every_delivery_has_visible_original_source_and_hashed_extension(self):
        for key in ('rifle_flame_thrower', 'rifle_acid_beam', 'pistol_launcher', 'heavy_particle_beam',
                    'heavy_acid_beam', 'heavy_lightning_beam', 'heavy_rocket_launcher'):
            row = self.assets['weapons'][key]
            path = row['projectile']
            emitters = self.assets['particles'][path]['emitters']
            self.assertTrue(any(e['visible'] and e['material']['texture'] for e in emitters), key)
            self.assertEqual(hashlib.sha256(self.media.read(path)).hexdigest(),
                             self.assets['provenance'][path]['sha256'])
            for emitter in emitters:
                self.assertIn(emitter['source_version'], ('0009', '0011', '0012'))
                self.assertTrue(emitter['remaining_source_hex'])
        tracer = self.assets['particles']['appearance/pt_rocket_tracer.prt']
        self.assertTrue(any(row['reason'] == 'attachment_motion_flattened' for row in tracer['bounded_omissions']))
        self.assertEqual(self.assets['failures'], [])

    def test_grenade_families_use_original_explosions_not_default_weapon_bolts(self):
        self.assertEqual(set(self.grenades['grenade_effects']),
                         {'fragmentation_light', 'fragmentation', 'cryoban', 'glop', 'imperial', 'thermal', 'proton'})
        for path in self.grenades['grenade_effects'].values():
            self.assertTrue(path.startswith('clienteffect/combat_grenade_'))
            effect = self.grenades['effects'][path]
            self.assertTrue(any(self.grenades['particles'][p['particle']]['emitters'] for p in effect['appearances']))
            self.assertTrue(effect['omitted_camera_shake_for_xr'])
        for path, row in self.grenades['provenance'].items():
            self.assertEqual(hashlib.sha256(self.media.read(path)).hexdigest(), row['sha256'])
        for particle in self.grenades['particles'].values():
            for emitter in particle['emitters']:
                material = emitter['material']
                original = Image.open(io.BytesIO(self.media.read(material['texture_source']))).convert('RGBA')
                converted = Image.open(ROOT/'runtime/assets/grenades'/material['texture']).convert('RGBA')
                self.assertEqual((original.size, original.tobytes()), (converted.size, converted.tobytes()))
        self.assertEqual(self.grenades['failures'], [])


if __name__ == '__main__':
    unittest.main()
