`timescale 1ns / 1ps

module shake256_tb;

    // DUT signals
    reg          clk;
    reg          rst_n;
    reg          start;
    reg  [63:0]  data_in;
    reg  [7:0]   data_in_keep;
    reg          data_in_valid;
    reg          data_in_last;
    wire         data_in_ready;
    reg  [12:0]  out_len;
    wire [63:0]  data_out;
    wire [7:0]   data_out_keep;
    wire         data_out_valid;
    reg          data_out_ready;
    wire         data_out_last;
    wire         done_sig;

    shake256 uut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .data_in        (data_in),
        .data_in_keep   (data_in_keep),
        .data_in_valid  (data_in_valid),
        .data_in_ready  (data_in_ready),
        .data_in_last   (data_in_last),
        .out_len        (out_len),
        .data_out       (data_out),
        .data_out_keep  (data_out_keep),
        .data_out_valid (data_out_valid),
        .data_out_ready (data_out_ready),
        .data_out_last  (data_out_last),
        .done           (done_sig)
    );

    // 10 ns clock
    always #5 clk = ~clk;

    // Expected output lanes (44 entries total)
    //   Test 1: indices  0- 3  (4 lanes,  32 bytes)
    //   Test 2: indices  4- 7  (4 lanes,  32 bytes)
    //   Test 3: indices  8-11  (4 lanes,  32 bytes)
    //   Test 4: indices 12-43  (32 lanes, 256 bytes)
    reg [63:0] expected_lanes [0:43];

    integer errors, total_errors, tc, timeout_cnt;
    localparam TIMEOUT = 20000;

    // -------------------------------------------------------
    // Task: pulse start and latch out_len
    // -------------------------------------------------------
    task start_hash;
        input [12:0] output_length;
        begin
            out_len = output_length;
            start   = 1;
            @(posedge clk);
            #1;
            start = 0;
        end
    endtask

    // -------------------------------------------------------
    // Task: feed one 64-bit word through the absorb interface
    // -------------------------------------------------------
    task absorb_word;
        input [63:0] word_data;
        input [7:0]  keep;
        input        is_last;
        begin
            // Wait until module is ready
            timeout_cnt = 0;
            while (!data_in_ready) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > TIMEOUT) begin
                    $display("TIMEOUT: data_in_ready"); $finish;
                end
            end
            // Drive data between clock edges
            #1;
            data_in       = word_data;
            data_in_keep  = keep;
            data_in_last  = is_last;
            data_in_valid = 1;
            // Transfer happens at next posedge
            @(posedge clk);
            #1;
            data_in_valid = 0;
            data_in_last  = 0;
        end
    endtask

    // -------------------------------------------------------
    // Task: read squeeze output and compare with expected
    // -------------------------------------------------------
    task squeeze_and_check;
        input integer test_num;
        input integer num_lanes;
        input integer base_idx;
        integer li;
        reg [63:0] exp;
        begin
            data_out_ready = 1;
            for (li = 0; li < num_lanes; li = li + 1) begin
                // Wait for valid output
                timeout_cnt = 0;
                while (!data_out_valid) begin
                    @(posedge clk);
                    timeout_cnt = timeout_cnt + 1;
                    if (timeout_cnt > TIMEOUT) begin
                        $display("TIMEOUT: data_out_valid (lane %0d)", li); $finish;
                    end
                end

                // Compare data
                exp = expected_lanes[base_idx + li];
                if (data_out !== exp) begin
                    $display("  FAIL lane %0d: expected %h, got %h", li, exp, data_out);
                    errors = errors + 1;
                end

                // Check last flag on final lane
                if (li == num_lanes - 1) begin
                    if (!data_out_last) begin
                        $display("  FAIL lane %0d: data_out_last should be 1", li);
                        errors = errors + 1;
                    end
                end else begin
                    if (data_out_last) begin
                        $display("  FAIL lane %0d: unexpected data_out_last", li);
                        errors = errors + 1;
                    end
                end

                @(posedge clk); // advance to next lane
            end
            #1;
            data_out_ready = 0;

            // Wait for done
            timeout_cnt = 0;
            while (!done_sig) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > TIMEOUT) begin
                    $display("TIMEOUT: done"); $finish;
                end
            end
        end
    endtask

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    initial begin
        $dumpfile("shake256_tb.vcd");
        $dumpvars(0, shake256_tb);
        $readmemh("shake256_vectors.hex", expected_lanes);

        clk            = 0;
        rst_n          = 0;
        start          = 0;
        data_in        = 0;
        data_in_keep   = 0;
        data_in_valid  = 0;
        data_in_last   = 0;
        out_len        = 0;
        data_out_ready = 0;
        total_errors   = 0;

        // Reset
        #25;
        rst_n = 1;
        @(posedge clk); #1;

        // ==================================================
        // Test 1: SHAKE256("", 32)
        //   Empty input: 1 word with keep=0, last=1
        //   Output: 4 lanes (indices 0-3)
        // ==================================================
        $display("\n=== Test 1: SHAKE256(\"\", 32) ===");
        errors = 0;
        start_hash(13'd32);
        absorb_word(64'h0, 8'h00, 1);
        squeeze_and_check(1, 4, 0);
        total_errors = total_errors + errors;
        $display("Test 1: %s", (errors == 0) ? "PASS" : "FAIL");

        // ==================================================
        // Test 2: SHAKE256("abc", 32)
        //   "abc" = 0x61,0x62,0x63 → LE lane 0x0000000000636261
        //   1 word, keep=0x07, last=1
        //   Output: 4 lanes (indices 4-7)
        // ==================================================
        $display("\n=== Test 2: SHAKE256(\"abc\", 32) ===");
        errors = 0;
        start_hash(13'd32);
        absorb_word(64'h0000000000636261, 8'h07, 1);
        squeeze_and_check(2, 4, 4);
        total_errors = total_errors + errors;
        $display("Test 2: %s", (errors == 0) ? "PASS" : "FAIL");

        // ==================================================
        // Test 3: SHAKE256(200 * 0xa3, 32)
        //   200 bytes = 25 words of 0xa3a3a3a3a3a3a3a3
        //   First 17 words fill rate block → permute
        //   Next 8 words: 7 normal + 1 last
        //   Output: 4 lanes (indices 8-11)
        // ==================================================
        $display("\n=== Test 3: SHAKE256(200 x 0xa3, 32) ===");
        errors = 0;
        start_hash(13'd32);
        // First 17 words (fills rate: lanes 0-16, word 16 triggers permutation)
        for (tc = 0; tc < 17; tc = tc + 1)
            absorb_word(64'ha3a3a3a3a3a3a3a3, 8'hFF, 0);
        // Remaining 8 words (7 not-last + 1 last)
        for (tc = 0; tc < 7; tc = tc + 1)
            absorb_word(64'ha3a3a3a3a3a3a3a3, 8'hFF, 0);
        absorb_word(64'ha3a3a3a3a3a3a3a3, 8'hFF, 1);
        squeeze_and_check(3, 4, 8);
        total_errors = total_errors + errors;
        $display("Test 3: %s", (errors == 0) ? "PASS" : "FAIL");

        // ==================================================
        // Test 4: SHAKE256("", 256)
        //   Squeeze 256 bytes = 32 lanes across rate boundary
        //   (17 lanes, permute, 15 more lanes)
        //   Output: 32 lanes (indices 12-43)
        // ==================================================
        $display("\n=== Test 4: SHAKE256(\"\", 256) ===");
        errors = 0;
        start_hash(13'd256);
        absorb_word(64'h0, 8'h00, 1);
        squeeze_and_check(4, 32, 12);
        total_errors = total_errors + errors;
        $display("Test 4: %s", (errors == 0) ? "PASS" : "FAIL");

        // ==================================================
        // Summary
        // ==================================================
        $display("\n=== Summary ===");
        if (total_errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d error(s)", total_errors);

        $finish;
    end

endmodule
