import unittest
from unittest.mock import patch
from server.jtl_protocol import normalize_state

class SpaceCommunications(unittest.TestCase):
 def test_original_parameters_and_plain_text(self):
  state={'communications':[{'id':'1','kind':'message','parameters':{'file':'spacequest','stringID':'progress','DI':3,'TO':{'customName':'pirates'}}},{'id':'2','kind':'message','sender':'Patrol leader','text':r'Incoming \#ffffffhostiles'},{'id':'3','kind':'music','sound':'sound/music.snd'}]}
  with patch('server.datapad_protocol.display',return_value='Destroyed %DI %TO'):normalize_state(state)
  self.assertEqual(state['communications'][0]['text'],'Destroyed 3 pirates')
  self.assertNotIn('parameters',state['communications'][0])
  self.assertEqual(state['communications'][1]['text'],'Incoming hostiles')
  self.assertEqual(state['communications'][1]['sender'],'Patrol leader')
  self.assertEqual(state['communications'][2]['sound'],'sound/music.snd')
