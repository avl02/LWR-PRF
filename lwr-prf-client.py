"""
This implementation:

Follows the depth-1 PRF formula from Section 5 exactly
Uses SHA-256 as the hash function H to map inputs to vectors in Z_{2N}^n
Implements the full encryption/decryption for transciphering
Handles multiple outputs by using different indices in the hash

The key operations are:

Computing <a,s> mod 2N to get the MSB
Computing <a,s> mod N for the rounding operation
Applying the sign based on the MSB
All arithmetic is done with appropriate modular reductions

This client-side code generates the ciphertexts that would be sent to the cloud, where the homomorphic evaluation would produce FHE encryptions of the same PRF outputs.
"""


from hashlib import shake_256
import numpy as np
from typing import List, Tuple
import json
import os

class LWR_PRF_Client:
    def __init__(self, n: int, N: int, p: int, seed = None, key_file: str = "secret_key.json", force_regenerate: bool = False):
        """
        Initialize the PRF with parameters.

        Args:
            n: Dimension of the secret key (e.g., 445 for the paper's example)
            N: Ring dimension, must be power of 2 (e.g., 2048)
            p: Plaintext modulus (e.g., 32 for 5-bit outputs)
            seed: Random seed for key generation (only used if generating new key)
            key_file: Path to JSON file for storing/loading secret key
            force_regenerate: If True, generate new key even if file exists
        """
        self.n = n
        self.N = N
        self.p = p
        self.key_file = key_file

        # Try to load existing secret key
        if not force_regenerate and os.path.exists(key_file):
            self._load_secret_key()
        else:
            # Generate new binary secret key
            if force_regenerate and os.path.exists(key_file):
                print(f"Force regenerating secret key (overwriting {key_file})...")
            else:
                print(f"Generating new secret key...")

            if seed is not None:
                np.random.seed(seed)
            self.s = np.random.randint(0, 2, size=n, dtype=np.uint64)

            # Save the newly generated key
            self._save_secret_key()
            print(f"✓ Secret key generated and saved to {key_file} (n_lwr = {n})")

        print(f"Secret key s (first 20): {self.s[:20]}")
        print(f"Secret key s (last 20): {self.s[-20:]}")

    def _save_secret_key(self):
        """Save the secret key to JSON file."""
        key_data = {
            "n_lwr": int(self.n),
            "secret_key": self.s.tolist()
        }
        with open(self.key_file, 'w') as f:
            json.dump(key_data, f, indent=2)

    def _load_secret_key(self):
        """Load the secret key from JSON file."""
        print(f"Loading secret key from {self.key_file}...")

        with open(self.key_file, 'r') as f:
            key_data = json.load(f)

        # Validate dimension
        if key_data["n_lwr"] != self.n:
            raise ValueError(
                f"Dimension mismatch: expected {self.n}, got {key_data['n_lwr']} in file"
            )

        # Load secret key
        self.s = np.array(key_data["secret_key"], dtype=np.uint64)

        # Validate all values are binary
        if not np.all((self.s == 0) | (self.s == 1)):
            raise ValueError("Secret key contains non-binary values")

        print(f"✓ Secret key loaded successfully (n_lwr = {key_data['n_lwr']})")
        
    def hash_to_vector(self, x: bytes, index: int = 0) -> np.ndarray:
        """
        Hash function H: {0,1}* -> Z_{2N}^n
        Uses SHAKE256 XOF to generate n elements in Z_{2N}

        This matches the Rust implementation for client-server compatibility.

        Args:
            x: Input bytes (nonce)
            index: Optional index for multiple PRF outputs (slot index)
        """
        # Use SHAKE256 XOF (eXtendable Output Function) to match Rust implementation
        hasher = shake_256()
        hasher.update(x) # absorb x into hasher
        # Use 8 bytes little-endian to match Rust's usize::to_le_bytes()
        hasher.update(index.to_bytes(8, 'little')) # absorb index into hasher

        # Generate n * 8 bytes from the XOF
        digest = hasher.digest(self.n * 8) # output bytes of hash of input and index

        # Create deterministic vector from XOF output
        a = np.zeros(self.n, dtype=np.uint64)

        for i in range(self.n):
            # Extract 8 bytes and convert to u64 (little-endian to match Rust)
            value = int.from_bytes(digest[i*8:(i+1)*8], 'little')
            a[i] = value % (2 * self.N)

        return a
    
    def evaluate(self, x: bytes) -> int:
        """
        Evaluate PRF_s(x) according to the depth-1 construction:
        PRF_s(x) = (-1)^msb(<H(x),s> mod 2N) * floor(p/N * (<H(x),s> mod N)) mod p
        
        Args:
            x: Input to the PRF
            
        Returns:
            PRF output in Z_p
        """
        # Get hash vector a = H(x)
        a = self.hash_to_vector(x)
        
        # Compute inner product <a,s>
        # print(a.shape, self.s.shape)
        inner_product = np.dot(a, self.s)
        
        # Compute <a,s> mod 2N
        inner_mod_2N = inner_product % (2 * self.N)
        
        # Extract MSB (check if >= N)
        msb = 1 if inner_mod_2N >= self.N else 0
        
        # Compute <a,s> mod N
        inner_mod_N = inner_product % self.N
        
        # Compute floor(p/N * inner_mod_N)
        # Using integer division for floor
        rounded = (self.p * inner_mod_N) // self.N
        
        # Apply sign from MSB
        if msb == 1:
            # result = (-rounded) % self.p # Original line
            # Using (p - x) % p as an elegant alternative to (-x) % p
            result = (self.p - rounded) % self.p
        else:
            result = rounded % self.p
            
        return result
    
    def evaluate_multiple(self, x: bytes, count: int) -> List[int]:
        """
        Generate multiple PRF outputs for the same input.
        Uses different indices to get independent outputs.
        
        Args:
            x: Input to the PRF
            count: Number of outputs needed
            
        Returns:
            List of PRF outputs
        """
        outputs = []
        for i in range(count):
            a = self.hash_to_vector(x, index=i)
            inner_product = np.dot(a, self.s)
            inner_mod_2N = inner_product % (2 * self.N)
            msb = 1 if inner_mod_2N >= self.N else 0
            inner_mod_N = inner_product % self.N
            rounded = (self.p * inner_mod_N) // self.N
            
            if msb == 1:
                # result = (-rounded) % self.p # Original line
                # Using (p - x) % p as an elegant alternative to (-x) % p
                result = (self.p - rounded) % self.p
            else:
                result = rounded % self.p
                
            outputs.append(result)
            
        return outputs
    
    def encrypt_message(self, message: List[int], nonce: bytes) -> Tuple[bytes, List[int]]:
        """
        Encrypt a message using the PRF in counter mode.
        
        Args:
            message: List of integers in Z_p
            nonce: Random nonce/IV
            
        Returns:
            (nonce, ciphertext) tuple
        """
        # Generate PRF stream
        prf_stream = self.evaluate_multiple(nonce, len(message))
        
        # Encrypt by adding PRF output mod p
        ciphertext = [(m + prf) % self.p for m, prf in zip(message, prf_stream)]
        
        return (nonce, ciphertext)
    
    def decrypt_message(self, nonce: bytes, ciphertext: List[int]) -> List[int]:
        """
        Decrypt a message.
        
        Args:
            nonce: The nonce used for encryption
            ciphertext: List of integers in Z_p
            
        Returns:
            Decrypted message
        """
        # Generate same PRF stream
        prf_stream = self.evaluate_multiple(nonce, len(ciphertext))

        print(f"PRF Stream: {prf_stream}")  # Debugging line to show PRF stream
        
        # Decrypt by subtracting PRF output mod p
        # message = [(c - prf) % self.p for c, prf in zip(ciphertext, prf_stream)] # Original line
        # To calculate (c - prf) % p, it calculates (c - prf + p) % p to ensure the number is positive before the modulo operation.
        message = [ (int(c) + self.p - int(prf)) % self.p for c, prf in zip(ciphertext, prf_stream) ]
        
        return message


