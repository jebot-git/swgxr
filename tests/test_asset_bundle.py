import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from tools.assets import bundle_assets as pack
from tools.assets.restore_asset_paths import restore
from tools.client.tester_data import install


class AssetBundleTests(unittest.TestCase):
    def test_runtime_profile_rejects_windows_filename_collisions(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            assets=root/'runtime/assets'
            assets.mkdir(parents=True)
            (assets/'model.json').write_text('{}')
            (assets/'MODEL.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'duplicate archive path'):
                pack.file_list(root, profile='client-runtime')

    def test_runtime_bundle_follows_catalogs_and_installs_without_source_archives(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'source'
            for directory in ('client/scripts', 'runtime/assets/models', 'runtime/assets/textures',
                              'runtime/assets/entertainment/items', 'runtime/assets/services'):
                (root/directory).mkdir(parents=True)
            (root/'client/scripts/main.gd').write_text('var path="res://../runtime/assets/catalog.json"')
            (root/'runtime/assets/catalog.json').write_text(json.dumps({'model':'models/actor.json', 'provenance':{'source':'source.trn'}}))
            (root/'runtime/assets/source.trn').write_bytes(b'original terrain; converted geometry is already in JSON')
            (root/'runtime/assets/models/actor.json').write_text(json.dumps({'texture':'textures/color.png','catalog':str(root/'runtime/assets/catalog.json')}))
            (root/'runtime/assets/textures/color.png').write_bytes(b'fixture texture')
            (root/'runtime/assets/unused.json').write_text('{}')
            (root/'runtime/assets/entertainment/items/catalog.json').write_text('{}')
            (root/'runtime/assets/services/screens.json').write_text('{}')
            output=root/'runtime/asset_archives/runtime.zip'
            with patch.object(pack.subprocess,'check_output',return_value='test-commit\n'):
                result=pack.bundle(output,root,profile='client-runtime')
            self.assertEqual(result['tre_count'],0)
            self.assertEqual(result['files'],5)
            with zipfile.ZipFile(output) as archive:
                self.assertNotIn('runtime/assets/unused.json',archive.namelist())
                self.assertNotIn('runtime/assets/source.trn',archive.namelist())
                self.assertNotIn('restore_asset_paths.py',archive.namelist())
                self.assertFalse(any('asset_sources/' in name for name in archive.namelist()))
            destination=Path(folder)/'tester'
            receipt=install(output,destination)
            self.assertEqual(receipt['verified_files'],5)
            self.assertTrue((destination/'runtime/assets/textures/color.png').is_file())
            self.assertFalse((destination/'runtime/asset_sources').exists())
            model=json.loads((destination/'runtime/assets/models/actor.json').read_text())
            self.assertEqual(model['catalog'],str(destination/'runtime/assets/catalog.json'))
            self.assertTrue(install(output,destination)['already_installed'])

    def fixture(self, root):
        (root/'runtime/assets/planets').mkdir(parents=True)
        (root/'runtime/assets/planets/catalog.json').write_text(json.dumps({'world': str(root/'runtime/assets/world.json')}))
        (root/'runtime/assets/world.json').write_text('{"geometry": [1, 2, 3]}')
        source=root/'runtime/asset_sources/active_tre';source.mkdir(parents=True)
        rows=[]
        for name in pack.CORE3_TRE_PRIORITY:
            raw=name.encode();(source/name).write_bytes(raw)
            rows.append(dict(filename=name,sha256=hashlib.sha256(raw).hexdigest()))
        extracted=root/'runtime/asset_sources/extracted/base/tre';extracted.mkdir(parents=True)
        (source/'bottom.tre').rename(extracted/'bottom.tre')
        (source/'bottom.tre').symlink_to('../extracted/base/tre/bottom.tre')
        (source/'provenance.json').write_text(json.dumps({'archives': rows}))
        (root/'tools/assets').mkdir(parents=True)
        (root/'tools/assets/restore_asset_paths.py').write_bytes(Path('tools/assets/restore_asset_paths.py').read_bytes())
        (root/'runtime/assets/debug.log').write_text('excluded')
        return root/'runtime/asset_archives/assets.zip'

    def test_bundle_materializes_sources_and_restores_elsewhere(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)/'original';output=self.fixture(root)
            with patch.object(pack.subprocess,'check_output',return_value='test-commit\n'):
                result=pack.bundle(output,root)
            self.assertTrue(result['passed'])
            with zipfile.ZipFile(output) as archive:
                self.assertNotIn('runtime/assets/debug.log',archive.namelist())
                info=archive.getinfo('runtime/asset_sources/active_tre/bottom.tre')
                self.assertEqual(info.external_attr >> 16 & 0o170000,0o100000)
                moved=Path(folder)/'new workspace';archive.extractall(moved)
            receipt=restore(moved)
            self.assertGreater(len(receipt['rebased_metadata']),0)
            catalog=json.loads((moved/'runtime/assets/planets/catalog.json').read_text())
            self.assertEqual(catalog['world'],str(moved/'runtime/assets/world.json'))
            self.assertTrue(Path(catalog['world']).is_file())

    def test_bad_tre_hash_and_runtime_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);output=self.fixture(root)
            (root/'runtime/assets/link').symlink_to(root/'runtime/assets/world.json')
            with self.assertRaisesRegex(ValueError,'runtime asset symlink'):pack.file_list(root)
            (root/'runtime/assets/link').unlink()
            (root/'runtime/asset_sources/active_tre/default_patch.tre').write_bytes(b'changed source')
            with patch.object(pack.subprocess,'check_output',return_value='test-commit\n'):
                with self.assertRaisesRegex(ValueError,'provenance hash mismatch'):pack.bundle(output,root)
            self.assertFalse(output.exists())


if __name__=='__main__':unittest.main()
