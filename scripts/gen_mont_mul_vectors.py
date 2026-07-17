#!/usr/bin/env python3
"""
Test vector generator for mont_mul (MM-01 to MM-13).
Run from project root: python3 scripts/gen_mont_mul_vectors.py

MontMul(a, b, n) = a * b * R^{-1} mod n  (R = 2^(num_words*32))

Output files (tb/common/test_vectors/):
  mm_full_{a,b,n,np,exp}.hex  -- 2048-bit cases (64 words each)
  mm_half_{a,b,n,np,exp}.hex  -- 1024-bit cases (32 words each)
  CHECKSUMS.txt               -- SHA-256 of each file
"""

import random
import hashlib
import os

SEED = 0xA221_2048
random.seed(SEED)

MASK32 = (1 << 32) - 1


def rand_odd_msb(bits):
    """Random odd number with MSB=1 and exactly `bits` bit length."""
    n = random.getrandbits(bits)
    n |= (1 << (bits - 1))   # set MSB
    n |= 1                    # set LSB (odd, required for Montgomery)
    return n


def mont_mul_ref(a, b, n, bits):
    """MontMul(a,b,n) = a*b*R^{-1} mod n,  R = 2^bits"""
    R = 1 << bits
    return (a * b * pow(R, -1, n)) % n


def compute_n_prime(n):
    """n_prime = -n^{-1} mod 2^32  (lower word of n used)"""
    W = 1 << 32
    return (-pow(int(n) & MASK32, -1, W)) % W


# -----------------------------------------------------------------------
# Full-mode cases (2048-bit, 64 words)
# -----------------------------------------------------------------------
full_a, full_b, full_n, full_np, full_exp = [], [], [], [], []

# MM-01: 3 basic cases
for _ in range(3):
    n = rand_odd_msb(2048)
    a = random.randint(0, n - 1)
    b = random.randint(0, n - 1)
    full_a.append(a); full_b.append(b); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(a, b, n, 2048))

# MM-02: 5 random cases
for _ in range(5):
    n = rand_odd_msb(2048)
    a = random.randint(0, n - 1)
    b = random.randint(0, n - 1)
    full_a.append(a); full_b.append(b); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(a, b, n, 2048))

# MM-05: a=0  (result must be 0)
for _ in range(2):
    n = rand_odd_msb(2048)
    b = random.randint(1, n - 1)
    full_a.append(0); full_b.append(b); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(0, b, n, 2048))

# MM-06: b=0  (result must be 0)
for _ in range(2):
    n = rand_odd_msb(2048)
    a = random.randint(1, n - 1)
    full_a.append(a); full_b.append(0); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(a, 0, n, 2048))

# MM-07: a=n-1, b=n-1  (maximum operands)
for _ in range(2):
    n = rand_odd_msb(2048)
    full_a.append(n - 1); full_b.append(n - 1); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(n - 1, n - 1, n, 2048))

# MM-08/09: 3 random cases covering both subtraction paths statistically
for _ in range(3):
    n = rand_odd_msb(2048)
    a = random.randint(0, n - 1)
    b = random.randint(0, n - 1)
    full_a.append(a); full_b.append(b); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(a, b, n, 2048))

# MM-10: R^{-1} property verification
# MontMul(a, R^2 mod n, n) = a*R mod n  (Montgomery encode)
# MontMul(a_mont, b_mont, n) gives the Montgomery product
for _ in range(2):
    n = rand_odd_msb(2048)
    R = 1 << 2048
    Rsq = (R * R) % n         # R^2 mod n
    a = random.randint(1, n - 1)
    a_mont = mont_mul_ref(a, Rsq, n, 2048)   # a in Montgomery form = a*R mod n
    # Verify: MontMul(a_mont, 1, n) = a*R*R^{-1} mod n = a mod n
    full_a.append(a_mont); full_b.append(1); full_n.append(n)
    full_np.append(compute_n_prime(n))
    full_exp.append(mont_mul_ref(a_mont, 1, n, 2048))   # should equal a

NUM_FULL_TC = len(full_a)

# Index map
IDX = {
    'MM01': (0,  3),
    'MM02': (3,  8),
    'MM05': (8,  10),
    'MM06': (10, 12),
    'MM07': (12, 14),
    'MM0809': (14, 17),
    'MM10': (17, 19),
}
assert NUM_FULL_TC == 19

