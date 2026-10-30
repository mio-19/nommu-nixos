"""Validate partition bounds and optional upstream component sizes before merging."""
import argparse
import csv
from pathlib import Path


def check(csv_path, flash_bytes, images=None):
    end = 0x9000  # bootloader + partition-table sector
    names = set()
    components = {'factory': 'network_adapter.bin', 'etc': 'etc.jffs2',
                  'linux': 'xipImage', 'rootfs': 'rootfs.cramfs', 'home': 'home.jffs2'}
    for row in csv.reader(Path(csv_path).read_text().splitlines()):
        if not row or row[0].lstrip().startswith('#'):
            continue
        name, kind, subtype, offset, size = [v.strip() for v in row[:5]]
        offset, size = int(offset, 0), int(size, 0)
        if name in names or size <= 0 or offset < end or offset + size > flash_bytes:
            raise ValueError(f'{name}: duplicate, overlapping, empty, or outside flash')
        if offset % 4096 or size % 4096:
            raise ValueError(f'{name}: partitions must be sector aligned')
        if kind == 'app' and offset % 65536:
            raise ValueError(f'{name}: app must be 64KiB aligned')
        names.add(name)
        end = offset + size
        if images and name in components:
            path = Path(images) / components[name]
            if not 0 < path.stat().st_size <= size:
                raise ValueError(f'{path}: empty or exceeds partition size {size}')
    if not set(components).issubset(names):
        raise ValueError('missing a firmware partition')
    if images:
        for filename, limit in [('bootloader.bin', 0x8000), ('partition-table.bin', 0x1000)]:
            if not 0 < (Path(images) / filename).stat().st_size <= limit:
                raise ValueError(f'{filename}: invalid size')
    return end


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv')
    parser.add_argument('--flash-bytes', type=int, required=True)
    parser.add_argument('--images')
    args = parser.parse_args()
    check(args.csv, args.flash_bytes, args.images)
    print('Partition bounds and component sizes OK (does not verify board compatibility).')
