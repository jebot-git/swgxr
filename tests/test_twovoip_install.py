"""Pinned dependency integrity/idempotence without network access or media."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('install_twovoip', Path(__file__).resolve().parents[1] / 'tools/client/install_twovoip.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_cached_digest_rejected_without_network(self):
        with tempfile.TemporaryDirectory() as d:
            cached=Path(d)/'archive.zip'; cached.write_bytes(b'corrupted')
            with patch.object(installer.urllib.request,'urlopen',side_effect=AssertionError('network forbidden')):
                with self.assertRaisesRegex(ValueError,'Cached dependency digest mismatch'):
                    installer.verified_download('https://example.invalid', '0'*64,cached)

    def test_verified_install_idempotent_and_modified_file_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); cache=root/'runtime/dependencies'; cache.mkdir(parents=True)
            (root/'client').mkdir()
            archive=cache/'TwoVoIP-v6.5.zip'
            with zipfile.ZipFile(archive,'w') as z:
                z.writestr('project/addons/twovoip/libs/libtwovoip.linux.template_release.x86_64.so',b'fixture binary')
                z.writestr('project/addons/twovoip/libs/libtwovoip.android.arm64.so',b'excluded')
                z.writestr('project/addons/twovoip/twovoip.gdextension',b'fixture descriptor')
            digest=hashlib.sha256(archive.read_bytes()).hexdigest()
            with patch.object(installer,'ROOT',root),patch.object(installer,'SHA256',digest),patch.object(installer,'NOTICES',{}),patch.object(installer.urllib.request,'urlopen',side_effect=AssertionError('network forbidden')):
                installer.install()
                lock=(root/'client/twovoip.lock.json').read_bytes()
                installer.install()
                self.assertEqual(lock,(root/'client/twovoip.lock.json').read_bytes())
                files=json.loads(lock)['files']
                self.assertEqual(len(files),2)
                for name,sha in files.items():
                    self.assertEqual(hashlib.sha256((root/'client/addons/twovoip'/name).read_bytes()).hexdigest(),sha)
                (root/'client/addons/twovoip/twovoip.gdextension').write_text('changed')
                with self.assertRaisesRegex(ValueError,'upstream dependency modified'):installer.install()

    def test_zip_traversal_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); cache=root/'runtime/dependencies'; cache.mkdir(parents=True)
            archive=cache/'TwoVoIP-v6.5.zip'
            with zipfile.ZipFile(archive,'w') as z:z.writestr('project/addons/twovoip/../escape',b'unsafe')
            digest=hashlib.sha256(archive.read_bytes()).hexdigest()
            with patch.object(installer,'ROOT',root),patch.object(installer,'SHA256',digest),patch.object(installer,'NOTICES',{}):
                with self.assertRaisesRegex(ValueError,'Unsafe dependency path'):installer.install()
            self.assertFalse((root/'client/addons/escape').exists())

    def test_installed_release_manifest(self):
        lockpath=installer.ROOT/'client/twovoip.lock.json'
        if not lockpath.exists():self.skipTest('Optional native dependency not installed')
        lock=json.loads(lockpath.read_text())
        self.assertEqual(lock['artifact_sha256'],installer.SHA256)
        self.assertEqual(lock['commit'],installer.COMMIT)
        for name,sha in lock['files'].items():
            self.assertEqual(hashlib.sha256((installer.ROOT/'client/addons/twovoip'/name).read_bytes()).hexdigest(),sha,name)
        self.assertEqual(len([name for name in lock['files'] if name.startswith('libs/')]),4)
        for name,notice in installer.NOTICES.items():self.assertEqual(lock['files']['notices/'+name],notice['sha256'])


if __name__=='__main__':unittest.main()
