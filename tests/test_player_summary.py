import unittest
from unittest.mock import Mock, patch
from server import adapter
from server.datapad_protocol import owner_summary


class PlayerSummaryTests(unittest.TestCase):
    def test_owner_summary_uses_existing_live_or_login_snapshot(self):
        summary = {'version': 1, 'character_id': '123', 'wallet': {'cash': 7, 'bank': 9},
                   'ham': [100, 20, 30], 'homepoints': {'residence': {'id': '0', 'status': 'unset'},
                   'cloning': {'id': '456', 'status': 'unavailable'}}}
        for variables in ({'player_summary': summary}, {'session': {'player_summary': summary}}):
            actual = owner_summary({'variables': variables}, '123')
            self.assertEqual(actual, summary)
            actual['wallet']['cash'] = 0
            self.assertEqual(summary['wallet']['cash'], 7)
        self.assertIsNone(owner_summary({'variables': {}}, '123'))
        with self.assertRaises(ValueError):
            owner_summary({'variables': {'player_summary': summary}}, '321')

    def test_live_replication_reuses_native_summary_without_another_request(self):
        summary = {'version': 1, 'character_id': '123', 'homepoints': {}}
        live = Mock()
        live.active_for.return_value = {'character_id': '123', 'id': 'owned'}
        live.request.return_value = {'native_variables': {'session': {'location': {}}, 'scene': {}},
                                     'snapshot': {'player': {'player_summary': summary}}}
        with patch.object(adapter, 'LIVE_COMBAT', live):
            result = adapter.invoke('owner', [{'action': 'selectContext', 'characterOid': 123},
                                             {'action': 'zoneInCharacter'}])
        self.assertEqual(owner_summary(result, '123'), summary)
        live.request.assert_called_once_with('owner', 'replication',
                                             {'character_id': '123', 'session_id': 'owned'})

    def test_original_summary_labels_resolve_without_changing_native_data(self):
        summary = {'version': 1, 'character_id': '123',
                   'homepoints': {'cloning': {'id': '8', 'status': 'available',
                                             'name': '@building_name:cloning_facility',
                                             'zone': 'tatooine', 'position': [1, 2, 3]}},
                   'armour': {'pieces': [{'id': '9', 'name': '@wearables_name:armor_chest',
                                         'protection_percent': {'kinetic': 45}}]}}
        with patch('server.datapad_protocol.display', side_effect=lambda t,k,f: 'Original '+k):
            actual = owner_summary({'variables': {'player_summary': summary}}, '123')
        self.assertEqual(actual['homepoints']['cloning']['name'], 'Original cloning_facility')
        self.assertEqual(actual['armour']['pieces'][0]['name'], 'Original armor_chest')
        self.assertEqual(actual['homepoints']['cloning']['position'], [1, 2, 3])
        self.assertEqual(actual['armour']['pieces'][0]['protection_percent'], {'kinetic': 45})
        self.assertTrue(summary['armour']['pieces'][0]['name'].startswith('@'))


if __name__ == '__main__':
    unittest.main()
