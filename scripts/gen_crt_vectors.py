#!/usr/bin/env python3
"""
Test vector generator for crt_controller (CRT-01 to CRT-12).
Run from project root: python3 scripts/gen_crt_vectors.py

CRT decryption (RFC 8017 §5.1.2):
  m1 = base_p ^ dp mod p          (1024-bit modular exponentiation)
  m2 = base_q ^ dq mod q          (1024-bit modular exponentiation)
  h  = qinv * ((m1 - m2) mod p) mod p
  result = m2 + h * q             (2048-bit)

Output files (tb/common/test_vectors/):
  crt_p.hex / crt_q.hex / crt_dp.hex / crt_dq.hex / crt_qinv.hex
  crt_base_p.hex / crt_base_q.hex
  crt_rsq_p.hex / crt_rsq_q.hex
  crt_np_prime.hex / crt_nq_prime.hex
  crt_result.hex
  crt_m1.hex / crt_m2.hex / crt_hq.hex  (intermediate references for CRT-08/09)

Test case index map (6 cases total):
  CRT-01: indices 0-2  (3 cases, basic CRT decryption)
  CRT-03: index   3    (1 case,  m1 < m2 — borrow correction path)
  CRT-04: index   4    (1 case,  m1 >= m2 — no borrow correction)
  CRT-05: index   5    (1 case,  m1 == m2 → h == 0 → result == m2)
CRT-02 / CRT-06..12 reuse vector 0 (operational / protocol / boundary cases).
"""

import random
import hashlib
import os

SEED = 0x0C7C_2048  # CRT seed (RC ~= "CRT")
random.seed(SEED)

MASK32 = (1 << 32) - 1


# ---------------------------------------------------------------------------
# Prime generation (Miller-Rabin)
# ---------------------------------------------------------------------------
def is_probable_prime(n, k=20):
    if n < 2:
        return False
    if n in (2, 3):
        return True
    if n % 2 == 0:
        return False
    small = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]
    for p in small:
        if n % p == 0:
            return n == p
    d = n - 1
    r = 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(k):
        a = random.randint(2, n - 2)
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def gen_prime(bits):
    """Random odd prime with exactly `bits` bit length (MSB=1)."""
    while True:
        n = random.getrandbits(bits) | (1 << (bits - 1)) | 1
        if is_probable_prime(n):
            return n


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def compute_n_prime(n):
    """n_prime = -n^{-1} mod 2^32 (lower 32 bits of n)"""
    W = 1 << 32
    return (-pow(int(n) & MASK32, -1, W)) % W


def compute_rsq(n, bits):
    """R^2 mod n, where R = 2^bits"""
    R = 1 << bits
    return (R * R) % n


# ---------------------------------------------------------------------------
# CRT keypair / case generation
# ---------------------------------------------------------------------------
def gen_keypair(e=65537):
    """Generate a 2048-bit RSA keypair (p, q, dp, dq, qinv, n)."""
    while True:
        p = gen_prime(1024)
        q = gen_prime(1024)
        if p == q:
            continue
        # Ensure q < p so qinv = q^{-1} mod p exists and is unique
        if p < q:
            p, q = q, p
        try:
            d = pow(e, -1, (p - 1) * (q - 1))
        except ValueError:
            continue  # gcd(e, phi) != 1
        dp = d % (p - 1)
        dq = d % (q - 1)
        try:
            qinv = pow(q, -1, p)
        except ValueError:
            continue
        n = p * q
        return p, q, dp, dq, qinv, n


def crt_decrypt(c, p, q, dp, dq, qinv):
    """Reference CRT decryption."""
    m1 = pow(c % p, dp, p)
    m2 = pow(c % q, dq, q)
    h = (qinv * ((m1 - m2) % p)) % p
    return m2 + h * q


# ---------------------------------------------------------------------------
# Vector accumulators
# ---------------------------------------------------------------------------
v_p, v_q, v_dp, v_dq, v_qinv = [], [], [], [], []
v_base_p, v_base_q = [], []
v_rsq_p, v_rsq_q = [], []
v_np_prime, v_nq_prime = [], []
v_result = []
v_m1, v_m2, v_hq = [], [], []


def add_case(p, q, dp, dq, qinv, base):
    """Add a CRT test case given (key, base/ciphertext)."""
    n = p * q
    m1 = pow(base % p, dp, p)
    m2 = pow(base % q, dq, q)
    h = (qinv * ((m1 - m2) % p)) % p
    result = m2 + h * q
    # Sanity: result equals pow(base, d, n) within [0, n)
    expected = pow(base, pow(65537, -1, (p - 1) * (q - 1)), n)
    assert result == expected, (
        f"CRT recombination mismatch: result={result:x} expected={expected:x}"
    )
    v_p.append(p)
    v_q.append(q)
    v_dp.append(dp)
    v_dq.append(dq)
    v_qinv.append(qinv)
    v_base_p.append(base % p)
    v_base_q.append(base % q)
    v_rsq_p.append(compute_rsq(p, 1024))
    v_rsq_q.append(compute_rsq(q, 1024))
    v_np_prime.append(compute_n_prime(p))
    v_nq_prime.append(compute_n_prime(q))
    v_result.append(result)
    v_m1.append(m1)
    v_m2.append(m2)
    v_hq.append(h * q)


