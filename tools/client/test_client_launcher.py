"""Desktop shortcuts and a terminal menu for the portable tester client."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import webbrowser

RELEASES = 'https://github.com/jebot-git/swgxr/releases'


def desktop_quote(value):
    # Desktop Entry Exec quoting is not shell quoting; percent is a field code.
    quoted = '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
    # The Desktop Entry string layer decodes escapes before Exec tokenization.
    return quoted.replace('\\', '\\\\')


def install_shortcuts(root):
    root = Path(root).resolve()
    entries = [('SWGXR', '--launcher'), ('SWGXR VR', ''),
               ('SWGXR Desktop', '--desktop'), ('SWGXR Updates', '--updates')]
    if os.name == 'nt':
        # Environment values avoid injecting user-controlled paths into PowerShell.
        script = '''$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$entries = @(@('SWGXR','--launcher'),@('SWGXR VR',''),@('SWGXR Desktop','--desktop'),@('SWGXR Updates','--updates'))
foreach ($entry in $entries) {
 $link = $shell.CreateShortcut((Join-Path $desktop ($entry[0]+'.lnk')))
 $link.TargetPath = Join-Path $env:SWGXR_SHORTCUT_ROOT 'python\\python.exe'
 $link.Arguments = '-I -X utf8 "' + (Join-Path $env:SWGXR_SHORTCUT_ROOT 'start_client.py') + '" ' + $entry[1]
 $link.WorkingDirectory = $env:SWGXR_SHORTCUT_ROOT
 $link.Save()
}
'''
        subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                       env=dict(os.environ, SWGXR_SHORTCUT_ROOT=str(root)), check=True)
    else:
        desktop = Path.home() / 'Desktop'
        if shutil.which('xdg-user-dir'):
            result = subprocess.run(['xdg-user-dir', 'DESKTOP'], capture_output=True, text=True, check=True)
            if result.stdout.strip(): desktop = Path(result.stdout.strip())
        applications = Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share'))) / 'applications'
        for directory in {desktop, applications}:
            directory.mkdir(parents=True, exist_ok=True)
            for name, argument in entries:
                path = directory / (name.lower().replace(' ', '-') + '.desktop')
                command = desktop_quote(sys.executable) + ' ' + desktop_quote(root/'start_client.py')
                if argument: command += ' ' + argument
                path.write_text('[Desktop Entry]\nType=Application\nName='+name+'\nExec='+command+'\nTerminal=true\nIcon=applications-games\nCategories=Game;\n', encoding='utf-8')
                path.chmod(0o755)
    print('Installed SWGXR desktop shortcuts. They point to ' + str(root), flush=True)


def menu(root):
    print('\nSWGXR test client\n1. Play VR\n2. Desktop mode (XR off)\n3. Import assets only\n4. Install client updates\n5. Install / refresh desktop shortcuts\n0. Exit')
    choice = input('Choose: ').strip()
    if choice == '4':
        try: from .update_test_client import update
        except ImportError: from update_test_client import update
        update(root); return None
    if choice == '5': install_shortcuts(root); return None
    return {'1': [], '2': ['--desktop'], '3': ['--import-only']}.get(choice)
