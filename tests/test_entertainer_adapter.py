"""Exercise real route composition with a mocked native transport, never a server proof."""
import unittest
from unittest.mock import patch, Mock
from server import adapter

class EntertainerAdapterTests(unittest.TestCase):
    def test_owns_live_session_and_projects_final_native_sequence(self):
        native={'sequence':41,'mutation':{'source_kind':'core3_entertainer','character_id':'12','state':{'character_id':'12'},'mutation':{'success':True}}}
        transport=Mock();transport.active_for.return_value={'id':'owned-live'};transport.request.return_value=native
        observed=[]
        with patch.object(adapter,'LIVE_COMBAT',transport),patch.object(adapter.PERFORMANCE_HUB,'observe_native',side_effect=lambda account,oid,value: observed.append((account,oid,value.get('sequence')))):
            result=adapter.entertainer_request('owner','12','image_accept',{'session_id':'991','revision':2,'request_id':'image_test_request','recipient_accepted':True})
        outgoing=transport.request.call_args.args[2]
        self.assertEqual(outgoing['session_id'],'owned-live')
        self.assertEqual(outgoing['entertainer']['session_id'],'991')
        self.assertNotIn('recipient_accepted',outgoing['entertainer'])
        self.assertEqual(observed,[('owner','12',41)])
        self.assertEqual(result['sequence'],41)
    def test_requires_persistent_native_owner_and_valid_response(self):
        transport=Mock();transport.active_for.return_value=None
        with patch.object(adapter,'LIVE_COMBAT',transport):
            with self.assertRaises(adapter.LiveConflict):adapter.entertainer_request('owner','12','status',{})
        transport.request.assert_not_called()
        transport.active_for.return_value={'id':'owned-live'}
        transport.request.return_value={'sequence':42,'mutation':{'source_kind':'core3_entertainer','character_id':'99','state':{'character_id':'99'}}}
        with patch.object(adapter,'LIVE_COMBAT',transport):
            with self.assertRaises(ValueError):adapter.entertainer_request('owner','12','status',{})

if __name__=='__main__':unittest.main()
