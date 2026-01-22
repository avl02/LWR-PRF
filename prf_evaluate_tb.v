`timescale 1ns / 1ps

module prf_evaluate_tb;
    // Parameters
    localparam N_LWR = 445;
    localparam N = 2048;
    localparam P = 32;
    localparam CLK_PERIOD = 10; // 10ns = 100MHz

    // Signals
    reg clk;
    reg rst_n;
    reg start;
    reg [63:0] nonce;
    reg [63:0] index;
    wire [4:0] prf_out;  // $clog2(32) = 5 bits
    wire done;

    // Instantiate DUT (Device Under Test)
    prf_evaluate #(
        .N_LWR(N_LWR),
        .N(N),
        .P(P)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .nonce(nonce),
        .index(index),
        .prf_out(prf_out),
        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Cycle counter for debugging
    integer cycle_count;
    always @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
        start = 0;
        nonce = 64'h0;
        index = 64'h0;

        // Dump waveforms for viewing
        $dumpfile("prf_evaluate_tb.vcd");
        $dumpvars(0, prf_evaluate_tb);

        // Display header
        $display("================================================================================");
        $display("PRF Evaluation Testbench");
        $display("================================================================================");
        $display("Parameters: N_LWR=%0d, N=%0d, P=%0d", N_LWR, N, P);
        $display("");

        // Release reset
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // Test Case 1: Basic PRF evaluation
        $display("Test Case 1: PRF Evaluation");
        $display("  Nonce: 0x%016h", nonce);
        $display("  Index: 0x%016h", index);
        $display("");

        // Start PRF evaluation
        start = 1;
        #CLK_PERIOD;
        start = 0;

        // Wait for completion
        wait(done);
        #CLK_PERIOD;

        $display("  Result:");
        $display("    PRF Output: %0d (0x%h)", prf_out, prf_out);
        $display("    Completed at cycle %0d", cycle_count);
        $display("");

        // Compare with expected value from Python
        $display("  Verification:");
        if (prf_out == 16) begin
            $display("    ✓ PASS: PRF output matches expected value (16)");
        end else begin
            $display("    ✗ FAIL: Expected 16, got %0d", prf_out);
        end
        $display("");

        // Test Case 2: Another evaluation with same inputs (should get same result)
        $display("Test Case 2: Repeat evaluation (determinism check)");
        #(CLK_PERIOD * 5);
        start = 1;
        #CLK_PERIOD;
        start = 0;

        wait(done);
        #CLK_PERIOD;

        $display("  PRF Output: %0d (should match Test Case 1)", prf_out);
        $display("");

        // End simulation
        $display("================================================================================");
        $display("Simulation Complete");
        $display("================================================================================");
        #(CLK_PERIOD * 10);
        $finish;
    end

    // Monitor internal signals for debugging
    always @(posedge clk) begin
        if (dut.hash_inst.hash_valid) begin
            $display("[Cycle %0d] Hash streaming: idx=%0d, value=0x%03h",
                     cycle_count, dut.hash_inst.hash_idx, dut.hash_inst.hash_out);
        end
    end

    // Display dot product result when done
    always @(posedge clk) begin
        if (dut.dp.done) begin
            $display("");
            $display("  Intermediate values:");
            $display("    Dot product:     %0d (expected: 480267)", dut.dot_prod);
            $display("    Inner mod 2N:    %0d (expected: 1035)", dut.round.inner_mod_2N);
            $display("    Inner mod N:     %0d (expected: 1035)", dut.round.inner_mod_N);
            $display("    MSB:             %0d (expected: 0)", dut.round.msb);
            $display("    Rounded:         %0d (expected: 16)", dut.round.rounded);
            $display("    PRF output:      %0d (expected: 16)", prf_out);

            // Verify intermediate values
            $display("");
            $display("  Intermediate value checks:");
            if (dut.dot_prod == 480267)
                $display("    ✓ Dot product correct");
            else
                $display("    ✗ Dot product FAILED: expected 480267, got %0d", dut.dot_prod);

            if (dut.round.inner_mod_2N == 1035)
                $display("    ✓ Inner mod 2N correct");
            else
                $display("    ✗ Inner mod 2N FAILED: expected 1035, got %0d", dut.round.inner_mod_2N);

            if (dut.round.msb == 0)
                $display("    ✓ MSB correct");
            else
                $display("    ✗ MSB FAILED: expected 0, got %0d", dut.round.msb);

            if (dut.round.rounded == 16)
                $display("    ✓ Rounded value correct");
            else
                $display("    ✗ Rounded FAILED: expected 16, got %0d", dut.round.rounded);

            $display("");
        end
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000); // 10000 cycles timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
