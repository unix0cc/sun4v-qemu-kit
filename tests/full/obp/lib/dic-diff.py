#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dic-diff.py -- structured comparison of two Forthmacs .dic images.
#
# A raw cmp/diff is close to useless on these files by design. Two files
# from otherwise-identical source can legitimately differ in every one of
# these ways, none of them a content change:
#
#   entry delta   The saved dictionary's own load address (header offset 20,
#                 "entry" in wrapper.h's header_t) differs whenever it was
#                 saved at a different point in the build (fresh vs grown).
#                 Most pointers inside the body are stored origin-RELATIVE
#                 (TESTS 5.2: "the loader rebases origin-relative pointers"),
#                 so this affects only a handful of absolute slots, not the
#                 whole body -- but it is one of the corrections tried below.
#   length shift  A word present in one file's assembler source and not the
#                 other (e.g. rdver, `[ifndef] SUN4V`, TESTS: the Solaris
#                 bootstrap and its 20 bytes) changes tlen by that word's compiled size. Every
#                 dictionary-relative pointer and every SPARC CALL
#                 instruction whose site and target straddle that word's old
#                 position then differs by a constant -- the byte shift for
#                 a plain stored address, the same shift divided by 4 (a
#                 SPARC CALL's displacement field counts instructions, not
#                 bytes) for a call site referring across the boundary.
#   engine addr   Pointers into the engine binary's own .data/.bss (the
#                 "engine-binary-address class", TESTS 5.2) -- concentrated
#                 in the saved user-area tail for a host dictionary (one
#                 actually run, not just metacompiled), unrelated to either
#                 correction above and not explained by this tool.
#
# What this tool does: parse the header; find every length-changing region
# with SequenceMatcher over the body as 4-byte cells (the dictionary's own
# unit); for every remaining same-length substitution, try each entry-delta /
# shift / call-shift correction (and the two stacked) and report which one
# explains it, if any. It does not decode SPARC sethi/or pairs (an address
# split across two instructions) -- only whole-cell values.
#
# What it refuses to pass quietly: a header with symbol, bss or relocation lengths (blen, slen, trlen, drlen -- this tool compares
# none of those regions), data lengths that differ (the data segment is compared cell for cell), a file whose size is not
# what its header adds up to, and trailing bytes (past the last whole 4-byte cell) that differ.
#
# The data segment (dlen bytes after the text) is the saved user area, and a host dictionary that was run carries engine
# addresses and run-time values there that Sun's copy does not. With --user-pin FILE it is checked cell for cell: a cell that
# differs is explained by the same corrections as the text (entry delta, length shift, both), and a cell no correction
# explains must be listed in FILE (one cell number, counted from the start of the data segment, per line; # starts a
# comment). An unexplained cell that is not listed fails, and so does a listed one that is now equal or explained, so a
# change there is seen and not assumed harmless. --write-user-pin FILE writes FILE from the two images given (review
# it before committing it).
#
# Usage: dic-diff.py <a.dic> <b.dic> [--label-a NAME] [--label-b NAME] [-v] [--user-pin FILE | --write-user-pin FILE]
# Exit: 0 if every difference is explained by one of the mechanisms above;
#       1 if a structural header field differs, or any cell is not.
import struct, sys, argparse, difflib

HEADER_FIELDS = ("magic", "tlen", "dlen", "blen", "slen", "entry", "trlen", "drlen")

def load(path):
    data = open(path, "rb").read()
    if len(data) < 32:
        sys.exit(f"{path}: too short to be a .dic image ({len(data)} B)")
    hdr = dict(zip(HEADER_FIELDS, struct.unpack(">8I", data[:32])))
    return hdr, data[32:]

def cells(b):
    n = len(b) - len(b) % 4
    return [struct.unpack(">I", b[i:i+4])[0] for i in range(0, n, 4)], len(b) - n

