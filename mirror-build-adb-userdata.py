#!/usr/bin/env python3
"""Build and verify a fresh ext4 userdata image with the owner's ADB public key.

Local image construction only: never opens a device or invokes fastboot.
Flashing the result REPLACES ALL USERDATA. Supply a size read from the target,
not one inferred from another board. The image does not contain a private key.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args[0]}\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', type=lambda value: int(value, 0), required=True,
                        help='Partition size queried from the target')
    parser.add_argument('--filesystem-size', type=lambda value: int(value, 0),
                        help='Explicit smaller filesystem size for a bounded diagnostic image')
    parser.add_argument('--public-key', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    if args.size < 128 * 1024 * 1024 or args.size % 4096:
        parser.error('Size must be at least 128 MiB and divisible by 4096')
    fs_size = args.filesystem_size if args.filesystem_size is not None else args.size
    if not 128 * 1024 * 1024 <= fs_size <= args.size or fs_size % 4096:
        parser.error('Filesystem size must be aligned, at least 128 MiB, and no larger than the partition')
    key_path = args.public_key.resolve()
    if key_path.suffix != '.pub':
        parser.error('Only an explicitly named .pub public-key file is accepted')
    key_line = key_path.read_text().strip()
    if len(key_line.splitlines()) != 1:
        parser.error('Expected exactly one public key')
    decoded = base64.b64decode(key_line.split()[0], validate=True)
    if len(decoded) != 524:
        parser.error('Expected the 524-byte Android RSA public-key structure')
    # Omit the workstation/user comment; retain only the public-key material.
    key_bytes = (key_line.split()[0] + '\n').encode('ascii')
    output = args.output_dir.resolve()
    if any(char.isspace() or char in '\"\\' for char in str(output)):
        parser.error('Choose an output directory without whitespace or quotes')
    output.mkdir(parents=True, exist_ok=False)
    image = output / 'userdata-adb.img'
    public_copy = output / 'adb_keys.pub'
    public_copy.write_bytes(key_bytes)

    platform_tools = Path('/opt/homebrew/bin/mke2fs').resolve().parent
    utilities = Path('/opt/homebrew/opt/e2fsprogs/sbin')
    env = dict(os.environ, MKE2FS_CONFIG=str(platform_tools / 'mke2fs.conf'))
    log = run([str(platform_tools / 'mke2fs'), '-t', 'ext4', '-F', '-b', '4096',
               '-I', '256', '-m', '0', '-L', 'userdata', '-M', '/data',
               '-E', 'lazy_itable_init=0,lazy_journal_init=0',
               str(image), str(fs_size // 4096)], env=env)
    print('Created fresh ext4 image with Android platform-tools configuration.', flush=True)

    commands = ['mkdir /misc', 'mkdir /misc/adb',
                f'write {public_copy} /misc/adb/adb_keys']
    nodes = [('/', 1000, 1000, '040771', 'system_data_file'),
             ('/misc', 1000, 9998, '041771', 'system_data_file'),
             ('/misc/adb', 1000, 2000, '042750', 'adb_keys_file'),
             ('/misc/adb/adb_keys', 1000, 2000, '0100640', 'adb_keys_file')]
    for path, uid, gid, mode, label in nodes:
        label_file = output / f'{label}.label'
        label_file.write_bytes(f'u:object_r:{label}:s0\0'.encode())
        commands.extend([f'set_inode_field {path} uid {uid}',
                         f'set_inode_field {path} gid {gid}',
                         f'set_inode_field {path} mode {mode}',
                         f'ea_set -f {label_file} {path} security.selinux'])
    command_file = output / 'populate.debugfs'
    command_file.write_text('\n'.join(commands) + '\n')
    log += run([str(utilities / 'debugfs'), '-w', '-f', str(command_file), str(image)])
    # debugfs can return success after individual command errors. Verify output,
    # file contents, ownership, modes, labels, and filesystem independently.
    extracted = output / 'verified-adb_keys.pub'
    log += run([str(utilities / 'debugfs'), '-R',
                f'dump /misc/adb/adb_keys {extracted}', str(image)])
    if extracted.read_bytes() != key_bytes:
        raise RuntimeError('Public-key readback mismatch')
    for path, uid, gid, mode, label in nodes:
        info = run([str(utilities / 'debugfs'), '-R', f'stat {path}', str(image)])
        log += info
        if not re.search(rf'User:\s+{uid}\s+Group:\s+{gid}\b', info):
            raise RuntimeError(f'Owner verification failed: {path}')
        expected_mode = int(mode, 8) & 0o7777
        match = re.search(r'Mode:\s+(0[0-7]+)', info)
        if not match or int(match.group(1), 8) != expected_mode:
            raise RuntimeError(f'Mode verification failed: {path}')
        if f'u:object_r:{label}:s0' not in info:
            raise RuntimeError(f'SELinux label verification failed: {path}')
    log += run([str(utilities / 'e2fsck'), '-f', '-n', str(image)])
    fs_info = run([str(utilities / 'dumpe2fs'), '-h', str(image)])
    log += fs_info
    features = re.search(r'^Filesystem features:\s+(.+)$', fs_info, re.MULTILINE).group(1).split()
    supported = {'has_journal', 'ext_attr', 'resize_inode', 'dir_index', 'filetype',
                 'extent', 'sparse_super', 'large_file', 'huge_file', 'uninit_bg',
                 'dir_nlink', 'extra_isize'}
    if set(features) - supported:
        raise RuntimeError(f'Unexpected filesystem features: {set(features) - supported}')
    if image.stat().st_size != fs_size:
        raise RuntimeError('Image length differs from selected filesystem size')
    digest = hashlib.sha256()
    with image.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    manifest = {'image': str(image), 'partition': 'userdata', 'bytes': fs_size,
                'target_partition_bytes': args.size,
                'image_sha256': digest.hexdigest(), 'filesystem_features': features,
                'public_key_sha256': hashlib.sha256(decoded).hexdigest(),
                'verification': 'key readback, ownership, modes, labels, e2fsck -fn passed',
                'warning': 'Flashing replaces all userdata. No private key included.'}
    (output / 'verification.log').write_text(log)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
