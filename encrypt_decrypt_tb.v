`timescale 1ns / 1ps

module encrypt_decrypt_tb;
    // Parameters
    localparam P = 32;
    localparam WIDTH = $clog2(P); // 5 bits

    // Signals
    reg [WIDTH-1:0] plaintext;
    reg [WIDTH-1:0] prf_out;
    wire [WIDTH-1:0] ciphertext;
    wire [WIDTH-1:0] decrypted;

    // Instantiate encrypt module
    encrypt #(
        .P(P)
    ) enc (
        .plaintext(plaintext),
        .prf_out(prf_out),
        .ciphertext(ciphertext)
    );

    // Instantiate decrypt module
    decrypt #(
        .P(P)
    ) dec (
        .ciphertext(ciphertext),
        .prf_out(prf_out),
        .plaintext(decrypted)
    );

    // Test vectors from Python example
    integer i;
    reg [WIDTH-1:0] test_plaintexts [0:9];
    reg [WIDTH-1:0] test_prf_outputs [0:9];

    integer pass_count;
    integer fail_count;

    initial begin
        // Test data (you can update these with actual PRF outputs from Python)
        // For now, using example message values from Python: [10, 20, 15, 8, 31, 18, 0, 21, 3, 6]
        test_plaintexts[0] = 10;
        test_plaintexts[1] = 20;
        test_plaintexts[2] = 15;
        test_plaintexts[3] = 8;
        test_plaintexts[4] = 31;
        test_plaintexts[5] = 18;
        test_plaintexts[6] = 0;
        test_plaintexts[7] = 21;
        test_plaintexts[8] = 3;
        test_plaintexts[9] = 6;

        // PRF outputs from generate_test_vectors.py
        // First PRF output (index=0) is 16
        test_prf_outputs[0] = 16;
        test_prf_outputs[1] = 12;
        test_prf_outputs[2] = 7;
        test_prf_outputs[3] = 19;
        test_prf_outputs[4] = 2;
        test_prf_outputs[5] = 14;
        test_prf_outputs[6] = 23;
        test_prf_outputs[7] = 9;
        test_prf_outputs[8] = 16;
        test_prf_outputs[9] = 11;

        pass_count = 0;
        fail_count = 0;

        $display("================================================================================");
        $display("Encrypt/Decrypt Round-Trip Testbench");
        $display("================================================================================");
        $display("Parameter P = %0d (plaintext modulus)", P);
        $display("");

        // Test each plaintext value
        for (i = 0; i < 10; i = i + 1) begin
            plaintext = test_plaintexts[i];
            prf_out = test_prf_outputs[i];
            #1; // Small delay for combinational logic

            $display("Test %0d:", i);
            $display("  Plaintext:  %0d", plaintext);
            $display("  PRF Output: %0d", prf_out);
            $display("  Ciphertext: %0d = (%0d + %0d) mod %0d",
                     ciphertext, plaintext, prf_out, P);
            $display("  Decrypted:  %0d = (%0d - %0d) mod %0d",
                     decrypted, ciphertext, prf_out, P);

            // Verify round-trip
            if (decrypted == plaintext) begin
                $display("  ✓ PASS: Round-trip successful");
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: Expected %0d, got %0d", plaintext, decrypted);
                fail_count = fail_count + 1;
            end
            $display("");
        end

        // Edge cases
        $display("Edge Case Tests:");
        $display("----------------");

        // Test 1: Zero plaintext
        plaintext = 0;
        prf_out = 15;
        #1;
        $display("Zero plaintext: %0d -> %0d -> %0d %s",
                 plaintext, ciphertext, decrypted,
                 (decrypted == plaintext) ? "✓" : "✗");
        if (decrypted == plaintext) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Test 2: Max plaintext
        plaintext = P - 1;
        prf_out = 7;
        #1;
        $display("Max plaintext:  %0d -> %0d -> %0d %s",
                 plaintext, ciphertext, decrypted,
                 (decrypted == plaintext) ? "✓" : "✗");
        if (decrypted == plaintext) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Test 3: Overflow case
        plaintext = 31;
        prf_out = 31;
        #1;
        $display("Overflow test:  %0d + %0d = %0d -> %0d %s",
                 plaintext, prf_out, ciphertext, decrypted,
                 (decrypted == plaintext) ? "✓" : "✗");
        if (decrypted == plaintext) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        // Test 4: Zero PRF output
        plaintext = 25;
        prf_out = 0;
        #1;
        $display("Zero PRF:       %0d + %0d = %0d -> %0d %s",
                 plaintext, prf_out, ciphertext, decrypted,
                 (decrypted == plaintext) ? "✓" : "✗");
        if (decrypted == plaintext) pass_count = pass_count + 1;
        else fail_count = fail_count + 1;

        $display("");
        $display("================================================================================");
        $display("Test Summary:");
        $display("  PASSED: %0d", pass_count);
        $display("  FAILED: %0d", fail_count);

        if (fail_count == 0) begin
            $display("  Status: ✓ ALL TESTS PASSED");
        end else begin
            $display("  Status: ✗ SOME TESTS FAILED");
        end
        $display("================================================================================");

        $finish;
    end

endmodule
