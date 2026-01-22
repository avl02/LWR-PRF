"""
Generate test vectors for Verilog hardware verification.

This script:
1. Loads the LWR-PRF client with the same parameters as hardware
2. Generates a hash vector for a test nonce and index
3. Saves hash_vector.mem for the hash stub module
4. Saves secret_key.mem for the secret key module
5. Computes and prints expected intermediate values for verification
"""

import sys
import os
import numpy as np

# Add parent directory to path to import lwr_prf_client
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import the Python implementation
# We need to use importlib
import importlib.util
spec = importlib.util.spec_from_file_location("lwr_prf_client", "lwr-prf-client.py")
lwr_prf_client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lwr_prf_client)

LWR_PRF_Client = lwr_prf_client.LWR_PRF_Client


def main():
    # Parameters matching hardware implementation
    n = 445      # N_LWR
    N = 2048     # N (ring dimension)
    p = 32       # P (plaintext modulus)

    print("=" * 80)
    print("LWR-PRF Hardware Test Vector Generation")
    print("=" * 80)
    print(f"Parameters: n={n}, N={N}, p={p}")
    print()

    # Initialize PRF client (loads or generates secret key)
    prf = LWR_PRF_Client(n=n, N=N, p=p, seed=42, force_regenerate=False)
    print()

    # Test case: Use a simple nonce
    nonce = b"test_nonce"
    index = 0

    print(f"Test Case:")
    print(f"  Nonce: {nonce}")
    print(f"  Index: {index}")
    print()

    # =========================================================================
    # Generate hash vector
    # =========================================================================
    print("Generating hash vector...")
    a = prf.hash_to_vector(nonce, index)

    # Save to .mem file for Verilog (hexadecimal format)
    with open("hash_vector.mem", "w") as f:
        for val in a:
            # Each value is in Z_{2*N} = Z_{4096}, needs 12 bits (3 hex digits)
            f.write(f"{val:03x}\n")

    print(f"✓ Hash vector saved to hash_vector.mem ({len(a)} elements)")
    print(f"  First 10 values: {a[:10].tolist()}")
    print(f"  Last 10 values:  {a[-10:].tolist()}")
    print()

    # =========================================================================
    # Save secret key
    # =========================================================================
    print("Saving secret key...")
    with open("secret_key.mem", "w") as f:
        for bit in prf.s:
            f.write(f"{bit}\n")

    print(f"✓ Secret key saved to secret_key.mem ({len(prf.s)} bits)")
    print(f"  First 20 bits: {prf.s[:20].tolist()}")
    print(f"  Last 20 bits:  {prf.s[-20:].tolist()}")
    print()

    # =========================================================================
    # Compute expected intermediate values
    # =========================================================================
    print("Computing expected intermediate values...")
    print("-" * 80)

    # Step 1: Dot product <a, s>
    inner_product = np.dot(a, prf.s)
    print(f"1. Dot Product <a,s>:")
    print(f"   inner_product = {inner_product}")
    print()

    # Step 2: Modular reductions
    inner_mod_2N = inner_product % (2 * N)
    inner_mod_N = inner_product % N
    print(f"2. Modular Reductions:")
    print(f"   inner_product mod 2N = {inner_mod_2N}")
    print(f"   inner_product mod N  = {inner_mod_N}")
    print()

    # Step 3: Extract MSB
    msb = 1 if inner_mod_2N >= N else 0
    print(f"3. MSB Extraction:")
    print(f"   MSB = {msb} (inner_mod_2N {'≥' if msb else '<'} N)")
    print()

    # Step 4: Rounding
    rounded = (p * inner_mod_N) // N
    print(f"4. Rounding Operation:")
    print(f"   rounded = floor({p} * {inner_mod_N} / {N})")
    print(f"   rounded = {rounded}")
    print()

    # Step 5: Apply sign and modular reduction
    if msb == 1:
        prf_out = (p - rounded) % p
        print(f"5. Apply Sign (MSB=1, negate):")
        print(f"   prf_out = ({p} - {rounded}) mod {p} = {prf_out}")
    else:
        prf_out = rounded % p
        print(f"5. Apply Sign (MSB=0, keep positive):")
        print(f"   prf_out = {rounded} mod {p} = {prf_out}")
    print()

    # Verify against Python implementation
    expected_prf = prf.evaluate(nonce)
    if prf_out == expected_prf:
        print(f"✓ Manual calculation matches prf.evaluate(): {prf_out}")
    else:
        print(f"✗ ERROR: Manual calculation ({prf_out}) != prf.evaluate() ({expected_prf})")
    print()

    # =========================================================================
    # Test encryption/decryption
    # =========================================================================
    print("Testing encryption/decryption...")
    print("-" * 80)

    # Test with the first message value from the Python example
    plaintext = 10
    ciphertext = (plaintext + prf_out) % p
    decrypted = (ciphertext - prf_out + p) % p

    print(f"Plaintext:  {plaintext}")
    print(f"PRF output: {prf_out}")
    print(f"Ciphertext: ({plaintext} + {prf_out}) mod {p} = {ciphertext}")
    print(f"Decrypted:  ({ciphertext} - {prf_out}) mod {p} = {decrypted}")
    print()

    if decrypted == plaintext:
        print(f"✓ Encryption/decryption round-trip successful")
    else:
        print(f"✗ ERROR: Round-trip failed!")
    print()

    # =========================================================================
    # Summary for Verilog testbench
    # =========================================================================
    print("=" * 80)
    print("EXPECTED VALUES FOR VERILOG TESTBENCH")
    print("=" * 80)
    print(f"Inner Product:     {inner_product}")
    print(f"Inner mod 2N:      {inner_mod_2N}")
    print(f"Inner mod N:       {inner_mod_N}")
    print(f"MSB:               {msb}")
    print(f"Rounded:           {rounded}")
    print(f"PRF Output:        {prf_out}")
    print(f"")
    print(f"Test encryption:")
    print(f"  Plaintext:       {plaintext}")
    print(f"  Ciphertext:      {ciphertext}")
    print(f"  Decrypted:       {decrypted}")
    print("=" * 80)
    print()

    print("Files generated:")
    print("  ✓ hash_vector.mem  - Hash vector for hash_to_vector module")
    print("  ✓ secret_key.mem   - Binary secret key for secret_key module")
    print()
    print("Next step: Run Verilog simulation and compare outputs!")


if __name__ == "__main__":
    main()
