// Generates reference test vectors for keccak_f1600 Verilog testbench.
//
// Outputs f1600_vectors.hex: 50 lines of 64-bit hex values
// (2 test cases x 25 lanes per state).
//
// Compile and run:
//   g++ -o gen_f1600_vectors gen_f1600_vectors.cpp && ./gen_f1600_vectors

#include <cstdint>
#include <cstdio>
#include <cstring>

static const uint64_t RC[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

static const int RHO[24] = {
    1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
    27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44
};

static const int PI[24] = {
    10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1
};

static uint64_t rotl(uint64_t x, int n) {
    return (x << n) | (x >> (64 - n));
}

static void keccak_round(uint64_t state[25], int round_num) {
    uint64_t C[5];

    // Theta
    for (int x = 0; x < 5; x++)
        C[x] = state[x] ^ state[x+5] ^ state[x+10] ^ state[x+15] ^ state[x+20];
    for (int x = 0; x < 5; x++) {
        uint64_t t = C[(x+4) % 5] ^ rotl(C[(x+1) % 5], 1);
        for (int y = 0; y < 5; y++)
            state[x + 5*y] ^= t;
    }

    // Rho + Pi
    uint64_t last = state[1];
    for (int i = 0; i < 24; i++) {
        int j = PI[i];
        uint64_t temp = state[j];
        state[j] = rotl(last, RHO[i]);
        last = temp;
    }

    // Chi
    for (int y = 0; y < 5; y++) {
        uint64_t row[5];
        for (int x = 0; x < 5; x++)
            row[x] = state[x + 5*y];
        for (int x = 0; x < 5; x++)
            state[x + 5*y] = row[x] ^ ((~row[(x+1) % 5]) & row[(x+2) % 5]);
    }

    // Iota
    state[0] ^= RC[round_num];
}

static void keccak_f1600(uint64_t state[25]) {
    for (int r = 0; r < 24; r++)
        keccak_round(state, r);
}

static void write_state(FILE *f, const uint64_t state[25], const char *label) {
    fprintf(stderr, "%s:\n", label);
    for (int i = 0; i < 25; i++) {
        fprintf(f, "%016llx\n", (unsigned long long)state[i]);
        fprintf(stderr, "  Lane[%2d] = %016llx\n", i, (unsigned long long)state[i]);
    }
}

int main() {
    FILE *f = fopen("f1600_vectors.hex", "w");
    if (!f) {
        fprintf(stderr, "Error: cannot open f1600_vectors.hex\n");
        return 1;
    }

    uint64_t state[25];

    // Test 1: All-zeros
    memset(state, 0, sizeof(state));
    keccak_f1600(state);
    write_state(f, state, "Test 1: keccak_f1600(all-zeros)");

    // Test 2: Lane 0 = 0xDEADBEEFCAFEBABE
    memset(state, 0, sizeof(state));
    state[0] = 0xDEADBEEFCAFEBABEULL;
    keccak_f1600(state);
    write_state(f, state, "\nTest 2: keccak_f1600(lane0=DEADBEEFCAFEBABE)");

    fclose(f);
    fprintf(stderr, "\nWrote f1600_vectors.hex (50 lines)\n");
    return 0;
}
