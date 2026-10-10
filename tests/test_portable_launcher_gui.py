"""Exercise actual Tk widgets and asynchronous actions without starting a game."""
import json
import os
from pathlib import Path
import queue
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from tools.client import test_client_launcher as launcher

class GuiTests(unittest.TestCase):
    def setUp(self):
        if os.name=='nt':
            os.environ['TCL_LIBRARY']=str(Path(sys.executable).parent/'tcl/tcl8.6')
            os.environ['TK_LIBRARY']=str(Path(sys.executable).parent/'tcl/tk8.6')
        import tkinter as tk
        try:self.window=tk.Tk()
        except tk.TclError as error:self.skipTest('Display unavailable: '+str(error))
        self.window.withdraw()
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        (self.root/'PACKAGE.json').write_text(json.dumps({'source_commit':'12345678'}))
        self.calls=[]
        def fake(root,args):
            self.calls.append(args)
            task=type('Task',(),{})();task.events=queue.Queue();return task
        self.app=launcher.LauncherWindow(self.window,self.root,task_factory=fake)
    def tearDown(self):
        if hasattr(self,'app'):
            self.app.task=None;self.app.close();self.temp.cleanup()
    def finish(self,code):
        self.app.task.events.put(('done',code));self.window.after_cancel(self.app.timer);self.app.poll()
    def test_buttons_dispatch_and_block_overlapping_actions(self):
        self.app.buttons[1].invoke()
        self.assertEqual(self.calls,[['--desktop']])
        self.app.update()
        self.assertEqual(len(self.calls),1)
        self.assertTrue(all(str(b['state'])=='disabled' for b in self.app.buttons))
        self.finish(0)
        self.app.buttons[0].invoke()
        self.assertEqual(self.calls[-1],[])
    def test_import_picker_and_cancellation(self):
        with patch('tkinter.filedialog.askdirectory',return_value=''):
            self.app.import_assets();self.assertFalse(self.calls)
        with patch('tkinter.filedialog.askdirectory',return_value='/path with spaces/SWG'):
            self.app.import_assets()
        self.assertEqual(self.calls,[['--import-only','--prepare-game-data','--game-installation','/path with spaces/SWG']])
    def test_update_error_is_visible_and_retry_enabled(self):
        self.app.update();self.app.task.events.put(('output','Checksum mismatch\n'));self.finish(2)
        self.assertIn('failed',self.app.status.get())
        self.assertIn('Checksum mismatch',self.app.log.get('1.0','end'))
        self.assertTrue(all(str(b['state'])=='normal' for b in self.app.buttons))
        self.app.update();self.assertEqual(len(self.calls),2)
    def test_close_does_not_interrupt_update(self):
        self.app.update()
        with patch('tkinter.messagebox.showinfo') as message:
            self.app.close();message.assert_called_once()
        self.assertTrue(self.window.winfo_exists())
    def test_real_child_failure_and_window_remains_responsive(self):
        (self.root/'start_client.py').write_text('import time\nprint("Verifying",flush=True)\ntime.sleep(0.4)\nprint("Example failure",flush=True)\nraise SystemExit(2)\n')
        self.app.task_factory=launcher.BackgroundTask
        self.app.update();ticks=[]
        self.window.after(25,lambda:ticks.append(True))
        deadline=time.monotonic()+10
        while self.app.task is not None and time.monotonic()<deadline:
            self.window.update();time.sleep(.01)
        self.assertIsNone(self.app.task)
        self.assertTrue(ticks)
        self.assertIn('Example failure',self.app.log.get('1.0','end'))
        self.assertIn('failed',self.app.status.get())

if __name__=='__main__':unittest.main()
