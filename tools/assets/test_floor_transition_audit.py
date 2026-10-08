#!/usr/bin/env python3
"""Verify conservative geometry classifications used by the read-only audit."""
import unittest
import numpy as np
from audit_floor_transitions import hits, closed_edge_crossings, terrain_handoffs, portal_corridors


def square(slope=0.):
    vertices = np.array([[-2., -2. * slope, -2.], [2., 2. * slope, -2.], [2., 2. * slope, 2.], [-2., -2. * slope, 2.]])
    return [(dict(id=0, edge_flags=[0, 0, 1], portal_ids=[-1]*3), vertices[[0, 1, 2]]),
            (dict(id=1, edge_flags=[1, 0, 0], portal_ids=[-1]*3), vertices[[0, 2, 3]])]


class FloorTransitionAuditTest(unittest.TestCase):
    def test_wall_across_sloped_floor_is_candidate(self):
        wall = np.array([[[0., -.1, -1.], [0., 3., -1.], [0., 3., 1.]], [[0., -.1, -1.], [0., 3., 1.], [0., -.1, 1.]]])
        found = hits(square(.2), wall)
        self.assertTrue(found)
        self.assertTrue(all(h['supported_both_sides'] for h in found))

    def test_boundary_wall_is_not_interior_clearance_candidate(self):
        wall = np.array([[[2., -.1, -2.], [2., 3., -2.], [2., 3., 2.]], [[2., -.1, -2.], [2., 3., 2.], [2., -.1, 2.]]])
        self.assertEqual(hits(square(), wall), [])

    def test_normal_outer_edges_have_no_two_sided_support(self):
        self.assertEqual(closed_edge_crossings(square()), [])

    def test_internal_closed_edge_is_reported(self):
        floor = square()
        floor[0][0]['edge_flags'][2] = 0
        found = closed_edge_crossings(floor)
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0]['floor_triangle'], found[0]['edge']), (0, 2))

    def test_open_ramp_to_fallthrough_is_terrain_handoff(self):
        solid = dict(id=1, neighbors=[2, -1, -1], edge_flags=[1, 0, 0], portal_ids=[-1]*3)
        ramp = np.array([[-2., 0., 0.], [2., 0., 0.], [0., 1., 2.]])
        source = [solid, dict(id=2, fallthrough=True)]
        found = terrain_handoffs([(solid, ramp)], source)
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0]['terrain_to_ramp_toe'])
        self.assertTrue(found[0]['neighbor_fallthrough'])
        self.assertAlmostEqual(found[0]['inward_slope'], .5)
        self.assertLess(found[0]['local_capsule_overlap_center'][2], 0.)

    def test_portal_and_closed_edges_are_not_terrain_handoffs(self):
        solid = dict(id=1, neighbors=[-1]*3, edge_flags=[1, 0, 0], portal_ids=[0, -1, -1])
        ramp = np.array([[-2., 0., 0.], [2., 0., 0.], [0., 1., 2.]])
        self.assertEqual(terrain_handoffs([(solid, ramp)], [solid]), [])
        solid['portal_ids'][0] = -1
        for flag in (0, 2, 3):
            solid['edge_flags'][0] = flag
            self.assertEqual(terrain_handoffs([(solid, ramp)], [solid]), [])

    def test_portal_corridor_uses_only_connected_solid_floor(self):
        a = np.array([[-1., 0., 0.], [1., 0., 0.], [1., 0., -2.]])
        b = np.array([[-1., 0., 0.], [1., 0., -2.], [-1., 0., -2.]])
        floor = [(dict(id=0, neighbors=[-1, -1, 1], edge_flags=[1, 0, 1], portal_ids=[0, -1, -1]), a),
                 (dict(id=1, neighbors=[0, -1, -1], edge_flags=[1, 1, 0], portal_ids=[-1]*3), b),
                 (dict(id=2, neighbors=[-1]*3, edge_flags=[1]*3, portal_ids=[-1]*3), a + [0, 0, -5])]
        portal = dict(id=7, floor_portal_index=0, passable=True, vertices=[-1., 0., 0., -1., 3., 0., 1., 3., 0., 1., 0., 0.])
        result = portal_corridors(floor, [portal], np.eye(4), np.empty((0, 3, 3)))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['connected_triangles'], [0, 1])
        self.assertAlmostEqual(max(abs(v) for span in result[0]['contiguous_portal_span'] for v in span), 2.)

    def test_portal_without_floor_root_has_no_corridor(self):
        portal = dict(id=0, floor_portal_index=0, passable=True, vertices=[-1., 0., 0., -1., 3., 0., 1., 3., 0.])
        self.assertEqual(portal_corridors(square(), [portal], np.eye(4), np.empty((0, 3, 3))), [])

    def test_other_storey_wall_is_excluded(self):
        wall = np.array([[[0., 5., -1.], [0., 8., -1.], [0., 8., 1.]]])
        self.assertEqual(hits(square(), wall), [])


if __name__ == '__main__':
    unittest.main()