def mask32(x):
    return x & 0xffffffff

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a"); ap.add_argument("b")
    ap.add_argument("--label-a", default=None)
    ap.add_argument("--label-b", default=None)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--user-pin"); ap.add_argument("--write-user-pin")
    args = ap.parse_args()
    pin_mode = bool(args.user_pin or args.write_user_pin)
    la, lb = args.label_a or args.a, args.label_b or args.b

    ha, ba = load(args.a)
    hb, bb = load(args.b)
    print(f"=== dic-diff: {la} vs {lb} ===")

    bad = False
    for f in ("magic", "blen", "slen", "trlen", "drlen"):
        if ha[f] != hb[f]:
            print(f"  HEADER MISMATCH {f}: {la}={ha[f]:#x} {lb}={hb[f]:#x}")
            bad = True
    for f in ("blen", "slen", "trlen", "drlen"):
        if ha[f] or hb[f]:
            print(f"  HEADER {f} nonzero ({la}={ha[f]:#x} {lb}={hb[f]:#x}): this tool compares no bss, symbol or "
                  "relocation region, so it cannot vouch for these files")
            bad = True
    if ha["dlen"] != hb["dlen"]:
        print(f"  HEADER MISMATCH dlen: {la}={ha['dlen']:#x} {lb}={hb['dlen']:#x} (the data segment is compared cell for cell)")
        bad = True
    for lab, h, body in ((la, ha, ba), (lb, hb, bb)):
        want = h["tlen"] + h["dlen"] + h["blen"] + h["slen"] + h["trlen"] + h["drlen"]
        if len(body) != want:
            print(f"  SIZE MISMATCH {lab}: body is {len(body)} B, the header adds up to {want} B")
            bad = True
    if bad:
        print("FAIL: structural header mismatch")
        return 1
    for f in ("tlen", "dlen"):
        if ha[f] != hb[f]:
            print(f"  NOTE {f} differs: {la}={ha[f]:#x} {lb}={hb[f]:#x} "
                  f"({ha[f] - hb[f]:+d} B) -- expect a length-changing region below")

    entry_delta = mask32(ha["entry"] - hb["entry"])
    print(f"  entry: {la}={ha['entry']:#x} {lb}={hb['entry']:#x} "
          f"(delta {entry_delta:#010x})")

    if ba == bb:
        print(f"  body: identical, {len(ba)} B")
        print("PASS: byte-identical body")
        return 0

    ca, pada = cells(ba)
    cb, padb = cells(bb)
    if pada or padb:
        ta_, tb_ = (ba[len(ba) - pada:] if pada else b""), (bb[len(bb) - padb:] if padb else b"")
        if ta_ != tb_:
            print(f"  TRAILING BYTES differ ({la}: {ta_.hex() or '-'}, {lb}: {tb_.hex() or '-'})")
            print("FAIL: bytes past the last whole cell differ")
            return 1
        print(f"  NOTE: body length not a multiple of 4; the {pada} trailing byte(s) are identical")

    ops = difflib.SequenceMatcher(a=ca, b=cb, autojunk=False).get_opcodes()

    shifts = [o for o in ops if o[0] != "equal" and (o[2]-o[1]) != (o[4]-o[3])]
    if shifts:
        print(f"  {len(shifts)} length-changing region(s):")
        for tag, i1, i2, j1, j2 in shifts:
            shift_b = (j1 - i1) * 4
            print(f"    {tag}: {la}[{i1}:{i2}] ({i2-i1} cells) <-> "
                  f"{lb}[{j1}:{j2}] ({j2-j1} cells) -- shift from here on "
                  f"{shift_b:+d} B ({shift_b//4:+d} words)")
            if args.verbose:
                for k in range(i1, min(i2, i1 + 8)):
                    print(f"      {la}[{k}] = {ca[k]:#010x}")
                for k in range(j1, min(j2, j1 + 8)):
                    print(f"      {lb}[{k}] = {cb[k]:#010x}")

    # Candidate corrections for a same-length substitution at (i, j). Two
    # sources of "shift": the LOCAL one, (j - i) * 4, valid at this opcode's
    # own position (right if there is exactly one length-changing region
    # between here and the start of the file); and the GLOBAL one, the
    # file-wide tlen delta, valid everywhere regardless of how many small
    # insert/delete pairs SequenceMatcher reports on the way there -- a
    # forward-referencing pointer (stored before the edit, pointing past it)
    # needs the global figure even though its own local shift reads zero.
    # Both are tried; duplicates (the common case, exactly one edit) collapse.
    global_shift = hb["tlen"] - ha["tlen"]
    def candidates(local_shift):
        out = [("entry-delta", entry_delta)]
        for name, s in (("local", local_shift), ("global", global_shift)):
            if s == 0:
                continue
            out.append((f"shift(+B,{name})", mask32(-s)))
            out.append((f"shift(-B,{name})", mask32(s)))
            if s % 4 == 0:
                out.append((f"shift(+word,{name})", mask32(-(s // 4))))
                out.append((f"shift(-word,{name})", mask32(s // 4)))
            if entry_delta:
                out.append((f"entry-delta+shift({name})", mask32(entry_delta - s)))
                out.append((f"entry-delta-shift({name})", mask32(entry_delta + s)))
        return out

    # Text/data (user-area) boundary, per side -- tlen may itself differ
    # (that is what a length-changing region means), so each side's own
    # header value decides which region a given index falls in.
    ta, tb = ha["tlen"] // 4, hb["tlen"] // 4

    explained = {}
    residual = []
    user_area = []
    for tag, i1, i2, j1, j2 in ops:
        if tag == "equal" or (i2 - i1) != (j2 - j1):
            continue  # equal cells need no explanation; length changes handled above
        local_shift = (j1 - i1) * 4
        cand = candidates(local_shift)
        for k in range(i2 - i1):
            i, j = i1 + k, j1 + k
            va, vb = ca[i], cb[j]
            d = mask32(va - vb)
            hit = next((name for name, val in cand if val and d == val), None)
            if hit:
                explained[hit] = explained.get(hit, 0) + 1
            elif i >= ta or j >= tb:
                user_area.append((i, j, va, vb))
            else:
                residual.append((i, j, va, vb, local_shift))

    if explained:
        print("  same-length substitutions explained:")
        for name, n in sorted(explained.items(), key=lambda kv: -kv[1]):
            print(f"    {name}: {n}")
    if user_area and not pin_mode:
        print(f"  data/user-area region (cell >= tlen/4): {len(user_area)} cells "
              "differ, unexplained by any correction above -- TESTS 5.2's "
              "engine-binary-address class (saved user-area tail: dead at cold "
              "start, never scored as a defect). Not counted against PASS/FAIL:")
        for i, j, va, vb in user_area[:20]:
            print(f"    {la}[{i}] = {va:#010x}   {lb}[{j}] = {vb:#010x}")
        if len(user_area) > 20:
            print(f"    ... and {len(user_area) - 20} more")

    pin_bad = False
    if pin_mode:
        da, db = ca[ta:], cb[tb:]
        dcells = [k for k in range(min(len(da), len(db))) if da[k] != db[k]]
        cand_u = candidates((tb - ta) * 4)
        by_rule, unexplained = {}, []
        for k in dcells:
            d = mask32(da[k] - db[k])
            hit = next((n for n, v in cand_u if v and d == v), None)
            if hit: by_rule[hit] = by_rule.get(hit, 0) + 1
            else: unexplained.append(k)
        rules = ", ".join(f"{n} {c}" for n, c in sorted(by_rule.items(), key=lambda kv: -kv[1])) or "none"
        if args.write_user_pin:
            with open(args.write_user_pin, "w") as fh:
                fh.write("# Data-segment cells (counted from its start) that differ from Sun's copy and that no correction explains\n"
                         "# (entry delta, length shift, both): the engine-binary-address and run-time class. dic-diff.py --user-pin.\n")
                for k in unexplained: fh.write(f"{k}\n")
            print(f"  data segment: {len(dcells)} of {len(da)} cells differ; explained by a correction: {rules}; "
                  f"wrote the {len(unexplained)} unexplained to {args.write_user_pin}")
        else:
            pinned = [int(x.split("#")[0]) for x in open(args.user_pin) if x.split("#")[0].strip()]
            new, gone = sorted(set(unexplained) - set(pinned)), sorted(set(pinned) - set(unexplained))
            print(f"  data segment: {len(dcells)} of {len(da)} cells differ; explained by a correction: {rules}; "
                  f"unexplained {len(unexplained)}, pinned {len(pinned)} in {args.user_pin}")
            if new:
                print(f"  NOT PINNED, differ and no correction explains them: cells {new[:20]}{' ...' if len(new) > 20 else ''}")
                for k in new[:10]: print(f"    cell {k}: {la}={da[k]:#010x} {lb}={db[k]:#010x} diff {mask32(da[k] - db[k]):#010x}")
            if gone:
                print(f"  PINNED, now equal or explained by a correction: cells {gone[:20]}{' ...' if len(gone) > 20 else ''}")
            pin_bad = bool(new or gone)

    print(f"  residual in the text region (no candidate matched): {len(residual)}")
    if residual:
        print("  UNEXPLAINED cells:")
        for i, j, va, vb, s in residual[:40]:
            print(f"    {la}[{i}] = {va:#010x}   {lb}[{j}] = {vb:#010x}   "
                  f"diff {mask32(va - vb):#010x}   local shift {s:+d} B")
        if len(residual) > 40:
            print(f"    ... and {len(residual) - 40} more")
        print("FAIL: unexplained content difference in the text region")
        return 1

    if pin_bad:
        print("FAIL: the data segment (user area) differs from Sun's in other cells than the pin lists")
        return 1

    print("PASS: every text-region difference is entry-delta rebasing, a "
          "named length-changing region, or a shift/call-shift correction "
          "across one; data/user-area differences are the accepted class")
    return 0

if __name__ == "__main__":
    sys.exit(main())
