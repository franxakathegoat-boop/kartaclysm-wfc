#!/usr/bin/env python3
"""Print wwfcPayloadPublicKey.hpp for an RSA-2048 private key (same output as wfc-patcher-wii's
misc/generate-key.py, but it reads the key with openssl, so no Python packages are needed).
Usage: pubkey-hpp.py private-key.pem > include/wwfcPayloadPublicKey.hpp"""
import re, struct, subprocess, sys

text = subprocess.run(["openssl", "rsa", "-in", sys.argv[1], "-noout", "-text"], capture_output=True, text=True, check=True).stdout
if not re.search(r"publicExponent: 65537\b", text):
    sys.exit("error: RSA key exponent must be 65537")
n = int(subprocess.run(["openssl", "rsa", "-in", sys.argv[1], "-noout", "-modulus"], capture_output=True, text=True, check=True).stdout.strip().split("=", 1)[1], 16)
if n.bit_length() != 2048:
    sys.exit("error: RSA key must be 2048 bits")

def words_le(v):  # 256 bytes, big-endian words in reverse order (what the payload's RSA code expects)
    b = v.to_bytes(0x100, "big")
    return b"".join(b[len(b) - i * 4 - 4:len(b) - i * 4] for i in range(len(b) >> 2))

data = struct.pack(">I", -pow(n, -1, 1 << 32) & 0xFFFFFFFF) + words_le(n) + words_le(pow(pow(2, 2048), 2, n))
out = "#pragma once\n\nnamespace wwfc\n{\n\nconstexpr unsigned char PayloadPublicKey[] = {"
for i, c in enumerate(data):
    out += ("\n   " if i % 12 == 0 else "") + " 0x{:02x},".format(c)
sys.stdout.write(out + "\n};\n\n} // namespace wwfc\n")
