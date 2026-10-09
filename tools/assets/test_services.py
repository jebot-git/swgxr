#!/usr/bin/env python3
"""Source service export invariants; optionally audit the local original assets."""
import hashlib
import json
import unittest
from pathlib import Path
from prepare_services import ROOT, SHUTTLES, WALLET, service_kind

class ServicesTests(unittest.TestCase):
    def test_original_trainer_coverage(self):
        path=ROOT/'runtime/assets/services/trainers.json'
        if not path.exists(): self.skipTest('Original trainer audit unavailable')
        data=json.loads(path.read_text())
        self.assertFalse(data['failures'])
        from server.profession_scope import TRAINERS, BASIC_TRAINERS
        self.assertEqual(set(data['trainers']),{'trainer_'+p for p in TRAINERS})
        self.assertEqual(sum(row['mobile'] in {'trainer_'+p for p in BASIC_TRAINERS} for row in data['placements']),51)
        ids={row['id'] for row in data['placements']}
        self.assertEqual(len(ids),len(data['placements']))
        for name,trainer in data['trainers'].items():
            self.assertEqual(len(trainer['templates']),4 if name == 'trainer_bountyhunter' else 3)
            self.assertEqual(len(trainer['skill_ids']),18)
            self.assertEqual(trainer['skill_ids'][0],trainer['profession']+'_novice')
            self.assertTrue(trainer['greeting'] and trainer['name'])
            self.assertTrue(set(trainer['placement_ids']) <= ids)
        for row in data['placements']:
            self.assertTrue(row['appearance_available'])
            self.assertIn(row['template'],data['trainers'][row['mobile']]['templates'])
        for filename,digest in data['provenance']['files_sha256'].items():
            self.assertEqual(hashlib.sha256(Path(filename).read_bytes()).hexdigest(),digest)

    def test_service_classification_includes_starship_terminals(self):
        self.assertEqual(service_kind('object/tangible/terminal/shared_terminal_bank.iff'),'bank')
        self.assertEqual(service_kind('object/tangible/terminal/terminal_bazaar.iff'),'bazaar')
        self.assertEqual(service_kind('object/tangible/terminal/shared_terminal_mission_scout.iff'),'mission')
        self.assertEqual(service_kind('object/tangible/crafting/station/shared_weapon_station.iff'),'crafting')
        self.assertEqual(service_kind('object/tangible/terminal/shared_terminal_space.iff'),'starship')
        self.assertEqual(service_kind('object/static/structure/general/shared_data_terminal_s1.iff'),'')

    def test_original_bazaar_hierarchy(self):
        path=ROOT/'runtime/assets/services/bazaar_categories.json'
        if not path.exists(): self.skipTest('Original bazaar category export unavailable')
        tree=json.loads(path.read_text()); nodes={n['id']:n for n in tree['nodes']}
        self.assertEqual(len(nodes),len(tree['nodes']))
        self.assertEqual(nodes[0]['label'],'All')
        self.assertEqual(nodes[0]['parent_id'],-1)
        self.assertEqual(nodes[0x2000a]['name'],'weapon_ranged_pistol')
        self.assertEqual(nodes[0x2000a]['parent_id'],0x20000)
        self.assertEqual(nodes[0x2000a]['label'],'Pistol')
        for ident,node in nodes.items():
            if ident: self.assertIn(ident,nodes[node['parent_id']]['children'])
            children=[nodes[n] for n in node['children']]
            self.assertEqual(children,sorted(children,key=lambda n:(n['label'],n['id'])))
            if ident and ident&255: self.assertEqual(node['parent_id'],ident&tree['mask'])
        header=Path(tree['provenance']['types_header'])
        self.assertEqual(hashlib.sha256(header.read_bytes()).hexdigest(),tree['provenance']['types_header_sha256'])

    def test_local_source_coverage(self):
        path=ROOT/'runtime/assets/services/catalog.json'
        if not path.exists(): self.skipTest('Original user assets have not been prepared')
        data=json.loads(path.read_text())
        self.assertFalse(data['failures'])
        self.assertEqual(set(data['races']),set(SHUTTLES))
        ids=[r['id'] for r in data['static_terminals']]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertTrue(any(p['name']=='Mos Eisley Starport' for p in data['travel_points']))
        for row in data['static_terminals']:
            self.assertNotEqual(int(row['id']),0)
            self.assertEqual(row['id_kind'],'snapshot_object' if int(row['id'])>0 else 'client_layout_placement')
            self.assertEqual(row['kind'],service_kind(row['template']))
            p=row['position']; g=row['godot_position']; o=data['origin']
            for value,expected in zip(p,[g[0]+o[0],g[1]+o[1],o[2]-g[2]]): self.assertAlmostEqual(value,expected)
        for template,race in data['races'].items():
            model=json.loads((path.parent/race['body']).read_text())
            names={b['name'] for b in model['bones']}
            self.assertEqual(set(race['clips']),{'loop_ground','loop_sky','land','take_off'})
            for item in race['attachments']:
                self.assertIn(item['bone'],names)
                geometry=json.loads((path.parent/item['model']).read_text())
                self.assertTrue(geometry['surfaces'])
                for surface in geometry['surfaces']: self.assertTrue((path.parent/surface['texture']).is_file())
            for clip in race['clips'].values():
                self.assertTrue(clip['tracks']);self.assertEqual(len(clip['source_sha256']),64)
            if template.endswith('/player_transport.iff'):
                self.assertEqual(len(race['attachments']),5)
                self.assertEqual(race['door_bone'],'hold_transport_door')
        for filename,digest in data['provenance']['files_sha256'].items():
            self.assertEqual(hashlib.sha256(Path(filename).read_bytes()).hexdigest(),digest)
        inventory=json.loads((ROOT/'runtime/assets/inventory/catalog.json').read_text())
        self.assertEqual(inventory['items'][WALLET]['status'],'ready')
        self.assertEqual(inventory['service_wallet']['template'],WALLET)
        for source,entry in data['provenance']['dependencies'].items():
            self.assertEqual(len(entry['sha256']),64)
            self.assertGreater(entry['bytes'],0)

if __name__=='__main__': unittest.main()
