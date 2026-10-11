import unittest
from pathlib import Path
from tools.server.export_ambient_npcs import herald_rows

class HeraldPlacements(unittest.TestCase):
    def test_named_coordinates_and_planet_filter(self):
        text = '''heraldList = {
          { planet="tatooine", template="herald_lorne_prestar", x=3376.1, z=5, y=-4786, angle=117, cell=0, destX=999 },
          { planet="naboo", template="other", x=1, z=2, y=3, angle=4, cell=5 }
        }'''
        rows = list(herald_rows(text, 'tatooine'))
        self.assertEqual(rows, [(['herald_lorne_prestar', 0, 3376.1, 5, -4786, 117, 0, 'neutral'], 2)])
    def test_multi_destination_list(self):
        text = 'multiDestHeraldList={{planet="tatooine",template="herald_tatooine_errik",x=3380.6,z=5,y=-4498,angle=160,cell=0,dest1Cost=60}}'
        rows = list(herald_rows(text, 'tatooine', 'multiDestHeraldList'))
        self.assertEqual(rows[0][0][:7], ['herald_tatooine_errik', 0, 3380.6, 5, -4498, 160, 0])
    def test_nonliteral_source_is_not_guessed(self):
        with self.assertRaises(ValueError):
            list(herald_rows('heraldList={{planet="tatooine",template="npc",x=dynamic(),z=5,y=2,angle=0,cell=0}}', 'tatooine'))

if __name__ == '__main__': unittest.main()
