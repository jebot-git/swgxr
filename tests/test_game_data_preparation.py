import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from tools.client import prepare_game_data as prep
from tools.client.game_data_plan import STEPS
from tools.client.iso_media import extract_cabinets

class GameDataPreparationTests(unittest.TestCase):
    def test_ambient_export_uses_bundled_revision_without_git(self):
        from tools.server.export_ambient_npcs import core_revision
        with tempfile.TemporaryDirectory() as folder:
            core=Path(folder);receipt=core/'REVISION';receipt.write_text('a'*40+'\n')
            with patch('tools.server.export_ambient_npcs.subprocess.check_output',side_effect=AssertionError('Portable export must not invoke Git')):
                self.assertEqual(core_revision(core),'a'*40)
                receipt.write_text('invalid')
                with self.assertRaisesRegex(ValueError,'Invalid bundled'):core_revision(core)

    def test_dependencies_precede_mounts(self):
        order=[name for name,_ in STEPS]
        self.assertLess(order.index('planets'),order.index('pets'))
        self.assertLess(order.index('pets'),order.index('mounts'))
        self.assertLess(order.index('population_sources'),order.index('pets'))
        self.assertLess(order.index('combat_assets'),order.index('mobile_audio'))
        self.assertLess(order.index('space_effects'),order.index('space_audio'))
        self.assertLess(order.index('animation_messages'),order.index('player_equipment'))
        self.assertIn('--all-equipment-races',dict(STEPS)['player_equipment'])
        self.assertIn('--wearable-items',dict(STEPS)['player_equipment'])

    def test_asset_fingerprint_ignores_only_non_asset_changes(self):
        from tools.client.package_data_preparation import asset_signature, compatible_recipes
        files={'tools/assets/convert.py':'a'*64,'server/catalog.py':'b'*64,
               'server/remote_gateway.py':'c'*64,'server/GROUND_COMBAT_INTEGRATION.md':'d'*64,
               'tools/client/prepare_game_data.py':'e'*64}
        changed=dict(files, **{'server/remote_gateway.py':'f'*64,
                              'server/GROUND_COMBAT_INTEGRATION.md':'0'*64,
                              'tools/client/prepare_game_data.py':'1'*64})
        self.assertEqual(asset_signature(files),asset_signature(changed))
        with tempfile.TemporaryDirectory() as temporary:
            old=Path(temporary)/'recipe.json'
            signature=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()
            old.write_text(json.dumps(dict(files=files,signature=signature)))
            self.assertEqual(compatible_recipes(changed,[old]),[signature])
            for key in ('tools/assets/convert.py','server/catalog.py','tools/client/game_data_plan.py'):
                new=dict(changed,**{key:'2'*64})
                self.assertNotEqual(asset_signature(files),asset_signature(new))
                self.assertEqual(compatible_recipes(new,[old]),[])
            old.write_text(json.dumps(dict(files=files,signature='invalid')))
            self.assertEqual(compatible_recipes(changed,[old]),[])

    def test_equivalent_upgrade_and_repeat_launch_never_stage_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);bundle=root/'engine/data-preparation';bundle.mkdir(parents=True)
            source_signature=hashlib.sha256(json.dumps([],sort_keys=True).encode()).hexdigest()
            recipe=dict(signature='new',compatible_recipes=['old'],files={},asset_signature='same-assets')
            (bundle/'recipe.json').write_text(json.dumps(recipe))
            installed=root/'runtime/assets/catalog.json';installed.parent.mkdir(parents=True);installed.write_text('{}')
            before=installed.stat().st_mtime_ns
            receipt=root/'GAME_DATA_RECEIPT.json'
            receipt.write_text(json.dumps(dict(signature='old:'+source_signature,recipe='old',workspace=root.as_posix(),ready=True)))
            with patch.object(prep,'REQUIRED',['catalog.json']),patch.object(prep,'collect_sources',return_value=({},dict(archives=[]))),patch.object(prep.shutil,'disk_usage',side_effect=AssertionError('Must not stage or convert current data')):
                for _ in range(2):
                    result=prep.prepare(root)
                    self.assertEqual(result['signature'],'new:'+source_signature)
                    self.assertEqual(installed.stat().st_mtime_ns,before)
                    self.assertFalse((root/'runtime/preparation').exists())
                # Missing prepared data must invalidate even an equivalent recipe.
                installed.unlink()
                with self.assertRaisesRegex(AssertionError,'Must not stage'):
                    prep.prepare(root)
                installed.write_text('{}')
                # New source media must not inherit a previous conversion receipt.
                with patch.object(prep,'collect_sources',return_value=({},dict(archives=[{'sha256':'changed'}]))):
                    with self.assertRaisesRegex(AssertionError,'Must not stage'):
                        prep.prepare(root)

    def test_bad_and_conflicting_archives_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'a.tre').write_bytes(b'not TRE')
            with self.assertRaisesRegex(ValueError,'Unsupported TRE'):prep.tre_files(root)
            (root/'a.tre').write_bytes(b'EERT5000a');(root/'nested').mkdir();(root/'nested/a.tre').write_bytes(b'EERT5000b')
            with self.assertRaisesRegex(ValueError,'Conflicting duplicate'):prep.tre_files(root)

    def test_iso_bounds_and_signature(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);iso=root/'invalid.iso';iso.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError,'outside image'):extract_cabinets(iso,root/'output')
            data=bytearray(18*2048);start=16*2048;data[start:start+7]=b'\x01CD001\x01';struct.pack_into('<H',data,start+128,2048)
            struct.pack_into('<I',data,start+158,99);struct.pack_into('<I',data,start+166,2048);iso.write_bytes(data)
            with self.assertRaisesRegex(ValueError,'outside image'):extract_cabinets(iso,root/'output')

    def test_failed_conversion_preserves_assets_and_resumes_completed_step(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);bundle=root/'engine/data-preparation';bundle.mkdir(parents=True)
            first=bundle/'first.py';first.write_text("from pathlib import Path\np=Path('counter');p.write_text(str(int(p.read_text())+1) if p.exists() else '1')\n")
            second=bundle/'second.py';second.write_text('raise SystemExit(9)\n')
            files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [first,second]}
            (bundle/'recipe.json').write_text(json.dumps({'signature':'fixture','files':files}))
            assets=root/'runtime/assets';assets.mkdir(parents=True);(assets/'keep').write_text('original')
            sources=({}, {'archives':[]})
            with patch.object(prep,'collect_sources',return_value=sources),patch.object(prep.shutil,'disk_usage',return_value=type('Usage',(),{'free':100*1024**3})()):
                for _ in range(2):
                    with self.assertRaisesRegex(ValueError,'failed at second'):
                        prep.prepare(root,steps=[('first',['first.py']),('second',['second.py'])])
                self.assertEqual((root/'runtime/preparation/workspace/counter').read_text(),'1')
                self.assertEqual((assets/'keep').read_text(),'original')
                self.assertFalse((root/'GAME_DATA_RECEIPT.json').exists())
                second.write_text('modified without checksum update')
                with self.assertRaisesRegex(ValueError,'checksum mismatch'):prep.prepare(root)

    def test_rebase_preserves_json_and_apostrophes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);path=root/'asset.json';old=Path('/old install');new=Path('/new user\'s install')
            path.write_text(json.dumps({'path':str(old/'runtime/assets/model.json')}))
            prep.rebase_assets(root,old,new)
            self.assertEqual(json.loads(path.read_text())['path'],str(new/'runtime/assets/model.json'))

if __name__=='__main__':unittest.main()
