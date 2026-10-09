"""Original CH artwork, creature head anchors and exact asset provenance."""
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/assets'))
from swg_formats import TreSet
from tools.pets.audit_assets import audit, HEAD_ANCHORS


@unittest.skipUnless((ROOT/'runtime/asset_sources/active_tre').exists(),'User-provided TREs required')
class CreatureHandlerAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tre = TreSet(ROOT/'runtime/asset_sources/active_tre')
        cls.icons_root = ROOT/'runtime/assets/combat/abilities'
        cls.icons = json.loads((cls.icons_root/'catalog.json').read_text())
        cls.audit = audit()

    def test_prepared_icons_match_original_atlas_pixels_and_provenance(self):
        for command in ('tame','emboldenpets','enragepets','mount','dismount','trainmount','pethigh','petlow'):
            row = self.icons['icons'][command]
            raw = self.tre.read(row['source'])
            self.assertEqual(self.icons['sources'][row['source']],hashlib.sha256(raw).hexdigest())
            x0,y0,x1,y1 = row['source_rect']
            expected = Image.open(io.BytesIO(raw)).convert('RGBA').crop((min(x0,x1),min(y0,y1),max(x0,x1),max(y0,y1)))
            if x1<x0: expected = expected.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if y1<y0: expected = expected.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            actual = Image.open(self.icons_root/row['path']).convert('RGBA')
            self.assertEqual(actual.size,(24,24))
            self.assertEqual(actual.tobytes(),expected.tobytes())

    def test_training_icon_alias_is_explicit_and_inverted_source_uv_is_preserved(self):
        self.assertEqual(self.icons['icons']['trainmount']['source_style'],'mount')
        self.assertEqual((self.icons_root/'trainmount.png').read_bytes(),(self.icons_root/'mount.png').read_bytes())
        high = Image.open(self.icons_root/'pethigh.png').convert('RGBA')
        low = Image.open(self.icons_root/'petlow.png').convert('RGBA')
        self.assertEqual(low.tobytes(),high.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes())

    def test_all_tatooine_tameable_bodies_and_existing_trainers_are_prepared(self):
        tatooine = [r for r in self.audit['creatures'] if r['planet']=='tatooine']
        self.assertGreater(len(tatooine),20)
        self.assertEqual([r for r in self.audit['missing'] if r['planet']=='tatooine'],[])
        self.assertEqual(len(self.audit['trainers']),2)
        self.assertTrue(all(r['prepared'] and r['complete'] for r in self.audit['trainers']))

    def test_all_local_creatures_have_authored_anatomical_anchor_and_source_hash(self):
        self.assertGreater(len(self.audit['creatures']),300)
        for row in self.audit['creatures']:
            with self.subTest(template=row['template'],planet=row['planet']):
                self.assertIn(row['anchor_name'],HEAD_ANCHORS)
                self.assertGreaterEqual(row['head_bone'],0)
                self.assertEqual(len(row['model_sha256']),64)
        self.assertTrue(any(r['anchor_name']=='head_base' for r in self.audit['creatures']))
        self.assertTrue(any(r['anchor_name']=='fambaa_head' for r in self.audit['creatures']))
        mounts = [r for r in self.audit['creatures'] if r['in_original_mount_scale_table']]
        self.assertEqual(len({r['appearance'] for r in mounts}),11)
        self.assertTrue(all(r['anchor_name'] in ('head','head_base','fambaa_head') for r in mounts))


if __name__ == '__main__': unittest.main()
