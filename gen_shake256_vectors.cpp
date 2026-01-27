// Generates reference test vectors for shake256 Verilog testbench.
//
// Outputs shake256_vectors.hex: expected 64-bit output lanes for each test.
//
// Compile and run:
//   g++ -o gen_shake256_vectors gen_shake256_vectors.cpp shake256_cpp/shake256.cpp -Ishake256_cpp

#include "shake256.hpp"
#include <cstdio>
#include <cstring>

static void output_lanes(FILE *f, const std::vector<uint8_t>& digest, const char *label) {
    fprintf(stderr, "%s (%zu bytes):\n", label, digest.size());
    size_t n_lanes = (digest.size() + 7) / 8;
    for (size_t i = 0; i < n_lanes; i++) {
        uint64_t lane = 0;
        for (size_t j = 0; j < 8 && (i*8+j) < digest.size(); j++)
            lane |= (uint64_t)digest[i*8+j] << (8*j);
        fprintf(f, "%016llx\n", (unsigned long long)lane);
        fprintf(stderr, "  [%2zu] %016llx\n", i, (unsigned long long)lane);
    }
}

int main() {
    FILE *f = fopen("shake256_vectors.hex", "w");
    if (!f) { perror("fopen"); return 1; }

    Shake256 h;

    // Test 1: SHAKE256("", 32) — 4 lanes
    h.reset();
    auto d1 = h.digest(32);
    output_lanes(f, d1, "Test 1: SHAKE256('', 32)");

    // Test 2: SHAKE256("abc", 32) — 4 lanes
    h.reset();
    uint8_t abc[] = {0x61, 0x62, 0x63};
    h.update(abc, 3);
    auto d2 = h.digest(32);
    output_lanes(f, d2, "\nTest 2: SHAKE256('abc', 32)");

    // Test 3: SHAKE256(200 * 0xa3, 32) — 4 lanes
    h.reset();
    uint8_t a3[200];
    memset(a3, 0xa3, 200);
    h.update(a3, 200);
    auto d3 = h.digest(32);
    output_lanes(f, d3, "\nTest 3: SHAKE256(200*0xa3, 32)");

    // Test 4: SHAKE256("", 256) — 32 lanes (tests squeeze across rate boundary)
    h.reset();
    auto d4 = h.digest(256);
    output_lanes(f, d4, "\nTest 4: SHAKE256('', 256)");

    fclose(f);
    fprintf(stderr, "\nWrote shake256_vectors.hex (44 lines)\n");
    return 0;
}
