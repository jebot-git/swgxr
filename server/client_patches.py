"""Read-only authenticated patch content. Only invited or explicitly allowlisted testers can read."""
from pathlib import Path
try:
    from .client_release_protocol import MAX_MANIFEST,channel_name,sha,digest,decode
except ImportError:
    from client_release_protocol import MAX_MANIFEST,channel_name,sha,digest,decode

class PatchStore:
    def __init__(self,root):self.root=Path(root).resolve()
    def read(self,route,account,*,entitled=False):
        if not entitled:
            access=decode((self.root/'access.json').read_bytes()) if (self.root/'access.json').exists() else {}
            if account not in access.get('accounts',[]):raise PermissionError('Tester is not allowed to download this client')
        if route.startswith('/patch/v1/channels/'):
            name=channel_name(route.removeprefix('/patch/v1/channels/'))
            path=self.root/'channels'/(name+'.json');maximum=4096
        elif route.startswith('/patch/v1/blobs/'):
            name=sha(route.removeprefix('/patch/v1/blobs/'))
            path=self.root/'blobs'/name;maximum=MAX_MANIFEST
        else:raise FileNotFoundError('Unknown patch endpoint')
        if path.is_symlink() or not path.resolve().is_relative_to(self.root):raise ValueError('Invalid patch storage path')
        with path.open('rb') as stream:raw=stream.read(maximum+1)
        if len(raw)>maximum:raise ValueError('Patch object too large')
        if route.startswith('/patch/v1/blobs/') and digest(raw)!=name:raise ValueError('Patch object failed integrity check')
        return raw
