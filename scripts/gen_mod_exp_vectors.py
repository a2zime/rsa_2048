#!/usr/bin/env python3
"""
Test vector generator for mod_exp (ME-01 to ME-16).
Run from project root: python3 scripts/gen_mod_exp_vectors.py

ModExp(base, exp, n) = base^exp mod n

Output files (tb/common/test_vectors/):
  me_full_{base,exp,n,np,rsq,result}.hex  -- 2048-bit cases (64 words each, np=1 word/case)
  me_half_{base,exp,n,np,rsq,result}.hex  -- 1024-bit cases (32 words each, np=1 word/case)
  CHECKSUMS.txt (appended)

Test case index map (full mode, 23 cases):
  ME01: indices  0- 2 (3 cases, e=65537)
  ME02: indices  3- 5 (3 cases, e=3)
  ME03: indices  6-10 (5 cases, random e)
  ME05: indices 11-12 (2 cases, exp=0)
  ME06: indices 13-14 (2 cases, exp=1)
  ME07: indices 15-16 (2 cases, base=0)
  ME08: indices 17-18 (2 cases, base=1)
  ME09: indices 19-20 (2 cases, base=n-1)
  ME10: index   21    (1 case,  exp=2^2047)
  ME11: index   22    (1 case,  exp=1 boundary)

Test case index map (half mode, 5 cases):
  ME04: indices 0-4 (5 cases, 1024-bit random)
"""

import random
import hashlib
import os

SEED = 0xB481_2048
random.seed(SEED)

MASK32 = (1 << 32) - 1


def rand_odd_msb(bits):
    """Random odd number with MSB=1 and exactly `bits` bit length."""
    n = random.getrandbits(bits)
    n |= (1 << (bits - 1))
    n |= 1
    return n


def compute_n_prime(n):
    """n_prime = -n^{-1} mod 2^32  (lower 32 bits of n)"""
    W = 1 << 32
    return (-pow(int(n) & MASK32, -1, W)) % W


def compute_rsq(n, bits):
    """R^2 mod n, where R = 2^bits"""
    R = 1 << bits
    return (R * R) % n


os.makedirs("tb/common/test_vectors", exist_ok=True)


# -----------------------------------------------------------------------
# Full-mode cases (2048-bit, 64 words)
# -----------------------------------------------------------------------
full_base, full_exp_v, full_n, full_np, full_rsq, full_result = [], [], [], [], [], []


def add_full(base, exp, n):
    full_base.append(base)
    full_exp_v.append(exp)
    full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_rsq.append(compute_rsq(n, 2048))
    full_result.append(pow(base, exp, n))


# ME-01: e=65537, 3 cases
for _ in range(3):
    n = rand_odd_msb(2048)
    base = random.randint(2, n - 1)
    add_full(base, 65537, n)

# ME-02: e=3, 3 cases
for _ in range(3):
    n = rand_odd_msb(2048)
    base = random.randint(2, n - 1)
    add_full(base, 3, n)

# ME-03: random 2048-bit exponent, 5 cases
for _ in range(5):
    n = rand_odd_msb(2048)
    base = random.randint(2, n - 1)
    e = random.randint(2, (1 << 2048) - 1)
    add_full(base, e, n)

# ME-05: exp=0 → result = 1 mod n, 2 cases
for _ in range(2):
    n = rand_odd_msb(2048)
    base = random.randint(1, n - 1)
    add_full(base, 0, n)

# ME-06: exp=1 → result = base mod n, 2 cases
for _ in range(2):
    n = rand_odd_msb(2048)
    base = random.randint(2, n - 1)
    add_full(base, 1, n)

# ME-07: base=0 → result = 0, 2 cases
for _ in range(2):
    n = rand_odd_msb(2048)
    add_full(0, 65537, n)

# ME-08: base=1 → result = 1, 2 cases
for _ in range(2):
    n = rand_odd_msb(2048)
    add_full(1, 65537, n)

# ME-09: base=n-1 → result depends on exp parity, 2 cases
for _ in range(2):
    n = rand_odd_msb(2048)
    e = random.randint(2, 65537)
    add_full(n - 1, e, n)

# ME-10: exp = 2^2047 (MSB only), 1 case
n = rand_odd_msb(2048)
base = random.randint(2, n - 1)
add_full(base, 1 << 2047, n)

# ME-11: exp=1 boundary (LSB only, same value as exp=1), 1 case
n = rand_odd_msb(2048)
base = random.randint(2, n - 1)
add_full(base, 1, n)

NUM_FULL_TC = len(full_base)

IDX = {
    'ME01': (0,  3),
    'ME02': (3,  6),
    'ME03': (6,  11),
    'ME05': (11, 13),
    'ME06': (13, 15),
    'ME07': (15, 17),
    'ME08': (17, 19),
    'ME09': (19, 21),
    'ME10': (21, 22),
    'ME11': (22, 23),
}
assert NUM_FULL_TC == 23, f"Expected 23 full cases, got {NUM_FULL_TC}"


# -----------------------------------------------------------------------
# Half-mode cases (1024-bit, 32 words) — ME-04
# -----------------------------------------------------------------------
half_base, half_exp_v, half_n, half_np, half_rsq, half_result = [], [], [], [], [], []


def add_half(base, exp, n):
    half_base.append(base)
    half_exp_v.append(exp)
    half_n.append(n)
    half_np.append(compute_n_prime(n))
    half_rsq.append(compute_rsq(n, 1024))
    half_result.append(pow(base, exp, n))


