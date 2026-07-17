#!/usr/bin/env python3
"""
Test vector generator for rsa_top (TOP-01 to TOP-16).
Run from project root: python3 scripts/gen_rsa_top_vectors.py

Generates 3 full RSA-2048 keypairs and, for each keypair, a message m together
with all intermediates that rsa_top needs to be exercised in public-key
(mode_i=0) and CRT (mode_i=1) modes.

Output files (tb/common/test_vectors/, 32-bit hex words, LSW first):

  Public-key parameters / golden outputs:
    rsa_top_msg.hex     (3 x 64 words) — message m (plaintext)
    rsa_top_cipher.hex  (3 x 64 words) — c = m^e mod n   (TOP-01 golden output)
    rsa_top_sig.hex     (3 x 64 words) — s = m^d mod n   (TOP-02 input / TOP-04 golden)
    rsa_top_exp.hex     (3 x 64 words) — e (=65537) zero-padded to 2048 bits
    rsa_top_mod.hex     (3 x 64 words) — n
    rsa_top_rsq.hex     (3 x 64 words) — R^2 mod n (R = 2^2048)
    rsa_top_nprime.hex  (3 x 1  word ) — n' = (-n^(-1)) mod 2^32

  CRT parameters / golden inputs:
    rsa_top_p.hex     / rsa_top_q.hex        (3 x 32 words each) — p, q
    rsa_top_dp.hex    / rsa_top_dq.hex       (3 x 32 words each) — dp, dq
    rsa_top_qinv.hex                         (3 x 32 words)      — q^(-1) mod p
    rsa_top_rsq_p.hex / rsa_top_rsq_q.hex    (3 x 32 words each) — R^2 mod p / mod q
    rsa_top_np_prime.hex / rsa_top_nq_prime.hex (3 x 1 word each) — (-p|q^(-1)) mod 2^32
    rsa_top_c_mod_p.hex / rsa_top_c_mod_q.hex (3 x 32 words each) — c mod p / mod q
                                                                     (TOP-03 input)
    rsa_top_m_mod_p.hex / rsa_top_m_mod_q.hex (3 x 32 words each) — m mod p / mod q
                                                                     (TOP-04 input)
"""

import random
import hashlib
import os

SEED = 0xAA12_2048
random.seed(SEED)

MASK32 = (1 << 32) - 1
E_FIXED = 65537
NUM_TC = 3
WORDS_FULL = 64   # 2048-bit / 32
WORDS_HALF = 32   # 1024-bit / 32


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
    for sp in small:
        if n % sp == 0:
            return n == sp
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
    while True:
        n = random.getrandbits(bits) | (1 << (bits - 1)) | 1
        if is_probable_prime(n):
            return n


# ---------------------------------------------------------------------------
# RSA helpers
# ---------------------------------------------------------------------------
def compute_n_prime(n):
    """n' = (-n^{-1}) mod 2^32  (lower 32 bits of n)."""
    W = 1 << 32
    return (-pow(int(n) & MASK32, -1, W)) % W


def compute_rsq(n, bits):
    """R^2 mod n where R = 2^bits."""
    R = 1 << bits
    return (R * R) % n


def gen_keypair(e=E_FIXED):
    """Generate a 2048-bit RSA keypair (p, q, d, dp, dq, qinv, n) with q < p."""
    while True:
        p = gen_prime(1024)
        q = gen_prime(1024)
        if p == q:
            continue
        # Enforce q < p so qinv = q^(-1) mod p is well-defined and matches the
        # convention used by crt_controller.
        if p < q:
            p, q = q, p
        try:
            d = pow(e, -1, (p - 1) * (q - 1))
        except ValueError:
            continue
        dp = d % (p - 1)
        dq = d % (q - 1)
        try:
            qinv = pow(q, -1, p)
        except ValueError:
            continue
        n = p * q
        return p, q, d, dp, dq, qinv, n


# ---------------------------------------------------------------------------
# Case accumulators
# ---------------------------------------------------------------------------
v_msg, v_cipher, v_sig = [], [], []
v_p, v_q = [], []
v_dp, v_dq = [], []
v_qinv = []
v_mod, v_rsq, v_rsq_p, v_rsq_q = [], [], [], []
v_nprime, v_np_prime, v_nq_prime = [], [], []
v_c_mod_p, v_c_mod_q = [], []
v_m_mod_p, v_m_mod_q = [], []

