#!/usr/bin/env python3
"""
Test vector generator for mul_add_unit (MAU-01 to MAU-06).
Run from project root: python3 scripts/gen_mul_add_vectors.py

Output files (tb/common/test_vectors/):
  mau_tv_a.hex      — a inputs (32-bit)
  mau_tv_b.hex      — b inputs (32-bit)
  mau_tv_c.hex      — c inputs (32-bit)
  mau_tv_exp_lo.hex — expected result[31:0]
  mau_tv_exp_hi.hex — expected result[63:32]
  CHECKSUMS.txt     — SHA-256 of each file
"""

import random
import hashlib
import os

SEED = 0xA221_2048
random.seed(SEED)

MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1


def ref_mul_add(a, b, c):
    return (a * b + c) & MASK64


cases = []

# MAU-01: basic multiply-only
cases.append((0x12345678, 0x9ABCDEF0, 0x00000000, "MAU-01"))

# MAU-02: 100 random cases
for _ in range(100):
    a = random.randint(0, MASK32)
    b = random.randint(0, MASK32)
    c = random.randint(0, MASK32)
    cases.append((a, b, c, "MAU-02"))

# MAU-03: a=0 (5 cases — result must equal c)
for _ in range(5):
    b = random.randint(1, MASK32)
    c = random.randint(0, MASK32)
    cases.append((0, b, c, "MAU-03"))

# MAU-04: b=0 (5 cases — result must equal c)
for _ in range(5):
    a = random.randint(1, MASK32)
    c = random.randint(0, MASK32)
    cases.append((a, 0, c, "MAU-04"))

# MAU-05/06: maximum inputs
# Python reference: (2^32-1)*(2^32-1)+(2^32-1) = (2^32-1)*2^32 = 0xFFFFFFFF_00000000
cases.append((0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, "MAU-05"))

NUM_TC = len(cases)

tv_a      = [c[0] for c in cases]
tv_b      = [c[1] for c in cases]
tv_c      = [c[2] for c in cases]
tv_exp    = [ref_mul_add(c[0], c[1], c[2]) for c in cases]
tv_exp_lo = [v & MASK32        for v in tv_exp]
tv_exp_hi = [(v >> 32) & MASK32 for v in tv_exp]

os.makedirs("tb/common/test_vectors", exist_ok=True)


def write_hex32(path, data):
    with open(path, "w") as f:
        for v in data:
            f.write(f"{v:08x}\n")


write_hex32("tb/common/test_vectors/mau_tv_a.hex",      tv_a)
write_hex32("tb/common/test_vectors/mau_tv_b.hex",      tv_b)
write_hex32("tb/common/test_vectors/mau_tv_c.hex",      tv_c)
write_hex32("tb/common/test_vectors/mau_tv_exp_lo.hex", tv_exp_lo)
write_hex32("tb/common/test_vectors/mau_tv_exp_hi.hex", tv_exp_hi)

# Verify MAU-05 expected value (spec v1.x has a typo; Python reference is authoritative)
exp05 = ref_mul_add(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)
print(f"MAU-05 Python reference: 0x{exp05:016x}")
print(f"  (spec says 0xFFFFFFFE_0000_0000 — testbench uses Python reference)")

# SHA-256 checksums
files = [
    "mau_tv_a.hex", "mau_tv_b.hex", "mau_tv_c.hex",
    "mau_tv_exp_lo.hex", "mau_tv_exp_hi.hex",
]
checksum_path = "tb/common/test_vectors/CHECKSUMS.txt"
with open(checksum_path, "a") as cf:
    cf.write(f"# mul_add_unit vectors (seed=0x{SEED:08x}, {NUM_TC} cases)\n")
    for fname in files:
        path = f"tb/common/test_vectors/{fname}"
        with open(path, "rb") as f:
            sha = hashlib.sha256(f.read()).hexdigest()
        cf.write(f"SHA256({fname}): {sha}\n")
    cf.write("\n")

print(f"\nGenerated {NUM_TC} test cases:")
print(f"  MAU-01 : index 0       (1 case,   basic multiply)")
print(f"  MAU-02 : indices 1-100 (100 cases, random)")
print(f"  MAU-03 : indices 101-105 (5 cases, a=0)")
print(f"  MAU-04 : indices 106-110 (5 cases, b=0)")
print(f"  MAU-05 : index 111     (1 case,   max inputs)")
print(f"\nFiles written to tb/common/test_vectors/")
