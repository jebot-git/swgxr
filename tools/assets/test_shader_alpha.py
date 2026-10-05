#!/usr/bin/env python3
"""Protect source cutouts without making specular-mask textures transparent."""
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from shader_alpha import effect_alpha,shader_alpha
from swg_formats import Iff,TreSet,parse_iff

def effect(sort='MAIN',flags=(False,),version='0009'):
    passes=[]
    for flag in flags:
        raw=bytearray(56);raw[11]=int(flag)
        passes.append(Iff('PASS',b'',[Iff(version,b'',[Iff('DATA',bytes(raw),[])])]))
    return Iff('EFCT',b'',[Iff('IMPL',b'',[Iff('0009',b'',[Iff('DATA',b'\x01'+sort[::-1].encode(),[])]+passes)])])

class SourceAlphaTests(unittest.TestCase):
    def test_opaque_sort_alpha_test(self):
        value=effect_alpha(effect(flags=(True,)),'effect/test.eft')[0]
        self.assertEqual(value['sort_tag'],'MAIN');self.assertTrue(value['alpha_test'])
    def test_secondary_specular_pass_does_not_punch_opaque_base(self):
        value=effect_alpha(effect(flags=(False,True)),'effect/test.eft')[0]
        self.assertFalse(value['alpha_test']);self.assertTrue(value['passes'][1]['alpha_test'])
    def test_opaque_specular_mask_not_opacity(self):
        self.assertFalse(effect_alpha(effect(),'effect/test.eft')[0]['alpha_test'])
    def test_alpha_sort_retained(self):
        self.assertEqual(effect_alpha(effect(sort='ALPH'),'effect/test.eft')[0]['sort_tag'],'ALPH')
    def test_unknown_layout_never_guessed(self):
        value=effect_alpha(effect(flags=(True,),version='9999'),'effect/test.eft')[0]
        self.assertFalse(value['alpha_test']);self.assertFalse(value['passes'][0]['decoded'])
    def test_all_implementations_retained(self):
        root=effect();root.children.extend(effect(flags=(True,)).children)
        evidence=effect_alpha(root,'effect/test.eft');self.assertEqual(len(evidence),2);self.assertTrue(any(e['alpha_test'] for e in evidence))

class OriginalMaterialCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory=Path(__file__).resolve().parents[2]/'runtime/assets/active_tre'
        if not directory.exists():raise unittest.SkipTest('Local original source archives unavailable')
        cls.source=TreSet(directory)
    def test_original_metal_masks_are_not_surface_holes(self):
        for name in ('a_specmap','a_envmask_specmap','a_detail_specmap','a_specmap_bump','a_simple'):
            with self.subTest(effect=name):
                evidence=effect_alpha(parse_iff(self.source.read('effect/'+name+'.eft')),name)
                self.assertFalse(any(e['alpha_test'] or e['sort_tag']=='ALPH' for e in evidence))
    def test_original_foliage_cutout_still_enabled(self):
        value=shader_alpha(parse_iff(self.source.read('shader/thm_tato_orchard_flora_ap10.sht')),self.source.read)
        self.assertTrue(value['alpha']);self.assertTrue(any(e['sort_tag']=='MAIN' and e['alpha_test'] for e in value['alpha_source']))

if __name__=='__main__':unittest.main()
