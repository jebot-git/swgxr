import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from tools.client import test_client_launcher as launcher


class LauncherTests(unittest.TestCase):
    def test_shortcuts_retarget_and_quote_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            with patch.object(Path, 'home', return_value=home), patch.object(launcher.shutil, 'which', return_value=None), patch.dict(os.environ, {'XDG_DATA_HOME': str(home/'share')}):
                for folder in ['first install', 'new "build" $%']:
                    root = home/folder
                    launcher.install_shortcuts(root)
                    for directory in [home/'Desktop', home/'share/applications']:
                        files=list(directory.glob('*.desktop'))
                        self.assertEqual(len(files),4)
                        entry=(directory/'swgxr-desktop.desktop').read_text()
                        self.assertIn(launcher.desktop_quote(root/'start_client.py')+' --desktop',entry)
                        self.assertIn('Terminal=true',entry)
                        self.assertTrue((directory/'swgxr.desktop').stat().st_mode & 0o111)

    def test_desktop_entry_exec_survives_real_glib_parsing(self):
        try:
            from gi.repository import Gio
        except ImportError:
            self.skipTest('GObject desktop entry parser unavailable')
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            root = home / 'space " dollar $ percent % slash \\ path'
            root.mkdir()
            (root/'start_client.py').write_text('from pathlib import Path\nPath(__file__).with_name("launched").write_text("ok")\n')
            with patch.object(Path, 'home', return_value=home), patch.object(launcher.shutil, 'which', return_value=None), patch.dict(os.environ, {'XDG_DATA_HOME': str(home/'share')}):
                launcher.install_shortcuts(root)
            entry = home/'Desktop/swgxr.desktop'
            entry.write_text(entry.read_text().replace('Terminal=true','Terminal=false'))
            app = Gio.DesktopAppInfo.new_from_filename(str(entry))
            app.launch([], None)
            for _ in range(30):
                if (root/'launched').exists(): break
                time.sleep(.05)
            self.assertTrue((root/'launched').exists())

    def test_menu_updates_does_not_launch_engine(self):
        with patch('builtins.input',return_value='4'), patch('tools.client.update_test_client.update') as updater:
            self.assertIsNone(launcher.menu(Path('/client')))
            updater.assert_called_once_with(Path('/client'))

    def test_explicit_desktop_and_import_choices(self):
        for choice, result in [('2',['--desktop']),('3',['--import-only']),('0',None)]:
            with patch('builtins.input',return_value=choice):
                self.assertEqual(launcher.menu(Path('/client')),result)
