"""Read original SWG string tables without image-conversion dependencies."""
import struct


def string_table(data):
    magic, version, unused, count = struct.unpack_from('<IBII', data)
    if magic != 0xabcd:
        raise ValueError('Invalid STF magic')
    pos = 13
    values, result = {}, {}
    for _ in range(count):
        ident, unknown, size = struct.unpack_from('<III', data, pos)
        pos += 12
        values[ident] = data[pos:pos + size * 2].decode('utf-16le')
        pos += size * 2
    for _ in range(count):
        ident, size = struct.unpack_from('<II', data, pos)
        pos += 8
        name = data[pos:pos + size].decode('utf-8').rstrip('\0')
        pos += size
        result[name] = values[ident]
    if pos != len(data):
        raise ValueError(f'STF trailing bytes: {len(data) - pos}')
    return result
