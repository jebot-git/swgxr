import unittest
from server.scout_protocol import command
from server.remote_gateway import POST

class BioEngineerSamplingProtocol(unittest.TestCase):
    def body(self, **kwargs):
        return dict(position=[10, 2, 20], hand_position=[10.5, 3.4, 20], target_id='123', request_id='dna_sample_001', **kwargs)

    def test_authenticated_gateway_routes(self):
        self.assertIn('/scout/sample_dna', POST)
        self.assertIn('/scout/discard_sample_dna', POST)

    def test_sampling_target_and_hand_preserved(self):
        result = command('sample_dna', self.body())
        self.assertEqual(result['target_id'], '123')
        self.assertEqual(result['hand_position'], [10.5, 3.4, 20])

    def test_rejects_missing_or_invalid_target(self):
        for value in [None, '', 123, '0', '-1', str(2**64), 'arbitrary']:
            data = self.body(); data['target_id'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): command('sample_dna', data)

    def test_rejects_missing_nonfinite_or_distant_hand(self):
        for value in [None, [0, 0], [True, 3, 20], ['10', 3, 20], [float('nan'), 3, 20], [10, float('inf'), 20], [14, 2, 20], [10, 6, 20]]:
            data = self.body(); data['hand_position'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): command('sample_dna', data)

    def test_each_mutation_needs_receipt(self):
        for action in ['sample_dna', 'discard_sample_dna']:
            data = self.body(); data.pop('request_id')
            with self.assertRaises(ValueError): command(action, data)

    def test_discard_has_no_sampling_target(self):
        result = command('discard_sample_dna', self.body())
        self.assertNotIn('target_id', result)
        self.assertNotIn('hand_position', result)

if __name__ == '__main__': unittest.main()
