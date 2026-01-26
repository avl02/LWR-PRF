module shake256 (
    input wire clk,
    input wire rst_n,

    input wire start,

    // Absorb
    input wire [64:0] data_in,
    input wire [7:0] data_in_keep,
    input wire data_in_valid,
    output wire data_in_ready,
    input wire data_in_last,

    // Squeeze
    input wire [12:0] out_len,
    output wire [63:0] data_out,
    output wire [7:0] data_out_keep,
    output wire data_out_valid,
    input wire data_out_ready,
    output wire data_out_last,
    output wire done
);

    // Parameters
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_ABSORB = 3'd1;
    localparam [2:0] S_ABSORB_PERM = 3'd2;
    localparam [2:0] S_PAD = 3'd3;
    localparam [2:0] S_PAD_PERM = 3'd4;
    localparam [2:0] S_SQUEEZE = 3'd5;
    localparam [2:0] S_SQUEEZE_PERM = 3'd6;
    localparam [2:0] S_DONE = 3'd7;

    // Signals
    reg [2:0] fsm_state;
    reg [1599:0] keccak_state;
    reg [4:0] lane_counter;
    reg [12:0] output_len_reg;
    reg [12:0] output_count;
    reg [3:0] pad_pos;

    // Keccak
    reg perm_start;
    wire perm_ready;
    wire perm_done;
    wire [1599:0] perm_state_out;

    keccak_f1600 keccak (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (perm_start),
        .state_in   (keccak_state),
        .state_out  (perm_state_out),
        .ready      (perm_ready),
        .done       (perm_done)
    );

    // Data masking -> check this
    function [63:0] mask_data;
        input [63:0] data;
        input [7:0]  keep;
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                mask_data[i*8 +: 8] = keep[i] ? data[i*8 +: 8] : 8'h00;
            end
        end
    endfunction

    // Count valid bytes from keep signal
    function [3:0] count_bytes;
        input [7:0] keep;
        begin
            case (keep)
                8'b00000000: count_bytes = 4'd0;
                8'b00000001: count_bytes = 4'd1;
                8'b00000011: count_bytes = 4'd2;
                8'b00000111: count_bytes = 4'd3;
                8'b00001111: count_bytes = 4'd4;
                8'b00011111: count_bytes = 4'd5;
                8'b00111111: count_bytes = 4'd6;
                8'b01111111: count_bytes = 4'd7;
                8'b11111111: count_bytes = 4'd8;
                default:     count_bytes = 4'd0;
            endcase
        end
    endfunction

    // Current lane
    wire [63:0] current_lane = keccak_state[lane_counter*64 +: 64];

    // Squeeze logic
    wire [12:0] bytes_remaining = output_len_reg - output_count;
    wire is_last_squeeze = (bytes_remaining <= 13'd8);
    
    // Generate keep signal for output
    reg [7:0] out_keep;
    always @(*) begin
        if (bytes_remaining >= 13'd8)
            out_keep = 8'b11111111;
        else begin
            case (bytes_remaining[2:0])
                3'd0: out_keep = 8'b00000000;
                3'd1: out_keep = 8'b00000001;
                3'd2: out_keep = 8'b00000011;
                3'd3: out_keep = 8'b00000111;
                3'd4: out_keep = 8'b00001111;
                3'd5: out_keep = 8'b00011111;
                3'd6: out_keep = 8'b00111111;
                3'd7: out_keep = 8'b01111111;
            endcase
        end
    end

    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state <= S_IDLE;
            keccak_state <= 1600'd0;
            lane_counter <= 5'd0;
            output_len_reg <= 13'd0;
            output_count <= 13'd0;
            pad_pos <= 4'd0;
            perm_start <= 1'b0;
        end
        else begin
            case (fsm_state)
                S_IDLE: begin
                    if (start) begin
                        fsm_state <= S_ABSORB;
                        keccak_state <= 1600'd0;
                        lane_counter <= 5'd0;
                        output_len_reg <= out_len;
                        output_count <= 13'd0;
                    end
                end

                S_ABSORB: begin
                    if (data_in_valid) begin
                        // XOR masked input into current state lane
                        keccak_state[lane_counter*64 +: 64] <= current_lane ^ mask_data(data_in, data_in_keep);
                        
                        if (data_in_last) begin
                            // Save padding position and go to PAD state
                            pad_pos <= count_bytes(data_in_keep);
                            fsm_state <= S_PAD;
                        end
                        else if (lane_counter == RATE_LANES - 1) begin
                            // Rate block full, trigger permutation
                            lane_counter <= 5'd0;
                            perm_start <= 1'b1;
                            fsm_state <= S_ABSORB_PERM;
                        end
                        else begin
                            lane_counter <= lane_counter + 1'd1;
                        end
                    end
                end

                // Squeeze
                S_SQUEEZE: begin
                    if (data_out_ready) begin
                        // Update byte count
                        if (bytes_remaining >= 13'd8)
                            output_count <= output_count + 13'd8;
                        else
                            output_count <= output_len_reg;
                        
                        if (is_last_squeeze) begin
                            // All output complete
                            fsm_state <= S_DONE;
                        end
                        else if (lane_counter == RATE_LANES - 1) begin
                            // Need more output, permute again
                            lane_counter <= 5'd0;
                            perm_start <= 1'b1;
                            fsm_state <= S_SQUEEZE_PERM;
                        end
                        else begin
                            lane_counter <= lane_counter + 1'd1;
                        end
                    end
                end

                // Squeeze perm done
                S_SQUEEZE_PERM: begin
                    if (perm_done) begin
                        keccak_state <= perm_state_out;
                        lane_counter <= 5'd0;
                        fsm_state <= S_SQUEEZE;
                    end
                end

                // Done
                S_DONE: begin
                    if (start) begin
                        keccak_state <= 1600'b0;
                        lane_counter <= 5'd0;
                        output_len_reg <= output_length;
                        output_count <= 13'd0;
                        fsm_state <= S_ABSORB;
                    end
                end

                default: fsm_state <= S_IDLE;
            endcase
        end
    end

    // Assign outputs
    assign data_in_ready = (fsm_state == S_ABSORB);
    assign data_out = current_lane;
    assign data_out_keep = out_keep;
    assign data_out_valid = (fsm_state == S_SQUEEZE);
    assign done = (fsm_state == S_DONE);
    assign data_out_last = (fsm_state == S_SQUEEZE) && is_last_squeeze;
    assign done = (fsm_state == S_DONE);

endmodule