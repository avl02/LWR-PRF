module encrypt #(
    parameter P = 32
) (
    input wire [$clog2(P)-1:0] plaintext,
    input wire [$clog2(P)-1:0] prf_out,
    output wire [$clog2(P)-1:0] ciphertext
);
    localparam WIDTH = $clog2(P);

    wire [WIDTH:0] sum; // one extra bit for overflow
    assign sum = plaintext + prf_out;
    assign ciphertext = (sum >= P) ? (sum - P) : sum[WIDTH-1:0];

endmodule