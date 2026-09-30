#!/usr/bin/python3
"""Tell whether AmneziaVPN's daemon will fail to find your default gateway.

The daemon reads the IPv4 routing table over netlink into an 8 KiB buffer. If the
dump is bigger, the last packet is truncated, the daemon logs
"Error in received packet" / "No default gateway available, skipping exclusion
route" and never excludes the VPN server from the tunnel. This emulates that
reader against the live table. Read-only, no root needed.
"""

import socket
import struct
import sys

RTM_GETROUTE, NLM_F_REQUEST, NLM_F_DUMP = 26, 1, 0x300
NLMSG_DONE, NLMSG_ERROR = 3, 2
BUFSIZE = 8192


def dump(reader: str):
    """reader='full' uses a big buffer; reader='amnezia' emulates the 8 KiB one."""
    sock = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
    sock.bind((0, 0))
    header = struct.pack("=LHHLL", 28, RTM_GETROUTE, NLM_F_REQUEST | NLM_F_DUMP, 1, 0)
    sock.send(header + struct.pack("=BBBBBBBBI", 2, 0, 0, 0, 0, 0, 0, 0, 0))
    total = messages = 0
    error = None
    while True:
        size = 65536 if reader == "full" else BUFSIZE - total
        if size <= 0:
            error = "buffer full before the dump ended"
            break
        data, _, flags, _ = sock.recvmsg(size)
        broken = bool(flags & socket.MSG_TRUNC)
        done = False
        offset = 0
        while offset + 16 <= len(data):
            length, kind = struct.unpack_from("=LH", data, offset)
            if length < 16 or offset + length > len(data):
                broken = True
                break
            if kind == NLMSG_DONE:
                done = True
                break
            if kind == NLMSG_ERROR:
                broken = True
                break
            messages += 1
            offset += (length + 3) & ~3
        total += len(data)
        if broken:
            error = "truncated netlink packet"
            break
        if done:
            break
    sock.close()
    return messages, total, error


def main() -> int:
    messages, total, _ = dump("full")
    print(f"routing table dump: {messages} IPv4 routes, {total} bytes (limit {BUFSIZE})")
    _, _, error = dump("amnezia")
    if error:
        print(f"AFFECTED: an {BUFSIZE}-byte reader fails ({error}).")
        print("AmneziaVPN will not create the exclusion route for the VPN server;")
        print("keep a host route to it (amnezia-ru-split does this).")
        return 1
    print("OK: the dump fits, AmneziaVPN can read the gateway.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
