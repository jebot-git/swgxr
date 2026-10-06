"""Ranger route authority using mocked transport; native mechanics have separate proof."""
import unittest
from unittest.mock import Mock, patch

from server import adapter


def native_snapshot(oid='12'):
    inventory = {'source_kind': 'core3_inventory', 'character_id': oid,
                 'items': [], 'inventory': {'id': '99'},
                 'containers': [{'id': '99', 'depth': 0, 'capacity': 80,
                                 'occupied': 0, 'direct_count': 0, 'item_ids': []}]}
    return {'source_kind': 'core3_scout', 'character_id': oid,
            'state': {'character_id': oid, 'inventory': inventory, 'ranger': {}},
            'mutation': {'success': True, 'charges_consumed': 1}}


class RangerAdapterTests(unittest.TestCase):
    def test_requires_retained_owned_session(self):
        transport = Mock()
        transport.active_for.return_value = None
        actions = [('ranger_status', {}), ('conceal', {'item_id': '44'}),
                   ('rescue', {'target_id': '45'}), ('area_track', {'track_type': 'animal'})]
        with patch.object(adapter, 'LIVE_COMBAT', transport), patch.object(adapter, 'invoke') as fallback:
            for action, detail in actions:
                with self.subTest(action=action), self.assertRaises(adapter.LiveConflict):
                    adapter.scout_request('owner', '12', action,
                                          dict(position=[0, 0, 0], request_id='ranger_test_123', **detail))
        transport.request.assert_not_called()
        fallback.assert_not_called()

    def test_exact_kit_and_physical_target_without_client_authority(self):
        transport = Mock()
        transport.active_for.return_value = {'id': 'owned-session'}
        transport.request.return_value = {'mutation': native_snapshot(), 'scout_attributes': {}}
        with patch.object(adapter, 'LIVE_COMBAT', transport):
            result = adapter.scout_request('owner', '12', 'conceal', {
                'position': [0, 0, 0], 'item_id': '44', 'target_id': '45',
                'hand_position': [1, 1, 0], 'request_id': 'ranger_test_123',
                'live_session_id': 'owned-session', 'duration': 99999,
                'camouflage': 99999, 'free': True, 'charges_consumed': 0})
        account, action, payload = transport.request.call_args.args
        self.assertEqual((account, action, payload['session_id']), ('owner', 'scout', 'owned-session'))
        command = payload['scout']
        self.assertEqual(command['item_id'], '44')
        self.assertEqual(command['target_id'], '45')
        self.assertEqual(command['hand_position'], [1, 1, 0])
        self.assertTrue({'duration', 'camouflage', 'free', 'charges_consumed'}.isdisjoint(command))
        self.assertEqual(result['mutation']['charges_consumed'], 1)

    def test_foreign_snapshot_cannot_confirm_action(self):
        transport = Mock()
        transport.active_for.return_value = {'id': 'owned-session'}
        transport.request.return_value = {'mutation': native_snapshot('13')}
        with patch.object(adapter, 'LIVE_COMBAT', transport), self.assertRaises(ValueError):
            adapter.scout_request('owner', '12', 'ranger_status', {'position': [0, 0, 0]})


if __name__ == '__main__':
    unittest.main()
