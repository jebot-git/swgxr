import copy
import unittest
from server.profession_protocol import translate

class PlayerAccuracyTranslation(unittest.TestCase):
 def test_accuracy_never_grants_damage_or_larger_contacts(self):
  for family,kind,path in [('pistol','ranged','pistol'),('rifle','ranged','rifle'),('carbine','ranged','carbine'),('onehandmelee','melee','knife'),('twohandmelee','melee','axe'),('polearm','melee','polearm')]:
   original={'kind':kind,'template':'object/weapon/'+path+'/fixture.iff','core3':{'minDamage':30,'maxDamage':50,'idealAccuracy':20}}
   profiles=[]
   for accuracy in [-100,0,80,200,9999]:
    profile=translate(copy.deepcopy(original),{family+'_accuracy':accuracy,family+'_speed':20},[])
    self.assertEqual(profile['core3'],original['core3'])
    self.assertEqual(profile['profession']['hit_radius'],0)
    self.assertEqual(profile['profession']['range_modifier_bonus'],0)
    tuning=profile['profession'].copy();tuning.pop('accuracy');profiles.append(tuning)
   self.assertTrue(all(p==profiles[0] for p in profiles))
   self.assertGreater(profiles[0]['stance_recovery_scale'] if kind=='melee' else profiles[0]['rpm_scale'],1)
