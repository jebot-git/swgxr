"""Portable launcher UI for the existing VRM 1.0 exporter."""
import json
import os
from pathlib import Path
import queue
import ssl
import sys
import threading
from urllib.request import Request, build_opener, HTTPSHandler
from urllib.error import HTTPError, URLError
from .export_character import ExportError, NoRedirect, MAX_JSON, normalize_snapshot, read_json, export, connection


class Gateway:
    def __init__(self, root):
        self.root = Path(root)
        self.base = json.loads((self.root/'server.json').read_text())['base_url'].rstrip('/')
        connection(self.base, None, 'validate-origin')
        self.opener = build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context(cafile=str(self.root/'server-ca.pem'))))
        self.token = None

    def request(self, path, payload=None):
        headers = {'Content-Type': 'application/json'}
        if self.token: headers['Authorization'] = 'Bearer '+self.token
        data = json.dumps(payload).encode() if payload is not None else None
        try:
            with self.opener.open(Request(self.base+path, data=data, headers=headers), timeout=90) as response:
                raw = response.read(MAX_JSON+1)
            if len(raw)>MAX_JSON: raise ExportError('Server response exceeds 32 MiB.')
            result = json.loads(raw)
            if not isinstance(result,dict): raise ExportError('Invalid server response.')
            return result
        except HTTPError as error:
            raise ExportError('Server returned HTTP '+str(error.code)+'. Check sign-in details, or close the game and retry.') from None
        except (URLError,TimeoutError,ValueError):
            raise ExportError('Cannot read the server response. Check the connection and certificate.') from None

    def roster(self, account, password):
        # Every operation gets its own short-lived session; never persist credentials.
        try:
            self.token = self.request('/auth/login', {'account':account,'password':password})['token']
            result = self.request('/characters')
            if result.get('backend')!='core3': raise ExportError('Expected native CoreCU characters.')
            return result.get('characters', [])
        finally: self.logout()

    def snapshot(self, account, password, identity):
        if not str(identity).isdecimal(): raise ExportError('Invalid character ID.')
        try:
            self.token = self.request('/auth/login', {'account':account,'password':password})['token']
            result = self.request('/characters/'+str(identity))
            if result.get('backend')!='core3' or result.get('character',{}).get('appearance',{}).get('source')!='core3_replication':
                raise ExportError('Expected native CoreCU appearance and equipment.')
            return normalize_snapshot(result, str(identity))
        finally: self.logout()

    def logout(self):
        if self.token:
            try: self.request('/auth/logout', {})
            except ExportError: pass
            self.token = None


def gui(root):
    if os.name=='nt':
        runtime=Path(sys.executable).parent
        os.environ['TCL_LIBRARY']=str(runtime/'tcl/tcl8.6')
        os.environ['TK_LIBRARY']=str(runtime/'tcl/tk8.6')
    import tkinter as tk
    from tkinter import ttk, filedialog
    root = Path(root).resolve()
    (root/'runtime/character_exports').mkdir(parents=True,exist_ok=True)
    window = tk.Tk(); window.title('SWGXR · Character to VRM'); window.geometry('660x430')
    pane=ttk.Frame(window,padding=20);pane.pack(fill='both',expand=True)
    ttk.Label(pane,text='Export your character as a VRM 1.0 avatar',font=('Arial',15,'bold')).pack(anchor='w')
    ttk.Label(pane,text='Uses prepared game data, current appearance and worn equipment.\nClose the game before exporting. No VR session is started.').pack(anchor='w',pady=10)
    fields=ttk.Frame(pane);fields.pack(fill='x')
    account=tk.StringVar();password=tk.StringVar();choice=tk.StringVar();status=tk.StringVar(value='Sign in to list your characters, or open a saved character snapshot.')
    for row,(label,variable) in enumerate([('Account',account),('Password',password)]):
        ttk.Label(fields,text=label).grid(row=row,column=0,sticky='w',padx=(0,12))
        ttk.Entry(fields,textvariable=variable,show='*' if row else '').grid(row=row,column=1,sticky='ew',pady=4)
    fields.columnconfigure(1,weight=1)
    selector=ttk.Combobox(pane,textvariable=choice,state='readonly');selector.pack(fill='x',pady=12)
    events=queue.Queue();busy=False;roster=[];buttons=[]
    def work(job):
        nonlocal busy
        if busy:return
        busy=True;status.set('Working…')
        for button in buttons:button.configure(state='disabled')
        def run():
            try:events.put(('ok',job()))
            except Exception as error:events.put(('error',str(error)))
        threading.Thread(target=run,daemon=True).start()
    def load():
        user,secret=account.get(),password.get();password.set('')
        if not user or not secret:status.set('Enter your account and password.');return
        work(lambda:('roster',Gateway(root).roster(user,secret)))
    def save(offline=False):
        snapshot=None
        if offline:
            path=filedialog.askopenfilename(parent=window,title='Full character response JSON',filetypes=[('Character snapshot','*.json')])
            if not path:return
            try:snapshot=normalize_snapshot(read_json(Path(path)));snapshot['offline']=True
            except (ExportError,OSError) as error:status.set(str(error));return
        elif selector.current()<0:status.set('Load and select a character first.');return
        user,secret=account.get(),password.get()
        if not offline and (not user or not secret):status.set('Re-enter your password to export the selected character.');return
        output=filedialog.asksaveasfilename(parent=window,title='Save VRM avatar (choose a new filename)',initialdir=str(root/'runtime/character_exports'),defaultextension='.vrm',filetypes=[('VRM 1.0 avatar','*.vrm')])
        if not output:return
        password.set('')
        identity=None if offline else str(roster[selector.current()]['id'])
        def convert():
            try:from update_test_client import installation_lock
            except ImportError:from tools.client.update_test_client import installation_lock
            with installation_lock(root):
                data=snapshot if offline else Gateway(root).snapshot(user,secret,identity)
                binary=root/'engine'/('godot.exe' if os.name=='nt' else 'godot')
                export(data,Path(output),str(binary),root=root)
            return ('export',output)
        work(convert)
    for label,callback in [('Load characters',load),('Export selected character…',save),('Export saved snapshot…',lambda:save(True))]:
        button=ttk.Button(pane,text=label,command=callback);button.pack(fill='x',pady=3);buttons.append(button)
    ttk.Label(pane,textvariable=status,wraplength=610).pack(anchor='w',pady=14)
    def poll():
        nonlocal busy,roster
        try:
            kind,value=events.get_nowait();busy=False
            for button in buttons:button.configure(state='normal')
            if kind=='error':status.set('Export failed: '+value)
            elif value[0]=='roster':
                roster=value[1];selector['values']=[str(c['name'])+' ('+str(c['id'])+')' for c in roster]
                if roster:selector.current(0)
                status.set('Select a character and re-enter your password to export.' if roster else 'No characters found.')
            else:status.set('Saved avatar and conversion report: '+value[1])
        except queue.Empty:pass
        window.after(100,poll)
    def close():
        if busy:status.set('Wait for the current operation to finish.');return
        password.set('');window.destroy()
    window.protocol('WM_DELETE_WINDOW',close);poll();window.mainloop();return 0
