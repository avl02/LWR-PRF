module decrypt #(
    parameter P = 32
) (
    input wire [$clog2(P)-1:0] ciphertext,
    input wire [$clog2(P)-1:0] prf_out,
    output wire [$clog2(P)-1:0] plaintext
);
    localparam WIDTH = $clog2(P);

    wire [WIDTH:0] diff; // one extra bit for overflow
    assign diff = ciphertext + P - prf_out;
    assign plaintext = (diff >= P) ? (diff - P) : diff[WIDTH-1:0];

endmodule