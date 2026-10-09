import unittest

from server.jtl_presence import JtlPresence


class JtlPresenceTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.
        self.hub = JtlPresence(lambda: self.now)

    def native(self, ship='10', cell=1, crew=('1', '2')):
        return {'space_active': True, 'ship': {'id': ship, 'player_position': [0, 0, 0],
                'cell_index': cell, 'crew': [{'id': oid, 'position': [0, 0, 0],
                'cell_index': cell, 'appearance': {'native': oid}} for oid in crew]}}

    def pose(self, sequence=1, **changes):
        value = {'sequence': sequence, 'position': [0, 0, 0], 'cell_index': 1,
                 'heading_radians': 0, 'physical_posture': 0,
                 'tracking': {'head': {'tracked': True, 'position': [0, 1.7, 0], 'rotation': [0, 0, 0, 1]}}}
        value.update(changes)
        return value

    def exchange(self, oid='1', native=None, pose=None, session='session'):
        return self.hub.exchange('account' + oid, oid, session, native or self.native(), pose)

    def test_native_roster_presents_mutual_head_and_hands(self):
        self.assertEqual(self.exchange(pose=self.pose())['crew_poses'], [])
        result = self.exchange('2', pose=self.pose())
        self.assertEqual(result['crew_pose_ttl_ms'], 750)
        peer = result['crew_poses'][0]
        self.assertEqual(peer['id'], '1')
        self.assertEqual(peer['appearance'], {'native': '1'})
        self.assertEqual(peer['tracking']['right_hand'], {'tracked': False})
        peer['tracking']['head']['position'][0] = 999
        self.assertEqual(self.exchange('2')['crew_poses'][0]['tracking']['head']['position'][0], 0)

    def test_client_cannot_publish_identity_appearance_or_authority(self):
        for name in ('id', 'appearance', 'ship_id', 'owner_id', 'crew', 'pilot_id'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.exchange(pose=self.pose(**{name: '99'}))

    def test_native_membership_and_exact_ship_and_cell_required(self):
        self.exchange(pose=self.pose())
        for native in (self.native(crew=('2',)), self.native(ship='11'), self.native(cell=2)):
            with self.subTest(native=native):
                self.assertEqual(self.exchange('2', native)['crew_poses'], [])
        contradictory = self.native()
        contradictory['ship']['crew'][0]['cell_index'] = 2
        self.assertEqual(self.exchange('2', contradictory)['crew_poses'], [])

    def test_roster_authority_overrides_cached_pose_location(self):
        self.exchange(pose=self.pose())
        native = self.native()
        native['ship']['crew'][0]['position'] = [9, 0, 0]
        self.assertEqual(self.exchange('2', native)['crew_poses'], [])

    def test_no_pose_after_ttl_or_offboard_or_remove(self):
        self.exchange(pose=self.pose())
        self.now += .751
        self.assertEqual(self.exchange('2')['crew_poses'], [])
        self.exchange(pose=self.pose(2))
        self.exchange(native={'space_active': False})
        self.assertEqual(self.exchange('2')['crew_poses'], [])
        self.exchange(pose=self.pose(3))
        self.hub.remove('ACCOUNT1')
        self.assertEqual(self.exchange('2')['crew_poses'], [])

    def test_monotonic_sequence_survives_native_and_cell_refresh(self):
        self.exchange(pose=self.pose(9))
        self.exchange()
        self.now += 1
        self.exchange(native=self.native(cell=2))
        with self.assertRaises(ValueError):
            self.exchange(native=self.native(cell=2), pose=self.pose(9, cell_index=2))
        self.exchange(native=self.native(cell=2), pose=self.pose(10, cell_index=2))
        self.exchange(pose=self.pose(1), session='replacement')

    def test_invalid_tracking_is_rejected_and_stale_pose_cleared(self):
        cases = [self.pose(position=[4, 0, 0]), self.pose(cell_index=2), self.pose(sequence=True),
                 self.pose(sequence=2**53), self.pose(heading_radians=float('nan')),
                 self.pose(physical_posture=True), self.pose(position=[float('inf'), 0, 0]),
                 self.pose(tracking={'pelvis': {'tracked': False}}),
                 self.pose(tracking={'head': {'tracked': 1}}),
                 self.pose(tracking={'head': {'tracked': True, 'position': [0, 5, 0], 'rotation': [0, 0, 0, 1]}}),
                 self.pose(tracking={'head': {'tracked': True, 'position': [0, 1, 0], 'rotation': [0, 0, 0, 2]}})]
        for bad in cases:
            with self.subTest(bad=bad):
                self.hub.remove('account1')
                self.exchange(pose=self.pose(0))
                with self.assertRaises(ValueError):
                    self.exchange(pose=bad)
                self.assertEqual(self.exchange('2')['crew_poses'], [])

    def test_untracked_transform_is_not_exposed(self):
        self.exchange(pose=self.pose(tracking={'head': {'tracked': False, 'position': [999, 999, 999]}}))
        self.assertEqual(self.exchange('2')['crew_poses'][0]['tracking']['head'], {'tracked': False})

    def test_same_ship_native_refresh_does_not_retime_old_tracking(self):
        self.exchange(pose=self.pose())
        self.now += .5
        self.exchange()
        self.now += .3
        self.assertEqual(self.exchange('2')['crew_poses'], [])

    def test_roster_bounds_and_duplicate_rejected(self):
        for crew in (('1', '1'), tuple(str(i+1) for i in range(21))):
            with self.assertRaises(ValueError):
                self.exchange(native=self.native(crew=crew))

    def test_invalid_native_refresh_and_explicit_invalidate_preserve_floor(self):
        self.exchange(pose=self.pose(9))
        with self.assertRaises(ValueError):
            self.exchange(native={'space_active': True, 'ship': {}})
        self.assertEqual(self.exchange('2')['crew_poses'], [])
        self.hub.invalidate('account1')
        with self.assertRaises(ValueError):
            self.exchange(pose=self.pose(9))
        self.exchange(pose=self.pose(10))


if __name__ == '__main__':
    unittest.main()
