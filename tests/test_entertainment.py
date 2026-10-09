import unittest
from server.entertainment import PerformanceHub
from server.entertainment_catalog import catalog, commands, eligible

HORN = 'object/tangible/instrument/slitherhorn.iff'

class EntertainmentTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.hub = PerformanceHub(lambda:self.now)
        self.sessions = {}
        self.seq = {}
        for oid in ('1','2','3'):
            learned = ['social_entertainer_novice'] if oid!='3' else []
            context = {'character_id':oid,'complete':True,'entertainer':bool(learned),'skills':learned,
                       'commands':sorted(commands(learned)),'flourishes':list(range(1,9)) if learned else []}
            self.sessions[oid] = self.hub.register_observation('account'+oid,context,{'10':HORN},[0,0,0])
            self.seq[oid]=0

    def update(self, oid, **data):
        self.seq[oid]+=1
        payload={'token':self.sessions[oid]['token'],'seq':self.seq[oid],'position':[0,0,0],'item_id':'10'}
        payload.update(data)
        return self.hub.update('account'+oid,payload)

    def test_original_skill_grants_gate_songs_and_instruments(self):
        choices=eligible(['social_entertainer_novice'],HORN)
        self.assertEqual({p['name'] for p in choices},{'starwars1'})
        self.assertEqual(eligible([],HORN),[])
        self.assertEqual(eligible(['social_entertainer_novice'],'object/tangible/instrument/nalargon.iff'),[])
        self.assertEqual({p['name'] for p in eligible(['social_entertainer_novice'],'')}, {'basic','rhythmic'})
        self.assertEqual(eligible(['social_entertainer_novice'],'object/static/item/item_ribbon.iff'), [])

    def test_start_band_without_instrument_and_join_only_inside_circle(self):
        band=self.update('1',action='start_band',item_id='')['band_id']
        with self.assertRaisesRegex(ValueError,'inside'): self.update('2',action='join',band_id=band,position=[8.1,0,0])
        with self.assertRaisesRegex(ValueError,'inside'): self.update('2',action='join',band_id=band,position=[0,3,0])
        state=self.update('2',action='join',band_id=band,position=[7.9,0,0])
        self.assertEqual(state['band_id'],band)
        self.assertEqual(len(state['bands'][0]['members']),2)
        with self.assertRaisesRegex(ValueError,'entertainer'): self.update('3',action='start_band')

    def test_leader_controls_shared_song_epoch_and_followers_wait_for_compatible_prop(self):
        band=self.update('1',action='perform',performance_id='music:starwars1:slitherhorn')['band_id']
        follower=self.update('2',action='join',band_id=band)
        self.assertEqual(follower['performance_id'],'music:starwars1:slitherhorn')
        with self.assertRaisesRegex(ValueError,'follow the leader'):
            self.update('2',action='perform',performance_id='dance:basic:dance',item_id='')
        waiting=self.update('2',item_id='')
        self.assertEqual(waiting['performance_id'],'')
        self.now+=1
        leader=self.update('1',action='perform',performance_id='dance:basic:dance',item_id='')
        dancer=self.update('2',item_id='')
        self.assertEqual(dancer['performance_id'],'dance:basic:dance')
        self.assertEqual(dancer['bands'][0]['started'],leader['bands'][0]['started'])

    def test_ownership_and_no_client_skill_grant(self):
        with self.assertRaisesRegex(ValueError,'owned'): self.update('1',item_id='999')
        with self.assertRaisesRegex(ValueError,'not been learned'):
            self.update('1',action='perform',performance_id='music:rock:slitherhorn',skills=['social_musician_master'])
        self.assertEqual(self.hub.bands,{})
        with self.assertRaisesRegex(ValueError,'expired'):
            self.hub.update('account2',{'token':self.sessions['1']['token'],'seq':10})

    def test_audience_auto_watch_exit_and_no_fake_persistent_buff(self):
        self.update('1',action='perform',performance_id='music:starwars1:slitherhorn')
        watching=self.update('3',position=[7,0,0])['watching']
        self.assertEqual(len(watching),1)
        self.now+=10
        value=next(iter(self.update('3',position=[7,0,0])['watching'].values()))
        self.assertEqual(value['seconds'],10)
        self.assertTrue(value['presentation_only'])
        self.assertNotIn('buff_applied',value)
        self.assertEqual(self.update('3')['audience']['status'],'unobserved')
        self.assertEqual(self.update('3',position=[9,0,0])['watching'],{})
        self.assertEqual(self.update('3',position=[97,0,0])['bands'],[])

    def test_flourish_random_learned_bounded_and_deduplicated(self):
        self.update('1',action='perform',performance_id='music:starwars1:slitherhorn')
        state=self.update('1',action='flourish')
        flourish=state['bands'][0]['flourish']
        self.assertIn(flourish['index'],range(1,9))
        replay=self.hub.update('account1',{'token':self.sessions['1']['token'],'seq':self.seq['1'],'action':'flourish'})
        self.assertEqual(replay['bands'][0]['flourish'],flourish)
        with self.assertRaisesRegex(ValueError,'recovering'): self.update('1',action='flourish')

    def test_lost_tracking_stops_leader_and_expired_presence_removes_circle(self):
        self.update('1',action='perform',performance_id='music:starwars1:slitherhorn')
        self.assertEqual(self.update('1',enabled=False)['performance_id'],'')
        self.now+=14
        self.update('3')
        self.now+=2
        self.assertEqual(self.update('3')['bands'],[])

    def test_long_initial_scene_load_retains_owned_session(self):
        self.now += 60
        state = self.update('1')
        self.assertEqual(state['context']['character_id'], '1')
        self.assertEqual(state['bands'], [])
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.hub.update('account2', {'token': self.sessions['1']['token'], 'seq': 2})

    def test_paused_presence_disappears_but_can_resume_without_replaying_actions(self):
        band = self.update('1', action='perform', performance_id='music:starwars1:slitherhorn')['band_id']
        self.now += 20
        self.assertEqual(self.update('3')['bands'], [])
        resumed = self.update('1')
        self.assertEqual(resumed['performance_id'], '')
        self.assertEqual(resumed['band_id'], '')
        self.assertNotIn(band, self.hub.bands)
        self.now += self.hub.SESSION_IDLE_SECONDS + 1
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.update('1')

    def test_new_entry_revokes_old_presence_token_even_during_loading_grace(self):
        self.now += 30
        prior = self.sessions['1']
        self.hub.register_observation('account1', prior['context'], {'10': HORN}, [0, 0, 0])
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.update('1')

    def test_native_performance_resume_requires_fresh_observation(self):
        performance = catalog()['performances']['music:starwars1:slitherhorn']
        envelope = {'source_kind': 'core3_entertainer', 'character_id': '1', 'sequence': 1,
                    'state': {'skills': ['social_entertainer_novice'], 'performing': True,
                              'performance_index': performance['performance_index'], 'kind': 'music'}}
        self.hub.observe_native('account1', '1', envelope)
        self.assertTrue(self.update('1')['bands'][0]['performance'])
        self.now += 20
        self.update('3')
        self.assertEqual(self.update('1')['performance_id'], '')
        envelope['sequence'] = 2
        self.hub.observe_native('account1', '1', envelope)
        resumed = self.update('1')
        self.assertEqual(resumed['performance_id'], performance['id'])
        self.assertEqual(resumed['bands'][0]['performance']['id'], performance['id'])

if __name__=='__main__': unittest.main()