# Example usage
if __name__ == "__main__":
    # Parameters from the paper (PARAM_MESSAGE_2_CARRY_2)
    n = 445  # LWR dimension (was 742)
    N = 2048  # Ring dimension
    p = 32   # Plaintext modulus (5 bits)

    # Create PRF instance (load existing key from secret_key.json)
    prf = LWR_PRF_Client(n=n, N=N, p=p, seed=42, force_regenerate=False)
    
    # Test single PRF evaluation
    test_input = b"some_seed"
    output = prf.evaluate(test_input)
    print(f"PRF({test_input}) = {output}")

    # Test multiple PRF evaluations for comparison with Rust
    print(f"\n=== Generating 10 PRF values with nonce '{test_input.decode()}' ===")
    prf_values = prf.evaluate_multiple(test_input, 10)
    for i, val in enumerate(prf_values):
        print(f"PRF[{i}] = {val}")
    print("=" * 60)

    # Test message encryption/decryption
    message = [10, 20, 15, 8, 31, 18, 0, 21, 3, 6]  # Message in Z_32
    nonce = b"some_seed"

    print(f"\nOriginal message: {message}")

    # Encrypt
    _, ciphertext = prf.encrypt_message(message, nonce)
    print(f"Ciphertext: {ciphertext}")

    # Decrypt
    decrypted = prf.decrypt_message(nonce, ciphertext)
    print(f"Decrypted: {decrypted}")

    # Verify correctness
    assert message == decrypted, "Decryption failed!"
    print("Encryption/decryption successful!")
