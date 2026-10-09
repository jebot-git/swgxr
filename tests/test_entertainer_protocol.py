import unittest
from copy import deepcopy
from server.entertainer_protocol import audience_snapshot, command, snapshot
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


class NativePlacedInstrumentProjectionTests(unittest.TestCase):
    def test_native_placed_whitelist_survives_inventory_refresh(self):
        from server.entertainment import PerformanceHub
        hub=PerformanceHub(lambda:100.)
        session=hub.register_observation('player',{'character_id':'1','skills':['social_entertainer_novice'],'entertainer':True},{'10':'object/tangible/instrument/slitherhorn.iff'},[0,0,0])
        native={'source_kind':'core3_entertainer','character_id':'1','sequence':1,'state':{'character_id':'1','skills':['social_entertainer_novice'],'placed_instruments':[{'id':'20','template':'object/tangible/instrument/nalargon.iff','playable':True}]},'mutation':{}}
        hub.observe_native('player','1',native)
        hub.update('player',{'token':session['token'],'seq':1,'position':[0,0,0],'item_id':'20'})
        hub.refresh_inventory('player','1',[{'id':'10','template':'object/tangible/instrument/slitherhorn.iff','equipped':True}])
        actor=hub._actor('1');self.assertEqual(actor['item'],'20');self.assertIn('10',actor['items'])
        with self.assertRaises(ValueError):hub.update('player',{'token':session['token'],'seq':2,'position':[0,0,0],'item_id':'999'})
        native['sequence']=2;native['state']['placed_instruments']=[];hub.observe_native('player','1',native)
        with self.assertRaises(ValueError):hub.update('player',{'token':session['token'],'seq':3,'position':[0,0,0],'item_id':'20'})


class AutomaticAudienceTests(unittest.TestCase):
    def setUp(self):
        from server.entertainment import PerformanceHub
        self.now = 100.
        self.hub = PerformanceHub(lambda:self.now)
        self.session = self.hub.register_observation('patron',
            {'character_id':'7','skills':[],'entertainer':False}, {}, [0,0,0])
        self.audience = {'policy':'automatic_radius','radius_m':8.,
            'minimum_seconds':60,'refresh_seconds':10,'sources':[
                {'id':'8','kind':'dance','seconds':65,'strength':20,'duration_minutes':15},
                {'id':'9','kind':'music','seconds':45,'strength':10,'duration_minutes':5}]}
        self.seq = 0

    def observe(self, sequence=10, audience=True):
        state = {'character_id':'7','zone':'tatooine','skills':[]}
        if audience: state['audience'] = deepcopy(self.audience)
        envelope = {'source_kind':'core3_entertainer','character_id':'7',
            'sequence':sequence,'state':state,'mutation':{'success':True}}
        out = snapshot(envelope,'7')
        self.hub.observe_native('patron','7',out)
        return out

    def update(self, **values):
        self.seq += 1
        payload = {'token':self.session['token'],'seq':self.seq,'position':[0,0,0]}
        payload.update(values)
        return self.hub.update('patron',payload)

    def test_native_state_is_bounded_and_strips_unreported_buff_claims(self):
        self.audience['buff_applied'] = True
        self.audience['sources'][0]['buff_applied'] = True
        out = self.observe()
        self.assertNotIn('buff_applied',out['state']['audience'])
        self.assertNotIn('buff_applied',out['state']['audience']['sources'][0])
        self.assertEqual(len(out['state']['audience']['sources']),2)
        self.assertTrue(out['ok'])

    def test_invalid_geometry_timing_and_source_shapes_rejected(self):
        bad = []
        for key, value in [('policy','manual_watch'),('radius_m',float('nan')),
                           ('radius_m',True),('radius_m',9),('minimum_seconds',True),
                           ('minimum_seconds',0),('refresh_seconds',.1),('sources',{})]:
            item = deepcopy(self.audience); item[key] = value; bad.append(item)
        item = deepcopy(self.audience); item['sources'] *= 2; bad.append(item)
        for key, value in [('id','0'),('id',str(2**64)),('id','8x'),('kind','unknown'),
                           ('seconds',-1),('seconds',2**31),('strength',True),
                           ('strength',float('inf')),('duration_minutes',1.5)]:
            item = deepcopy(self.audience); item['sources'][0][key] = value; bad.append(item)
        for key, value in [('id','8'),('kind','dance')]:
            item = deepcopy(self.audience); item['sources'][1][key] = value; bad.append(item)
        for item in bad:
            with self.subTest(audience=item), self.assertRaises(ValueError):
                audience_snapshot(item)

    def test_client_positions_and_claims_never_create_or_replace_benefits(self):
        self.assertEqual(self.session['buff_authority'],'native_core3')
        unknown = self.update(audience=self.audience,buff_applied=True)
        self.assertEqual(unknown['audience']['status'],'unobserved')
        self.observe()
        reply = self.update(position=[9000,0,0],audience={'sources':[]},buff_applied=False)
        self.assertEqual(reply['bands'],[])
        self.assertEqual(reply['audience']['state'],self.audience)
        self.assertEqual(reply['audience']['status'],'fresh')
        self.assertEqual(reply['audience']['sequence'],10)
        self.assertNotIn('buff_applied',reply['audience'])

    def test_expired_observation_is_unknown_without_expiring_native_buff(self):
        self.observe()
        self.now += 12
        self.assertEqual(self.update()['audience']['status'],'fresh')
        self.now += .01
        stale = self.update()['audience']
        self.assertEqual(stale['status'],'stale')
        self.assertIsNone(stale['state'])
        self.assertAlmostEqual(stale['observation_age_seconds'],12.01)
        self.assertNotIn('buff_applied',stale)
        self.observe(sequence=9)
        self.assertEqual(self.update()['audience']['status'],'stale')
        self.audience['sources'] = []
        self.observe(sequence=11)
        self.assertEqual(self.update()['audience']['state']['sources'],[])
        self.assertEqual(self.update()['audience']['status'],'fresh')

    def test_presence_disabled_or_wrong_planet_never_shows_fresh_native_audience(self):
        self.observe()
        self.assertEqual(self.update(enabled=False)['audience']['status'],'stale')
        self.assertEqual(self.update(enabled=True,area='naboo')['audience']['status'],'stale')
        self.assertIsNone(self.update(area='naboo')['audience']['state'])

    def test_native_missing_field_clears_observation_and_projection_is_a_copy(self):
        self.observe()
        reply = self.update()
        reply['audience']['state']['sources'].clear()
        self.assertEqual(len(self.update()['audience']['state']['sources']),2)
        self.observe(sequence=11,audience=False)
        self.assertEqual(self.update()['audience']['status'],'unobserved')
        self.assertIsNone(self.update()['audience']['state'])

    def test_native_wrong_owner_cannot_supply_audience(self):
        out = self.observe()
        out['character_id'] = '8'
        with self.assertRaises(ValueError):
            self.hub.observe_native('patron','7',out)
        self.assertEqual(self.update()['audience']['state'],self.audience)

    def test_command_does_not_forward_client_audience_eligibility_or_buff_amount(self):
        request = command('status',{'audience':self.audience,'buff_applied':True,
                                   'strength':125,'recipient_ids':['7','8']})
        self.assertEqual(request,{'action':'status'})
