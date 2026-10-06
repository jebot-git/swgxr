"""Owned retained sessions and the authenticated faction route boundary."""
import unittest
from unittest.mock import Mock, patch

from server import adapter, remote_gateway


class GcwAdapter(unittest.TestCase):
    def test_mutations_cannot_use_short_lived_native_login_fallback(self):
        live = Mock()
        live.active_for.return_value = None
        actions = [('recruiter_join', {'terminal_id': '99'}),
                   ('recruiter_promote', {'terminal_id': '99', 'expected_rank': 0}),
                   ('recruiter_status_toggle', {'terminal_id': '99', 'expected_status': 1}),
                   ('recruiter_purchase', {'terminal_id': '99', 'reward_id': 'imperial:uniforms:boots_s14'}),
                   ('contraband_answer', {'scan_id': '77', 'accept': False})]
        with patch.object(adapter, 'LIVE_COMBAT', live), patch.object(adapter, 'invoke') as fallback:
            for action, fields in actions:
                with self.subTest(action=action), self.assertRaises(adapter.LiveConflict):
                    adapter.services_request('owner', '12', action,
                        dict(position=[0, 0, 0], request_id='faction_test_123', **fields))
        fallback.assert_not_called()
        live.request.assert_not_called()

    def test_native_reward_purchase_keeps_exact_owner_session_and_no_price_authority(self):
        live = Mock()
        live.active_for.return_value = {'id': 'owned-session'}
        live.request.return_value = {'mutation': {'source_kind': 'core3_services', 'character_id': '12',
            'player': {}, 'mutation': {'success': True}}, 'service_attributes': {}}
        with patch.object(adapter, 'LIVE_COMBAT', live), \
                patch.object(adapter.SERVICES_PRESENCE, 'register', return_value={}), \
                patch.object(adapter.VOICE_STATE, 'publish'):
            result = adapter.services_request('owner', '12', 'recruiter_purchase', {
                'position': [0, 0, 0], 'terminal_id': '99', 'request_id': 'faction_test_123',
                'reward_id': 'imperial:uniforms:boots_s14', 'live_session_id': 'owned-session',
                'free': True, 'cost': 0, 'faction_points': 99999, 'rank': 20})
        account, action, payload = live.request.call_args.args
        self.assertEqual((account, action, payload['session_id'], payload['character_id']),
                         ('owner', 'services', 'owned-session', '12'))
        self.assertEqual(payload['service']['reward_id'], 'imperial:uniforms:boots_s14')
        self.assertTrue({'free', 'cost', 'faction_points', 'rank'}.isdisjoint(payload['service']))
        self.assertTrue(result['mutation']['success'])

    def test_foreign_native_reply_cannot_confirm_faction_membership(self):
        live = Mock()
        live.active_for.return_value = {'id': 'owned-session'}
        live.request.return_value = {'mutation': {'source_kind': 'core3_services', 'character_id': '13'}}
        with patch.object(adapter, 'LIVE_COMBAT', live), self.assertRaises(ValueError):
            adapter.services_request('owner', '12', 'recruiter_join', {
                'position': [0, 0, 0], 'terminal_id': '99', 'request_id': 'faction_test_123'})

    def test_gateway_exposes_only_requested_choices_not_scan_or_gcw_admin_actions(self):
        for action in ('recruiter_join', 'recruiter_promote', 'recruiter_status_toggle', 'recruiter_purchase', 'contraband_answer'):
            self.assertIn('/services/' + action, remote_gateway.POST)
        for action in ('contraband_start', 'crackdown_spawn', 'faction_set', 'faction_grant', 'recruiter_overt'):
            self.assertNotIn('/services/' + action, remote_gateway.POST)


if __name__ == '__main__':
    unittest.main()
