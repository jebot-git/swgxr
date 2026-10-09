"""Independent security cases for the native-stage-bound crew handshake."""
import unittest

from server.services_presence import PresenceHub


class CrewHandshakeTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.
        self.hub = PresenceHub(lambda: self.now)
        self.seq, self.tokens = {}, {}
        for oid in ('1', '2', '3'):
            self.seq[oid] = 0
            self.tokens[oid] = self.hub.register('account' + oid, oid, {
                'position': [0, 0, 0], 'zone': 'tatooine', 'cell_id': '0'})['token']
        self.stage = {'id': 'launch_stage_001', 'pilot_id': '1'}
        self.hub.observe_launch_stage('account1', '1', self.stage)

    def pose(self, oid, x=0, grip=True, free=True, tracked=True, side='right', fist=False):
        self.seq[oid] += 1
        return self.hub.update('account' + oid, oid, self.tokens[oid], {
            'sequence': self.seq[oid], 'position': [0, 0, 0], 'wallet_held': False,
            'main_hand_side': side, 'hand': {'tracked': tracked, 'grip': grip, 'position': [x, 1, 0]},
            'hands': {side: {'position': [x, 1, 0], 'tracked': tracked, 'fist': fist, 'free': free}}})

    def ready(self):
        self.pose('1', -.5)
        self.pose('2', .5)
        self.pose('1')
        self.pose('2')
        self.now += .26
        result = self.pose('2')
        peer = next(row for row in result['peers'] if row['id'] == '1')
        self.assertTrue(peer['crew_handshake_ready'])
        return peer['crew_handshake_id']

    def authorize(self, key, request='crew_request_001', pilot='1', member='2', launch=None):
        return self.hub.authorize_crew_handshake('account' + member, member, pilot,
                launch or self.stage['id'], request, key)

    def test_free_handshake_needs_no_party_and_is_one_receipt(self):
        key = self.ready()
        self.assertFalse(self.authorize(key)['receipt_only'])
        self.assertTrue(self.authorize(key)['receipt_only'])
        with self.assertRaises(ValueError):
            self.authorize(key, 'second_request')
        with self.assertRaises(ValueError):
            self.authorize(key, member='3')

    def test_initial_overlap_and_pre_stage_contact_cannot_authorize(self):
        for reset in (False, True):
            with self.subTest(reset=reset):
                self.setUp()
                self.pose('1'); self.pose('2')
                if reset:
                    self.hub.observe_launch_stage('account1', '1', dict(self.stage, id='new_launch_001'))
                self.now += .3
                peer = next(row for row in self.pose('2')['peers'] if row['id'] == '1')
                self.assertFalse(peer['crew_handshake_ready'])

    def test_changed_stage_wrong_pilot_wrong_account_cannot_consume(self):
        key = self.ready()
        with self.assertRaises(ValueError): self.authorize(key, pilot='3')
        with self.assertRaises(ValueError):
            self.hub.authorize_crew_handshake('intruder', '2', '1', self.stage['id'], 'crew_request_001', key)
        self.hub.observe_launch_stage('account1', '1', dict(self.stage, id='new_launch_001'))
        with self.assertRaises(ValueError): self.authorize(key)

    def test_canceled_stage_or_expired_proof_cannot_consume(self):
        for change in ('cancel', 'stale'):
            with self.subTest(change=change):
                self.setUp(); key = self.ready()
                if change == 'cancel': self.hub.observe_launch_stage('account1', '1', None)
                else: self.now += 1.01
                with self.assertRaises(ValueError): self.authorize(key)

    def test_occupied_untracked_released_or_distant_hand_invalidates_proof(self):
        for change in ({'free': False}, {'tracked': False}, {'grip': False}, {'x': .5}):
            with self.subTest(change=change):
                self.setUp(); key = self.ready(); self.pose('2', **change)
                with self.assertRaises(ValueError): self.authorize(key)

    def test_native_cell_transition_invalidates_unconsumed_proof(self):
        key = self.ready()
        self.hub.register('account2', '2', {'position': [0, 0, 0], 'zone': 'tatooine', 'cell_id': '99'})
        with self.assertRaises(ValueError): self.authorize(key)

    def test_consumed_receipt_retry_does_not_reboard_after_cancellation(self):
        key = self.ready(); self.authorize(key)
        self.hub.observe_launch_stage('account1', '1', None)
        self.now += 2
        self.assertTrue(self.authorize(key)['receipt_only'])

    def test_wallet_and_party_proofs_do_not_substitute_crew_proof(self):
        self.hub.proofs[('2', '1')] = {'created': self.now, 'request_id': '', 'amount': None}
        self.hub.bump_proofs['a'*24] = {'pair': ('1', '2'), 'created': self.now, 'request_id': '', 'actor_id': ''}
        with self.assertRaises(ValueError): self.authorize('a'*24)

    def test_same_stage_status_refresh_does_not_arm_existing_overlap(self):
        self.pose('1'); self.pose('2')
        self.now += .3
        self.hub.observe_launch_stage('account1', '1', self.stage)
        peer = next(row for row in self.pose('2')['peers'] if row['id'] == '1')
        self.assertFalse(peer['crew_handshake_ready'])

    def test_duplicate_main_hand_positions_must_agree(self):
        key=self.ready()
        self.hub.actors['2']['hands']['right']['position']=[.5,1,0]
        with self.assertRaises(ValueError):self.authorize(key)

    def test_crew_stage_does_not_issue_party_proof_for_same_contact(self):
        self.pose('1',-.5,fist=True);self.pose('2',.5,fist=True)
        self.pose('1',fist=True);self.pose('2',fist=True);self.now+=.3
        result=self.pose('2',fist=True)
        peer=next(row for row in result['peers'] if row['id']=='1')
        self.assertFalse(peer['group_bump_ready'])
        self.assertFalse(self.hub.bump_proofs)


if __name__ == '__main__':
    unittest.main()
