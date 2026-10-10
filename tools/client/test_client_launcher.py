"""Desktop GUI, shortcuts and an optional terminal menu for the portable tester client."""
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
               ('SWGXR Desktop', '--desktop'), ('SWGXR Updates', '--launcher --updates')]
    if os.name == 'nt':
        # Environment values avoid injecting user-controlled paths into PowerShell.
        script = '''$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$entries = @(@('SWGXR','--launcher'),@('SWGXR VR',''),@('SWGXR Desktop','--desktop'),@('SWGXR Updates','--launcher --updates'))
foreach ($entry in $entries) {
 $link = $shell.CreateShortcut((Join-Path $desktop ($entry[0]+'.lnk')))
 $link.TargetPath = Join-Path $env:SWGXR_SHORTCUT_ROOT 'python\\python.exe'
 if ($entry[1].Contains('--launcher')) { $link.TargetPath = Join-Path $env:SWGXR_SHORTCUT_ROOT 'python\\pythonw.exe' }
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
                path.write_text('[Desktop Entry]\nType=Application\nName='+name+'\nExec='+command+'\nTerminal='+('false' if '--launcher' in argument else 'true')+'\nIcon=applications-games\nCategories=Game;\n', encoding='utf-8')
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


class BackgroundTask:
    """Capture child output without blocking Tk or redirecting global stdout."""
    def __init__(self, root, arguments):
        import queue
        import threading
        self.events = queue.Queue()
        self.running = True
        self.process = None
        self.root = Path(root)
        self.arguments = arguments
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        executable = Path(sys.executable)
        if executable.name.lower() == 'pythonw.exe':
            executable = executable.with_name('python.exe')
        command = [str(executable), '-u', '-X', 'utf8', str(self.root/'start_client.py'), *self.arguments]
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        try:
            self.process = subprocess.Popen(command, cwd=self.root, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, encoding='utf-8',
                                            errors='replace', **options)
            with self.process.stdout:
                for line in self.process.stdout:
                    self.events.put(('output', line))
            code = self.process.wait()
        except OSError as error:
            self.events.put(('output', str(error)+'\n'))
            code = 2
        self.running = False
        self.events.put(('done', code))


def installed_summary(root):
    import json
    root = Path(root)
    def read(name):
        try:
            return json.loads((root/name).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            return {}
    package = read('PACKAGE.json')
    version = read('UPDATE_RECEIPT.json').get('version') or package.get('release_version')
    if not version:
        version = 'Build ' + package.get('source_commit', 'unknown')[:8]
    prepared = read('GAME_DATA_RECEIPT.json')
    receipt = read('ASSET_RESTORE_RECEIPT.json')
    assets = (receipt.get('workspace') == root.resolve().as_posix()
              and (root/'runtime/assets').is_dir() and (root/'ASSET_MANIFEST.json').is_file())
    assets=assets or (prepared.get('ready') and prepared.get('workspace')==root.resolve().as_posix() and (root/'runtime/assets').is_dir())
    return version, bool(assets), read('server.json').get('base_url', 'Not configured')


class LauncherWindow:
    def __init__(self, window, root, task_factory=BackgroundTask):
        import tkinter as tk
        from tkinter import ttk
        self.tk, self.ttk = tk, ttk
        self.window, self.root, self.task_factory = window, Path(root).resolve(), task_factory
        self.task = None
        self.action = ''
        self.buttons = []
        self.bg, self.panel, self.fg, self.muted, self.accent = '#101b27', '#192b3b', '#eef7fc', '#a9becc', '#6ee7dc'
        window.title('SWGXR Launcher')
        window.geometry('840x660')
        window.minsize(740, 620)
        window.configure(bg=self.bg)
        window.protocol('WM_DELETE_WINDOW', self.close)
        style = ttk.Style(window)
        style.theme_use('clam')
        style.configure('Launcher.Horizontal.TProgressbar', troughcolor=self.panel, background=self.accent,
                        bordercolor=self.panel, lightcolor=self.accent, darkcolor=self.accent)
        main = tk.Frame(window, bg=self.bg, padx=28, pady=24)
        main.pack(fill='both', expand=True)
        tk.Label(main, text='SWGXR', font=('Arial', 26, 'bold'), bg=self.bg, fg=self.fg).pack(anchor='w')
        tk.Label(main, text='TEST CLIENT  /  LAUNCHER', font=('Arial', 10), bg=self.bg, fg=self.accent).pack(anchor='w', pady=(0,18))
        info = tk.Frame(main, bg=self.panel, padx=16, pady=12)
        info.pack(fill='x')
        self.version_text = tk.StringVar()
        self.assets_text = tk.StringVar()
        self.server_text = tk.StringVar()
        for variable in (self.version_text, self.assets_text, self.server_text):
            tk.Label(info, textvariable=variable, font=('Arial', 11), bg=self.panel, fg=self.fg, anchor='w').pack(fill='x', pady=3)
        play = tk.Frame(main, bg=self.bg)
        play.pack(fill='x', pady=(20,8))
        play.columnconfigure(0, weight=2); play.columnconfigure(1, weight=1)
        self.button(play, 'Play in VR', lambda: self.start('game', []), primary=True).grid(row=0,column=0,sticky='ew',padx=(0,10))
        self.button(play, 'Desktop mode', lambda: self.start('game', ['--desktop'])).grid(row=0,column=1,sticky='ew')
        tk.Label(main, text='Desktop mode is for asset inspection and regression testing.', font=('Arial',10), bg=self.bg, fg=self.muted).pack(anchor='w')
        actions = tk.Frame(main, bg=self.bg)
        actions.pack(fill='x', pady=(18,12))
        for column in range(3): actions.columnconfigure(column, weight=1)
        self.button(actions, 'Check & install updates', self.update).grid(row=0,column=0,sticky='ew',padx=(0,8))
        self.button(actions, 'Prepare game data…', self.import_assets).grid(row=0,column=1,sticky='ew',padx=(0,8))
        self.button(actions, 'Create shortcuts', lambda: self.start('shortcuts', ['--install-shortcuts'])).grid(row=0,column=2,sticky='ew')
        self.status = tk.StringVar(value='Ready. Choose an action to begin.')
        tk.Label(main, textvariable=self.status, font=('Arial',11), bg=self.bg, fg=self.accent, anchor='w', wraplength=740, justify='left').pack(fill='x', pady=(6,8))
        self.progress = ttk.Progressbar(main, mode='indeterminate', style='Launcher.Horizontal.TProgressbar')
        self.progress.pack(fill='x')
        tk.Label(main, text='Activity', font=('Arial',10,'bold'), bg=self.bg, fg=self.muted).pack(anchor='w', pady=(14,6))
        logs = tk.Frame(main, bg=self.panel)
        logs.pack(fill='both', expand=True)
        self.log = tk.Text(logs, height=6, bg=self.panel, fg=self.fg, insertbackground=self.fg, font=('Courier',10),
                           relief='flat', padx=12, pady=10, wrap='word', state='disabled')
        scrollbar = ttk.Scrollbar(logs, orient='vertical', command=self.log.yview)
        self.log.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side='right',fill='y');self.log.pack(side='left',fill='both',expand=True)
        footer = tk.Frame(main, bg=self.bg)
        footer.pack(fill='x', pady=(12,0))
        for title, callback in [('Installation guide', lambda: self.open_file(self.root/'TESTER_INSTALL.md')),
                                ('Open client folder', lambda: self.open_file(self.root)),
                                ('Release notes', lambda: webbrowser.open(RELEASES))]:
            tk.Button(footer, text=title, command=callback, bg=self.bg, fg=self.muted, activebackground=self.panel,
                      activeforeground=self.fg, relief='flat', cursor='hand2', font=('Arial',10)).pack(side='left', padx=(0,14))
        self.refresh()
        self.append('Updates preserve installed assets and connection settings.\n')
        self.timer = window.after(100, self.poll)

    def button(self, parent, text, command, primary=False):
        button = self.tk.Button(parent, text=text, command=command, font=('Arial',11,'bold'),
                                bg=self.accent if primary else self.panel, fg=self.bg if primary else self.fg,
                                activebackground='#b3fff3' if primary else '#2b465a', activeforeground=self.bg if primary else self.fg,
                                disabledforeground='#71828e', relief='flat', padx=12, pady=12, cursor='hand2')
        self.buttons.append(button)
        return button

    def refresh(self):
        version, assets, server = installed_summary(self.root)
        self.version_text.set('Installed  ·  '+version)
        self.assets_text.set('Assets  ·  '+('Installed' if assets else 'Prepare from your SWG installation or five TTE discs'))
        self.server_text.set('Server  ·  '+server)

    def append(self, text):
        self.log.configure(state='normal');self.log.insert('end',text)
        # Bound the view for long-running game logs.
        if int(self.log.index('end-1c').split('.')[0])>600:self.log.delete('1.0','100.0')
        self.log.see('end');self.log.configure(state='disabled')

    def start(self, action, arguments):
        if self.task is not None:return
        if action=='game' and (self.root/'engine/data-preparation/recipe.json').is_file() and not (self.root/'runtime/original-game/sources.json').is_file():
            images=[p for p in (self.root/'data').glob('*') if p.suffix.lower()=='.iso']
            if len(images)!=5:
                self.import_assets();return
        self.action = action
        self.status.set({'update':'Checking for client updates…','import':'Verifying and importing assets…',
                         'shortcuts':'Creating desktop shortcuts…','game':'Client is starting / running. Close the game to return.'}[action])
        self.append('\n'+self.status.get()+'\n')
        for button in self.buttons:button.configure(state='disabled')
        self.progress.start(15)
        self.task = self.task_factory(self.root,arguments)

    def update(self):
        self.start('update', ['--updates'])

    def import_assets(self):
        from tkinter import filedialog
        if self.task is not None:return
        images=[p for p in (self.root/'data').glob('*') if p.suffix.lower()=='.iso']
        if len(images)==5:
            self.start('import',['--import-only','--prepare-game-data']);return
        installation=filedialog.askdirectory(parent=self.window,title='Select your SWG The Total Experience installation (or put all five ISOs in data/)')
        if installation:self.start('import',['--import-only','--prepare-game-data','--game-installation',installation])

    def poll(self):
        import queue
        if self.task is not None:
            for _ in range(100):
                try:kind, value = self.task.events.get_nowait()
                except queue.Empty:break
                if kind=='output':self.append(value)
                else:
                    self.progress.stop()
                    self.task=None
                    for button in self.buttons:button.configure(state='normal')
                    if value:
                        self.status.set('Action failed. See the activity log below, then retry.')
                    else:
                        self.status.set({'update':'Update check complete. Your client is ready.', 'import':'Assets imported. Ready to play.',
                                         'shortcuts':'Desktop shortcuts created.', 'game':'Client closed. Ready.'}[self.action])
                    self.refresh()
                    break
        self.timer = self.window.after(100,self.poll)

    def open_file(self, path):
        try:
            if os.name=='nt':os.startfile(str(path))
            else:subprocess.Popen(['xdg-open',str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        except OSError as error:
            self.append(str(error)+'\n')

    def close(self):
        if self.task is not None:
            from tkinter import messagebox
            messagebox.showinfo('SWGXR is busy','Please finish the current operation or close the game before closing the launcher.',parent=self.window)
            return
        self.progress.stop()
        self.window.after_cancel(self.timer)
        self.window.destroy()


def gui(root, update_on_open=False):
    # Tk is imported only for graphical launches; CLI repair remains available.
    if os.name=='nt':
        import ctypes
        try:ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError,OSError):pass
        runtime = Path(sys.executable).parent
        os.environ['TCL_LIBRARY'] = str(runtime/'tcl/tcl8.6')
        os.environ['TK_LIBRARY'] = str(runtime/'tcl/tk8.6')
    try:
        import tkinter as tk
        window=tk.Tk()
    except Exception as error:
        message = 'The desktop launcher could not open. Linux: install python3-tkinter (Fedora) or python3-tk (Debian/Ubuntu), and run from your desktop session. Windows: extract the complete client package.\n\n'+str(error)
        if os.name=='nt':
            ctypes.windll.user32.MessageBoxW(None,message,'SWGXR Launcher',0x10)
        elif shutil.which('kdialog'):
            subprocess.run(['kdialog','--error',message],check=False)
        elif shutil.which('zenity'):
            subprocess.run(['zenity','--error','--text='+message],check=False)
        raise ValueError(message) from error
    app=LauncherWindow(window,root)
    if update_on_open:window.after(250,app.update)
    window.mainloop()
    return 0
