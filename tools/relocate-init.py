"""Relocate host-generated sixos init references to target FHS compatibility links."""
from pathlib import Path
import os
import re
import sys

# All host maker references must point to executables from the target stack.
patterns = (
    (re.compile(rb'/nix/store/[^/\s]+/bin/'), b'/usr/bin/'),
    (re.compile(rb'/nix/store/[^/\s]+/sbin/'), b'/usr/sbin/'),
    (re.compile(rb'/nix/store/[^/\s]+/libexec/'), b'/usr/libexec/'),
)


def relocate(data):
    for pattern, replacement in patterns:
        data = pattern.sub(replacement, data)
    return data
for path in Path(sys.argv[1]).rglob('*'):
    if path.is_symlink():
        target = os.readlink(path).encode()
        relocated = relocate(target)
        if relocated != target:
            path.unlink()
            path.symlink_to(os.fsdecode(relocated))
    elif path.is_file():
        data = path.read_bytes()
        relocated = relocate(data)
        if relocated != data:
            path.write_bytes(relocated)
    else:
        continue
    data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
    if b'/nix/store/' in data:
        raise ValueError(f'unresolved host store reference: {path}')
