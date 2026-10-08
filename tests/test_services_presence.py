import unittest
from server.services_presence import PresenceHub


class PresenceTests(unittest.TestCase):
    def setUp(self):
        self.time = 100.0
        self.hub = PresenceHub(lambda: self.time)
        self.tokens = {}
        self.sequences = {'1': 0, '2': 0}
        for oid in self.sequences:
            self.tokens[oid] = self.hub.register('account' + oid, oid, {
                'position': [0, 0, 0], 'zone': 'tatooine', 'cell_id': '0', 'name': oid})['token']

    def pose(self, oid, **changes):
        self.sequences[oid] += 1
        payload = dict(sequence=self.sequences[oid], position=[0, 0, 0],
                       hand=dict(position=[0, 1, 0], grip=True, tracked=True), wallet_held=oid == '1')
        payload.update(changes)
        return self.hub.update('account' + oid, oid, self.tokens[oid], payload)

    def shake(self):
        self.pose('1'); self.pose('2')
        self.time += 0.3
        self.pose('2')
        return self.pose('1')

    def test_mutual_contact_authorizes_one_explicit_amount(self):
        response = self.shake()
        self.assertTrue(response['peers'][0]['handshake_authorized'])
        first = self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.assertEqual(first, self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5))
        for key, amount in [('payment_002', 5), ('payment_001', 6)]:
            with self.assertRaises(ValueError):
                self.hub.authorize_payment('account1', '1', '2', key, amount)

    def test_no_payment_without_dwell_or_wallet(self):
        self.pose('1'); self.pose('2')
        with self.assertRaises(ValueError):
            self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.time += 0.3; self.pose('1', wallet_held=False); self.pose('2')
        with self.assertRaises(ValueError):
            self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)

    def test_handshake_binds_all_currencies(self):
        self.shake()
        amount = (5, {'imperial': 0, 'rebel': 20})
        first = self.hub.authorize_payment('account1', '1', '2', 'payment_001', amount)
        self.assertEqual(first, self.hub.authorize_payment('account1', '1', '2', 'payment_001', amount))
        for changed in ((5, {'imperial': 0, 'rebel': 21}), (6, {'imperial': 0, 'rebel': 20})):
            with self.assertRaises(ValueError):
                self.hub.authorize_payment('account1', '1', '2', 'payment_001', changed)

    def test_lost_tracking_or_distance_blocks_issued_proof(self):
        self.shake()
        self.pose('2', hand=dict(position=[0, 1, 0], grip=True, tracked=False))
        with self.assertRaises(ValueError):
            self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.pose('2', position=[4, 0, 0], hand=dict(position=[4, 1, 0], grip=True, tracked=True))
        with self.assertRaises(ValueError):
            self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)

    def test_authentication_sequence_and_reach(self):
        self.pose('1')
        payload = dict(sequence=1, position=[0, 0, 0], hand=dict(position=[0, 1, 0], grip=True, tracked=True), wallet_held=True)
        for account, token in [('wrong', self.tokens['1']), ('account1', 'wrong')]:
            with self.assertRaises(ValueError): self.hub.update(account, '1', token, payload)
        with self.assertRaises(ValueError): self.hub.update('account1', '1', self.tokens['1'], payload)
        with self.assertRaises(ValueError): self.pose('1', hand=dict(position=[0, 4, 0], grip=True, tracked=True))

    def test_pose_and_authentication_expiry(self):
        self.shake(); self.time += 2
        with self.assertRaises(ValueError): self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.time += 120
        with self.assertRaises(ValueError): self.pose('1')

    def test_different_cells_do_not_touch(self):
        self.hub.register('account2', '2', dict(position=[0, 0, 0], cell_id='99'))
        self.assertEqual(self.shake()['peers'], [])

    def test_new_handshake_requires_release(self):
        self.shake(); self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.time += 0.3; self.pose('1'); self.pose('2')
        with self.assertRaises(ValueError): self.hub.authorize_payment('account1', '1', '2', 'payment_002', 5)
        self.pose('1', hand=dict(position=[0, 1, 0], grip=False, tracked=True))
        self.shake()
        self.hub.authorize_payment('account1', '1', '2', 'payment_002', 5)

    def test_cell_transition_invalidates_handshake_until_native_refresh(self):
        self.shake()
        with self.assertRaises(ValueError): self.pose('1', building_id='100', cell_index=1)
        with self.assertRaises(ValueError): self.hub.authorize_payment('account1', '1', '2', 'payment_001', 5)
        self.assertEqual(self.hub.proofs, {})
        self.hub.register('account1', '1', dict(position=[0, 0, 0], building_id='100', cell_index=1, cell_id='101'))
        self.assertEqual(self.pose('1', building_id='100', cell_index=1)['peers'], [])

    def test_reconnect_can_resume_sequence_without_replaying_old_pose(self):
        self.pose('1')
        entry = self.hub.register('account1', '1', dict(position=[0, 0, 0], cell_id='0'))
        self.assertEqual(entry['sequence_floor'], 1)
        self.assertEqual(entry['token'], self.tokens['1'])


if __name__ == '__main__': unittest.main()
