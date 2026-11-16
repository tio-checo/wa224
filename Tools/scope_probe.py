#!/usr/bin/env python3
"""Read-only VICP diagnostic client for a single oscilloscope."""
import argparse
import json
from pathlib import Path
import socket
import struct
import time


class VICP:
    def __init__(self, host, timeout=4):
        self.socket = socket.create_connection((host, 1861), timeout)
        self.socket.settimeout(timeout)
        self.sequence = 0

    def exact(self, count):
        result = bytearray()
        while len(result) < count:
            chunk = self.socket.recv(count - len(result))
            if not chunk:
                raise ConnectionError("Oscilloscope closed the connection")
            result.extend(chunk)
        return bytes(result)

    def query(self, command):
        if not command.rstrip().endswith("?") and "? " not in command:
            raise ValueError("Diagnostic tool accepts queries only")
        self.sequence = self.sequence % 255 + 1
        payload = (command.rstrip() + "\n").encode("ascii")
        self.socket.sendall(struct.pack(">BBBBI", 0x81, 1, self.sequence, 0, len(payload)) + payload)
        result = bytearray()
        for _ in range(1024):
            operation, version, sequence, reserved, length = struct.unpack(">BBBBI", self.exact(8))
            if version != 1 or length > 16 * 1024 * 1024:
                raise ValueError("Invalid VICP header")
            result.extend(self.exact(length))
            if len(result) > 16 * 1024 * 1024:
                raise ValueError("Response too large")
            if operation & 1:
                return bytes(result)
        raise ValueError("Too many VICP frames")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("commands", nargs="+", help="Read-only instrument queries")
    parser.add_argument("--host", default="192.168.0.100")
    parser.add_argument("--output", type=Path, help="Save the last binary response")
    args = parser.parse_args()
    scope = VICP(args.host)
    try:
        for command in args.commands:
            started = time.monotonic()
            response = scope.query(command)
            print(json.dumps({"query": command, "bytes": len(response),
                              "seconds": round(time.monotonic() - started, 4),
                              "preview": repr(response[:160])}))
        if args.output:
            args.output.write_bytes(response)
    finally:
        scope.socket.close()


if __name__ == "__main__":
    main()
