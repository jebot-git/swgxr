"""Portable launcher checks: run on Linux or Windows with Python 3.10+ and Tk."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from server import client_release_protocol as protocol
from tools.client.launcher_platform import default_install_dir, host_target, installation_lock
from tools.client.package_launcher import package
from tools.client.patcher import Patcher


class Platforms(unittest.TestCase):
    def test_host_and_install_defaults(self):
        for system, machine, target in [('Windows','AMD64','windows-x86_64'),('Linux','x86_64','linux-x86_64')]:
            with patch('platform.system',return_value=system),patch('platform.machine',return_value=machine):
                self.assertEqual(host_target(),target)
        with patch('platform.machine',return_value='arm64'), self.assertRaises(ValueError):host_target()
        with patch.dict(os.environ,{'LOCALAPPDATA':'user data','XDG_DATA_HOME':'linux data'}):
            self.assertEqual(default_install_dir('windows-x86_64'),Path('user data/swgxr'))
            self.assertEqual(default_install_dir('linux-x86_64'),Path('linux data/swgxr'))

    def test_exclusive_lock_across_processes_and_release(self):
        with tempfile.TemporaryDirectory() as temp:
            lock=Path(temp)/'lock'
            code='from tools.client.launcher_platform import installation_lock; import sys\nwith installation_lock(sys.argv[1]): pass'
            with installation_lock(lock):
                result=subprocess.run([sys.executable,'-c',code,str(lock)],capture_output=True)
                self.assertNotEqual(result.returncode,0)
                self.assertIn(b'Another launcher or client',result.stderr)
            self.assertEqual(subprocess.run([sys.executable,'-c',code,str(lock)],capture_output=True).returncode,0)

    def test_archives_are_self_contained_and_target_specific(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); ca=root/'public.pem';ca.write_text('TEST PUBLIC CERTIFICATE')
            for target in protocol.PLATFORMS:
                windows=target.startswith('windows')
                output=root/(target+('.zip' if windows else '.tar.gz'))
                with patch('tools.client.package_launcher.Transport'):
                    package(output,'https://server.test',ca,target=target)
                if windows:
                    with zipfile.ZipFile(output) as archive:files={n:archive.read(n) for n in archive.namelist()}
                else:
                    with tarfile.open(output) as archive:
                        files={m.name:archive.extractfile(m).read() for m in archive.getmembers() if m.isfile()}
                        self.assertEqual(archive.getmember('swgxr-launcher/launch.sh').mode&0o111,0o111)
                files={k.removeprefix('swgxr-launcher/'):v for k,v in files.items()}
                self.assertEqual(set(files),{'launcher.py','patcher.py','launcher_platform.py','client_release_protocol.py','launcher.json','server-ca.pem','START-HERE.txt','launch.cmd' if windows else 'launch.sh'})
                config=json.loads(files['launcher.json'])
                self.assertEqual(config['platform'],target)
                self.assertEqual(config['channel'],'testing-'+target.replace('_','-'))
                self.assertEqual(files['server-ca.pem'],ca.read_bytes())
                # Verify bundled fallback imports without any repository on sys.path.
                isolated=root/target;isolated.mkdir()
                for name,raw in files.items():(isolated/name).write_bytes(raw)
                result=subprocess.run([sys.executable,'-I','-c',
                    'import sys; sys.path.insert(0,sys.argv[1]); import launcher, patcher; print("BOOTSTRAP_OK")',str(isolated)],capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(b'BOOTSTRAP_OK',result.stdout)
            ca.write_text('PRIVATE KEY')
            with patch('tools.client.package_launcher.Transport'),self.assertRaises(ValueError):
                package(root/'bad.zip','https://server.test',ca,target='windows-x86_64')


class TargetPayloads(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'install with spaces'

    def fixture(self,target):
        chunks={};rows=[]
        for name,raw in {protocol.PLATFORMS[target]:b'fixture engine', 'client/project.godot':b'config_version=5\n',
                         'runtime/assets/sample.json':b'{"path":"@@SWGXR_ROOT@@/runtime/assets/sample.bin"}'}.items():
            key=protocol.digest(raw);chunks[key]=raw
            rows.append(dict(path=name,size=len(raw),sha256=key,chunks=[key],executable=name.startswith('engine/'),relocate=name.endswith('.json')))
        channel='testing-'+target.replace('_','-')
        manifest=protocol.manifest(dict(schema=1,platform=target,channel=channel,version='fixture',sequence=1,files=rows,total_bytes=sum(row['size'] for row in rows)))
        raw=protocol.encode(manifest);key=protocol.digest(raw);chunks[key]=raw
        descriptor=protocol.encode(dict(schema=1,manifest_sha256=key,manifest_size=len(raw),version='fixture',sequence=1))
        class Transport:
            session=dict(token='x'*43);origin='https://server.test';ca='public.pem'
            def fetch(self,path,maximum):
                if path=='/patch/v1/channels/'+channel:return descriptor
                return chunks[path.removeprefix('/patch/v1/blobs/')]
        return Transport(),manifest

    def test_both_targets_install_relocate_and_launch_arguments(self):
        for target,engine in protocol.PLATFORMS.items():
            with self.subTest(target=target):
                transport,manifest=self.fixture(target)
                patcher=Patcher(self.root/target,transport,manifest['channel'],target=target)
                seen=[]
                def run(args,**kwargs):
                    self.assertEqual(Path(args[0]).name,Path(engine).name)
                    self.assertEqual(args[args.index('--rendering-driver')+1],'vulkan')
                    self.assertEqual(args[args.index('--rendering-method')+1],'forward_plus')
                    self.assertEqual(args[args.index('--xr-mode')+1],'off')
                    profile=Path(next(a.split('=',1)[1] for a in args if a.startswith('--connection-profile=')))
                    self.assertEqual(json.loads(profile.read_text())['launcher_session'],transport.session)
                    self.assertNotIn(transport.session['token'],' '.join(args));seen.append(profile)
                    raise OSError('Fixture process failure')
                with patcher.lock():
                    installed=patcher.update()
                    self.assertTrue((installed/engine).is_file())
                    self.assertEqual(json.loads((installed/'runtime/assets/sample.json').read_text())['path'],installed.as_posix()+'/runtime/assets/sample.bin')
                    with patch('tools.client.patcher.subprocess.run',side_effect=run),self.assertRaises(OSError):patcher.launch(desktop=True)
                self.assertEqual(len(seen),1);self.assertFalse(seen[0].exists())

    def test_mismatched_target_rejected_before_payload_install(self):
        transport,manifest=self.fixture('linux-x86_64')
        patcher=Patcher(self.root,transport,manifest['channel'],target='windows-x86_64')
        with patcher.lock(),self.assertRaisesRegex(ValueError,'platform mismatch'):patcher.update()
        self.assertIsNone(patcher.current());self.assertFalse(list((self.root/'versions').iterdir()))

    def test_windows_manifest_requires_windows_engine(self):
        _,manifest=self.fixture('windows-x86_64')
        manifest['files'][0]['path']='engine/godot'
        with self.assertRaisesRegex(ValueError,'runtime or project missing'):protocol.manifest(manifest)


if __name__=='__main__':unittest.main()
