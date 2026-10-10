from pathlib import Path
import hashlib
import json
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from tools.client import tester_data
from tools.client.package_test_client import included

class TesterData(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.base=Path(self.temp.name);self.root=self.base/'client with spaces';self.root.mkdir();self.archive=self.base/'data.zip'
 def bundle(self,entries=None,extra=None,mutate=None,symlink=None):
  entries=entries or {'runtime/assets/catalog.json':json.dumps({'source':'/original/runtime/assets/file.png','other':'unchanged'}).encode(),'runtime/asset_sources/active_tre/data.tre':b'original data'}
  manifest={'schema':1,'layout':'swgxr-assets-v2','workspace_root':'/original','source_bytes':sum(map(len,entries.values())),'files':[{'path':name,'bytes':len(value),'sha256':hashlib.sha256(value).hexdigest()} for name,value in entries.items()]}
  if mutate:mutate(manifest)
  with zipfile.ZipFile(self.archive,'w') as archive:
   for name,value in entries.items():
    if name==symlink:
     info=zipfile.ZipInfo(name);info.external_attr=(0o120777<<16);archive.writestr(info,value)
    else:archive.writestr(name,value)
   archive.writestr('ASSET_MANIFEST.json',json.dumps(manifest))
   archive.writestr('restore_asset_paths.py','raise RuntimeError("must never execute/extract")')
   for name,value in (extra or {}).items():archive.writestr(name,value)
  return manifest
 def test_verified_data_rebased_without_code_extraction_and_repeat(self):
  self.bundle();result=tester_data.install(self.archive,self.root)
  self.assertEqual(result['verified_files'],2);self.assertFalse((self.root/'restore_asset_paths.py').exists())
  data=json.loads((self.root/'runtime/assets/catalog.json').read_text());self.assertEqual(data['source'],self.root.as_posix()+'/runtime/assets/file.png');self.assertEqual(data['other'],'unchanged')
  self.assertEqual((self.root/'runtime/asset_sources/active_tre/data.tre').read_bytes(),b'original data')
  self.assertTrue(tester_data.install(self.archive,self.root)['already_installed'])
 def test_imported_assets_work_without_retaining_zip(self):
  self.bundle();tester_data.install(self.archive,self.root);self.archive.unlink()
  self.assertTrue(tester_data.ensure_data(self.root)['already_installed'])
 def test_bad_hash_rolls_back_all_data(self):
  self.bundle(mutate=lambda m:m['files'][0].update(sha256='0'*64))
  with self.assertRaisesRegex(ValueError,'SHA256'):tester_data.install(self.archive,self.root)
  self.assertFalse((self.root/'runtime/assets').exists());self.assertFalse((self.root/'ASSET_RESTORE_RECEIPT.json').exists());self.assertFalse((self.root/'.asset-import.lock').exists())
 def test_manifest_zip_mismatch_and_unlisted_files(self):
  for extra in ({'client/project.godot':b'bad'},{'runtime/assets/unlisted.json':b'{}'}):
   with self.subTest(extra=extra):
    self.bundle(extra=extra)
    with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
  self.bundle(mutate=lambda m:m['files'][0].update(bytes=1))
  with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
 def test_no_paths_or_executable_payloads_escape_data(self):
  for name in ('../outside.json','/runtime/assets/file.json','runtime/assets/../client/file.json','runtime/assets\\file.json','runtime/assets/evil.py','runtime/assets/evil.gd','runtime/assets/evil.dll','runtime/assets/evil.tscn','runtime/assets/CON.json','runtime/assets/file. json','runtime/assets/foo:bar.json','runtime/assets/.hidden.json'):
   with self.subTest(name=name):
    self.bundle(entries={name:b'{}'})
    with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
  self.assertFalse((self.base/'outside.json').exists())
 def test_symlink_and_duplicate_archive_entry(self):
  self.bundle(symlink='runtime/assets/catalog.json')
  with self.assertRaisesRegex(ValueError,'regular'):tester_data.install(self.archive,self.root)
  self.bundle(extra={'RUNTIME/ASSETS/CATALOG.JSON':b'{}'})
  with self.assertRaisesRegex(ValueError,'Duplicate'):tester_data.install(self.archive,self.root)
 def test_existing_runtime_symlink_or_data_not_overwritten(self):
  self.bundle();(self.root/'runtime').symlink_to(self.base,target_is_directory=True)
  with self.assertRaisesRegex(ValueError,'symlink'):tester_data.install(self.archive,self.root)
  (self.root/'runtime').unlink();(self.root/'runtime/assets').mkdir(parents=True)
  with self.assertRaisesRegex(ValueError,'empty'):tester_data.install(self.archive,self.root)
 def test_manifest_limits_before_extraction(self):
  self.bundle()
  with patch.object(tester_data,'MAX_BYTES',1):
   with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
  with patch.object(tester_data,'MAX_FILES',1):
   with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
  with patch.object(tester_data,'MAX_MANIFEST',1):
   with self.assertRaises(ValueError):tester_data.install(self.archive,self.root)
 def test_moved_data_folder_requires_fresh_import(self):
  self.bundle();tester_data.install(self.archive,self.root);moved=self.base/'moved';self.root.rename(moved)
  with self.assertRaisesRegex(ValueError,'different archive or package location'):tester_data.install(self.archive,moved)
 def test_dropin_requires_one_archive(self):
  with self.assertRaisesRegex(ValueError,'exactly one'):tester_data.ensure_data(self.root)
  (self.root/'data').mkdir();self.bundle();self.archive.rename(self.root/'data/test.zip');self.assertEqual(tester_data.ensure_data(self.root)['verified_files'],2)
 def test_package_filter_excludes_logs_editor_tests_builds_and_other_platform(self):
  for name in ('tests/foo.gd','tools/dev.gd','benchmarks/test.gd','.godot/editor/layout.cfg','native/bin/build/libswg_native.so','native/src/test.cpp','addons/x/.git/config','state.log','addons/foo.dll'):
   self.assertFalse(included(Path(name),'linux-x86_64'),name)
  for name in ('scripts/main.gd','native/bin/libswg_native.so','.godot/imported/icon.ctex','.godot/global_script_class_cache.cfg'):
   self.assertTrue(included(Path(name),'linux-x86_64'),name)
  self.assertTrue(included(Path('native/src/test.cpp'),'windows-x86_64'));self.assertFalse(included(Path('addons/godot-steam-audio/bin/plugin.gdextension'),'windows-x86_64'))
 def test_desktop_bootstrap_uses_export_cwd_no_path_override_and_public_profile(self):
  from tools.client import start_test_client
  from types import SimpleNamespace
  (self.root/'PACKAGE.json').write_text(json.dumps({'runnable':True,'engine':'godot','working_directory':'engine'}))
  (self.root/'server.json').write_text(json.dumps({'base_url':'https://test.example:18443'}))
  with patch.object(start_test_client,'__file__',str(self.root/'start_client.py')),patch('sys.argv',['start_client.py','--desktop']),patch.object(start_test_client,'ensure_data') as data,patch.object(start_test_client.subprocess,'run',return_value=SimpleNamespace(returncode=0)) as launch:
   self.assertEqual(start_test_client.main(),0)
  data.assert_called_once_with(self.root)
  command=launch.call_args.args[0];self.assertNotIn('--path',command);self.assertEqual(command[command.index('--xr-mode')+1],'off');self.assertEqual(launch.call_args.kwargs['cwd'],self.root/'engine')
  profile=json.loads((self.root/'runtime/client/connection.json').read_text());self.assertEqual(set(profile),{'base_url','ca_certificate'});self.assertTrue(Path(profile['ca_certificate']).is_absolute())
 def test_windows_handoff_cannot_accidentally_launch(self):
  from tools.client import start_test_client
  (self.root/'PACKAGE.json').write_text(json.dumps({'runnable':False}))
  with patch.object(start_test_client,'__file__',str(self.root/'start_client.py')),patch('sys.argv',['start_client.py']),patch.object(start_test_client,'ensure_data') as data,patch.object(start_test_client.subprocess,'run') as launch:
   self.assertEqual(start_test_client.main(),2)
  data.assert_not_called();launch.assert_not_called()
if __name__=='__main__':unittest.main()
