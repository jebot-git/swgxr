import io
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from tools.client import update_test_client as updater

class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name);self.root=self.base/'installed';self.root.mkdir()
        self.stage=self.base/'stage';self.stage.mkdir()
        for folder,value in [(self.root,b'old'),(self.stage,b'new')]:
            for name in ['engine/godot','client/main.gd','start_client.py','server.json']:
                p=folder/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value)
            files=[dict(path=str(p.relative_to(folder)),bytes=p.stat().st_size,sha256=updater.sha(p)) for p in folder.rglob('*') if p.is_file()]
            (folder/'PACKAGE.json').write_text(json.dumps(dict(target='linux-x86_64',runnable=True,files=files)))
        (self.root/'runtime/assets').mkdir(parents=True);(self.root/'runtime/assets/original').write_bytes(b'private')
        self.package=json.loads((self.stage/'PACKAGE.json').read_text())
    def archive(self):
        path=self.base/'client.tar.gz'
        with tarfile.open(path,'w:gz') as out:out.add(self.stage,arcname='client-package')
        return path
    def test_verified_install_preserves_assets_settings_and_backup(self):
        extracted=self.base/'extract';extracted.mkdir()
        files=updater.unpack(self.archive(),extracted)
        package=updater.validate(extracted,'linux-x86_64',files)
        receipt=updater.install(self.root,extracted,package,'v2026.10.10-test.11','abc')
        self.assertEqual((self.root/'client/main.gd').read_bytes(),b'new')
        self.assertEqual((self.root/'server.json').read_bytes(),b'old')
        self.assertEqual((self.root/'runtime/assets/original').read_bytes(),b'private')
        self.assertEqual((Path(receipt['backup'])/'engine/godot').read_bytes(),b'old')
    def test_corrupt_file_and_platform_fail_validation(self):
        files={str(p.relative_to(self.stage)) for p in self.stage.rglob('*') if p.is_file()}
        with self.assertRaises(ValueError):updater.validate(self.stage,'windows-x86_64',files)
        (self.stage/'client/main.gd').write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError,'checksum'):updater.validate(self.stage,'linux-x86_64',files)
    def test_tar_links_and_traversal_rejected(self):
        for name,link in [('client/../../escape',False),('client/link',True),('client/runtime/assets/private',False)]:
            path=self.base/'bad.tar.gz'
            with tarfile.open(path,'w:gz') as out:
                row=tarfile.TarInfo(name);row.size=1
                if link:row.type=tarfile.SYMTYPE;row.linkname='/tmp/escape';row.size=0
                out.addfile(row,io.BytesIO(b'x'))
            with self.assertRaises(ValueError):updater.unpack(path,self.base/'bad')
        self.assertFalse((self.base/'escape').exists())
    def test_zip_duplicate_and_links_rejected(self):
        path=self.base/'bad.zip'
        with zipfile.ZipFile(path,'w') as out:
            row=zipfile.ZipInfo('client/link');row.external_attr=0o120777<<16;out.writestr(row,'/tmp/escape')
        with self.assertRaises(ValueError):updater.unpack(path,self.base/'bad')
    def test_failure_rolls_back_all_replaced_files(self):
        replace=updater.os.replace
        def fail(source,target):
            if Path(source)==self.stage/'engine/godot':raise OSError('simulated locked executable')
            return replace(source,target)
        with patch.object(updater.os,'replace',side_effect=fail),self.assertRaises(OSError):updater.install(self.root,self.stage,self.package,'v2026.10.10-test.11','abc')
        for name in ['engine/godot','client/main.gd','start_client.py']:self.assertEqual((self.root/name).read_bytes(),b'old')
        self.assertFalse((self.root/'UPDATE_RECEIPT.json').exists())
        self.assertEqual(json.loads((self.root/'.updates/transaction.json').read_text())['state'],'rolled_back')
    def test_linked_installation_rejected_before_changes(self):
        (self.root/'client/main.gd').unlink();(self.root/'client/main.gd').symlink_to(self.stage/'client/main.gd')
        with self.assertRaisesRegex(ValueError,'Linked'):updater.install(self.root,self.stage,self.package,'v2026.10.10-test.11','abc')
        self.assertEqual((self.root/'engine/godot').read_bytes(),b'old')
    def test_exclusive_lock(self):
        with updater.installation_lock(self.root),self.assertRaises(ValueError):
            with updater.installation_lock(self.root):pass
    def test_bad_download_hash_does_not_touch_installation(self):
        archive=self.archive();checks=self.base/'checks';checks.write_text('0'*64+'  client.tar.gz\n')
        def download(url,path,maximum=0):shutil.copy2(archive if url=='archive' else checks,path)
        release=('v2026.10.10-test.11',{'name':'client.tar.gz','browser_download_url':'archive'},{'browser_download_url':'checks'})
        with patch.object(updater,'discover',return_value=release),patch.object(updater,'download',side_effect=download),self.assertRaisesRegex(ValueError,'archive checksum'):
            updater.update(self.root)
        self.assertEqual((self.root/'engine/godot').read_bytes(),b'old')
    def test_safe_paths(self):
        for name in ['../a','/a','a/../b','a//b','C:/a','a\\b','']:
            with self.assertRaises(ValueError):updater.safe_name(name)

if __name__=='__main__':unittest.main()
