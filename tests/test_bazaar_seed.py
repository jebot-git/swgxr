"""Offline stock plan, exact-item resume and original-stat provisioning safeguards."""
from pathlib import Path
from contextlib import contextmanager
import json
import re
import tempfile
import unittest
from unittest.mock import patch
from tools.server.seed_bazaar import ROOT, TAG, plan, units, lua_prepare, listing_decision, save, apply


class BazaarSeed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = plan()

    def test_every_original_planet_has_bounded_existing_bazaar_stock(self):
        from server.planets import SUPPORTED_PLANETS
        data = self.manifest
        self.assertEqual(tuple(p['planet'] for p in data['planets']), SUPPORTED_PLANETS)
        self.assertEqual(len(data['items']), 17)
        self.assertEqual(len(units(data)), 24)
        self.assertEqual(len({u['key'] for u in units(data)}), 24)
        self.assertTrue(all(p['building_id'] == '0' and p['cell_index'] == 0 and int(p['terminal_id']) > 0
                            for p in data['planets']))
        self.assertEqual(len({p['account'] for p in data['planets']}), 10)
        self.assertTrue(all(0 < i['price'] <= 75 for i in data['items']))

    def test_provision_uses_exact_default_templates_and_persistent_slots(self):
        planet = self.manifest['planets'][0]
        owner = dict(id='42', name=planet['name'], account=planet['account'])
        function, source = lua_prepare(self.manifest, planet, owner)
        self.assertIn('function Tests:'+function+'()', source)
        self.assertIn('getSceneObject(42)', source)
        self.assertIn('giveItem(inv,row[2],-1)', source)
        self.assertIn('readScreenPlayData(p,namespace,row[1])', source)
        self.assertIn('writeScreenPlayData(p,namespace,row[1],id)', source)
        self.assertIn('getTemplateObjectPath()~="object/tangible/terminal/terminal_bazaar.iff"', source)
        self.assertIn(TAG, source)
        for setter in ('setUseCount', 'setMinDamage', 'setMaxDamage', 'setAttackSpeed',
                       'setQuality', 'setSkillPoints', 'awardSkill', 'setCustomObjectName'):
            self.assertNotIn(setter, source)

    def test_all_stock_owner_names_pass_original_active_name_filters(self):
        source = (ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/managers/name/name_manager.lua').read_text()
        block = source.split('oldFilterWords = {', 1)[1].split('\n}', 1)[0]
        patterns = [json.loads('"'+p+'"') for p in re.findall(
            r'^\s*\{\s*"((?:\\.|[^"\\])*)"\s*,\s*DECLINED_[A-Z_]+\s*\}', block, re.M)]
        self.assertEqual(len(patterns), 634)
        names = [p['name'] for p in self.manifest['planets']]
        self.assertEqual(len(set(names)), 10)
        for name in names:
            self.assertRegex(name, r'^[A-Za-z]{3,15}$')
            self.assertFalse(any(re.search(pattern, name, re.I) for pattern in patterns), name)

    def test_owner_mismatch_cannot_generate_admin_provisioning(self):
        planet = self.manifest['planets'][0]
        for owner in (dict(id='42', name='Existingplayer', account=planet['account']),
                      dict(id='42', name=planet['name'], account='blux'),
                      dict(id='42); bad()', name=planet['name'], account=planet['account'])):
            with self.subTest(owner=owner), self.assertRaises(ValueError):
                lua_prepare(self.manifest, planet, owner)

    def test_existing_sold_and_active_listings_never_create_duplicate_items(self):
        item = dict(id='101', owner_id='42', template='object/weapon/test.iff')
        for status in (0, 1, 2, 3):
            self.assertEqual(listing_decision(item, dict(owner_id='42', status=status), {}), 'existing')
        with self.assertRaises(ValueError):
            listing_decision(item, dict(owner_id='43'), {})
        self.assertEqual(listing_decision(item, None, {}), 'unresolved')

    def test_only_exact_unlisted_owned_template_can_be_sold(self):
        item = dict(id='101', owner_id='42', template='object/weapon/test.iff')
        self.assertEqual(listing_decision(item, None, {'101': {'template': item['template']}}), 'sell')
        with self.assertRaises(ValueError):
            listing_decision(item, None, {'101': {'template': 'object/weapon/other.iff'}})

    def test_ledger_is_private_and_atomic(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'ledger.json'
            save(path, {'tag': TAG})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertFalse(path.with_suffix('.tmp').exists())

    def test_apply_resumes_native_item_ids_after_sale_and_retrieval(self):
        manifest = dict(self.manifest, planets=self.manifest['planets'][:1])
        planet = manifest['planets'][0]

        class Fixture:
            def __init__(self):
                self.created = self.sold = self.stopped = self.started = 0
                self.location = dict(zone='tatooine', position=[0, 0, 0], building_id='0', cell_index=0)
                self.inventory = {str(100+i): dict(id=str(100+i), template=u['template'])
                                  for i, u in enumerate(units(manifest))}
                self.listings = {}

            @contextmanager
            def screenplay(self, function, source):
                yield

            def call(self, function):
                self.location = dict(zone=planet['planet'], position=planet['position'], building_id='0', cell_index=0)
                return 'ready:'+','.join(str(100+i) for i in range(24))

            def request(self, path, data=None):
                if path.startswith('/characters?'):
                    return dict(characters=[])
                if path == '/characters':
                    self.created += 1
                    return dict(character=dict(id='42', name=planet['name']))
                if path == '/enter':
                    return dict(source_location=self.location)
                if path == '/session/start':
                    self.started += 1
                    return dict(session_id='session'+str(self.started))
                if path == '/session/update':
                    return {}
                if path == '/combat/session/stop':
                    self.stopped += 1
                    return {}
                if path == '/inventory/status':
                    return dict(items=list(self.inventory.values()))
                if path == '/services/open':
                    return dict(state=dict(terminal=dict(listings=list(self.listings.values()), has_more=False)))
                if path == '/services/bazaar_sell':
                    assert 'position' not in data  # Native range, no client teleport.
                    ident = data['item_id']
                    self.inventory.pop(ident)
                    self.listings[ident] = dict(id=ident, owner_id='42')
                    self.sold += 1
                    return dict(mutation=dict(listing_id=ident))
                raise AssertionError(path)

        native = Fixture()
        with tempfile.TemporaryDirectory() as directory, patch('tools.server.seed_bazaar.plan', return_value=manifest):
            ledger = Path(directory)/'ledger.json'
            self.assertTrue(apply(manifest, native, ledger)['applied'])
            self.assertEqual((native.created, native.sold, native.started, native.stopped), (1, 24, 2, 2))
            # Sold and collected stock no longer appears in either inventory or market.
            native.listings.clear()
            self.assertTrue(apply(manifest, native, ledger)['applied'])
            self.assertEqual((native.created, native.sold), (1, 24))
            self.assertEqual(len(json.loads(ledger.read_text())['planets'][planet['planet']]), 24)


if __name__ == '__main__':
    unittest.main()
