import struct
import unittest
from server.unarmed_protocol import player_stats, resolve, unarmed_snapshot

def baseline(strength=300, quickness=250, modifiers=None):
    ham=[500,strength,300,500,quickness,250,500,200,200]
    first=struct.pack('<IIII9iII',0,0,9,1,*ham,0,1)
    entries=modifiers or {}
    fourth=struct.pack('<ffIIII',1,1,0,1,len(entries),1)
    for name,(value,bonus) in entries.items():
        data=name.encode('ascii')
        fourth+=struct.pack('<BH',0,len(data))+data+struct.pack('<ii',value,bonus)
    return {'type':0x4352454f,'baseline1':first.hex(),'baseline4':fourth.hex()}

class UnarmedProtocolTests(unittest.TestCase):
    def test_real_layout_and_signed_bonus(self):
        stats=player_stats(baseline(modifiers={'unarmed_damage':(85,5),'unarmed_speed':(15,-2)}))
        self.assertEqual(stats,{'strength':300,'quickness':250,
                                'skill_mods':{'unarmed_damage':90,'unarmed_speed':13},
                                'unarmed_damage':90,'unarmed_speed':13})
        profile=resolve(stats,'42')
        self.assertEqual(profile['power'],152.5)
        self.assertEqual(profile['stance_recovery'],138)
        self.assertEqual(profile['character_id'],'42')
        self.assertNotIn('capacity',profile)
        self.assertNotIn('rpm',profile)

    def test_brawler_and_teras_kasi_source_modifiers(self):
        # Read the supplied skills table, not copied profession-name heuristics.
        from server.character_protocol import assets
        from tools.assets.character_formats import datatable
        rows={r['NAME']:r for r in datatable(assets().read('datatables/skill/skills.iff'))}
        base=resolve(player_stats(baseline()))
        mods={}
        for skill in ['combat_brawler_novice','combat_unarmed_novice','combat_unarmed_master']:
            for entry in rows[skill]['SKILL_MODS'].split(','):
                name,value=entry.split('=')
                mods[name]=(mods.get(name,(0,0))[0]+int(value),0)
            current=resolve(player_stats(baseline(modifiers=mods)))
            self.assertGreater(current['power'],base['power'])
            self.assertGreater(current['stance_recovery'],base['stance_recovery'])
            base=current

    def test_attributes_are_independent(self):
        base=resolve(player_stats(baseline()))
        strength=resolve(player_stats(baseline(strength=500)))
        quickness=resolve(player_stats(baseline(quickness=500)))
        self.assertGreater(strength['power'],base['power'])
        self.assertEqual(strength['stance_recovery'],base['stance_recovery'])
        self.assertGreater(quickness['stance_recovery'],base['stance_recovery'])
        self.assertEqual(quickness['power'],base['power'])

    def test_missing_foreign_truncated_baselines_fail_closed(self):
        with self.assertRaises(ValueError): player_stats({'baseline1':'00'})
        record=baseline();record['baseline4']=record['baseline4'][:-2]
        with self.assertRaises(ValueError): player_stats(record)
        with self.assertRaises(ValueError): unarmed_snapshot({'variables':{'replication':{'objects':{'o42':baseline()}}}},'99')

    def test_invalid_and_bounded_stats(self):
        for value in [float('nan'),float('inf'),'100']:
            with self.assertRaises(ValueError): resolve({'strength':value,'quickness':0,'unarmed_damage':0,'unarmed_speed':0})
        stats={'strength':99999,'quickness':99999,'unarmed_damage':99999,'unarmed_speed':99999}
        self.assertEqual(resolve(stats)['power'],400)
        self.assertEqual(resolve(stats)['stance_recovery'],400)

if __name__=='__main__':unittest.main()
