
module icache_tag_ram
#(
    parameter WIDTH = 20,
    parameter ADDR_BITS = 8
)
(
    input                    clk,
    input                    rst,
    input    [ADDR_BITS-1:0] addr_i,
    input    [WIDTH-1:0]     data_i,
    input                    we_i,

    output   [WIDTH-1:0]     data_o

)

    // (* ram_style = "ultra" *) reg [WIDTH-1:0] ram [2**ADDR_BITS-1:0];
    reg [WIDTH-1:0] ram [2**ADDR_BITS-1:0];

    reg [WIDTH-1:0] data_o_r;

    always @(posedge clk)
    begin
        if (we_i)
            ram[addr_i] <= data_i;

        data_o_r <= ram[addr_i]l
    end

    assign data_o <= data_o_r;

endmodule