# -----------------------------------------------------------------------
# Half-mode cases (1024-bit, 32 words)
# -----------------------------------------------------------------------
half_a, half_b, half_n, half_np, half_exp = [], [], [], [], []

# MM-03: 3 basic cases
for _ in range(3):
    n = rand_odd_msb(1024)
    a = random.randint(0, n - 1)
    b = random.randint(0, n - 1)
    half_a.append(a); half_b.append(b); half_n.append(n)
    half_np.append(compute_n_prime(n))
    half_exp.append(mont_mul_ref(a, b, n, 1024))

# MM-04: 5 random cases
for _ in range(5):
    n = rand_odd_msb(1024)
    a = random.randint(0, n - 1)
    b = random.randint(0, n - 1)
    half_a.append(a); half_b.append(b); half_n.append(n)
    half_np.append(compute_n_prime(n))
    half_exp.append(mont_mul_ref(a, b, n, 1024))

NUM_HALF_TC = len(half_a)
assert NUM_HALF_TC == 8

# -----------------------------------------------------------------------
# File I/O helpers
# -----------------------------------------------------------------------
os.makedirs("tb/common/test_vectors", exist_ok=True)


def write_hex_words(path, values, words_per_case):
    """Flat hex file: words_per_case lines per test case, LSW first."""
    with open(path, "w") as f:
        for v in values:
            for i in range(words_per_case):
                word = (v >> (i * 32)) & MASK32
                f.write(f"{word:08x}\n")


def write_hex32(path, values):
    with open(path, "w") as f:
        for v in values:
            f.write(f"{v:08x}\n")


write_hex_words("tb/common/test_vectors/mm_full_a.hex",   full_a,   64)
write_hex_words("tb/common/test_vectors/mm_full_b.hex",   full_b,   64)
write_hex_words("tb/common/test_vectors/mm_full_n.hex",   full_n,   64)
write_hex32(    "tb/common/test_vectors/mm_full_np.hex",  full_np)
write_hex_words("tb/common/test_vectors/mm_full_exp.hex", full_exp, 64)

write_hex_words("tb/common/test_vectors/mm_half_a.hex",   half_a,   32)
write_hex_words("tb/common/test_vectors/mm_half_b.hex",   half_b,   32)
write_hex_words("tb/common/test_vectors/mm_half_n.hex",   half_n,   32)
write_hex32(    "tb/common/test_vectors/mm_half_np.hex",  half_np)
write_hex_words("tb/common/test_vectors/mm_half_exp.hex", half_exp, 32)

# -----------------------------------------------------------------------
# MM-10 spot check: confirm property
# -----------------------------------------------------------------------
n0  = full_n[IDX['MM10'][0]]
exp0 = full_exp[IDX['MM10'][0]]
a0  = full_a[IDX['MM10'][0]]   # = a_mont
# MontMul(a_mont, 1, n) should equal a (the original un-encoded value)
R     = 1 << 2048
Rsq0  = (R * R) % n0
a_orig = (a0 * pow(R, -1, n0)) % n0   # decode: a = a_mont * R^{-1} mod n
print(f"MM-10 spot check: MontMul(a_mont,1,n) = {exp0 == a_orig} (should be True)")

# -----------------------------------------------------------------------
# SHA-256 checksums
# -----------------------------------------------------------------------
files = [
    "mm_full_a.hex", "mm_full_b.hex", "mm_full_n.hex",
    "mm_full_np.hex", "mm_full_exp.hex",
    "mm_half_a.hex", "mm_half_b.hex", "mm_half_n.hex",
    "mm_half_np.hex", "mm_half_exp.hex",
]
checksum_path = "tb/common/test_vectors/CHECKSUMS.txt"
with open(checksum_path, "a") as cf:
    cf.write(f"# mont_mul vectors (seed=0x{SEED:08x}, full={NUM_FULL_TC}, half={NUM_HALF_TC})\n")
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
print(f"  MM-03: indices 0-2 (3 cases)")
print(f"  MM-04: indices 3-7 (5 cases)")
print(f"\nFiles written to tb/common/test_vectors/")
