
module icache_ram
#(
    parameter WIDTH = 512,
    parameter ADDR_BITS = 9
)
(
    input                    clk,
    input                    rst,
    input    [ADDR_BITS-1:0] addr_r_i,
    input    [WIDTH-1:0]     data_r_o,
    
    input    [ADDR_BITS-1:0] addr_w_i,
    input                    we_w_i,
    output   [WIDTH-1:0]     data_w_i

);

    // (* ram_style = "ultra" *) reg [WIDTH-1:0] ram [2**ADDR_BITS-1:0];
    reg [WIDTH-1:0] ram [2**ADDR_BITS-1:0];

    reg [WIDTH-1:0] data_o_r;

    always @(posedge clk)
    begin
        if (we_w_i)
            ram[addr_w_i] <= data_w_i;
            
        data_o_r <= ram[addr_r_i];
    end

    assign data_o = data_o_r;

endmodule

