"""Check Xtensa ELF architecture, loaders and DT_NEEDED closure in a target root."""
from pathlib import Path, PurePosixPath
import os
import re
import struct
import sys


def resolve(root, name):
    pending = list(PurePosixPath('/' + name.lstrip('/')).parts[1:])
    parts = []
    links = 0
    while pending:
        part = pending.pop(0)
        if part in ('', '.'):
            continue
        if part == '..':
            if parts:
                parts.pop()
            continue
        path = root.joinpath(*parts, part)
        if path.is_symlink():
            links += 1
            if links > 40:
                raise ValueError(f'symlink loop: {name}')
            target = os.readlink(path)
            if target.startswith('/'):
                parts = []
            pending = list(PurePosixPath(target).parts) + pending
            pending = [p for p in pending if p != '/']
        else:
            parts.append(part)
    return root.joinpath(*parts)


def elf_info(data):
    if data[:4] != b'\x7fELF':
        return None
    if data[4:6] != b'\x01\x01' or struct.unpack_from('<H', data, 18)[0] != 94:
        raise ValueError('expected 32-bit little-endian Xtensa ELF')
    phoff = struct.unpack_from('<I', data, 28)[0]
    entsize, count = struct.unpack_from('<HH', data, 42)
    segments = [struct.unpack_from('<8I', data, phoff + i * entsize) for i in range(count)]
    interp = None
    dynamic = []
    for kind, off, va, pa, size, memsz, flags, align in segments:
        if kind == 3:
            interp = data[off:off + size].rstrip(b'\0').decode()
        elif kind == 2:
            for pos in range(off, off + size, 8):
                tag, value = struct.unpack_from('<II', data, pos)
                if tag == 0:
                    break
                dynamic.append((tag, value))
    strings = next((v for k, v in dynamic if k == 5), None)
    needed = []
    if strings is not None:
        for kind, off, va, pa, size, memsz, flags, align in segments:
            if kind == 1 and va <= strings < va + size:
                table = off + strings - va
                break
        else:
            raise ValueError('ELF string table is outside load segments')
        for tag, offset in dynamic:
            if tag == 1:
                start = table + offset
                needed.append(data[start:data.index(b'\0', start)].decode())
    return interp, needed


def check(root):
    root = Path(root).absolute()
    count = 0
    for path in root.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            info = elf_info(path.read_bytes())
            if info is None:
                continue
            count += 1
            interp, needed = info
            if interp and not resolve(root, interp).is_file():
                raise ValueError(f'missing interpreter {interp}')
            for name in needed:
                if '/' in name or not any(resolve(root, prefix + name).is_file()
                                          for prefix in ('/lib/', '/usr/lib/', '/nix/var/nix/profiles/system/lib/')):
                    raise ValueError(f'missing dependency {name}')
        except (ValueError, struct.error) as error:
            raise ValueError(f'{path.relative_to(root)}: {error}') from error
    profile = resolve(root, '/nix/var/nix/profiles/system')
    store_root = (root / 'nix/store').resolve()
    try:
        profile.relative_to(store_root)
    except ValueError as error:
        raise ValueError('system profile does not resolve into /nix/store') from error
    if not profile.is_dir() or not re.fullmatch(
            r'[0-9abcdfghijklmnpqrsvwxyz]{32}-six-system-reterminal-e1002-.+', profile.name):
        raise ValueError('invalid target system closure in /nix/store')
    system = '/nix/var/nix/profiles/system'
    for name in ('/bin/sh', '/sbin/init', system + '/bin/s6-svscan',
                 system + '/bin/s6-supervise', system + '/bin/s6-linux-init',
                 system + '/bin/s6-rc', system + '/bin/activate',
                 system + '/boot/init', system + '/boot/s6-linux-init.cpio',
                 system + '/six/s6-rc/db/resolve.cdb'):
        executable = resolve(root, name)
        if not executable.is_file():
            raise ValueError(f'missing required boot file {name}')
        if name.endswith(('/init', '/activate', '/s6-svscan', '/s6-supervise', '/s6-linux-init', '/s6-rc')) and not executable.stat().st_mode & 0o111:
            raise ValueError(f'boot executable is not executable: {name}')
    # Runtime closure references must resolve within the staged root, never on
    # the build host. This also catches accidentally retained native packages.
    store_pattern = re.compile(rb'/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[a-zA-Z0-9+._?=-]+')
    for path in (root / 'nix/store').rglob('*'):
        if path.is_symlink():
            data = os.readlink(path).encode()
        elif path.is_file():
            data = path.read_bytes()
            if data.startswith(b'#!'):
                interpreter = data.splitlines()[0][2:].split()[0].decode()
                if not resolve(root, interpreter).is_file():
                    raise ValueError(f'{path.relative_to(root)}: missing script interpreter {interpreter}')
        else:
            continue
        for reference in store_pattern.findall(data):
            if not resolve(root, reference.decode()).exists():
                raise ValueError(f'{path.relative_to(root)}: missing store object {reference.decode()}')
    print(f'Checked {count} Xtensa ELF files and their loaders/libraries')


if __name__ == '__main__':
    check(sys.argv[1])
