import copy
import unittest
from server.multiplayer_sync import MultiplayerSync

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.now=100.
        self.hub=MultiplayerSync(lambda:self.now)
        self.world={'source_kind':'core3_world','full':True,'players':[{'id':'1','building_id':'0','cell_index':0},{'id':'2','building_id':'0','cell_index':0}],'actors':[]}
        self.snapshot={'player':{'position':[0,0,0],'building_id':'0','cell_index':0,'zone':'tatooine'},'world':self.world}
        for n in (1,2):self.hub.publish('test'+str(n),str(n),'session'+str(n),self.snapshot,1)
    def payload(self,n=1,**changes):
        value={'character_id':str(n),'session_id':'session'+str(n),'sequence':1,'position':[0,0,0], 'building_id':'0','cell_index':0,
               'tracking':{'head':{'tracked':True,'position':[0,1.7,0],'rotation':[0,0,0,1]}}}
        value.update(changes);return value
    def sync(self,n=1,**changes):return self.hub.sync('test'+str(n),self.payload(n,**changes))
    def test_native_identity_and_visibility_required(self):
        for changes in ({'session_id':'wrong'},{'character_id':'2'}):
            with self.assertRaises(ValueError):self.sync(**changes)
        self.sync(2);reply=self.sync()
        self.assertEqual([x['id'] for x in reply['poses']],['2'])
        self.assertNotIn('session_id',reply['poses'][0]);self.assertNotIn('account',reply['poses'][0])
        self.now+=.1
        self.hub.publish('test1','1','session1',dict(self.snapshot,world=dict(self.world,players=[])),2)
        self.assertEqual(self.sync(sequence=2)['poses'],[])
    def test_world_revisions_delta_and_snapshot_immutability(self):
        first=self.sync();first['world']['players'].clear();self.now+=.1
        self.assertIsNone(self.sync(sequence=2,world_revision=1)['world']);self.now+=.1
        self.assertEqual(len(self.sync(sequence=3,world_revision=-1)['world']['players']),2)
    def test_monotonic_sequence_rate_and_expiry(self):
        self.sync()
        with self.assertRaises(ValueError):self.sync(sequence=2)
        self.now+=.1
        with self.assertRaises(ValueError):self.sync(sequence=1)
        self.sync(sequence=2);self.now+=16
        with self.assertRaises(ValueError):self.sync(sequence=3)
    def test_pose_tracking_loss_and_expiry(self):
        self.sync(2);self.now+=1
        self.assertEqual(self.sync()['poses'],[])
        self.now+=.1;self.sync(2,sequence=2,tracking={});self.now+=.1
        pose=self.sync(sequence=2)['poses'][0]
        self.assertTrue(all(not v['tracked'] for v in pose['tracking'].values()))
    def test_cell_transition_and_native_anchor_bounds(self):
        for changes in ({'position':[33,0,0]},{'building_id':'42','cell_index':2}):
            with self.assertRaises(ValueError):self.sync(**changes)
        self.sync(2)
        moved=copy.deepcopy(self.snapshot);moved['player'].update(building_id='42',cell_index=2)
        self.hub.publish('test2','2','session2',moved,2)
        self.now+=.1
        self.assertEqual(self.sync()['poses'],[])
    def test_nonfinite_rotations_reach_and_no_input_authority(self):
        for head in ({'tracked':True,'position':[0,4,0],'rotation':[0,0,0,1]}, {'tracked':True,'position':[0,1,0],'rotation':[0,0,0,0]}, {'tracked':True,'position':[0,1,0],'rotation':[float('nan'),0,0,1]}):
            with self.assertRaises(ValueError):self.sync(tracking={'head':head})
        reply=self.sync(actions={'damage':1000,'credits':1000})
        self.assertNotIn('actions',reply);self.assertEqual(reply['events'],[])
    def test_reconnect_removes_old_pose_and_session(self):
        self.sync(2);self.hub.remove('test2')
        self.assertEqual(self.sync()['poses'],[])
        self.hub.publish('test2','2','replacement',self.snapshot,1)
        with self.assertRaises(ValueError):self.sync(2,sequence=2)
    def test_native_actions_only_success_no_replay_no_private_data(self):
        command={'action':'gathering','gathering':{'action':'survey','resource_id':'private'}}
        self.hub.publish('test2','2','session2',self.snapshot,2,command=command,mutation={'mutation':{'success':False}})
        self.assertEqual(self.sync()['events'],[]);self.now+=.1
        self.hub.publish('test2','2','session2',self.snapshot,3,command=command,mutation={'mutation':{'success':True}})
        reply=self.sync(sequence=2);self.assertEqual([e['kind']for e in reply['events']],['survey']);self.assertNotIn('resource_id',reply['events'][0])
        self.now+=.1
        self.hub.publish('test2','2','session2',self.snapshot,4,command=command,mutation={'mutation':{'success':True,'replayed':True}})
        self.assertEqual(self.sync(sequence=3,event_sequence=reply['event_sequence'])['events'],[])
    def test_action_interest_and_expiry(self):
        self.hub.publish('test2','2','session2',self.snapshot,2,command={'action':'fire','origin':[0,1,0],'direction':[0,0,1]},mutation={'success':True})
        self.assertEqual(self.sync()['events'][0]['kind'],'fire');self.now+=6
        self.assertEqual(self.sync(sequence=2)['events'],[])
    def test_confirmed_shot_weapon_identity_survives_switch_and_ignores_client_template(self):
        self.hub.publish('test2','2','session2',self.snapshot,2,command={'action':'fire','origin':[0,1,0],'direction':[0,0,1], 'item_id':'42','shot_id':'confirmed','weapon_template':'untrusted'},mutation={'success':True})
        self.hub.publish('test2','2','session2',self.snapshot,3,command={'action':'impact','target_id':'3','hit_position':[1,0,0], 'shot_id':'confirmed','item_id':'99'},mutation={'success':True})
        events=self.sync()['events']
        self.assertEqual([event['weapon_id'] for event in events],['42','42'])
        self.assertTrue(all('weapon_template' not in event for event in events))
        self.hub.publish('test2','2','session2',self.snapshot,4,command={'action':'fire','origin':[0,1,0],'direction':[0,0,1], 'item_id':'99','shot_id':'rejected'},mutation={'success':False})
        self.assertNotIn('rejected',self.hub.sessions['test2']['shots'])
    def test_invalid_cursor_does_not_consume_sequence_or_update_peer_pose(self):
        with self.assertRaises(ValueError):self.sync(event_sequence='bad')
        self.assertIsNone(self.hub.sessions['test1']['pose'])
        self.assertEqual(self.sync()['sequence'],1)
    def test_connected_population_uncapped_and_event_ring_bounded(self):
        for n in range(3,66):self.hub.publish('test'+str(n),str(n),'s'+str(n),self.snapshot,1)
        self.hub.publish('extra','66','s66',self.snapshot,1)
        for n in range(300):self.hub.publish('test1','1','session1',self.snapshot,n+2,command={'action':'life'},mutation={'success':True})
        self.assertEqual(len(self.hub.events),256)
        self.assertEqual(len(self.hub.sessions),66)

if __name__=='__main__':unittest.main()