# CRT-01: 3 basic keypairs with random ciphertext
keys = []
for _ in range(3):
    p, q, dp, dq, qinv, n = gen_keypair()
    keys.append((p, q, dp, dq, qinv, n))
    c = random.randint(2, n - 1)
    add_case(p, q, dp, dq, qinv, c)

# CRT-03: m1 < m2 (borrow correction needed)
p, q, dp, dq, qinv, n = gen_keypair()
keys.append((p, q, dp, dq, qinv, n))
attempts = 0
while True:
    c = random.randint(2, n - 1)
    m1 = pow(c % p, dp, p)
    m2 = pow(c % q, dq, q)
    if m1 < m2:
        break
    attempts += 1
    if attempts > 200:
        raise RuntimeError("Failed to find m1<m2 case in 200 attempts")
add_case(p, q, dp, dq, qinv, c)

# CRT-04: m1 >= m2 (no correction)
p, q, dp, dq, qinv, n = gen_keypair()
keys.append((p, q, dp, dq, qinv, n))
attempts = 0
while True:
    c = random.randint(2, n - 1)
    m1 = pow(c % p, dp, p)
    m2 = pow(c % q, dq, q)
    if m1 >= m2:
        break
    attempts += 1
    if attempts > 200:
        raise RuntimeError("Failed to find m1>=m2 case in 200 attempts")
add_case(p, q, dp, dq, qinv, c)

# CRT-05: m1 == m2 → h == 0 → result == m2
# Easiest realization: choose base such that base mod p == base mod q.
# c = 1 gives m1 = m2 = 1 trivially.
p, q, dp, dq, qinv, n = gen_keypair()
keys.append((p, q, dp, dq, qinv, n))
c = 1
add_case(p, q, dp, dq, qinv, c)
assert v_m1[-1] == v_m2[-1], "CRT-05 setup: m1 must equal m2"
assert v_hq[-1] == 0, "CRT-05 setup: h*q must be 0"
assert v_result[-1] == v_m2[-1], "CRT-05 setup: result must equal m2"

NUM_TC = len(v_p)
assert NUM_TC == 6, f"Expected 6 cases, got {NUM_TC}"

WORDS_HALF = 32   # 1024-bit values
WORDS_FULL = 64   # 2048-bit values


# ---------------------------------------------------------------------------
# File I/O helpers
# ---------------------------------------------------------------------------
os.makedirs("tb/common/test_vectors", exist_ok=True)


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


write_hex_words("tb/common/test_vectors/crt_p.hex",       v_p,       WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_q.hex",       v_q,       WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_dp.hex",      v_dp,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_dq.hex",      v_dq,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_qinv.hex",    v_qinv,    WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_base_p.hex",  v_base_p,  WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_base_q.hex",  v_base_q,  WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_rsq_p.hex",   v_rsq_p,   WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_rsq_q.hex",   v_rsq_q,   WORDS_HALF)
write_hex32(    "tb/common/test_vectors/crt_np_prime.hex", v_np_prime)
write_hex32(    "tb/common/test_vectors/crt_nq_prime.hex", v_nq_prime)
write_hex_words("tb/common/test_vectors/crt_result.hex",  v_result,  WORDS_FULL)
write_hex_words("tb/common/test_vectors/crt_m1.hex",      v_m1,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_m2.hex",      v_m2,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/crt_hq.hex",      v_hq,      WORDS_FULL)


# ---------------------------------------------------------------------------
# SHA-256 checksums
# ---------------------------------------------------------------------------
files = [
    "crt_p.hex", "crt_q.hex", "crt_dp.hex", "crt_dq.hex", "crt_qinv.hex",
    "crt_base_p.hex", "crt_base_q.hex",
    "crt_rsq_p.hex", "crt_rsq_q.hex",
    "crt_np_prime.hex", "crt_nq_prime.hex",
    "crt_result.hex", "crt_m1.hex", "crt_m2.hex", "crt_hq.hex",
]
checksum_path = "tb/common/test_vectors/CHECKSUMS.txt"
with open(checksum_path, "a") as cf:
    cf.write(f"# crt_controller vectors (seed=0x{SEED:08x}, cases={NUM_TC})\n")
    for fname in files:
        fpath = f"tb/common/test_vectors/{fname}"
        with open(fpath, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()
        cf.write(f"SHA256({fname}): {sha}\n")
    cf.write("\n")

print(f"Generated {NUM_TC} CRT cases:")
print(f"  CRT-01: indices 0-2 (3 cases, basic CRT)")
print(f"  CRT-03: index   3   (m1 < m2, borrow correction)")
print(f"  CRT-04: index   4   (m1 >= m2, no correction)")
print(f"  CRT-05: index   5   (m1 == m2, h == 0)")
print(f"Files written to tb/common/test_vectors/")
