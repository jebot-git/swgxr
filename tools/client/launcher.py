#!/usr/bin/env python3
"""Desktop launcher; the game starts only when the tester presses Play."""
import argparse
import json
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import ttk
try:
    from .patcher import Patcher, Transport
    from .launcher_platform import host_target, default_install_dir
except ImportError:
    from patcher import Patcher, Transport
    from launcher_platform import host_target, default_install_dir


class Launcher:
    def __init__(self, window, config_path, install_dir, *, desktop=False):
        self.desktop = desktop
        self.play_label = 'Play desktop (test)' if desktop else 'Play VR'
        self.window = window; self.events = queue.Queue(); self.busy = False
        config_path = config_path.resolve()
        config = json.loads(config_path.read_text())
        target = host_target()
        if config.get('platform', target) != target:
            raise ValueError('Download the launcher package for ' + target)
        self.transport = Transport(config['base_url'], config_path.parent / config['ca_certificate'])
        self.patcher = Patcher(install_dir, self.transport, config.get('channel','testing'),
                               lambda msg: self.events.put(('status', msg)), target=target)
        window.title('CoreCU • SWGXR Launcher'); window.geometry('660x500'); window.minsize(620,500)
        window.protocol('WM_DELETE_WINDOW', self.close)
        box = ttk.Frame(window, padding=24); box.pack(fill='both', expand=True)
        ttk.Label(box, text='CoreCU / SWGXR', font=('',20,'bold')).pack(anchor='w')
        ttk.Label(box, text=self.transport.origin).pack(anchor='w', pady=(4,18))
        self.account = tk.StringVar(); self.password = tk.StringVar(); self.invite = tk.StringVar()
        form = ttk.Frame(box); form.pack(fill='x')
        for i, (label, variable, hidden) in enumerate((('Account',self.account,False), ('Password',self.password,True), ('Invite code (if required)',self.invite,True))):
            ttk.Label(form, text=label).grid(row=i,column=0,sticky='w',padx=(0,12),pady=5)
            ttk.Entry(form,textvariable=variable,show='•' if hidden else '').grid(row=i,column=1,sticky='ew',pady=5)
        form.columnconfigure(1,weight=1)
        ttk.Label(box, text='New account: 3–24 lowercase letters/digits/_; password: 12–128 characters.', wraplength=560).pack(anchor='w',pady=8)
        buttons = ttk.Frame(box); buttons.pack(fill='x', pady=6)
        self.buttons = []
        for title, command in (('Sign in',lambda:self.auth(False)), ('Create account',lambda:self.auth(True)), ('Install / Update',lambda:self.work(self.update)), (self.play_label,lambda:self.work(self.play))):
            button = ttk.Button(buttons,text=title,command=command); button.pack(side='left',padx=(0,6)); self.buttons.append(button)
        self.status = tk.StringVar(value='Sign in or create a tester account.')
        ttk.Label(box,textvariable=self.status,wraplength=560).pack(anchor='w',pady=14)
        runtime = 'SteamVR or WiVRn' if target.startswith('linux') else 'an active OpenXR runtime (for example SteamVR)'
        ttk.Label(box,text='Updates download only changed chunks. Passwords are never saved.\n' + target + ' • Vulkan • ' + runtime,wraplength=560).pack(anchor='w')
        ttk.Label(box,text='Installation: ' + str(self.patcher.root),wraplength=560).pack(anchor='w',pady=6)
        window.after(100,self.drain)

    def auth(self, register):
        account, password, invite = self.account.get().strip(), self.password.get(), self.invite.get().strip()
        self.password.set(''); self.invite.set('')
        def action():
            self.transport.authenticate(account,password,invite if register and invite else None,register=register)
            return 'Signed in as ' + account + '. Install/update the client, then press ' + self.play_label + '.'
        self.work(action)

    def update(self):
        if not self.transport.session: raise ValueError('Sign in first')
        with self.patcher.lock(): self.patcher.update()
        return 'Client ready. Press ' + self.play_label + ('. XR is disabled.' if self.desktop else ' when your headset runtime is ready.')

    def play(self):
        if not self.transport.session: raise ValueError('Sign in first')
        with self.patcher.lock():
            self.patcher.update()
            self.events.put(('status','Client running. Close the game to return to the launcher.'))
            code = self.patcher.launch(desktop=self.desktop)
        return 'Client closed.' if code == 0 else 'Client exited with code %d. See logs/client.log in the installation folder.' % code

    def work(self, action):
        if self.busy: return
        self.busy = True
        for button in self.buttons: button.state(['disabled'])
        self.status.set('Working…')
        def worker():
            try: message = action()
            except ValueError as error: message = str(error)
            except Exception: message = 'Operation failed. Check the connection, free disk space and file permissions; then retry.'
            self.events.put(('done',message))
        threading.Thread(target=worker,daemon=False).start()

    def drain(self):
        latest = None
        while True:
            try: kind, message = self.events.get_nowait()
            except queue.Empty: break
            latest = message
            if kind == 'done':
                self.busy = False
                for button in self.buttons: button.state(['!disabled'])
        if latest is not None: self.status.set(latest)
        self.window.after(100,self.drain)

    def close(self):
        if self.busy:
            self.status.set('Wait for the update to finish, or close the running game before closing the launcher.')
        else: self.window.destroy()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',type=Path,default=Path(__file__).with_name('launcher.json'))
    p.add_argument('--install-dir',type=Path,default=default_install_dir())
    p.add_argument('--desktop',action='store_true',help='Explicit regression/asset-inspection mode; disables OpenXR')
    args=p.parse_args(); window=tk.Tk()
    try: Launcher(window,args.config,args.install_dir,desktop=args.desktop)
    except Exception as error:
        window.destroy(); raise SystemExit('Cannot initialize launcher: '+str(error)) from None
    window.mainloop()

if __name__ == '__main__': main()