# ME-04: 1024-bit random exponent, 5 cases
for _ in range(5):
    n = rand_odd_msb(1024)
    base = random.randint(2, n - 1)
    e = random.randint(2, (1 << 1024) - 1)
    add_half(base, e, n)

NUM_HALF_TC = len(half_base)
assert NUM_HALF_TC == 5, f"Expected 5 half cases, got {NUM_HALF_TC}"


# -----------------------------------------------------------------------
# File I/O helpers
# -----------------------------------------------------------------------
def write_hex_words(path, values, words_per_case):
    """Flat hex file: words_per_case lines per test case, LSW first."""
    with open(path, "w") as f:
        for v in values:
            for i in range(words_per_case):
                word = (v >> (i * 32)) & MASK32
                f.write(f"{word:08x}\n")


def write_hex32(path, values):
    """One 32-bit hex value per line."""
    with open(path, "w") as f:
        for v in values:
            f.write(f"{v:08x}\n")


write_hex_words("tb/common/test_vectors/me_full_base.hex",   full_base,   64)
write_hex_words("tb/common/test_vectors/me_full_exp.hex",    full_exp_v,  64)
write_hex_words("tb/common/test_vectors/me_full_n.hex",      full_n,      64)
write_hex32(    "tb/common/test_vectors/me_full_np.hex",     full_np)
write_hex_words("tb/common/test_vectors/me_full_rsq.hex",    full_rsq,    64)
write_hex_words("tb/common/test_vectors/me_full_result.hex", full_result, 64)

write_hex_words("tb/common/test_vectors/me_half_base.hex",   half_base,   32)
write_hex_words("tb/common/test_vectors/me_half_exp.hex",    half_exp_v,  32)
write_hex_words("tb/common/test_vectors/me_half_n.hex",      half_n,      32)
write_hex32(    "tb/common/test_vectors/me_half_np.hex",     half_np)
write_hex_words("tb/common/test_vectors/me_half_rsq.hex",    half_rsq,    32)
write_hex_words("tb/common/test_vectors/me_half_result.hex", half_result, 32)


# -----------------------------------------------------------------------
# ME-16: expected mont_start count for ME-01[0] (e=65537)
# -----------------------------------------------------------------------
def expected_mont_start_count(e, bit_width):
    """
    Count expected mont_start_o assertions for given exponent and bit width.
    Breakdown:
      1  ToMont:    MontMul(base, R^2, n)
      1  InitR:     MontMul(1,    R^2, n)
      bit_width squares (one per exponent bit, MSB down to LSB)
      popcount(e)  multiplies (one per 1-bit in exponent)
      1  FromMont:  MontMul(result, 1, n)
    """
    return 1 + 1 + bit_width + bin(e).count('1') + 1


e0 = 65537
cnt = expected_mont_start_count(e0, 2048)
print(f"ME-16: e=65537, expected mont_start_o count = {cnt}")
print(f"  1 ToMont + 1 InitR + 2048 Squares + {bin(e0).count('1')} Muls + 1 FromMont")


# -----------------------------------------------------------------------
# Spot checks
# -----------------------------------------------------------------------
# ME-05: exp=0 must give result=1
for i, tc in enumerate(range(*IDX['ME05'])):
    assert full_result[tc] == 1, f"ME-05[{i}]: expected result=1, got {full_result[tc]}"
print("ME-05 spot check: all results = 1 ✓")

# ME-07: base=0 must give result=0
for i, tc in enumerate(range(*IDX['ME07'])):
    assert full_result[tc] == 0, f"ME-07[{i}]: expected result=0, got {full_result[tc]}"
print("ME-07 spot check: all results = 0 ✓")

# ME-08: base=1 must give result=1
for i, tc in enumerate(range(*IDX['ME08'])):
    assert full_result[tc] == 1, f"ME-08[{i}]: expected result=1, got {full_result[tc]}"
print("ME-08 spot check: all results = 1 ✓")

# ME-06/ME-11: exp=1 must give result=base
for i, tc in enumerate(list(range(*IDX['ME06'])) + list(range(*IDX['ME11']))):
    assert full_result[tc] == full_base[tc], \
        f"ME-06/11[{i}]: expected result=base, got {full_result[tc]}"
print("ME-06/ME-11 spot check: all results = base ✓")


# -----------------------------------------------------------------------
# SHA-256 checksums
# -----------------------------------------------------------------------
files = [
    "me_full_base.hex", "me_full_exp.hex", "me_full_n.hex",
    "me_full_np.hex", "me_full_rsq.hex", "me_full_result.hex",
    "me_half_base.hex", "me_half_exp.hex", "me_half_n.hex",
    "me_half_np.hex", "me_half_rsq.hex", "me_half_result.hex",
]
checksum_path = "tb/common/test_vectors/CHECKSUMS.txt"
with open(checksum_path, "a") as cf:
    cf.write(f"# mod_exp vectors (seed=0x{SEED:08x}, full={NUM_FULL_TC}, half={NUM_HALF_TC})\n")
    for fname in files:
        fpath = f"tb/common/test_vectors/{fname}"
        with open(fpath, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()
        cf.write(f"SHA256({fname}): {sha}\n")
    cf.write("\n")

print(f"\nGenerated {NUM_FULL_TC} full-mode (2048-bit) cases:")
for k, (s, e) in IDX.items():
    print(f"  {k}: indices {s}-{e-1} ({e-s} cases)")
print(f"\nGenerated {NUM_HALF_TC} half-mode (1024-bit) cases:")
print(f"  ME-04: indices 0-4 (5 cases)")
print(f"\nFiles written to tb/common/test_vectors/")
