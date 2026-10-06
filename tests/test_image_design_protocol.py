"""Image design authority boundaries and source option coverage."""
import unittest
from server.image_design_protocol import command, normalize
from server.image_design_catalog import options, proposal, definitions
from tools.entertainment.prepare_image_design import build

class Tests(unittest.TestCase):
    def test_recipient_cannot_supply_consent_flags_or_native_commit_fields(self):
        out=command('image_accept',{'session_id':'42','revision':3,'designer_accepted':True,'price':0,'target_id':'99'})
        self.assertEqual(out,{'session_id':'42','revision':3})
        for revision in (-1,True,'3',2**31):
            with self.assertRaises(ValueError):command('image_accept',{'session_id':'42','revision':revision})
        with self.assertRaises(ValueError):command('image_propose',{'session_id':'42','revision':0,'draft':{'stat_migration':True}})
        with self.assertRaises(ValueError):command('image_open',{'target_id':'0'})

    def test_bounded_numeric_draft(self):
        base={'session_id':'42','revision':0}
        for draft in ({'price':True},{'price':-1},{'price':10001},{'attributes':{'height':float('nan')}},{'attributes':{'height':False}},{'attributes':[]},{'hair_template':['bad']}):
            with self.assertRaises(ValueError):command('image_propose',dict(base,draft=draft))
        out=command('image_propose',dict(base,draft={'price':50,'attributes':{'height':.7}}))
        self.assertEqual(out['draft']['attributes']['height'],.7)

    def test_original_policy_matches_runtime_options_for_every_race(self):
        data=build();_,_,chars=definitions()
        self.assertEqual(len(data['races']),20)
        for race,source in chars['races'].items():
            native=data['races'][source['template']]
            appearance={'race':race,'customization':{},'hair':None}
            for master in (False,True):
                ctx={'skills':['social_imagedesigner_master'] if master else [],'skill_mods':dict.fromkeys(('body','face','hair','markings'),100)}
                current=options(ctx,appearance)
                rules={r['id']:r for r in native['controls']}
                self.assertEqual(set(rules),{r['id'] for r in current['controls']})
                for control in current['controls']:
                    self.assertEqual(rules[control['id']]['maxima'][5 if master else 0],control['max'])
            self.assertTrue(native['hair'] or native['allow_bald'])

    def test_existing_control_values_roundtrip_source_customization(self):
        ctx={'skills':['social_imagedesigner_master'],'skill_mods':dict.fromkeys(('body','face','hair','markings'),100)}
        for race in definitions()[2]['races']:
            original={'race':race,'customization':{},'hair':None,'height':1.0}
            for control in options(ctx,original)['controls']:
                if control['scope']=='hair':continue
                value=min(3,control['max']) if control['type']=='color' else .31
                preview=proposal(ctx,original,{'attributes':{control['id']:value}})['preview']
                actual=next(c['value'] for c in options(ctx,preview)['controls'] if c['id']==control['id'])
                restored=proposal(ctx,original,{'attributes':{control['id']:actual}})['preview']
                self.assertAlmostEqual(preview['height'],restored['height'],delta=1e-6)
                for key,amount in preview['customization'].items():
                    self.assertAlmostEqual(restored['customization'][key],amount,delta=1,msg=race+':'+control['id'])

    def test_unlearned_values_and_prices_never_produce_preview(self):
        original={'race':'human_male','customization':{},'hair':None,'height':1.0}
        novice={'skills':[],'skill_mods':{}}
        self.assertEqual(options(novice,original)['controls'],[])
        for draft in ({'attributes':{'height':.5}},{'holoemote':'arbitrary'},{'hair_template':'object/tangible/hair/human/hair_human_female_s01.iff'}):
            with self.assertRaises(ValueError):proposal(novice,original,draft)
        self.assertEqual(normalize({'active':False}),{'active':False})

if __name__=='__main__':unittest.main()
