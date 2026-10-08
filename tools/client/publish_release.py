#!/usr/bin/env python3
"""Publish a prepared target-specific payload to a local, immutable patch store."""
import argparse
import fcntl
import os
from pathlib import Path
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from server import client_release_protocol as protocol


def atomic(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.write-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def publish(payload, store, *, version, sequence, channel='testing', source_root=None, target='linux-x86_64'):
    payload, store = Path(payload).resolve(), Path(store).resolve()
    if store.is_relative_to(payload): raise ValueError('Patch store must be outside payload')
    protocol.channel_name(channel)
    if target not in protocol.PLATFORMS: raise ValueError('Unsupported client platform')
    store.mkdir(parents=True, exist_ok=True)
    with (store / '.publish.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = store / 'channels' / (channel + '.json')
        if current.exists() and protocol.decode(current.read_bytes())['sequence'] >= sequence:
            raise ValueError('Release sequence must increase')
        def blob(raw):
            key = protocol.digest(raw); target = store / 'blobs' / key
            if not target.exists() or protocol.digest(target.read_bytes()) != key: atomic(target, raw)
            return key
        rows = []
        for path in sorted(payload.rglob('*')):
            if path.is_symlink(): raise ValueError('Payload must not contain symlinks: ' + str(path))
            if not path.is_file(): continue
            name = protocol.safe_path(path.relative_to(payload).as_posix())
            if any(p in {'.git', '.env', '__pycache__', 'tre', 'jtl', 'tte'} for p in path.relative_to(payload).parts) or path.suffix.lower() in {'.pem','.key','.iso','.tre','.db','.sqlite','.sqlite3'}:
                raise ValueError('Private or original archive file in payload: ' + name)
            relocate = False
            raw = None
            if path.suffix == '.json' and source_root:
                raw = path.read_bytes()
                prefix = protocol.encode(str(Path(source_root).resolve()).replace('\\', '/'))[1:-1]
                raw = raw.replace(prefix + b'/', protocol.ROOT_TOKEN + b'/')
                relocate = protocol.ROOT_TOKEN in raw
                protocol.decode(raw)
            import hashlib
            import io
            hashed = hashlib.sha256(); chunks = []; size = 0
            with io.BytesIO(raw) if raw is not None else path.open('rb') as stream:
                while chunk := stream.read(protocol.CHUNK_SIZE):
                    hashed.update(chunk); size += len(chunk); chunks.append(blob(chunk))
            rows.append(dict(path=name, size=size, sha256=hashed.hexdigest(), chunks=chunks,
                             executable=name==protocol.PLATFORMS[target] or bool(path.stat().st_mode & 0o111), relocate=relocate))
        release = protocol.manifest(dict(schema=1, platform=target, channel=channel,
                    version=version, sequence=sequence, files=rows, total_bytes=sum(r['size'] for r in rows)))
        raw = protocol.encode(release)
        if len(raw) > protocol.MAX_MANIFEST: raise ValueError('Manifest too large')
        descriptor = dict(schema=1, manifest_sha256=blob(raw), manifest_size=len(raw), sequence=sequence, version=version)
        atomic(current, protocol.encode(descriptor))
        return descriptor


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--payload', type=Path, required=True); p.add_argument('--store', type=Path, required=True)
    p.add_argument('--version', required=True); p.add_argument('--sequence', type=int, required=True)
    p.add_argument('--channel', default='testing'); p.add_argument('--source-root', type=Path)
    p.add_argument('--target', choices=protocol.PLATFORMS, default='linux-x86_64')
    args = vars(p.parse_args()); print(protocol.encode(publish(**args)).decode())

if __name__ == '__main__': main()