print(f"Generating {NUM_TC} RSA-2048 keypairs (this takes a few seconds per prime)...")
for tc in range(NUM_TC):
    p, q, d, dp, dq, qinv, n = gen_keypair(E_FIXED)
    # Pick a message in [2, n-1]
    m = random.randint(2, n - 1)
    c = pow(m, E_FIXED, n)
    s = pow(m, d, n)
    # Sanity round-trips
    assert pow(c, d, n) == m, f"sanity fail: Dec(Enc(m)) != m for tc={tc}"
    assert pow(s, E_FIXED, n) == m, f"sanity fail: Ver(Sign(m)) != m for tc={tc}"
    v_msg.append(m)
    v_cipher.append(c)
    v_sig.append(s)
    v_p.append(p)
    v_q.append(q)
    v_dp.append(dp)
    v_dq.append(dq)
    v_qinv.append(qinv)
    v_mod.append(n)
    v_rsq.append(compute_rsq(n, 2048))
    v_rsq_p.append(compute_rsq(p, 1024))
    v_rsq_q.append(compute_rsq(q, 1024))
    v_nprime.append(compute_n_prime(n))
    v_np_prime.append(compute_n_prime(p))
    v_nq_prime.append(compute_n_prime(q))
    v_c_mod_p.append(c % p)
    v_c_mod_q.append(c % q)
    v_m_mod_p.append(m % p)
    v_m_mod_q.append(m % q)
    print(f"  tc{tc}: keypair generated (n.bit_length={n.bit_length()})")


# ---------------------------------------------------------------------------
# File I/O helpers
# ---------------------------------------------------------------------------
os.makedirs("tb/common/test_vectors", exist_ok=True)


def write_hex_words(path, values, words_per_case):
    with open(path, "w") as f:
        for v in values:
            for i in range(words_per_case):
                w = (v >> (i * 32)) & MASK32
                f.write(f"{w:08x}\n")


def write_hex32(path, values):
    with open(path, "w") as f:
        for v in values:
            f.write(f"{v:08x}\n")


# Public-key parameters / golden outputs
write_hex_words("tb/common/test_vectors/rsa_top_msg.hex",     v_msg,    WORDS_FULL)
write_hex_words("tb/common/test_vectors/rsa_top_cipher.hex",  v_cipher, WORDS_FULL)
write_hex_words("tb/common/test_vectors/rsa_top_sig.hex",     v_sig,    WORDS_FULL)
write_hex_words("tb/common/test_vectors/rsa_top_exp.hex",     [E_FIXED] * NUM_TC, WORDS_FULL)
write_hex_words("tb/common/test_vectors/rsa_top_mod.hex",     v_mod,    WORDS_FULL)
write_hex_words("tb/common/test_vectors/rsa_top_rsq.hex",     v_rsq,    WORDS_FULL)
write_hex32(    "tb/common/test_vectors/rsa_top_nprime.hex",  v_nprime)

# CRT parameters / golden inputs
write_hex_words("tb/common/test_vectors/rsa_top_p.hex",        v_p,       WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_q.hex",        v_q,       WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_dp.hex",       v_dp,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_dq.hex",       v_dq,      WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_qinv.hex",     v_qinv,    WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_rsq_p.hex",    v_rsq_p,   WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_rsq_q.hex",    v_rsq_q,   WORDS_HALF)
write_hex32(    "tb/common/test_vectors/rsa_top_np_prime.hex", v_np_prime)
write_hex32(    "tb/common/test_vectors/rsa_top_nq_prime.hex", v_nq_prime)
write_hex_words("tb/common/test_vectors/rsa_top_c_mod_p.hex",  v_c_mod_p, WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_c_mod_q.hex",  v_c_mod_q, WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_m_mod_p.hex",  v_m_mod_p, WORDS_HALF)
write_hex_words("tb/common/test_vectors/rsa_top_m_mod_q.hex",  v_m_mod_q, WORDS_HALF)


# ---------------------------------------------------------------------------
# SHA-256 checksums (append to CHECKSUMS.txt)
# ---------------------------------------------------------------------------
files = [
    "rsa_top_msg.hex", "rsa_top_cipher.hex", "rsa_top_sig.hex",
    "rsa_top_exp.hex", "rsa_top_mod.hex", "rsa_top_rsq.hex",
    "rsa_top_nprime.hex",
    "rsa_top_p.hex", "rsa_top_q.hex",
    "rsa_top_dp.hex", "rsa_top_dq.hex", "rsa_top_qinv.hex",
    "rsa_top_rsq_p.hex", "rsa_top_rsq_q.hex",
    "rsa_top_np_prime.hex", "rsa_top_nq_prime.hex",
    "rsa_top_c_mod_p.hex", "rsa_top_c_mod_q.hex",
    "rsa_top_m_mod_p.hex", "rsa_top_m_mod_q.hex",
]
checksum_path = "tb/common/test_vectors/CHECKSUMS.txt"
with open(checksum_path, "a") as cf:
    cf.write(f"# rsa_top vectors (seed=0x{SEED:08x}, cases={NUM_TC}, e={E_FIXED})\n")
    for fname in files:
        fpath = f"tb/common/test_vectors/{fname}"
        with open(fpath, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()
        cf.write(f"SHA256({fname}): {sha}\n")
    cf.write("\n")


print(f"Generated {NUM_TC} RSA-2048 cases (e={E_FIXED}).")
print(f"Files written to tb/common/test_vectors/")
