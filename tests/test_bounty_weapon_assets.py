"""BH weapon presentation and source profiles must use the exact original items."""
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
from character_formats import datatable
from export_catalog import parse_template
from prepare_assets import Assets
from swg_formats import TreSet, parse_iff, cstring

WEAPONS = {
    'pistol_scatter': ('appearance/mesh/wp_pistol_scatter_pistol_l0.msh', 'appearance/pt_bolt_scatter.prt', 'cert_pistol_scatter'),
    'rifle_lightning': ('appearance/mesh/wp_rifle_lightning_cannon_l0.msh', 'appearance/pt_beam_lightning.prt', 'cert_rifle_lightning'),
}


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(), 'Supplied TREs required')
class BountyWeaponAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = ROOT/'runtime/assets/combat'
        cls.media = TreSet(ROOT/'runtime/asset_sources/active_tre')
        cls.assets = json.loads((cls.directory/'assets.json').read_text())
        cls.catalog = json.loads((cls.directory/'catalog.json').read_text())
        cls.balance = json.loads((ROOT/'client/combat/balance.json').read_text())

    def test_exact_models_and_original_muzzle_transforms(self):
        for key, (mesh, _, _) in WEAPONS.items():
            row = self.assets['weapons'][key]
            self.assertEqual([part['mesh'] for part in row['parts']], [mesh])
            self.assertEqual(row['muzzle_hardpoint'], 'muzzle')
            root = parse_iff(self.media.read(row['muzzle_source']))
            hardpoint = next(h for h in root.walk('HPNT') if cstring(h.data, 48)[0] == 'muzzle')
            matrix = list(struct.unpack_from('<12f', hardpoint.data))
            self.assertEqual(row['muzzle_source_matrix'], matrix)
            self.assertEqual(row['muzzle'], [matrix[3], matrix[7], -matrix[11]])
            descriptor = self.assets['meshes'][mesh]
            converted = json.loads((self.directory/descriptor['path']).read_text())
            self.assertEqual(sum(len(s['vertices'])//3 for s in converted['surfaces']), descriptor['vertices'])
            self.assertGreater(descriptor['triangles'], 0)
        self.assertNotEqual(self.assets['weapons']['rifle_lightning']['parts'],
                            self.assets['weapons']['heavy_lightning_beam']['parts'])

    def test_effects_match_original_template_datatable_join(self):
        importer = Assets(ROOT/'runtime/asset_sources/active_tre', self.directory, bounded_particle_graphs=True)
        rows = datatable(self.media.read('datatables/weapon/weapon.iff'))
        for key, (_, projectile, _) in WEAPONS.items():
            row = self.assets['weapons'][key]
            source = importer.properties_all(row['shared_template'])
            index = struct.unpack_from('<i', source['weaponEffectIndex'], 1)[0]
            effect_id = cstring(source.get('weaponEffect', b'bolt\0'))[0]
            original = next(r for r in rows if r['Weapon Effect Index'] == index and r['Weapon Effect Id'] == effect_id)
            self.assertEqual(row['effect_row'], original)
            self.assertEqual(row['projectile'], projectile)
            self.assertEqual(projectile, original['Projectile Appearance Template'])
            for phase, column in [('fire', 'Fire Client Effect'), ('hit', 'Hit (Other) Client Effect'), ('hit_creature', 'Hit (Creature) Client Effect')]:
                self.assertEqual(row['effects'][phase], original[column].lower())
                self.assertTrue(self.assets['effects'][row['effects'][phase]]['omitted_camera_shake_for_xr'])

    def test_original_textures_and_visible_particles_are_ready(self):
        for key, (mesh, projectile, _) in WEAPONS.items():
            converted = json.loads((self.directory/self.assets['meshes'][mesh]['path']).read_text())
            emitters = self.assets['particles'][projectile]['emitters']
            self.assertTrue(any(e['visible'] and e['material']['texture'] for e in emitters), key)
            materials = converted['surfaces'] + [e['material'] for e in emitters]
            for material in materials:
                original = Image.open(io.BytesIO(self.media.read(material['texture_source']))).convert('RGBA')
                png = Image.open(self.directory/material['texture']).convert('RGBA')
                self.assertEqual((original.size, original.tobytes()), (png.size, png.tobytes()))
            for path in [mesh, projectile, self.assets['weapons'][key]['shared_template'], *self.assets['weapons'][key]['effects'].values()]:
                self.assertEqual(hashlib.sha256(self.media.read(path)).hexdigest(), self.assets['provenance'][path]['sha256'])
        self.assertEqual(self.assets['failures'], [])

    def test_certificates_and_delivery_policy_export_without_commando_alias(self):
        for key, (_, _, certificate) in WEAPONS.items():
            profile = self.catalog['weapons'][key]
            path = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'/profile['source_file']
            self.assertEqual(profile['core3'], parse_template(path))
            self.assertEqual(profile['core3']['certificationsRequired'], [certificate])
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), profile['source_sha256'])
            override = self.balance['weapons'][key]
            expected = dict(self.balance['classes'][override['class']], **override)
            for field, value in expected.items():
                self.assertEqual(profile[field], value)
            self.assertNotEqual(profile.get('native_family'), 'commando')
        scatter = self.catalog['weapons']['pistol_scatter']
        self.assertEqual((scatter['class'], scatter['delivery'], scatter['pellet_count'], scatter['pellet_half_angle_degrees']),
                         ('pistol', 'scatter', 8, 4.0))
        lightning = self.catalog['weapons']['rifle_lightning']
        self.assertEqual((lightning['class'], lightning['delivery'], lightning['projectile_speed']), ('rifle', 'guided_bolt', 160))
        self.assertEqual((lightning['guidance_acquisition_degrees'], lightning['guidance_turn_degrees_per_second'], lightning['guidance_max_turn_degrees']), (5.0, 20.0, 8.0))
        self.assertEqual(self.catalog['balance_sha256'], hashlib.sha256((ROOT/'client/combat/balance.json').read_bytes()).hexdigest())
        self.assertEqual(self.catalog['failures'], [])


if __name__ == '__main__':
    unittest.main()
