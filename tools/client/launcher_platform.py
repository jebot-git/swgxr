"""Host selection and portable installation locking for the tester launcher."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import platform

SUPPORTED = ('linux-x86_64', 'windows-x86_64')


def host_target():
    machine = platform.machine().lower()
    system = platform.system()
    if machine not in ('x86_64', 'amd64') or system not in ('Linux', 'Windows'):
        raise ValueError('The testing launcher supports Linux and Windows x86_64 only')
    return system.lower() + '-x86_64'


def default_install_dir(target=None):
    target = target or host_target()
    if target == 'windows-x86_64':
        base = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local')))
    else:
        base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    return base / 'swgxr'


@contextmanager
def installation_lock(path):
    # Windows byte-range locks need a real byte and a consistent file position.
    with Path(path).open('a+b') as stream:
        stream.seek(0, os.SEEK_END)
        if stream.tell() == 0:
            stream.write(b'\0'); stream.flush()
        stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            acquire = lambda: msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            release = lambda: msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            acquire = lambda: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            release = lambda: fcntl.flock(stream, fcntl.LOCK_UN)
        try:
            acquire()
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                raise ValueError('Another launcher or client is using this installation') from None
            raise
        try:
            yield
        finally:
            stream.seek(0); release()
