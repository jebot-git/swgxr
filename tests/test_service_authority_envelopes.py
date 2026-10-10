"""Read projections must retain the native revision after moving the character."""
import unittest
from unittest.mock import patch
from server import adapter
class ServiceAuthority(unittest.TestCase):
 def test_pose_mutating_projections_keep_native_envelope(self):
  native={'session_live':True,'character_id':'42','sequence':19,'mutation':{},'snapshot':{'player':{'locomotion':{'movement_revision':8}}}}
  cases=[('medic_request','medic_command','medic_snapshot'),('scout_request','scout_command','scout_snapshot'),('corpse_request',None,'corpse_snapshot')]
  for function,command,snapshot in cases:
   with self.subTest(function=function),patch.object(adapter.LIVE_COMBAT,'active_for',return_value={'id':'owned'}),patch.object(adapter.LIVE_COMBAT,'request',return_value=native),patch.object(adapter,snapshot,return_value={'ok':True}),patch.object(adapter,'check_live_error'):
    with patch.object(adapter,command or 'planet_context',return_value={}):
     result=getattr(adapter,function)('tester','42','corpses' if function=='corpse_request' else 'status',{'position':[0,0,0]})
    self.assertIs(result['live_response'],native)
    self.assertEqual(result['live_response']['snapshot']['player']['locomotion']['movement_revision'],8)
if __name__=='__main__':unittest.main()
