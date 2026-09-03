#!/usr/bin/env python3
"""Capture the MIRROR's UART without transmitting to it."""

from __future__ import annotations

import argparse
import errno
import glob
import os
from pathlib import Path
import select
import sys
import termios
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
    parser = argparse.ArgumentParser(
        description="Read and save a 115200 8N1 UART boot log. This program never writes to the serial port."
    )
    parser.add_argument("device", nargs="?", help="serial device, such as /dev/cu.usbserial-FT1234")
    parser.add_argument("-o", "--output", type=Path, help="capture path (default: captures/mirror-uart-TIMESTAMP.log)")
    parser.add_argument("--list", action="store_true", help="list candidate serial devices and exit")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    devices = serial_devices()

    if args.list:
        if devices:
            print("\n".join(devices))
            return 0
        print("No USB serial adapters found.", file=sys.stderr)
        return 1

    if args.device:
        device = args.device
    elif len(devices) == 1:
        device = devices[0]
    elif not devices:
        print("No USB serial adapter found. Connect it and rerun this command.", file=sys.stderr)
        return 1
    else:
        print("More than one serial adapter was found; pass one of these paths:", file=sys.stderr)
        for candidate in devices:
            print(f"  {candidate}", file=sys.stderr)
        return 2

    output = args.output or Path("captures") / f"mirror-uart-{datetime.now():%Y%m%d-%H%M%S}.log"
    output.parent.mkdir(parents=True, exist_ok=True)

    try:
        fd = os.open(device, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
        configure_115200_8n1(fd)
    except OSError as exc:
        print(f"Could not open {device}: {exc}", file=sys.stderr)
        return 1

    print(f"Listening read-only on {device} at 115200 8N1.", file=sys.stderr)
    print(f"Saving raw UART bytes to {output.resolve()}.", file=sys.stderr)
    print("Power-cycle the MIRROR now. Press Control-C after boot completes.", file=sys.stderr)

    try:
        with output.open("wb") as capture:
            while True:
                readable, _, _ = select.select([fd], [], [], 0.5)
                if not readable:
                    continue
                try:
                    data = os.read(fd, 4096)
                except OSError as exc:
                    if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        continue
                    raise
                if not data:
                    continue
                capture.write(data)
                capture.flush()
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
    except KeyboardInterrupt:
        print(f"\nCapture stopped. Log saved to {output.resolve()}.", file=sys.stderr)
    finally:
        os.close(fd)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
