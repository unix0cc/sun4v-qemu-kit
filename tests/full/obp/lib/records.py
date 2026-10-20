#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# records.py -- walk an openboot.bin's OBMD dropin chain. Shared by every
# test that needs per-record hashes or names: sun-records (byte hashes vs
# Sun's own images) and patch-locality (which records our own patches may
# touch) both read the same 32-byte-aligned "OBMD<size><...name...>" chain,
# so the walk lives in one place rather than three copies of the struct
# layout drifting apart.
#
# As a library: `from records import walk` (see below). As a script: prints
# one line per record, "<sha256|-> <name>", '-' for names in NO_HASH (a
# record whose content is expected to differ for a documented reason --
# decomp.o codegen for OBP, the engine-binary-address class for bootprom;
# TESTS 5).
import hashlib, struct, sys

NO_HASH = frozenset({"OBP", "bootprom"})

def walk(path):
    """Yield (name, offset, record_bytes) for each OBMD record in path, in
    file order. record_bytes includes the 32-byte header, so it can be
    hashed or re-written directly."""
    d = open(path, "rb").read()
    off = 0
    while off < len(d):
        if len(d) - off < 8:
            raise ValueError(f"{path}: {len(d)-off} trailing bytes at {off:#x}, "
                              "not a full record header")
        magic, size = struct.unpack(">4sI", d[off:off+8])
        if magic != b"OBMD":
            raise ValueError(f"{path}: broken chain at {off:#x} (magic {magic!r})")
        name = d[off+16:off+32].split(b"\0")[0].decode()
        n = 32 + ((size + 3) & ~3)
        yield name, off, d[off:off+n]
        off += n

def names(path):
    return [name for name, _, _ in walk(path)]

# No record_map(): record names are NOT unique within one image. The pci
# config's openboot.bin carries two distinct "support-pkg" records (measured
# patch-locality.sh's first run -- Sun's own dropins.src binds
# that package into more than one subtree). A name -> bytes dict would
# silently keep only one. Compare by POSITION (zip two walk() lists) instead,
# as patch-locality.sh does; it also catches a reordering that a set/dict
# comparison would miss.

def sha_line(name, rec, label=None):
    h = "-" if name in NO_HASH else hashlib.sha256(rec).hexdigest()
    return f"{h}  {label + ' ' if label else ''}{name}"

if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(f"usage: {sys.argv[0]} <openboot.bin> [label]")
    path = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) == 3 else None
    for name, _, rec in walk(path):
        print(sha_line(name, rec, label))
