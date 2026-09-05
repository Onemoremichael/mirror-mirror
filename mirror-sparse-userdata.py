#!/usr/bin/env python3
"""Convert a fresh ext4 image to Android sparse without FILL chunks.

Only filesystem-free blocks may become DONT_CARE, and all must be zero in
the input. Allocated blocks, including zero metadata, are sent as RAW chunks.
Never accesses or flashes a device. This is not a secure-erasure operation:
free blocks on a destination device are left unchanged.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

MAGIC, RAW, SKIP = 0xED26FF3A, 0xCAC1, 0xCAC3
HEADER, CHUNK = struct.Struct('<IHHHHIIII'), struct.Struct('<HHII')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    info = subprocess.run(['/opt/homebrew/opt/e2fsprogs/sbin/dumpe2fs', str(args.image)],
                          capture_output=True, text=True, check=True).stdout
    number = lambda label: int(re.search(rf'^{label}:\s+(\d+)$', info, re.M).group(1))
    block_size, total, free_count = number('Block size'), number('Block count'), number('Free blocks')
    if block_size != 4096 or args.image.stat().st_size != total * block_size:
        raise ValueError('Expected a complete 4096-byte-block ext4 image')
    free = []
    for line in re.findall(r'^  Free blocks: (.*)$', info, re.M):
        for part in line.split(', '):
            match = re.fullmatch(r'(\d+)(?:-(\d+))?', part.strip())
            if not match:
                raise ValueError(f'Unrecognized free-block range: {part!r}')
            start, end = int(match[1]), int(match[2] or match[1]) + 1
            if not 0 <= start < end <= total or (free and start < free[-1][1]):
                raise ValueError('Invalid or overlapping free-block ranges')
            free.append((start, end))
    if sum(end - start for start, end in free) != free_count:
        raise ValueError('Free-block ranges disagree with filesystem summary')

    chunks, cursor = [], 0
    for start, end in free + [(total, total)]:
        while cursor < start:
            count = min(start - cursor, 4096)  # <=16 MiB per RAW chunk.
            chunks.append((RAW, cursor, count))
            cursor += count
        if end > start:
            chunks.append((SKIP, start, end - start))
        cursor = end

    original_hash = hashlib.sha256()
    with args.image.open('rb') as source, args.output.open('xb') as dest:
        dest.write(HEADER.pack(MAGIC, 1, 0, HEADER.size, CHUNK.size, block_size, total, len(chunks), 0))
        for kind, start, count in chunks:
            if source.tell() != start * block_size:
                raise ValueError('Chunk coverage is not contiguous')
            remaining = count * block_size
            dest.write(CHUNK.pack(kind, 0, count, CHUNK.size + (remaining if kind == RAW else 0)))
            while remaining:
                data = source.read(min(remaining, 8 * 1024 * 1024))
                if not data:
                    raise ValueError('Truncated source image')
                original_hash.update(data)
                if kind == RAW:
                    dest.write(data)
                elif data != bytes(len(data)):
                    raise ValueError('Refusing to omit nonzero data in filesystem-free blocks')
                remaining -= len(data)

    # Independently parse the generated stream and verify its expanded hash.
    expanded_hash, seen_blocks, seen_chunks = hashlib.sha256(), 0, 0
    with args.output.open('rb') as source:
        header = HEADER.unpack(source.read(HEADER.size))
        if header != (MAGIC, 1, 0, HEADER.size, CHUNK.size, block_size, total, len(chunks), 0):
            raise ValueError('Sparse header mismatch')
        for _ in range(header[7]):
            kind, reserved, count, size = CHUNK.unpack(source.read(CHUNK.size))
            remaining = count * block_size
            if kind not in (RAW, SKIP) or reserved or size != CHUNK.size + (remaining if kind == RAW else 0):
                raise ValueError('Invalid chunk header')
            while remaining:
                length = min(remaining, 8 * 1024 * 1024)
                data = source.read(length) if kind == RAW else bytes(length)
                if len(data) != length:
                    raise ValueError('Truncated sparse payload')
                expanded_hash.update(data)
                remaining -= length
            seen_blocks += count
            seen_chunks += 1
        if source.read(1) or seen_blocks != total or seen_chunks != len(chunks):
            raise ValueError('Sparse coverage mismatch')
    if original_hash.digest() != expanded_hash.digest():
        raise ValueError('Expanded sparse hash differs from raw ext4 image')
    manifest = {'image': str(args.output.resolve()), 'bytes': args.output.stat().st_size,
                'expanded_bytes': total * block_size, 'chunks': len(chunks), 'fill_chunks': 0,
                'raw_blocks': total - free_count, 'skipped_free_blocks': free_count,
                'expanded_sha256': expanded_hash.hexdigest(),
                'verification': 'Expanded hash matches raw image; only zero-valued filesystem-free blocks skipped'}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
