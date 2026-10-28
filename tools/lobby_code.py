#!/usr/bin/env python3
"""Encode a test server's IPv4 endpoint using the game's CA invite format."""
import argparse
import ipaddress

ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def encode(address: str, port: int) -> str:
    if not 1 <= port <= 65535:
        raise ValueError("Port must be between 1 and 65535")
    packed = (int(ipaddress.IPv4Address(address)) << 16) | port
    return "CA-" + "".join(ALPHABET[(packed >> shift) & 31] for shift in range(45, -1, -5))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("port", type=int)
    args = parser.parse_args()
    print(encode(args.address, args.port))
