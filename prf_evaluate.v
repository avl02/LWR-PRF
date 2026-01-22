module prf_evaluate #(
    parameter N_LWR = 445,
    parameter N = 2048,
    parameter P = 32
) (
    input wire clk,
    input wire rst_n,

    input wire start,

    input wire [63:0] nonce,
    input wire [63:0] index,

    output wire [$clog2(P)-1:0] prf_out,
    output wire done
);

    localparam ELEM_WIDTH = $clog2(N) + 1;
    localparam ACC_WIDTH = 32;
    localparam ADDR_WIDTH = $clog2(N_LWR);
    localparam OUT_WIDTH = $clog2(P);

    wire [ELEM_WIDTH-1:0] hash;
    wire [ADDR_WIDTH-1:0] idx;
    wire valid;
    wire last;
    wire key_bit;
    wire [ELEM_WIDTH-1:0] a_in;

    wire [ACC_WIDTH-1:0] dot_prod;
    wire dot_done;

    // Hash Module
    hash_to_vector #(
        .N_LWR(N_LWR),
        .N(N),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) hash_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .nonce(nonce),
        .index(index),
        .hash_out(a_in),
        .hash_idx(idx),
        .hash_valid(valid),
        .hash_last(last)
    );

    // Secret Key
    secret_key #(
        .N_LWR(N_LWR),
        .KEY_FILE("secret_key.mem")
    ) sk (
        .addr(idx),
        .key_bit(key_bit)
    );

    // Dot Product
    dot_product #(
        .N_LWR(N_LWR),
        .ELEM_WIDTH(ELEM_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dp (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a_in(a_in),
        .a_valid(valid),
        .a_last(last),
        .key_bit(key_bit),
        .dot_product(dot_prod),
        .done(dot_done)
    );

    prf_rounding #(
        .N(N),
        .P(P),
        .ACC_WIDTH(ACC_WIDTH)
    ) round (
        .inner_product(dot_prod),
        .prf_out(prf_out)
    );

    assign done = dot_done;
    
    

endmodule