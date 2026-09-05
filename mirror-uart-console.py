#!/usr/bin/env python3
"""Open a logged, interactive 115200 8N1 console to the MIRROR UART."""

from __future__ import annotations

import argparse
import errno
import glob
import os
from pathlib import Path
import select
import sys
import termios
import tty
from datetime import datetime

DEVICE_PATTERNS = (
    "/dev/cu.usbserial*",
    "/dev/cu.usbmodem*",
    "/dev/cu.SLAB_USBtoUART*",
    "/dev/cu.wchusbserial*",
    "/dev/ttyUSB*",
    "/dev/ttyACM*",
)


def serial_devices() -> list[str]:
    return sorted({device for pattern in DEVICE_PATTERNS for device in glob.glob(pattern)})


def configure_115200_8n1(fd: int) -> None:
    attrs = termios.tcgetattr(fd)
    attrs[0] = termios.IGNBRK
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] = 0
    attrs[4] = termios.B115200
    attrs[5] = termios.B115200
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 1
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Logged interactive MIRROR UART console")
    parser.add_argument("device", nargs="?", help="serial device path")
    parser.add_argument("-o", "--output", type=Path, help="capture path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    devices = serial_devices()
    device = args.device or (devices[0] if len(devices) == 1 else None)
    if not device:
        print("Pass a serial device path (zero or multiple adapters found).", file=sys.stderr)
        return 2

    output = args.output or Path("captures") / f"mirror-uart-interactive-{datetime.now():%Y%m%d-%H%M%S}.log"
    output.parent.mkdir(parents=True, exist_ok=True)

    try:
        serial_fd = os.open(device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        configure_115200_8n1(serial_fd)
    except OSError as exc:
        print(f"Could not open {device}: {exc}", file=sys.stderr)
        return 1

    stdin_fd = sys.stdin.fileno()
    old_stdin = termios.tcgetattr(stdin_fd)
    print(f"Interactive console on {device} at 115200 8N1.", file=sys.stderr)
    print(f"Saving received bytes to {output.resolve()}.", file=sys.stderr)
    print("Press Control-] to exit.", file=sys.stderr)

    try:
        tty.setraw(stdin_fd)
        with output.open("wb") as capture:
            while True:
                readable, _, _ = select.select([serial_fd, stdin_fd], [], [], 0.5)
                if serial_fd in readable:
                    try:
                        data = os.read(serial_fd, 4096)
                    except OSError as exc:
                        if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                            data = b""
                        else:
                            raise
                    if data:
                        capture.write(data)
                        capture.flush()
                        os.write(sys.stdout.fileno(), data)
                if stdin_fd in readable:
                    data = os.read(stdin_fd, 1024)
                    if b"\x1d" in data:
                        break
                    if data:
                        os.write(serial_fd, data)
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_stdin)
        os.close(serial_fd)
        print(f"\nConsole closed. Log saved to {output.resolve()}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
