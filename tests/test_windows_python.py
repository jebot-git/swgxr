import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from tools.client import windows_python


class WindowsPythonTests(unittest.TestCase):
    def test_corrupt_cached_runtime_is_rejected_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/windows_python.FILENAME).write_bytes(b'not the official runtime')
            with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                windows_python.install(root/'python', cache=root)
            self.assertFalse((root/'python').exists())

    def test_isolated_runtime_keeps_license_and_app_import_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/windows_python.FILENAME
            with zipfile.ZipFile(archive,'w') as out:
                for name in ('python.exe','python313.dll','python313.zip','LICENSE.txt','python313._pth'):
                    out.writestr(name,b'fixture')
            digest=hashlib.sha256(archive.read_bytes()).hexdigest()
            with patch.object(windows_python,'SHA256',digest), patch.object(windows_python,'install_tk',return_value={'bundled':True}):
                report=windows_python.install(root/'python',cache=root)
            self.assertFalse(report['system_python_required'])
            self.assertEqual((root/'python/LICENSE.txt').read_bytes(),b'fixture')
            self.assertEqual((root/'python/python313._pth').read_text().splitlines(),['python313.zip','.','..'])


if __name__=='__main__':unittest.main()
