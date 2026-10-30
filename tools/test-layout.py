import importlib.util
from pathlib import Path
import sys
import tempfile

spec = importlib.util.spec_from_file_location('layout', sys.argv[1])
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
base = '''factory,app,factory,0x10000,0xc0000
etc,0x40,1,0xd0000,0x70000
linux,0x40,0,0x140000,0x400000
rootfs,0x40,1,0x540000,0x780000
home,0x40,1,0xcc0000,0x340000
'''
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'partitions.csv'
    path.write_text(base)
    assert layout.check(path, 16 * 1024 * 1024) == 16 * 1024 * 1024
    for bad in [base.replace('0xcc0000', '0xcb0000'),
                base.replace('0x340000', '0x350000'),
                base.replace('0x340000', '0x0'),
                base.replace('home,', 'rootfs,'),
                base.replace('0x340000', '0x340001')]:
        path.write_text(bad)
        try:
            layout.check(path, 16 * 1024 * 1024)
        except ValueError:
            pass
        else:
            raise AssertionError(f'accepted invalid partition table: {bad}')
print('Layout regression checks passed')
