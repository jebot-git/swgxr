"""Route authority checks use a mocked transport; native game proof is separate."""
import unittest
from unittest.mock import Mock,patch
from server import adapter

class CreatureHandlerAdapterTests(unittest.TestCase):
    def test_requires_retained_owned_native_session(self):
        transport=Mock();transport.active_for.return_value=None
        with patch.object(adapter,'LIVE_COMBAT',transport),patch.object(adapter,'invoke') as fallback:
            for action,fields in [('ch_status',{}),('ch_tame',{'target_id':'44','request_id':'tame_test_0001'}),('ch_embolden',{'request_id':'buff_test_0001'})]:
                with self.subTest(action=action),self.assertRaises(adapter.LiveConflict):
                    adapter.vehicles_request('owner','12',action,fields)
        transport.request.assert_not_called();fallback.assert_not_called()

    def test_original_target_and_owned_session_reach_only_native_command(self):
        native={'source_kind':'core3_vehicles','character_id':'12','state':{'character_id':'12','creature_handler':{'candidates':[]}},'mutation':{'success':True,'pending':True}}
        transport=Mock();transport.active_for.return_value={'id':'owned-live'}
        transport.request.return_value={'sequence':9,'mutation':native,'session_id':'owned-live','character_id':'12'}
        with patch.object(adapter,'LIVE_COMBAT',transport):
            out=adapter.vehicles_request('owner','12','ch_tame',{'live_session_id':'owned-live','target_id':'44','request_id':'tame_test_0001','force':True,'adult':True,'skills':['outdoors_creaturehandler_master'],'gesture_seconds':10000,'success':True})
        account,action,payload=transport.request.call_args.args
        self.assertEqual((account,action,payload['session_id']),('owner','vehicles','owned-live'))
        self.assertEqual(payload['vehicles'],{'action':'ch_tame','target_id':'44','request_id':'tame_test_0001'})
        self.assertTrue(out['mutation']['pending']);self.assertNotIn('learned',out['mutation'])

    def test_foreign_actor_snapshot_cannot_confirm_pet_creation(self):
        transport=Mock();transport.active_for.return_value={'id':'owned-live'}
        transport.request.return_value={'mutation':{'source_kind':'core3_vehicles','character_id':'13','state':{'character_id':'13'},'mutation':{'success':True}}}
        with patch.object(adapter,'LIVE_COMBAT',transport):
            with self.assertRaises(ValueError):adapter.vehicles_request('owner','12','ch_status',{})

if __name__=='__main__':unittest.main()
