"""Transform newc metadata without asking the build sandbox to create setgid dirs."""
import stat
import sys


def entries(data):
    offset = 0
    while offset + 110 <= len(data):
        header = data[offset:offset + 110]
        if header[:6] != b'070701':
            raise ValueError('expected an uncompressed newc init archive')
        fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        start = offset + 110
        name = data[start:start + namesize - 1].decode()
        body = (start + namesize + 3) & ~3
        end = (body + size + 3) & ~3
        if not namesize or end > len(data):
            raise ValueError('truncated newc entry')
        yield offset, end, name, fields[1]
        offset = end
        if name == 'TRAILER!!!':
            return
    raise ValueError('missing newc trailer')


def transform(data, modes=None):
    output = bytearray(data)
    for offset, end, name, mode in entries(data):
        if modes is None:
            mode &= ~0o6000
        elif name in modes:
            mode = modes[name]
        output[offset + 14:offset + 22] = f'{mode:08x}'.encode()
    return output


def validate(data):
    modes = {name: mode for _, _, name, mode in entries(data)}
    for service in ('s6-linux-init-shutdownd', 's6-svscan-log'):
        path = f'run-image/service/{service}/fifo'
        if not stat.S_ISFIFO(modes.get(path, modes.get('./' + path, 0))):
            raise ValueError(f'init archive lost FIFO: {path}')
    return modes


if __name__ == '__main__':
    archive = sys.stdin.buffer.read()
    validate(archive)
    if len(sys.argv) == 1:
        sys.stdout.buffer.write(transform(archive))
    else:
        with open(sys.argv[1], 'rb') as template:
            modes = validate(template.read())
        # cpio may add ./ to names during repacking.
        modes.update({'./' + name: mode for name, mode in modes.copy().items()})
        sys.stdout.buffer.write(transform(archive, modes))
