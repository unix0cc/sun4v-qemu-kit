#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""Generate an OBP NVRAM image (nvram1) for -M niagara.

The format is not documented anywhere; it is read out of the OBP sources this
repo vendors, and every rule below cites the file it came from:

  src/obp/obp/dev/sun4v-devices/legion-nvram/nvram.tok   region layout
  src/obp/obp/pkg/confvar/hashdevice.fth                 hash, crc, record
  src/obp/obp/pkg/confvar/nvdevice.fth                   magic, validity
  src/obp/obp/pkg/confvar/fixed-access.fth               fixed region

Layout (nvram.tok:57-66), total 8192 bytes:

    0x0000  nvfixed    0x40 bytes
    0x0040  nvhash     0x1ee0 bytes   <- variables live here
    0x1f20  keystore   0x100 bytes

The nvhash region is a magic dword followed by an append-only record log
(nvdevice.fth: `nvtoken-region-ok?` reads 4 bytes at offset 0 and compares
against nvmagic#; `load-nvtoken-data` then seeks to 4 and scans).

Record (hashdevice.fth `(write-record)`, :108):

    4  hash    big-endian, bit 31 set   (create-nvhash of the variable name)
    1  crc     simple-crc(data, seed=len)
    2  len     big-endian
    N  data

    0xffffffff as a hash marks end of log (`write-eof`, :100).

Verified against Sun's shipped nvram1: every record's crc recomputes, and the
hashes resolve to the expected variable names --
    0x8ec8724c input-device   0x8dfc53cd output-device
    0x89f1308b boot-device    0x88b5f04a auto-boot?
    0x8b6bb54c use-nvramrc?

The fixed region needs no checksum: `nvfixed-region-ok?` is literally
`( -- ) true` (fixed-access.fth:105). It still carries real settings, so by
default it is copied from a reference image rather than invented.
"""

import argparse, struct, sys

NVFIXED_BASE, NVFIXED_SIZE = 0x0000, 0x40
NVHASH_BASE,  NVHASH_SIZE  = 0x0040, 0x1ee0
KEYSTORE_BASE, KEYSTORE_SIZE = 0x1f20, 0x100
TOTAL = 0x2000
VALID_HASH_MASK = 0x80000000
HASH_PRIMES = [2971, 8747, 1031, 1151, 2861]   # hashdevice.fth:69


def _fold16(x):     # `lwsplit +` -- split a long into two words, add
    return ((x >> 16) & 0xffff) + (x & 0xffff)


def _fold8(x):      # `wbsplit +` -- split a word into two bytes, add
    return ((x >> 8) & 0xff) + (x & 0xff)


def create_nvhash(name: str) -> int:
    """hashdevice.fth:71 `create-nvhash`."""
    b = name.encode('ascii')
    if not b:
        raise ValueError("empty variable name")
    mod = (((b[0] & 0x5f) << 6) | (len(b) & 0x1f)) | VALID_HASH_MASK
    h = 0
    for i, ch in enumerate(b):
        h = _fold16(h + ch * HASH_PRIMES[i % 5])
    h = (h << 12) & 0xffffffff
    if h & VALID_HASH_MASK:
        raise ValueError(f"HASH/Valid collision for {name!r}")   # OBP aborts here too
    return mod | h


def simple_crc(data: bytes, seed: int) -> int:
    """hashdevice.fth:63 `simple-crc`, called with seed = len."""
    c = _fold8(seed)
    for byte in data:
        c = _fold8(c + byte)
    return c


def encode_string(s: str) -> bytes:
    """A string value is <count byte><chars><NUL> -- deduced from Sun's image:
    boot-device holds 05 'vdisk' 00, len 7."""
    b = s.encode('ascii')
    if len(b) > 255:
        raise ValueError(f"value too long: {s!r}")
    return bytes([len(b)]) + b + b'\0'


def encode_bool(v: bool) -> bytes:
    """0x00 false / 0xff true -- auto-boot? is 00 and use-nvramrc? is ff in
    Sun's image."""
    return b'\xff' if v else b'\x00'


def encode(value) -> bytes:
    if isinstance(value, bool):
        return encode_bool(value)
    if isinstance(value, str):
        return encode_string(value)
    if isinstance(value, (bytes, bytearray)):
        return bytes(value)
    raise TypeError(f"cannot encode {value!r}")


def record(name: str, value) -> bytes:
    data = encode(value)
    return (struct.pack('>I', create_nvhash(name))
            + bytes([simple_crc(data, len(data))])
            + struct.pack('>H', len(data))
            + data)


def build(variables: dict, magic: int, fixed: bytes) -> bytes:
    if len(fixed) != NVFIXED_SIZE:
        raise ValueError(f"fixed region must be {NVFIXED_SIZE} bytes, got {len(fixed)}")

    log = struct.pack('>I', magic)
    for name, value in variables.items():
        log += record(name, value)
    log += struct.pack('>I', 0xffffffff)          # write-eof

    if len(log) > NVHASH_SIZE:
        raise ValueError(f"variables need {len(log)} bytes, region is {NVHASH_SIZE}")

    img = bytearray(TOTAL)
    img[NVFIXED_BASE:NVFIXED_BASE + NVFIXED_SIZE] = fixed
    img[NVHASH_BASE:NVHASH_BASE + len(log)] = log
    return bytes(img)


def parse(img: bytes, verbose=True):
    """Walk an existing image -- used to check this tool against Sun's."""
    magic, = struct.unpack('>I', img[NVHASH_BASE:NVHASH_BASE + 4])
    if verbose:
        print(f"magic {magic:#010x}  (computed for this platform: "
              f"{(create_nvhash('NVRAM magic') + NVFIXED_SIZE) & 0xffffffff:#010x})")
    known = {create_nvhash(n): n for n in KNOWN_NAMES}
    off, out = NVHASH_BASE + 4, []
    while off + 7 <= len(img):
        h, = struct.unpack('>I', img[off:off + 4])
        if h == 0xffffffff:
            if verbose:
                print(f"  {off:#06x}  end of log")
            break
        crc = img[off + 4]
        ln, = struct.unpack('>H', img[off + 5:off + 7])
        data = img[off + 7:off + 7 + ln]
        if not (h & VALID_HASH_MASK) or simple_crc(data, ln) != crc:
            if verbose:
                print(f"  {off:#06x}  stops here: "
                      f"{'invalid hash' if not h & VALID_HASH_MASK else 'crc mismatch'}")
            break
        name = known.get(h, f"<unknown {h:#010x}>")
        if verbose:
            print(f"  {off:#06x}  {name:<22} {data!r}")
        out.append((name, data))
        off += 7 + ln
    return out


# Only used to give parse() readable names; not needed to generate.
KNOWN_NAMES = """input-device output-device boot-device boot-file auto-boot?
diag-switch? diag-device diag-file screen-#columns screen-#rows security-mode
use-nvramrc? nvramrc oem-banner oem-banner? oem-logo oem-logo? ansi-terminal?
fcode-debug? local-mac-address? boot-command error-reset-recovery verbosity
ttya-mode ttyb-mode auto-boot-on-error? diag-level asr-policy
security-#badlogins multipath-boot? network-boot-arguments""".split()

# What Sun's shipped image effectively sets, and a sane default for QEMU:
# serial console, boot off the virtual disk.
DEFAULTS = {
    "input-device":  "ttya",
    "output-device": "ttya",
    "auto-boot?":    False,
    "boot-device":   "vdisk",
    "use-nvramrc?":  True,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", help="write an image here")
    ap.add_argument("-r", "--reference",
                    help="existing nvram1 to take the fixed region and magic from")
    ap.add_argument("--magic", type=lambda s: int(s, 0),
                    help="override the magic dword (default: computed, or the "
                         "reference's if -r is given)")
    ap.add_argument("--parse", metavar="IMAGE", help="decode an image and exit")
    ap.add_argument("--set", action="append", default=[], metavar="NAME=VALUE",
                    help="set a variable; true/false become booleans")
    args = ap.parse_args()

    if args.parse:
        parse(open(args.parse, 'rb').read())
        return 0

    if not args.output:
        ap.error("need -o/--output (or --parse)")

    fixed = bytes(NVFIXED_SIZE)
    magic = (create_nvhash("NVRAM magic") + NVFIXED_SIZE) & 0xffffffff
    if args.reference:
        ref = open(args.reference, 'rb').read()
        if len(ref) != TOTAL:
            ap.error(f"reference must be {TOTAL} bytes, got {len(ref)}")
        fixed = ref[NVFIXED_BASE:NVFIXED_BASE + NVFIXED_SIZE]
        magic, = struct.unpack('>I', ref[NVHASH_BASE:NVHASH_BASE + 4])
    if args.magic is not None:
        magic = args.magic

    variables = dict(DEFAULTS)
    for item in args.set:
        if '=' not in item:
            ap.error(f"--set wants NAME=VALUE, got {item!r}")
        name, _, val = item.partition('=')
        if val.lower() in ("true", "false"):
            variables[name] = (val.lower() == "true")
        else:
            variables[name] = val

    img = build(variables, magic, fixed)
    with open(args.output, 'wb') as f:
        f.write(img)
    print(f"{args.output}: {len(img)} bytes, magic {magic:#010x}, "
          f"{len(variables)} variables")
    for n, v in variables.items():
        print(f"  {n:<22} {v!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
