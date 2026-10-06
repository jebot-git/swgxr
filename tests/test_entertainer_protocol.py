import unittest
from server.entertainer_protocol import command, snapshot
from server.entertainment_catalog import catalog, commands
from server.profession_scope import ENTERTAINER_TRAINERS, TRAINERS

class EntertainerProtocolTests(unittest.TestCase):
    def test_source_performance_not_client_grant(self):
        source=next(p for p in catalog()['performances'].values()if p['kind']=='dance')
        out=command('perform',dict(request_id='entertain_test_1',performance_id=source['id'],xp=10000,skills=['social_dancer_master']))
        self.assertEqual(out['name'],source['name']);self.assertNotIn('xp',out);self.assertNotIn('skills',out)
        with self.assertRaises(ValueError):command('perform',dict(request_id='entertain_test_1',kind='dance',name='invented'))
    def test_random_selection_cannot_be_client_forced(self):
        out=command('flourish',dict(request_id='entertain_test_2',index=8,effect_file='anything',level=3))
        self.assertEqual(out,{'action':'flourish','request_id':'entertain_test_2'})
    def test_request_reach_zone_and_identity_bounds(self):
        base=dict(request_id='entertain_test_3',position=[3500,5,-4700],building_id='123',cell_index=2,zone='tatooine')
        self.assertEqual(command('register_location',base)['cell_index'],2)
        for field,value in [('request_id','x'),('zone','space_corellia'),('position',[0,float('nan'),0]),('cell_index',0),('building_id','-1')]:
            with self.assertRaises(ValueError):command('register_location',dict(base,**{field:value}))
    def test_original_effect_rows_and_skill_tree_grants(self):
        data=catalog();effects=data['special_effects'];self.assertEqual(len(effects),21)
        self.assertEqual(effects['firejets3']['command'],'firejet')
        self.assertEqual(effects['smokebomb3']['required_skill_mod_value'],75)
        self.assertTrue(all(row['effect_file'].startswith('clienteffect/entertainer_')for row in effects.values()))
        self.assertIn('spotlight',commands(['social_dancer_ability_01']))
        self.assertNotIn('spotlight',commands(['social_dancer_knowledge_01']))
        self.assertEqual(ENTERTAINER_TRAINERS,('dancer','musician','imagedesigner'))
        self.assertTrue(set(ENTERTAINER_TRAINERS)<=set(TRAINERS))
    def test_owned_native_envelope_only(self):
        data=dict(source_kind='core3_entertainer',character_id='12',state=dict(character_id='12'),mutation={'success':True})
        self.assertTrue(snapshot(data,'12')['ok'])
        with self.assertRaises(ValueError):snapshot(data,'13')
        with self.assertRaises(ValueError):snapshot(dict(data,state=dict(character_id='12',flourishes=list(range(9)))),'12')

class NativePerformanceProjectionTests(unittest.TestCase):
    def test_native_effect_choice_not_rerolled_or_replayed(self):
        from server.entertainment import PerformanceHub
        hub=PerformanceHub(lambda:100.)
        session=hub.register_observation('player',{'character_id':'1','skills':['social_entertainer_novice'],'entertainer':True},{'10':'object/tangible/instrument/slitherhorn.iff'},[0,0,0])
        performance=next(p for p in catalog()['performances'].values()if p['kind']=='dance'and p['name']=='basic')
        envelope=dict(source_kind='core3_entertainer',character_id='1',sequence=10,
                      state=dict(character_id='1',zone='tatooine',skills=['social_entertainer_novice','social_dancer_ability_01'],commands=['spotlight'],flourishes=[1,2],performing=True,kind='dance',performance_index=performance['performance_index']),
                      mutation=dict(success=True,operation='flourish',command='spotlight',level=1,effect_file='clienteffect/entertainer_spot_light_level_1.cef',effect_position=[1,2,3]))
        hub.observe_native('player','1',envelope)
        reply=hub.update('player',dict(token=session['token'],seq=1,position=[0,0,0],item_id='10',action='flourish'))
        cue=reply['bands'][0]['flourish']
        self.assertEqual(cue['command'],'spotlight');self.assertEqual(cue['sequence'],10);self.assertNotIn('index',cue)
        self.assertEqual(reply['context']['commands'],['spotlight'])
        stale=dict(envelope,sequence=9,mutation=dict(success=True,operation='flourish',command='flourish',index=8))
        hub.observe_native('player','1',stale)
        self.assertEqual(hub.bands['1']['flourish'],cue)
