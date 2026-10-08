#!/usr/bin/env python3
"""Package Linux or Windows tester launchers without building a client payload."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from tools.client.patcher import Transport
from tools.client.launcher_platform import SUPPORTED
from server.client_release_protocol import channel_name

WINDOWS_START = r'''@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    set "PYTHON=py -3"
) else (
    set "PYTHON=python"
)
%PYTHON% -c "import sys, tkinter; assert sys.version_info >= (3,10)" >nul 2>nul
if errorlevel 1 (
    echo Install Python 3.10 or later ^(64-bit^) with Tcl/Tk and the Python launcher.
    echo Then run launch.cmd again. See START-HERE.txt.
    pause
    exit /b 1
)
%PYTHON% launcher.py %*
if errorlevel 1 (
    echo Launcher failed. See the error above.
    pause
    exit /b 1
)
'''
LINUX_START = '''#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
if ! python3 -c 'import sys, tkinter; assert sys.version_info >= (3,10)' 2>/dev/null; then
    echo 'Install Python 3.10+ and Tk (Debian/Ubuntu: python3-tk); see START-HERE.txt.' >&2
    exit 1
fi
exec python3 launcher.py "$@"
'''


def package(output, origin, ca, channel=None, target='linux-x86_64'):
    if target not in SUPPORTED: raise ValueError('Unsupported launcher target')
    channel = channel or 'testing-' + target.replace('_','-')
    ca=Path(ca).resolve(); Transport(origin,ca); channel_name(channel)
    if b'PRIVATE KEY' in ca.read_bytes(): raise ValueError('CA file must not contain a private key')
    output=Path(output)
    windows=target=='windows-x86_64'
    if not str(output).endswith('.zip' if windows else '.tar.gz'):
        raise ValueError('Use .zip for Windows or .tar.gz for Linux')
    repo=Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory() as temporary:
        folder=Path(temporary)/'swgxr-launcher';folder.mkdir()
        for name in ('launcher.py','patcher.py','launcher_platform.py'):
            shutil.copy2(repo/'tools/client'/name,folder/name)
        shutil.copy2(repo/'server/client_release_protocol.py',folder/'client_release_protocol.py')
        shutil.copyfile(ca,folder/'server-ca.pem')
        (folder/'launcher.json').write_text(json.dumps(dict(base_url=origin,ca_certificate='server-ca.pem',channel=channel,platform=target),indent=2)+'\n',encoding='utf-8')
        start = folder / ('launch.cmd' if windows else 'launch.sh')
        start.write_bytes(WINDOWS_START.replace('\n','\r\n').encode('ascii') if windows else LINUX_START.encode('ascii'))
        start.chmod(0o755)
        instructions = (
            'Install Python 3.10+ (64-bit) with Tcl/Tk and the Python launcher.\n'
            'Extract ALL files to a local folder, then double-click launch.cmd.\n'
            'Installation: %LOCALAPPDATA%\\swgxr (or launch.cmd --install-dir "PATH").\n'
            'Use your personal Windows account; administrator privileges are not needed.\n'
            'Enable Windows long paths for large client asset trees before installing the client.\n'
            'Select a working OpenXR runtime (for example SteamVR) before pressing Play VR.\n'
            if windows else
            'Install Python 3.10+ and Tk (Debian/Ubuntu: python3-tk).\n'
            'Extract all files, then run ./launch.sh.\n'
            'Installation: $XDG_DATA_HOME/swgxr or ~/.local/share/swgxr.\n'
            'Override with ./launch.sh --install-dir "PATH".\n'
            'Start SteamVR or WiVRn with OpenXR configured before pressing Play VR.\n'
        )
        (folder/'START-HERE.txt').write_text(
            'CoreCU / SWGXR tester launcher - ' + target + '\n\n' + instructions + '\n'
            'Create an account with your invitation, or sign in. Install / Update, then Play VR.\n'
            'The launcher stays on the desktop. A Vulkan-capable GPU is required for the client.\n'
            'The client build is delivered separately through channel: ' + channel + '\n'
            'Until a build is published, Install / Update reports that no client build is available.\n'
            'This package includes no game assets, engine, passwords or invitations.\n'
            'Passwords and invitations are never saved; sign in again after restarting.\n'
            'Obtain this bootstrap and its bundled public CA directly from the administrator.\n'
            'The first installation downloads the client; later updates reuse verified chunks.\n'
            'Allow space for cached chunks, old releases and the new release (at least 3x payload).\n'
            'Do not remove cache/versions while the launcher or game is running.\n'
            'Client diagnostics: logs/client.log under the installation folder.\n',encoding='utf-8')
        output.parent.mkdir(parents=True,exist_ok=True)
        if windows:
            with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(folder.iterdir()): archive.write(path,folder.name+'/'+path.name)
        else:
            with tarfile.open(output,'w:gz') as archive:archive.add(folder,arcname=folder.name)
    return output

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--origin',required=True);p.add_argument('--ca',type=Path,required=True)
    p.add_argument('--channel',help='Default: testing-<target>')
    p.add_argument('--target',choices=SUPPORTED,default='linux-x86_64')
    print(package(**vars(p.parse_args())))
