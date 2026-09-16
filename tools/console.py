#!/usr/bin/env python3
"""Talk to the MILO loader over the machine's serial port.

MAME opens that port as a client, so this listens on the port MAME is told to
connect to, waits for the loader's prompt and types the boot line one character
at a time. Sent in one go the loader drops characters.

Usage: console.py <port> [--boot "<line>"] [--log <file>] [--quiet]
"""
import socket
import sys
import time

BOOT = "boot hda2:vmlinux.gz root=/dev/hda2"
PROMPT = b"MILO>"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    port = int(sys.argv[1])
    boot = BOOT
    log = None
    quiet = "--quiet" in sys.argv
    if "--boot" in sys.argv:
        boot = sys.argv[sys.argv.index("--boot") + 1]
    if "--log" in sys.argv:
        log = open(sys.argv[sys.argv.index("--log") + 1], "wb", buffering=0)

    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(1)
    listener.settimeout(300)

    try:
        line, _ = listener.accept()
    except socket.timeout:
        sys.exit("the emulator never connected to the serial port")

    line.settimeout(1.0)
    seen = b""
    sent = not boot

    while True:
        try:
            data = line.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not data:
            break

        if log:
            log.write(data)
        if not quiet:
            sys.stdout.write(data.decode("latin-1"))
            sys.stdout.flush()

        seen = (seen + data)[-4096:]
        if not sent and PROMPT in seen:
            time.sleep(2)
            for letter in boot:
                line.send(letter.encode())
                time.sleep(0.06)
            line.send(b"\r")
            sent = True

    line.close()


if __name__ == "__main__":
    main()
