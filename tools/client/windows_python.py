"""Package the pinned official CPython embeddable runtime for Windows testers."""
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = '3.13.16'
FILENAME = 'python-3.13.16-embed-amd64.zip'
URL = 'https://www.python.org/ftp/python/3.13.16/' + FILENAME
# Published at https://www.python.org/downloads/release/python-31316/
SHA256 = '97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297'


def verified_archive(cache=None):
    cache = Path(cache) if cache else ROOT / 'runtime/toolchains'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / FILENAME
    if not archive.exists():
        temporary = archive.with_suffix('.partial')
        try:
            with urllib.request.urlopen(URL, timeout=60) as source, temporary.open('wb') as destination:
                shutil.copyfileobj(source, destination)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != SHA256:
                raise ValueError('Official embedded Python SHA256 mismatch')
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError('Cached embedded Python SHA256 mismatch')
    return archive


def install(destination, cache=None):
    archive = verified_archive(cache)
    destination = Path(destination)
    destination.mkdir(exist_ok=False)
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            # The official distribution is flat. Reject unexpected path layouts.
            if '/' in entry.filename or '\\' in entry.filename or entry.filename in ('.', '..'):
                raise ValueError('Unexpected embedded Python archive path')
        source.extractall(destination)
    for name in ('python.exe', 'python313.dll', 'python313.zip', 'LICENSE.txt', 'python313._pth'):
        if not (destination / name).is_file():
            raise ValueError('Incomplete embedded Python runtime: ' + name)
    # Only the standard library, runtime DLL directory and our launcher modules.
    # Keep site/user packages, registry paths and PYTHONPATH disabled.
    (destination / 'python313._pth').write_text('python313.zip\n.\n..\n', encoding='utf-8')
    report = dict(version=VERSION, platform='windows-x86_64', url=URL, sha256=SHA256,
                  executable='python/python.exe', isolated=True, system_python_required=False,
                  license='python/LICENSE.txt')
    (destination / 'SWGXR-PYTHON.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def write_launchers(output):
    for name, argument in (('play-vr.cmd', ''), ('play-desktop.cmd', '--desktop '), ('import-data.cmd', '--import-only ')):
        script = ('@echo off\nsetlocal\ncd /d "%~dp0"\n'
                  'if not exist "%~dp0python\\python.exe" (\n'
                  '  echo Bundled Python is missing. Extract the complete Windows client ZIP again.\n'
                  '  pause\n  exit /b 2\n)\n'
                  '"%~dp0python\\python.exe" -I -X utf8 "%~dp0start_client.py" ' + argument + '%*\n'
                  'set "SWGXR_EXIT=%ERRORLEVEL%"\n'
                  'if not "%SWGXR_EXIT%"=="0" pause\nexit /b %SWGXR_EXIT%\n')
        (Path(output) / name).write_bytes(script.replace('\n', '\r\n').encode('ascii'))
