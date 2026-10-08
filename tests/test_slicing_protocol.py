import copy
import unittest

from server.remote_gateway import POST
from server.services_protocol import command
from server.slicing_protocol import ACTIONS


class SlicingProtocolTests(unittest.TestCase):
    def begin(self):
        return dict(request_id='slice_request_001', tool_id='42', target_id='43',
                    target_kind='item', tool_position=[1, 1, 1],
                    target_position=[1, 1, 1], anchor_position=[1, 1.5, 1],
                    heading_radians=0)

    def complete(self):
        return dict(request_id='slice_request_002', attempt_id='native_attempt_001',
                    paths=[dict(color=0, cells=[[0, 0, 0], [1, 0, 0], [2, 0, 0]]),
                           dict(color=1, cells=[[0, 1, 0], [1, 1, 0], [2, 1, 0]])])

    def test_remote_actions_and_receipts(self):
        self.assertTrue(all('/services/' + action in POST for action in ACTIONS))
        self.assertNotIn('attempt_id', command('slicing_status', {}))
        for action in ('slicing_begin', 'slicing_complete', 'slicing_cancel'):
            with self.subTest(action=action), self.assertRaises(ValueError):
                command(action, {})
        self.assertEqual(command('slicing_cancel', self.complete())['attempt_id'], 'native_attempt_001')

    def test_owned_item_and_terminal_contact_fields(self):
        source = self.begin()
        self.assertEqual(command('slicing_begin', source)['target_position'], [1, 1, 1])
        terminal = dict(source, target_kind='terminal')
        del terminal['target_position']
        self.assertEqual(command('slicing_begin', terminal)['target_kind'], 'terminal')
        for field, value in [('tool_id', '0'), ('target_id', str(2**64)),
                             ('target_kind', 'player'), ('heading_radians', float('nan')),
                             ('heading_radians', True), ('tool_position', [0, True, 0]),
                             ('target_position', [0, 0]), ('anchor_position', [0, 2049, 0])]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                command('slicing_begin', dict(source, **{field: value}))

    def test_complete_accepts_only_bounded_disjoint_adjacent_paths(self):
        source = self.complete()
        result = command('slicing_complete', source)
        self.assertEqual(result['paths'], source['paths'])
        result['paths'][0]['cells'][0][0] = 4
        self.assertEqual(source['paths'][0]['cells'][0][0], 0)
        invalid = []
        for cells in ([[0, 0, 0], [2, 0, 0]], [[0, 0, 0], [1, 1, 0]],
                      [[0, 0, 0], [1, 0, 0], [0, 0, 0]],
                      [[0, 0, 0], [True, 0, 0]], [[4, 0, 0], [5, 0, 0]]):
            data = copy.deepcopy(source)
            data['paths'][0]['cells'] = cells
            invalid.append(data)
        duplicate = copy.deepcopy(source)
        duplicate['paths'][1]['color'] = 0
        invalid.append(duplicate)
        crossing = copy.deepcopy(source)
        crossing['paths'][1]['cells'] = [[1, 1, 0], [1, 0, 0], [1, 0, 1]]
        invalid.append(crossing)
        for paths in ([], source['paths'][:1], source['paths'] * 3, None):
            invalid.append(dict(source, paths=paths))
        for data in invalid:
            with self.subTest(data=data), self.assertRaises(ValueError):
                command('slicing_complete', data)

    def test_native_authority_cannot_be_supplied_by_client(self):
        result = command('slicing_complete', dict(self.complete(), success=True,
                         bonus=500, solution='trust-me', tier=5, remaining_seconds=999))
        self.assertFalse({'success', 'bonus', 'solution', 'tier', 'remaining_seconds'} & result.keys())
        for attempt in ('', 'bad', 'x' * 65, None, 1):
            with self.subTest(attempt=attempt), self.assertRaises(ValueError):
                command('slicing_complete', dict(self.complete(), attempt_id=attempt))


if __name__ == '__main__':
    unittest.main()
