module secret_key #(
    parameter N_LWR = 445,
    parameter KEY_FILE = "secret_key.mem"
) (
    input wire [$clog2(N_LWR)-1:0] addr,
    output wire key_bit
);
    reg secret_key [0:N_LWR-1];
    integer i;
    initial begin
        // init
        for (i = 0; i < N_LWR; i = i + 1) begin
            secret_key[i] = 1'b0;
        end
        // read from file
        $readmemb(KEY_FILE, secret_key);
    end

    assign key_bit = secret_key[addr];

endmodule